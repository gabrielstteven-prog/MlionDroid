import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:http/http.dart' as http;

import 'cache_manager.dart';
import 'config_manager.dart';
import 'performance_manager.dart';
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

const List<Color> _coresItens = [
  Color(0xFF18FFFF),
  Color(0xFF00E676),
  Color(0xFFFFD740),
  Color(0xFFFF6D00),
  Color(0xFFE040FB),
  Color(0xFFFF4081),
  Color(0xFF40C4FF),
  Color(0xFFCCFF90),
  Color(0xFFFF6E40),
  Color(0xFFEA80FC),
];

const _verde = Color(0xFF00E676);

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
    with SingleTickerProviderStateMixin {
  final _cfg = ConfigManager();
  final _scroll = ScrollController();
  late final AnimationController _bgCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

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
    if (PerformanceManager.instance.animacoesDecorativasAtivas) {
      _bgCtrl.repeat(reverse: true);
    }
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
    _bgCtrl.dispose();
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: _BgPainter(_bgCtrl))),
          ),
          Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.45))),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(r),
                Expanded(child: _buildCorpo(r)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(R r) {
    final podeFalar = _client != null && _listaId != null;
    final restantes = _itens.where((i) => !_pendentes.containsKey(i.id)).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: _verde.withValues(alpha: 0.4), width: 1.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [_verde, Color(0xFF18FFFF)]),
            ),
            child: Icon(Icons.shopping_cart_rounded, color: Colors.black, size: r.icon(26)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nomeLista.isEmpty ? 'LISTA DE COMPRAS' : _nomeLista.toUpperCase(),
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: r.fs(22),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5),
                ),
                Text(
                  _estado != _Estado.pronto
                      ? ''
                      : restantes == 0
                          ? 'Tudo comprado! 🎉'
                          : '$restantes ${restantes == 1 ? 'item' : 'itens'} para comprar'
                              '${_atualizadoEm != null ? '  •  atualizado ${descreverIdade(_atualizadoEm!)}' : ''}',
                  style: GoogleFonts.poppins(
                      color: _verde.withValues(alpha: 0.8), fontSize: r.fs(13)),
                ),
              ],
            ),
          ),
          if (podeFalar)
            GestureDetector(
              onTap: _adicionarPorVoz,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: _verde.withValues(alpha: _ouvindo ? 0.35 : 0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: _verde.withValues(alpha: 0.6), width: 1.5),
                ),
                child: Row(children: [
                  Icon(_ouvindo ? Icons.hearing_rounded : Icons.mic_rounded,
                      color: _verde, size: r.icon(24)),
                  const SizedBox(width: 8),
                  Text(_ouvindo ? 'Ouvindo...' : 'Adicionar por voz',
                      style: GoogleFonts.poppins(
                          color: _verde, fontSize: r.fs(15), fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCorpo(R r) {
    switch (_estado) {
      case _Estado.carregando:
        return const Center(child: CircularProgressIndicator(color: _verde));
      case _Estado.semConta:
        return _aviso(r, Icons.account_circle_outlined, 'Conta Google não conectada',
            'Abra Configurações › Calendário e toque em "Conectar conta Google".');
      case _Estado.semLista:
        return _aviso(r, Icons.playlist_add_rounded, 'Nenhuma lista de compras encontrada',
            'No Google Tasks, crie uma lista chamada "Compras" (ou "Mercado").');
      case _Estado.erro:
        return _aviso(r, Icons.cloud_off_rounded, 'Não foi possível carregar a lista',
            'Verifique a internet. A tela tenta de novo na próxima vez.');
      case _Estado.pronto:
        if (_itens.isEmpty) return _buildListaVazia(r);
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          itemCount: _itens.length,
          itemBuilder: (_, i) => _buildItem(_itens[i], i, r),
        );
    }
  }

  Widget _aviso(R r, IconData icone, String titulo, String texto) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: _verde, size: r.icon(64)),
            const SizedBox(height: 16),
            Text(titulo,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: r.fs(24), fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(texto,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white60, fontSize: r.fs(16))),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(ItemCompra item, int index, R r) {
    final cor = _coresItens[index % _coresItens.length];
    final pendente = _pendentes.containsKey(item.id);
    return GestureDetector(
      onTap: () => _marcar(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 14),
        height: r.isCompact ? r.sp(72) : r.sp(95),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: pendente
              ? Colors.white.withValues(alpha: 0.03)
              : const Color(0xFF0A0F14).withValues(alpha: 0.75),
          border: Border.all(
            color: cor.withValues(alpha: pendente ? 0.25 : 0.6),
            width: pendente ? 1.5 : 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cor.withValues(alpha: 0.15),
                border: Border.all(color: cor.withValues(alpha: 0.5), width: 2),
              ),
              child: Text('${index + 1}',
                  style: GoogleFonts.poppins(
                      color: cor, fontSize: r.fs(17), fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                item.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: pendente ? Colors.white38 : Colors.white,
                  fontSize: r.fs(26),
                  fontWeight: FontWeight.w700,
                  decoration: pendente ? TextDecoration.lineThrough : null,
                  decorationColor: Colors.white54,
                ),
              ),
            ),
            if (pendente)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.7)),
                ),
                child: Row(children: [
                  const Icon(Icons.undo_rounded, color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 6),
                  Text('Desfazer',
                      style: GoogleFonts.poppins(
                          color: Colors.orangeAccent,
                          fontSize: r.fs(15),
                          fontWeight: FontWeight.w700)),
                ]),
              )
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cor.withValues(alpha: 0.12),
                  border: Border.all(color: cor.withValues(alpha: 0.5), width: 2),
                ),
                child: Icon(Icons.check_rounded, color: cor.withValues(alpha: 0.7), size: 24),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaVazia(R r) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [_verde, Color(0xFF18FFFF)]),
            ),
            child: Icon(Icons.check_rounded, color: Colors.black, size: r.icon(52)),
          ),
          const SizedBox(height: 28),
          Text('Tudo comprado!',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: r.fs(32), fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Toque em "Adicionar por voz" ou diga ao Google Assistente:',
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: r.fs(16))),
          const SizedBox(height: 12),
          Text('"Ok Google, adicionar leite na lista Compras"',
              style: GoogleFonts.poppins(
                  color: Colors.white38, fontSize: r.fs(14), fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  final Animation<double> anim;
  _BgPainter(this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = const Color(0xFF04080F);
    canvas.drawRect(Offset.zero & s, p);

    void orb(Offset c, double r, Color cor, double op) {
      p.shader = RadialGradient(colors: [cor.withValues(alpha: op), Colors.transparent])
          .createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, p);
    }

    final wave = math.sin(anim.value * math.pi);
    orb(Offset(s.width * 0.15, s.height * (0.2 + wave * 0.05)), s.width * 0.35,
        _verde, 0.10);
    orb(Offset(s.width * 0.85, s.height * (0.3 - wave * 0.04)), s.width * 0.30,
        const Color(0xFF18FFFF), 0.08);
    orb(Offset(s.width * 0.50, s.height * (0.75 + wave * 0.03)), s.width * 0.28,
        const Color(0xFFFFD740), 0.07);
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.anim != anim;
}
