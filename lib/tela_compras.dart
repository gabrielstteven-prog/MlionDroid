import 'dart:async';

import 'package:flutter/material.dart';
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:http/http.dart' as http;

import 'cache_manager.dart';
import 'config_manager.dart';
import 'design/tema.dart';
import 'responsive.dart';
import 'services/google_auth_service.dart';
import 'sistema.dart';

class ItemCompra {
  final String id;
  final String titulo;
  const ItemCompra({required this.id, required this.titulo});

  Map<String, dynamic> toJson() => {'id': id, 'titulo': titulo};
  static ItemCompra fromJson(Map<String, dynamic> j) =>
      ItemCompra(id: j['id'] as String? ?? '', titulo: j['titulo'] as String? ?? '');
}

const _verde = Destaques.compras;

/// Lista de compras do Google Tasks (lista chamada "Compras", "Mercado"...).
///
/// - Tocar num item marca como comprado, com 5s para DESFAZER (antes, um
///   toque acidental apagava o item na hora).
/// - Botão de microfone adiciona item por voz.
class TelaCompras extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaCompras({super.key, required this.aoTerminar});

  @override
  State<TelaCompras> createState() => _TelaComprasState();
}

enum _Estado { carregando, semConta, semLista, pronto, erro }

class _TelaComprasState extends State<TelaCompras>
 {
  final _cfg = ConfigManager();
  final _scroll = ScrollController();

  _Estado _estado = _Estado.carregando;
  List<ItemCompra> _itens = [];
  String _nomeLista = '';
  String? _listaId;
  DateTime? _atualizadoEm;
  http.Client? _client;

  /// Itens marcados aguardando os 5s de "desfazer".
  final Map<String, Timer> _pendentes = {};
  bool _ouvindo = false;

  Timer? _saidaTimer;
  Timer? _scrollTimer;

  static const _chaveCache = 'compras_itens_v2';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    // Itens com "desfazer" pendente são confirmados ao sair da tela; o
    // cliente HTTP só é fechado depois que esses envios terminarem.
    final envios = <Future<void>>[];
    for (final e in _pendentes.entries.toList()) {
      e.value.cancel();
      envios.add(_concluirNoGoogle(e.key));
    }
    _pendentes.clear();
    final client = _client;
    Future.wait(envios).whenComplete(() => client?.close());
    _scroll.dispose();
    _saidaTimer?.cancel();
    _scrollTimer?.cancel();
    super.dispose();
  }

  int get _duracaoSeg => _cfg.getInt('compras', 'duracao_seg', 30).clamp(10, 300);

  Future<void> _carregar() async {
    final cache = await CacheManager.instance.obterEntrada<Map<String, dynamic>>(_chaveCache);
    if (!mounted) return;
    if (cache != null) {
      setState(() {
        _itens = (cache.dados['itens'] as List? ?? [])
            .map((e) => ItemCompra.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _nomeLista = cache.dados['nomeLista'] as String? ?? '';
        _listaId = cache.dados['listaId'] as String?;
        _atualizadoEm = cache.salvoEm;
        _estado = _Estado.pronto;
      });
    }

    _client = await GoogleAuthService.instance.cliente();
    if (!mounted) return;
    if (_client == null) {
      if (cache == null) setState(() => _estado = _Estado.semConta);
      _finalizarCarga();
      return;
    }
    if (cache == null || cache.venceu(_cfg.getIntervaloAtualizacao('compras'))) {
      await _buscarDoGoogle();
    }
    _finalizarCarga();
  }

  void _finalizarCarga() {
    if (!mounted) return;
    _iniciarScroll();
    _iniciarSaida(_estado == _Estado.pronto ? _duracaoSeg : 12);
  }

  Future<void> _buscarDoGoogle() async {
    try {
      final api = tasks.TasksApi(_client!);
      final listas = await api.tasklists.list();
      final alvo = (listas.items ?? <tasks.TaskList>[])
          .where((l) => l.id != null && ehListaDeCompras(l.title ?? ''))
          .firstOrNull;
      if (alvo == null) {
        if (mounted) setState(() => _estado = _Estado.semLista);
        return;
      }
      final tl = await api.tasks.list(alvo.id!,
          showCompleted: false, showHidden: false, maxResults: 100);
      final novos = (tl.items ?? <tasks.Task>[])
          .where((t) => t.status != 'completed' && (t.title ?? '').trim().isNotEmpty)
          .map((t) => ItemCompra(id: t.id ?? '', titulo: t.title!.trim()))
          .toList();
      if (!mounted) return;
      setState(() {
        _itens = novos;
        _nomeLista = alvo.title ?? 'Compras';
        _listaId = alvo.id;
        _atualizadoEm = DateTime.now();
        _estado = _Estado.pronto;
      });
      await _salvarCache();
    } catch (e) {
      debugPrint('TelaCompras: $e');
      if (mounted && _estado == _Estado.carregando) {
        setState(() => _estado = _Estado.erro);
      }
    }
  }

  Future<void> _salvarCache() => CacheManager.instance.salvar(_chaveCache, {
        'itens': _itens.where((i) => !_pendentes.containsKey(i.id)).map((i) => i.toJson()).toList(),
        'nomeLista': _nomeLista,
        'listaId': _listaId,
      });

  // ── Marcar comprado (com desfazer) ─────────────────────────────────────────
  void _marcar(ItemCompra item) {
    if (_client == null || _listaId == null || item.id.isEmpty) return;
    _iniciarSaida(_duracaoSeg);
    if (_pendentes.containsKey(item.id)) {
      // Segundo toque = desfazer
      _pendentes.remove(item.id)?.cancel();
      setState(() {});
      return;
    }
    setState(() {
      _pendentes[item.id] = Timer(const Duration(seconds: 5), () {
        _pendentes.remove(item.id);
        _concluirNoGoogle(item.id);
        if (mounted) setState(() => _itens.removeWhere((i) => i.id == item.id));
        _salvarCache();
      });
    });
  }

  Future<void> _concluirNoGoogle(String id) async {
    final client = _client;
    final lista = _listaId;
    if (client == null || lista == null) return;
    try {
      final api = tasks.TasksApi(client);
      await api.tasks.patch(tasks.Task(status: 'completed'), lista, id);
    } catch (e) {
      debugPrint('TelaCompras concluir: $e');
    }
  }

  // ── Adicionar por voz ──────────────────────────────────────────────────────
  Future<void> _adicionarPorVoz() async {
    if (_client == null || _listaId == null || _ouvindo) return;
    _saidaTimer?.cancel();
    setState(() => _ouvindo = true);
    final falado = await Sistema.ouvir(prompt: 'Diga o item para a lista de compras');
    if (!mounted) return;
    setState(() => _ouvindo = false);
    final itens = _separarItens(falado);
    for (final titulo in itens) {
      try {
        final criada = await tasks.TasksApi(_client!)
            .tasks
            .insert(tasks.Task(title: titulo), _listaId!);
        if (!mounted) return;
        setState(() => _itens.insert(0, ItemCompra(id: criada.id ?? '', titulo: titulo)));
      } catch (e) {
        debugPrint('TelaCompras inserir: $e');
      }
    }
    if (itens.isNotEmpty) await _salvarCache();
    _iniciarSaida(_duracaoSeg);
  }

  /// "arroz, feijão e leite" → [Arroz, Feijão, Leite]
  static List<String> _separarItens(String falado) {
    return falado
        .split(RegExp(r',| e |;'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .toList();
  }

  // ── Scroll / saída ─────────────────────────────────────────────────────────
  void _iniciarScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(seconds: 4), () async {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max < 50) return;
      await _scroll.animateTo(max,
          duration: Duration(seconds: (max / 40).clamp(6, 60).toInt()),
          curve: Curves.linear);
      await Future.delayed(const Duration(seconds: 3));
      if (mounted && _scroll.hasClients) {
        await _scroll.animateTo(0,
            duration: const Duration(seconds: 2), curve: Curves.easeOut);
      }
    });
  }

  void _iniciarSaida(int seg) {
    _saidaTimer?.cancel();
    _saidaTimer = Timer(Duration(seconds: seg), () {
      if (mounted && _pendentes.isEmpty && !_ouvindo) widget.aoTerminar();
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final t = Tipo(r);
    final restantes = _itens.where((i) => !_pendentes.containsKey(i.id)).length;
    final podeFalar = _client != null && _listaId != null;
    return EstruturaTela(
      icone: Icons.shopping_cart_rounded,
      titulo: _nomeLista.isEmpty ? 'Lista de compras' : _nomeLista,
      subtitulo: _estado != _Estado.pronto
          ? null
          : restantes == 0
              ? 'Tudo comprado'
              : (restantes == 1 ? '1 item para comprar' : '$restantes itens para comprar'),
      destaque: _verde,
      rodapeDireita:
          _atualizadoEm != null ? 'Atualizado ${descreverIdade(_atualizadoEm!)}' : null,
      acaoDireita: podeFalar
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _ouvindo ? _verde : _verde.withValues(alpha: 0.18),
                foregroundColor: _ouvindo ? Colors.black : _verde,
                padding: EdgeInsets.symmetric(horizontal: r.sp(20), vertical: r.sp(14)),
              ),
              onPressed: _adicionarPorVoz,
              icon: Icon(_ouvindo ? Icons.hearing_rounded : Icons.mic_rounded, size: r.icon(24)),
              label: Text(_ouvindo ? 'Ouvindo...' : 'Adicionar por voz',
                  style: t.corpo(
                      cor: _ouvindo ? Colors.black : _verde, peso: FontWeight.w700)),
            )
          : null,
      child: _buildCorpo(r),
    );
  }

  Widget _buildCorpo(R r) {
    switch (_estado) {
      case _Estado.carregando:
        return const Carregando(cor: _verde);
      case _Estado.semConta:
        return const AvisoTela(
            icone: Icons.account_circle_outlined,
            titulo: 'Conta Google não conectada',
            texto: 'Abra Configurações › Calendário e toque em "Conectar conta Google".',
            cor: _verde);
      case _Estado.semLista:
        return const AvisoTela(
            icone: Icons.playlist_add_rounded,
            titulo: 'Nenhuma lista de compras encontrada',
            texto: 'No Google Tasks, crie uma lista chamada "Compras" ou "Mercado".',
            cor: _verde);
      case _Estado.erro:
        return const AvisoTela(
            icone: Icons.cloud_off_rounded,
            titulo: 'Não foi possível carregar a lista',
            texto: 'Verifique a internet. A tela tenta de novo na próxima passagem.');
      case _Estado.pronto:
        if (_itens.isEmpty) {
          return const AvisoTela(
            icone: Icons.check_circle_outline_rounded,
            titulo: 'Tudo comprado',
            texto: 'Para incluir algo, toque em "Adicionar por voz" ou diga ao '
                'assistente: "adiciona leite na lista".',
            cor: _verde,
          );
        }
        return LayoutBuilder(builder: (context, box) {
          final colunas = box.maxWidth > r.sp(900) ? 2 : 1;
          return GridView.builder(
            controller: _scroll,
            padding: EdgeInsets.only(bottom: r.sp(40)),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: colunas,
              mainAxisExtent: r.sp(84),
              crossAxisSpacing: r.sp(16),
              mainAxisSpacing: r.sp(12),
            ),
            itemCount: _itens.length,
            itemBuilder: (_, i) => _buildItem(_itens[i], r),
          );
        });
    }
  }

  Widget _buildItem(ItemCompra item, R r) {
    final t = Tipo(r);
    final pendente = _pendentes.containsKey(item.id);
    return GestureDetector(
      onTap: () => _marcar(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.symmetric(horizontal: r.sp(20)),
        decoration: BoxDecoration(
          color: pendente ? Colors.transparent : Cores.superficie,
          borderRadius: BorderRadius.circular(r.sp(20)),
          border: Border.all(color: pendente ? Cores.aviso.withValues(alpha: 0.6) : Cores.contorno),
        ),
        child: Row(
          children: [
            Icon(pendente ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: pendente ? Cores.textoApagado : _verde, size: r.icon(32)),
            SizedBox(width: r.sp(16)),
            Expanded(
              child: Text(
                item.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.subtitulo(cor: pendente ? Cores.textoApagado : Cores.texto).copyWith(
                    decoration: pendente ? TextDecoration.lineThrough : null,
                    decorationColor: Cores.textoApagado),
              ),
            ),
            if (pendente)
              Row(children: [
                Icon(Icons.undo_rounded, color: Cores.aviso, size: r.icon(22)),
                SizedBox(width: r.sp(6)),
                Text('Desfazer', style: t.corpo(cor: Cores.aviso, peso: FontWeight.w700)),
              ]),
          ],
        ),
      ),
    );
  }
}
