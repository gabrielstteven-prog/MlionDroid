import 'dart:async';

import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'design/icones.dart';
import 'design/tema.dart';
import 'responsive.dart';
import 'services/google_auth_service.dart';

// ─── MODELOS ──────────────────────────────────────────────────────────────────
enum TipoItem { evento, tarefa }

class ItemAgenda {
  final String id;
  final String listaId;
  final String titulo;
  final String? horario;
  final TipoItem tipo;
  final DateTime? dataHora;
  final bool semData; // tarefa sem data: aparece em "Hoje" como lembrete
  final bool aniversario;
  bool concluido;

  ItemAgenda({
    this.id = '',
    this.listaId = '',
    required this.titulo,
    required this.tipo,
    this.horario,
    this.dataHora,
    this.concluido = false,
    this.semData = false,
    this.aniversario = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'listaId': listaId,
        'titulo': titulo,
        'horario': horario,
        'tipo': tipo == TipoItem.evento ? 'evento' : 'tarefa',
        'dataHora': dataHora?.toIso8601String(),
        'concluido': concluido,
        'semData': semData,
        'aniversario': aniversario,
      };

  factory ItemAgenda.fromJson(Map<String, dynamic> j) => ItemAgenda(
        id: j['id'] as String? ?? '',
        listaId: j['listaId'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        tipo: j['tipo'] == 'evento' ? TipoItem.evento : TipoItem.tarefa,
        horario: j['horario'] as String?,
        dataHora: j['dataHora'] != null
            ? DateTime.tryParse(j['dataHora'] as String)
            : null,
        concluido: j['concluido'] as bool? ?? false,
        semData: j['semData'] as bool? ?? false,
        aniversario: j['aniversario'] as bool? ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
class TelaCalendario extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaCalendario({super.key, required this.aoTerminar});

  @override
  State<TelaCalendario> createState() => _TelaCalendarioState();
}

class _TelaCalendarioState extends State<TelaCalendario>
    with TickerProviderStateMixin {
  final _cfg = ConfigManager();
  // ── DADOS ─────────────────────────────────────────────────────────────────
  final DateTime _hoje = DateTime.now();
  final Map<DateTime, List<ItemAgenda>> _itensPorDia = {};
  List<ItemAgenda> _itensHoje = [];
  List<ItemAgenda> _itensAmanha = [];
  bool _carregando = true;
  bool _semConta = false;
  String _statusMsg = 'Conectando ao Google...';
  DateTime? _atualizadoEm;

  // ── DIA SELECIONADO ───────────────────────────────────────────────────────
  DateTime? _diaSelecionado;
  Timer? _diaTimer;

  // ── AUTH ──────────────────────────────────────────────────────────────────
  http.Client? _client;
  Timer? _antiTravamento;

  // ── CONTROLLERS ───────────────────────────────────────────────────────────
  final ScrollController _scrollHoje = ScrollController();
  final ScrollController _scrollAmanha = ScrollController();
  final ScrollController _scrollDia = ScrollController();
  Timer? _scrollTimer;
  Timer? _saidaTimer;

  // ── ANIMAÇÃO do painel do dia (só ao tocar num dia) ──────────────────────
  late final AnimationController _painelCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  late final Animation<double> _painelAnim =
      CurvedAnimation(parent: _painelCtrl, curve: Curves.easeOutCubic);

  final Set<String> _marcando = {};

  // ── CORES (padrão do app) ─────────────────────────────────────────────────
  static const _corEvento = Destaques.agenda;
  static const _corTarefa = Cores.aviso;
  static const _corAtraso = Cores.alerta;
  static const _corAniversario = Destaques.fotos;

  @override
  void initState() {
    super.initState();
    _autenticarECarregar();
    // Anti-travamento
    _antiTravamento = Timer(const Duration(minutes: 2), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _painelCtrl.dispose();
    _scrollTimer?.cancel();
    _saidaTimer?.cancel();
    _diaTimer?.cancel();
    _scrollHoje.dispose();
    _scrollAmanha.dispose();
    _scrollDia.dispose();
    _antiTravamento?.cancel();
    _client?.close();
    super.dispose();
  }

  // ── AUTH + CARREGAMENTO ───────────────────────────────────────────────────
  static const _chaveCache = 'calendario_itens_v2';

  int get _duracaoSeg =>
      _cfg.getInt('calendario', 'duracao_seg', 35).clamp(10, 300);

  Future<void> _autenticarECarregar() async {
    // Login SILENCIOSO apenas — a janela de escolher conta só abre pelo
    // botão "Conectar conta Google" nas Configurações.
    _client = await GoogleAuthService.instance.cliente();

    // Mostra o que estiver no cache na hora (mesmo vencido), e atualiza
    // por cima se o cache estiver velho.
    final cache = await CacheManager.instance
        .obterEntrada<Map<String, dynamic>>(_chaveCache);
    if (!mounted) return;
    if (cache != null) _aplicarCache(cache);

    final venceu = cache == null ||
        cache.venceu(_cfg.getIntervaloAtualizacao('calendario'));
    if (_client != null && venceu) {
      if (cache == null) {
        setState(() => _statusMsg = 'Carregando agenda do Google...');
      }
      try {
        final novos = <DateTime, List<ItemAgenda>>{};
        await Future.wait([_carregarEventos(novos), _carregarTarefas(novos)]);
        if (!mounted) return;
        _itensPorDia
          ..clear()
          ..addAll(novos);
        _atualizadoEm = DateTime.now();
        await _salvarCache();
      } catch (e) {
        debugPrint('TelaCalendario erro: $e');
        if (cache == null) _statusMsg = 'Falha na conexão com o Google';
      }
    }
    if (!mounted) return;
    setState(() {
      _semConta = _client == null && _itensPorDia.isEmpty;
      _carregando = false;
    });
    _rebuild();
    _iniciarScrolls();
    _iniciarSaida(_itensPorDia.isEmpty ? 10 : _duracaoSeg);
  }

  void _aplicarCache(EntradaCache<Map<String, dynamic>> cache) {
    _itensPorDia.clear();
    cache.dados.forEach((chaveIso, lista) {
      final dia = DateTime.tryParse(chaveIso);
      if (dia == null || lista is! List) return;
      _itensPorDia[dia] = lista
          .map((e) => ItemAgenda.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    });
    _atualizadoEm = cache.salvoEm;
    setState(() => _carregando = false);
    _rebuild();
  }

  Future<void> _salvarCache() async {
    final serializado = <String, dynamic>{};
    _itensPorDia.forEach((dia, lista) {
      serializado[dia.toIso8601String()] =
          lista.map((i) => i.toJson()).toList();
    });
    await CacheManager.instance.salvar(_chaveCache, serializado);
  }

  void _adicionar(
      Map<DateTime, List<ItemAgenda>> mapa, DateTime dia, ItemAgenda item) {
    (mapa[_chave(dia)] ??= []).add(item);
  }

  Future<void> _carregarEventos(Map<DateTime, List<ItemAgenda>> mapa) async {
    final api = cal.CalendarApi(_client!);
    // Mês atual + mês seguinte: no último dia do mês, "Amanhã" já é o mês
    // seguinte (antes essa lista ficava vazia).
    final inicio = DateTime(_hoje.year, _hoje.month, 1);
    final fim = DateTime(_hoje.year, _hoje.month + 2, 0, 23, 59);
    final res = await api.events.list('primary',
        timeMin: inicio.toUtc(),
        timeMax: fim.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 250);

    for (final ev in res.items ?? <cal.Event>[]) {
      final dt = ev.start?.dateTime ?? ev.start?.date;
      if (dt == null) continue;
      final local = ev.start?.dateTime != null ? dt.toLocal() : dt;
      _adicionar(
          mapa,
          local,
          ItemAgenda(
            id: ev.id ?? '',
            titulo: ev.summary ?? 'Sem título',
            tipo: TipoItem.evento,
            aniversario: ev.eventType == 'birthday',
            horario: ev.start?.dateTime != null
                ? DateFormat('HH:mm').format(local)
                : null,
            dataHora: local,
          ));
    }
  }

  Future<void> _carregarTarefas(Map<DateTime, List<ItemAgenda>> mapa) async {
    final api = tasks.TasksApi(_client!);
    final listas = await api.tasklists.list();

    for (final lista in listas.items ?? <tasks.TaskList>[]) {
      if (lista.id == null) continue;
      // Listas de compras aparecem na tela de Compras, não aqui.
      if (ehListaDeCompras(lista.title ?? '')) continue;

      // Uma chamada só, com pendentes e concluídas (antes eram duas).
      final tl = await api.tasks.list(lista.id!,
          showCompleted: true, showHidden: false, maxResults: 100);
      for (final t in tl.items ?? <tasks.Task>[]) {
        final concluida = t.status == 'completed';
        DateTime? due;
        if (t.due != null) {
          // 'due' do Google Tasks é sempre meia-noite UTC: usa só a data,
          // sem converter fuso (converter mudaria o dia).
          final parsed = DateTime.tryParse(t.due!)?.toUtc();
          if (parsed != null) {
            due = DateTime(parsed.year, parsed.month, parsed.day);
          }
        }
        if (due == null && concluida) continue;
        _adicionar(
            mapa,
            due ?? _hoje,
            ItemAgenda(
              id: t.id ?? '',
              listaId: lista.id!,
              titulo: t.title ?? 'Tarefa sem título',
              tipo: TipoItem.tarefa,
              dataHora: due,
              concluido: concluida,
              semData: due == null,
            ));
      }
    }
  }

  void _rebuild() {
    final amanha = _hoje.add(const Duration(days: 1));
    _itensHoje = _sort(_itensPorDia[_chave(_hoje)] ?? []);
    _itensAmanha = _sort(_itensPorDia[_chave(amanha)] ?? []);
    if (mounted) setState(() {});
  }

  List<ItemAgenda> _sort(List<ItemAgenda> l) {
    final c = List<ItemAgenda>.from(l)
      ..sort((a, b) {
        if (a.concluido != b.concluido) return a.concluido ? 1 : -1;
        if (a.dataHora != null && b.dataHora != null) {
          return a.dataHora!.compareTo(b.dataHora!);
        }
        if (a.dataHora != null) return -1;
        if (b.dataHora != null) return 1;
        return 0;
      });
    return c;
  }

  DateTime _chave(DateTime d) => DateTime(d.year, d.month, d.day);

  // ── TOQUE NO DIA ──────────────────────────────────────────────────────────
  void _tocarNoDia(DateTime dia) {
    final itens = _itensPorDia[_chave(dia)] ?? [];
    if (itens.isEmpty) {
      if (_diaSelecionado != null) _fecharPainelDia();
      return;
    }
    _saidaTimer?.cancel();
    setState(() => _diaSelecionado = _chave(dia));
    _painelCtrl.forward(from: 0);
    _diaTimer?.cancel();
    _diaTimer = Timer(const Duration(seconds: 20), _fecharPainelDia);
  }

  void _fecharPainelDia() {
    _diaTimer?.cancel();
    _painelCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _diaSelecionado = null);
      _iniciarSaida(15);
    });
  }

  Future<void> _alternarTarefa(ItemAgenda item) async {
    if (_client == null || item.id.isEmpty) return;
    if (_marcando.contains(item.id)) return;
    _saidaTimer?.cancel();
    setState(() => _marcando.add(item.id));
    try {
      final api = tasks.TasksApi(_client!);
      final taskAtual = await api.tasks.get(item.listaId, item.id);
      final novoConcluido = !item.concluido;
      taskAtual.status = novoConcluido ? 'completed' : 'needsAction';
      if (!novoConcluido) taskAtual.completed = null;
      await api.tasks.update(taskAtual, item.listaId, item.id);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        setState(() {
          item.concluido = novoConcluido;
          _marcando.remove(item.id);
          if (_diaSelecionado != null) {
            final chave = _chave(_diaSelecionado!);
            _itensPorDia[chave] = _sort(_itensPorDia[chave] ?? []);
          }
          _rebuild();
        });
        await _salvarCache();
      }
    } catch (e) {
      debugPrint('alternarTarefa erro: $e');
      if (mounted) setState(() => _marcando.remove(item.id));
    } finally {
      _iniciarSaida(20);
    }
  }

  bool _temTarefaAtrasada(DateTime dia) {
    final chave = _chave(dia);
    if (!chave.isBefore(_chave(_hoje))) return false;
    return (_itensPorDia[chave] ?? [])
        .any((i) => i.tipo == TipoItem.tarefa && !i.concluido);
  }

  void _iniciarScrolls() {
    _scrollTimer = Timer(const Duration(seconds: 3), () async {
      if (_diaSelecionado != null) return;
      await _scrollLista(_scrollHoje);
      if (!mounted || _diaSelecionado != null) return;
      await Future.delayed(const Duration(seconds: 1));
      await _scrollLista(_scrollAmanha);
    });
  }

  Future<void> _scrollLista(ScrollController c) async {
    if (!mounted || !c.hasClients) return;
    final max = c.position.maxScrollExtent;
    if (max <= 10) return;
    await c.animateTo(max,
        duration: Duration(milliseconds: (max * 40).toInt()),
        curve: Curves.linear);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await c.animateTo(0,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
  }

  void _iniciarSaida(int seg) {
    _saidaTimer?.cancel();
    _saidaTimer = Timer(Duration(seconds: seg), () {
      if (!mounted) return;
      if (_diaSelecionado != null) {
        _fecharPainelDia();
        return;
      }
      widget.aoTerminar();
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return EstruturaTela(
      icone: Icons.calendar_month_rounded,
      marca: IconeGoogleAgenda(tamanho: r.sp(52), dia: _hoje.day),
      titulo: 'Google Agenda',
      subtitulo: DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_hoje),
      destaque: _corEvento,
      rodapeDireita: _atualizadoEm != null
          ? 'Atualizado ${descreverIdade(_atualizadoEm!)}'
          : null,
      child: _semConta
          ? const AvisoTela(
              icone: Icons.account_circle_outlined,
              titulo: 'Conta Google não conectada',
              texto:
                  'Abra Configurações › Calendário e toque em "Conectar conta Google".',
              cor: _corEvento,
            )
          : _carregando
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const Expanded(child: Carregando(cor: _corEvento)),
                  Text(_statusMsg, style: Tipo(r).apoio()),
                ])
              : r.useSideBySide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 11, child: _buildCalendario(r)),
                        SizedBox(width: r.sp(32)),
                        Expanded(flex: 9, child: _buildDireita(r)),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(flex: 5, child: _buildCalendario(r)),
                        SizedBox(height: r.sp(16)),
                        Expanded(flex: 4, child: _buildDireita(r)),
                      ],
                    ),
    );
  }

  Widget _buildDireita(R r) {
    if (_diaSelecionado != null) {
      return FadeTransition(
        opacity: _painelAnim,
        child: _buildPainelDia(_diaSelecionado!, r),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
            child: _buildLista(
                titulo: 'Hoje', itens: _itensHoje, ctrl: _scrollHoje, r: r)),
        SizedBox(height: r.sp(20)),
        Expanded(
            child: _buildLista(
                titulo: 'Amanhã',
                itens: _itensAmanha,
                ctrl: _scrollAmanha,
                r: r)),
      ],
    );
  }

  // ── CALENDÁRIO DO MÊS ─────────────────────────────────────────────────────
  Widget _buildCalendario(R r) {
    final t = Tipo(r);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        // Respiro entre o título "Google Agenda" e o calendário.
        padding: EdgeInsets.only(top: r.sp(20)),
        child: Superficie(
          padding: EdgeInsets.fromLTRB(r.sp(16), r.sp(16), r.sp(16), r.sp(8)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                      _capitalizar(
                          DateFormat('MMMM yyyy', 'pt_BR').format(_hoje)),
                      style: t.subtitulo()),
                  const Spacer(),
                  _legenda(_corEvento, 'Evento', r),
                  SizedBox(width: r.sp(14)),
                  _legenda(_corTarefa, 'Tarefa', r),
                  SizedBox(width: r.sp(14)),
                  _legenda(_corAtraso, 'Atrasada', r),
                  SizedBox(width: r.sp(14)),
                  _legenda(_corAniversario, 'Aniversário', r),
                ],
              ),
              SizedBox(height: r.sp(8)),
              TableCalendar(
                locale: 'pt_BR',
                focusedDay: _diaSelecionado ?? _hoje,
                firstDay: DateTime.utc(2020),
                lastDay: DateTime.utc(2035),
                // Linhas compactas: o círculo já diz tudo, sem sobra de espaço.
                rowHeight: r.sp(80),
                daysOfWeekHeight: r.sp(32),
                headerVisible: false,
                availableGestures: AvailableGestures.none,
                selectedDayPredicate: (d) =>
                    _diaSelecionado != null &&
                    _chave(d) == _chave(_diaSelecionado!),
                onDaySelected: (sel, _) => _tocarNoDia(sel),
                eventLoader: (d) => _itensPorDia[_chave(d)] ?? [],
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: t.legenda(),
                  weekendStyle: t.legenda(),
                ),
                calendarStyle: const CalendarStyle(
                  outsideDaysVisible: false,
                  markersMaxCount: 0,
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (_, d, __) => _diaCell(d, false, false, r),
                  todayBuilder: (_, d, __) => _diaCell(d, true, false, r),
                  selectedBuilder: (_, d, __) =>
                      _diaCell(d, _chave(d) == _chave(_hoje), true, r),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalizar(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Um círculo por dia, sem pontinhos: a COR do círculo é a situação.
  /// Hoje = círculo cheio branco; atrasada > tarefa > evento > aniversário
  /// = anel na cor da legenda (com fundo leve).
  Widget _diaCell(DateTime day, bool isHoje, bool isSel, R r) {
    final t = Tipo(r);
    final itens = _itensPorDia[_chave(day)] ?? const <ItemAgenda>[];
    final Color? situacao = _temTarefaAtrasada(day)
        ? _corAtraso
        : itens.any((i) => i.tipo == TipoItem.tarefa && !i.concluido)
            ? _corTarefa
            : itens.any((i) => i.tipo == TipoItem.evento && !i.aniversario)
                ? _corEvento
                : itens.any((i) => i.aniversario)
                    ? _corAniversario
                    : null;

    final diametro = r.sp(60);
    return Center(
      child: Container(
        width: diametro,
        height: diametro,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isHoje ? Cores.texto : situacao?.withValues(alpha: 0.22),
          border: isHoje
              ? (situacao != null
                  ? Border.all(color: situacao, width: 3.5)
                  : null)
              : situacao != null
                  ? Border.all(color: situacao, width: 2.5)
                  : isSel
                      ? Border.all(color: Cores.texto, width: 2)
                      : null,
        ),
        child: Text('${day.day}',
            style: t
                .subtitulo(cor: isHoje ? Colors.black : Cores.texto)
                .copyWith(
                    fontWeight: isHoje || situacao != null
                        ? FontWeight.w800
                        : FontWeight.w500)),
      ),
    );
  }

  Widget _ponto(Color cor, R r) => Container(
        width: r.sp(6),
        height: r.sp(6),
        margin: EdgeInsets.symmetric(horizontal: r.sp(1.5)),
        decoration: BoxDecoration(shape: BoxShape.circle, color: cor),
      );

  Widget _legenda(Color cor, String texto, R r) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ponto(cor, r),
          SizedBox(width: r.sp(6)),
          Text(texto, style: Tipo(r).legenda()),
        ],
      );

  // ── LISTAS HOJE / AMANHÃ ──────────────────────────────────────────────────
  Widget _buildLista({
    required String titulo,
    required List<ItemAgenda> itens,
    required ScrollController ctrl,
    required R r,
  }) {
    final t = Tipo(r);
    final pend = itens.where((i) => !i.concluido).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(titulo, style: t.subtitulo()),
          SizedBox(width: r.sp(10)),
          if (pend.isNotEmpty)
            Text(pend.length == 1 ? '1 item' : '${pend.length} itens',
                style: t.apoio()),
        ]),
        SizedBox(height: r.sp(10)),
        Expanded(
          child: pend.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text('Nada marcado.', style: t.apoio()),
                )
              : ListView.builder(
                  controller: ctrl,
                  padding: EdgeInsets.zero,
                  itemCount: pend.length,
                  itemBuilder: (_, i) => _itemLinha(pend[i], r),
                ),
        ),
      ],
    );
  }

  // ── PAINEL DO DIA SELECIONADO ─────────────────────────────────────────────
  Widget _buildPainelDia(DateTime dia, R r) {
    final t = Tipo(r);
    final itens = _sort(_itensPorDia[_chave(dia)] ?? []);
    final pend = itens.where((i) => !i.concluido).toList();
    final conc = itens.where((i) => i.concluido).toList();
    final atrasado = _chave(dia).isBefore(_chave(_hoje)) && pend.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(
                _capitalizar(
                    DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(dia)),
                style: t.subtitulo(cor: atrasado ? _corAtraso : Cores.texto)),
          ),
          IconButton(
            onPressed: _fecharPainelDia,
            icon: Icon(Icons.close_rounded,
                color: Cores.textoSecundario, size: r.icon(28)),
          ),
        ]),
        if (atrasado)
          Text('${pend.length} tarefa(s) atrasada(s)',
              style: t.apoio(cor: _corAtraso)),
        SizedBox(height: r.sp(10)),
        Expanded(
          child: ListView(
            controller: _scrollDia,
            padding: EdgeInsets.zero,
            children: [
              ...pend.map((i) => _itemLinha(i, r)),
              if (conc.isNotEmpty) ...[
                SizedBox(height: r.sp(12)),
                Text('Concluídos', style: t.legenda()),
                SizedBox(height: r.sp(6)),
                ...conc.map((i) => _itemLinha(i, r)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Uma linha de compromisso. Tarefas: tocar marca/desmarca.
  Widget _itemLinha(ItemAgenda item, R r) {
    final t = Tipo(r);
    final isEv = item.tipo == TipoItem.evento;
    final cor =
        item.aniversario ? _corAniversario : (isEv ? _corEvento : _corTarefa);
    final marcando = _marcando.contains(item.id);
    final icone = item.aniversario
        ? Icons.cake_rounded
        : isEv
            ? Icons.event_rounded
            : (item.concluido
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isEv ? null : () => _alternarTarefa(item),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: r.sp(8)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: r.sp(36),
              child: marcando
                  ? SizedBox(
                      width: r.icon(24),
                      height: r.icon(24),
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: cor))
                  : Icon(icone,
                      color: item.concluido ? Cores.textoApagado : cor,
                      size: r.icon(26)),
            ),
            SizedBox(width: r.sp(8)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t
                        .corpo(
                          cor:
                              item.concluido ? Cores.textoApagado : Cores.texto,
                          peso: FontWeight.w600,
                        )
                        .copyWith(
                            decoration: item.concluido
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: Cores.textoApagado),
                  ),
                  if (item.horario != null || item.semData)
                    Text(
                      item.horario ?? 'Sem data definida',
                      style: t.apoio(
                          cor: item.horario != null ? cor : Cores.textoApagado),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
