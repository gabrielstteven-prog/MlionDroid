import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'config_manager.dart';
import 'cache_manager.dart';
import 'responsive.dart';
import 'performance_manager.dart';

// ─── MODELOS ──────────────────────────────────────────────────────────────────
enum TipoItem { evento, tarefa }

class ItemAgenda {
  final String id;
  final String listaId;
  final String titulo;
  final String? horario;
  final TipoItem tipo;
  final DateTime? dataHora;
  bool concluido;

  ItemAgenda({
    this.id = '',
    this.listaId = '',
    required this.titulo,
    required this.tipo,
    this.horario,
    this.dataHora,
    this.concluido = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'listaId': listaId,
        'titulo': titulo,
        'horario': horario,
        'tipo': tipo == TipoItem.evento ? 'evento' : 'tarefa',
        'dataHora': dataHora?.toIso8601String(),
        'concluido': concluido,
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
      );
}

// ─── CLIENTE HTTP ─────────────────────────────────────────────────────────────
class _AuthClient extends http.BaseClient {
  final Map<String, String> _h;
  final http.Client _inner = http.Client();
  _AuthClient(this._h);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) {
    r.headers.addAll(_h);
    return _inner.send(r);
  }
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
  String _statusMsg = 'Conectando ao Google...';

  // ── LISTAS DE COMPRAS — ignoradas no calendário ───────────────────────────
  static const _nomesCompras = [
    'compras',
    'compra',
    'lista de compras',
    'shopping',
    'shopping list',
    'mercado',
    'supermercado',
  ];

  // ── DIA SELECIONADO ───────────────────────────────────────────────────────
  DateTime? _diaSelecionado;
  Timer? _diaTimer;

  // ── AUTH ──────────────────────────────────────────────────────────────────
  _AuthClient? _client;
  final _googleSignIn = GoogleSignIn(scopes: [
    cal.CalendarApi.calendarReadonlyScope,
    tasks.TasksApi.tasksScope,
  ]);

  // ── CONTROLLERS ───────────────────────────────────────────────────────────
  final ScrollController _scrollHoje = ScrollController();
  final ScrollController _scrollAmanha = ScrollController();
  final ScrollController _scrollDia = ScrollController();
  Timer? _scrollTimer;
  Timer? _saidaTimer;

  // ── ANIMAÇÕES ─────────────────────────────────────────────────────────────
  late AnimationController _auroraCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _entradaCtrl;
  late Animation<double> _entradaAnim;
  late AnimationController _painelCtrl;
  late Animation<double> _painelAnim;

  final Set<String> _marcando = {};

  // ── CORES ─────────────────────────────────────────────────────────────────
  static const _verde = Color(0xFF00E676);
  static const _ciano = Color(0xFF18FFFF);
  static const _amarelo = Color(0xFFFFD740);
  static const _vermelho = Color(0xFFFF5252);
  static const _roxo = Color(0xFFE040FB);
  static const _rosa = Color(0xFFFF4081);

  @override
  void initState() {
    super.initState();

    _auroraCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 8));

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Aurora de fundo e pulso são decorativos — só em loop no modo completo.
    if (!PerformanceManager.instance.modoEconomico) {
      _auroraCtrl.repeat(reverse: true);
      _pulseCtrl.repeat(reverse: true);
    }

    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _entradaAnim =
        CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOutCubic);
    _entradaCtrl.forward();

    _painelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _painelAnim =
        CurvedAnimation(parent: _painelCtrl, curve: Curves.easeOutCubic);

    _autenticarECarregar();

    // Anti-travamento
    Timer(const Duration(minutes: 2), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _auroraCtrl.dispose();
    _pulseCtrl.dispose();
    _entradaCtrl.dispose();
    _painelCtrl.dispose();
    _scrollTimer?.cancel();
    _saidaTimer?.cancel();
    _diaTimer?.cancel();
    _scrollHoje.dispose();
    _scrollAmanha.dispose();
    _scrollDia.dispose();
    super.dispose();
  }

  // ── AUTH + CARREGAMENTO ───────────────────────────────────────────────────
  static const _chaveCache = 'calendario_itens';

  Future<void> _autenticarECarregar() async {
    try {
      setState(() => _statusMsg = 'Autenticando...');
      final conta =
          await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (conta == null) {
        setState(() {
          _carregando = false;
          _statusMsg = 'Login cancelado';
        });
        _iniciarSaida(10);
        return;
      }
      // Mantém o _client sempre pronto, mesmo em cache hit — é ele que
      // permite marcar tarefa como concluída direto na tela.
      _client = _AuthClient(await conta.authHeaders);

      // Tenta usar o cache antes de fazer as buscas pesadas (evento + tarefas
      // de cada lista). Isso é o que normalmente demora nessa tela.
      final cache = await CacheManager.instance.obter<Map<String, dynamic>>(
        _chaveCache,
        validade: _cfg.getIntervaloAtualizacao('calendario'),
      );
      if (cache != null && mounted) {
        _itensPorDia.clear();
        cache.forEach((chaveIso, lista) {
          final dia = DateTime.parse(chaveIso);
          _itensPorDia[dia] = (lista as List)
              .map((e) => ItemAgenda.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        });
        setState(() => _carregando = false);
        _rebuild();
        _iniciarScrolls();
        _iniciarSaida(35);
        return;
      }

      setState(() => _statusMsg = 'Carregando agenda do Google...');
      await Future.wait([_carregarEventos(), _carregarTarefas()]);
      setState(() => _carregando = false);
      _iniciarScrolls();
      _iniciarSaida(35);
      await _salvarCache();
    } catch (e) {
      debugPrint('TelaCalendario erro: $e');
      setState(() {
        _carregando = false;
        _statusMsg = 'Falha na conexão';
      });
      _iniciarSaida(8);
    }
  }

  Future<void> _salvarCache() async {
    final serializado = <String, dynamic>{};
    _itensPorDia.forEach((dia, lista) {
      serializado[dia.toIso8601String()] =
          lista.map((i) => i.toJson()).toList();
    });
    await CacheManager.instance.salvar(_chaveCache, serializado);
  }

  Future<void> _carregarEventos() async {
    if (_client == null) return;
    final api = cal.CalendarApi(_client!);
    final inicio = DateTime(_hoje.year, _hoje.month, 1);
    final fim = DateTime(_hoje.year, _hoje.month + 1, 0, 23, 59);
    final res = await api.events.list('primary',
        timeMin: inicio.toUtc(),
        timeMax: fim.toUtc(),
        singleEvents: true,
        orderBy: 'startTime');

    for (final ev in res.items ?? []) {
      final dt = ev.start?.dateTime ?? ev.start?.date;
      if (dt == null) continue;
      final chave = _chave(dt);
      _itensPorDia[chave] ??= [];
      _itensPorDia[chave]!.add(ItemAgenda(
        titulo: ev.summary ?? 'Sem título',
        tipo: TipoItem.evento,
        horario: ev.start?.dateTime != null
            ? DateFormat('HH:mm').format(ev.start!.dateTime!.toLocal())
            : null,
        dataHora: dt.toLocal(),
      ));
    }
    _rebuild();
  }

  Future<void> _carregarTarefas() async {
    if (_client == null) return;
    final api = tasks.TasksApi(_client!);
    final listas = await api.tasklists.list();

    for (final lista in listas.items ?? []) {
      if (lista.id == null) continue;

      // ── IGNORA listas de compras ──────────────────────────────────────────
      final nomeMin = (lista.title ?? '').toLowerCase().trim();
      if (_nomesCompras.any((n) => nomeMin.contains(n))) {
        debugPrint('Calendário: ignorando lista de compras "${lista.title}"');
        continue;
      }

      // Pendentes
      final tl = await api.tasks
          .list(lista.id!, showCompleted: false, showHidden: false);
      for (final t in tl.items ?? []) {
        if (t.status == 'completed') continue;
        DateTime? due;
        try {
          if (t.due != null) {
            // O campo 'due' do Google Tasks é sempre meia-noite UTC.
            // NÃO convertemos para local pois isso muda o dia.
            // Usamos apenas a data (ano, mês, dia) diretamente do UTC.
            final parsed = DateTime.parse(t.due!).toUtc();
            due = DateTime(parsed.year, parsed.month, parsed.day);
          }
        } catch (_) {}
        final chave = due != null ? _chave(due) : _chave(_hoje);
        _itensPorDia[chave] ??= [];
        _itensPorDia[chave]!.add(ItemAgenda(
          id: t.id ?? '',
          listaId: lista.id!,
          titulo: t.title ?? 'Tarefa sem título',
          tipo: TipoItem.tarefa,
          dataHora: due,
        ));
      }

      // Concluídos (para painel do dia)
      final tlC = await api.tasks
          .list(lista.id!, showCompleted: true, showHidden: false);
      for (final t in tlC.items ?? []) {
        if (t.status != 'completed') continue;
        DateTime? due;
        try {
          if (t.due != null) {
            // Mesma correção: usa só a data UTC sem converter timezone
            final parsed = DateTime.parse(t.due!).toUtc();
            due = DateTime(parsed.year, parsed.month, parsed.day);
          }
        } catch (_) {}
        if (due == null) continue;
        final chave = _chave(due);
        _itensPorDia[chave] ??= [];
        final jaExiste = _itensPorDia[chave]!
            .any((i) => i.id == (t.id ?? '') && i.id.isNotEmpty);
        if (!jaExiste) {
          _itensPorDia[chave]!.add(ItemAgenda(
            id: t.id ?? '',
            listaId: lista.id!,
            titulo: t.title ?? 'Tarefa sem título',
            tipo: TipoItem.tarefa,
            dataHora: due,
            concluido: true,
          ));
        }
      }
    }
    _rebuild();
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildAurora()),
          Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.28))),
          FadeTransition(
            opacity: _entradaAnim,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _carregando ? _buildCarregando(r) : _buildLayout(r),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAurora() {
    return AnimatedBuilder(
      animation: _auroraCtrl,
      builder: (_, __) => CustomPaint(
        painter: _AuroraPainter(_auroraCtrl.value),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildCarregando(R r) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                    colors: [_ciano, _roxo, _verde, _ciano]),
                boxShadow: [
                  BoxShadow(
                      color: _ciano.withValues(alpha: _pulseAnim.value * 0.6),
                      blurRadius: 24,
                      spreadRadius: 4)
                ],
              ),
              child: Icon(Icons.calendar_month_rounded,
                  color: Colors.white, size: r.icon(40)),
            ),
          ),
          const SizedBox(height: 20),
          Text(_statusMsg,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 18)),
        ],
      ),
    );
  }

  // ── LAYOUT: esquerda calendário, direita compromissos ─────────────────────
  Widget _buildLayout(R r) {
    if (!r.useSideBySide) {
      return Column(
        children: [
          SizedBox(
            height: r.isCompact ? r.h(0.42) : r.h(0.46),
            child: _buildCalendario(r),
          ),
          const SizedBox(height: 10),
          Expanded(child: _buildColunasDireita(r)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 54,
          child: _buildCalendario(r),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 46,
          child: _buildColunasDireita(r),
        ),
      ],
    );
  }

  Widget _buildColunasDireita(R r) {
    if (_diaSelecionado != null) {
      return FadeTransition(
        opacity: _painelAnim,
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
                  .animate(_painelAnim),
          child: _buildPainelDia(_diaSelecionado!, r),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
            child: _buildLista(
          titulo: 'Compromissos de Hoje',
          subtitulo: DateFormat("dd 'de' MMMM", 'pt_BR').format(_hoje),
          itens: _itensHoje,
          cor: _verde,
          ctrl: _scrollHoje,
          r: r,
        )),
        const SizedBox(height: 12),
        Expanded(
            child: _buildLista(
          titulo: 'Compromissos de Amanhã',
          subtitulo: DateFormat("dd 'de' MMMM", 'pt_BR')
              .format(_hoje.add(const Duration(days: 1))),
          itens: _itensAmanha,
          cor: _ciano,
          ctrl: _scrollAmanha,
          r: r,
        )),
      ],
    );
  }

  // ── CALENDÁRIO ────────────────────────────────────────────────────────────
  Widget _buildCalendario(R r) {
    return _card(
      gradient: LinearGradient(colors: [
        Colors.white.withValues(alpha: 0.13),
        Colors.white.withValues(alpha: 0.05),
      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        children: [
          // ── Topo: Calendário do Google ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ícone colorido do Google Calendar
                Image.asset(
                  'assets/icons/Gemini_Generated_Image_tl4qrktl4qrktl4q.png',
                  width: r.fs(60),
                  height: r.fs(60),
                  errorBuilder: (_, __, ___) => _googleCalIcon(r.fs(34)),
                ),
                const SizedBox(width: 10),
                Text(
                  'Calendário do Google',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: r.fs(18),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // ── Divider sutil ─────────────────────────────────────────────
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.18),
                Colors.transparent,
              ]),
            ),
          ),

          // Header (mês + legendas)
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                decoration: BoxDecoration(
                  gradient:
                      const LinearGradient(colors: [_ciano, Color(0xFF448AFF)]),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                        color: _ciano.withValues(alpha: 0.5), blurRadius: 16)
                  ],
                ),
                child: Text(
                  DateFormat('MMMM  yyyy', 'pt_BR').format(_hoje).toUpperCase(),
                  style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: r.fs(17),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2),
                ),
              ),
              const Spacer(),
              _legenda(_verde, 'Evento', r, fontSize: r.fs(14)),
              const SizedBox(width: 12),
              _legenda(_amarelo, 'Tarefa', r, fontSize: r.fs(14)),
              const SizedBox(width: 12),
              _legenda(_vermelho, 'Atrasado', r, fontSize: r.fs(14)),
            ],
          ),
          const SizedBox(height: 10),

          // Calendário
          Expanded(
            child: TableCalendar(
              locale: 'pt_BR',
              focusedDay: _diaSelecionado ?? _hoje,
              firstDay: DateTime.utc(2020),
              lastDay: DateTime.utc(2035),
              rowHeight: r.isCompact ? 52 : 66,
              daysOfWeekHeight: r.isCompact ? 32 : 40,
              headerVisible: false,
              selectedDayPredicate: (d) =>
                  _diaSelecionado != null &&
                  _chave(d) == _chave(_diaSelecionado!),
              onDaySelected: (sel, _) => _tocarNoDia(sel),
              eventLoader: (d) => _itensPorDia[_chave(d)] ?? [],
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: r.fs(14),
                    fontWeight: FontWeight.w700),
                weekendStyle: GoogleFonts.poppins(
                    color: _rosa.withValues(alpha: 0.9),
                    fontSize: r.fs(14),
                    fontWeight: FontWeight.w700),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                defaultTextStyle: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: r.fs(17),
                    fontWeight: FontWeight.w600),
                weekendTextStyle: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: r.fs(17),
                    fontWeight: FontWeight.w600),
                todayDecoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_ciano, Color(0xFF448AFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: _ciano.withValues(alpha: 0.65),
                        blurRadius: 18,
                        spreadRadius: 2)
                  ],
                ),
                todayTextStyle: GoogleFonts.poppins(
                    color: Colors.black,
                    fontSize: r.fs(17),
                    fontWeight: FontWeight.w900),
                selectedDecoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                selectedTextStyle: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: r.fs(17),
                    fontWeight: FontWeight.w800),
                markersMaxCount: 0,
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (_, d, __) => _diaCell(d, false, false, r),
                todayBuilder: (_, d, __) => _diaCell(d, true, false, r),
                selectedBuilder: (_, d, __) => _diaCell(d, false, true, r),
                markerBuilder: (_, day, __) {
                  final itens = _itensPorDia[_chave(day)] ?? [];
                  if (itens.isEmpty) return const SizedBox.shrink();
                  final temEv = itens.any((i) => i.tipo == TipoItem.evento);
                  final temTa = itens
                      .any((i) => i.tipo == TipoItem.tarefa && !i.concluido);
                  final atr = _temTarefaAtrasada(day);
                  return Positioned(
                    bottom: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (temEv) _dot(_verde, 9),
                        if (temEv && (temTa || atr)) const SizedBox(width: 4),
                        if (temTa && !atr) _dot(_amarelo, 9),
                        if (atr) _dot(_vermelho, 9),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.touch_app_rounded,
                    size: 13, color: Colors.white38),
                const SizedBox(width: 6),
                Text('Toque num dia para ver detalhes',
                    style: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _diaCell(DateTime day, bool isHoje, bool isSel, R r) {
    final atrasado = _temTarefaAtrasada(day);
    final sel = isSel ||
        (_diaSelecionado != null && _chave(day) == _chave(_diaSelecionado!));

    BoxDecoration? deco;
    Color tc = Colors.white;
    FontWeight fw = FontWeight.w600;

    if (isHoje) {
      deco = BoxDecoration(
        gradient: const LinearGradient(
            colors: [_ciano, Color(0xFF448AFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: _ciano.withValues(alpha: 0.65),
              blurRadius: 18,
              spreadRadius: 2)
        ],
      );
      tc = Colors.black;
      fw = FontWeight.w900;
    } else if (atrasado) {
      deco = BoxDecoration(
        color: _vermelho.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _vermelho.withValues(alpha: 0.7), width: 1.5),
      );
      tc = _vermelho;
      fw = FontWeight.w800;
    } else if (sel) {
      deco = BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 2),
      );
      fw = FontWeight.w800;
    }

    return Container(
      margin: const EdgeInsets.all(3),
      decoration: deco,
      child: Center(
          child: Text('${day.day}',
              style: GoogleFonts.poppins(
                  color: tc, fontSize: r.fs(17), fontWeight: fw))),
    );
  }

  // ── PAINEL DO DIA SELECIONADO ─────────────────────────────────────────────
  Widget _buildPainelDia(DateTime dia, R r) {
    final itens = _sort(_itensPorDia[_chave(dia)] ?? []);
    final pend = itens.where((i) => !i.concluido).toList();
    final conc = itens.where((i) => i.concluido).toList();
    final isPassado = _chave(dia).isBefore(_chave(_hoje));
    final isHoje = _chave(dia) == _chave(_hoje);
    final cor = isPassado && pend.isNotEmpty
        ? _vermelho
        : isHoje
            ? _verde
            : _ciano;

    return _card(
      gradient: LinearGradient(colors: [
        cor.withValues(alpha: 0.2),
        Colors.white.withValues(alpha: 0.05)
      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _painelHeader(dia, cor, pend.length, isPassado, r),
          Expanded(
            child: itens.isEmpty
                ? Center(
                    child: Text('Nenhum item',
                        style: GoogleFonts.poppins(
                            color: Colors.white38, fontSize: 16)))
                : ListView(
                    controller: _scrollDia,
                    padding: const EdgeInsets.all(14),
                    children: [
                      if (pend.isNotEmpty) ...[
                        _secao('PENDENTES', cor, r),
                        ...pend.map((i) => _itemCard(i, cor, r)),
                      ],
                      if (conc.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _secao('CONCLUÍDOS', Colors.white38, r),
                        ...conc.map((i) => _itemCard(i, Colors.white38, r)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _painelHeader(
      DateTime dia, Color cor, int numPend, bool isPassado, R r) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [cor.withValues(alpha: 0.28), Colors.transparent],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(bottom: BorderSide(color: cor.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 24,
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(color: cor.withValues(alpha: 0.8), blurRadius: 12)
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat("dd 'de' MMMM", 'pt_BR').format(dia).toUpperCase(),
                  style: GoogleFonts.poppins(
                      color: cor,
                      fontSize: r.fs(16),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8),
                ),
                if (isPassado && numPend > 0)
                  Text('⚠️ $numPend tarefa(s) atrasada(s)',
                      style: GoogleFonts.poppins(
                          color: _vermelho.withValues(alpha: 0.9),
                          fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _fecharPainelDia,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.close_rounded,
                  color: Colors.white70, size: r.icon(17)),
            ),
          ),
        ],
      ),
    );
  }

  // ── LISTA HOJE / AMANHÃ ───────────────────────────────────────────────────
  Widget _buildLista({
    required String titulo,
    required String subtitulo,
    required List<ItemAgenda> itens,
    required Color cor,
    required ScrollController ctrl,
    required R r,
  }) {
    final pend = itens.where((i) => !i.concluido).toList();

    return _card(
      gradient: LinearGradient(colors: [
        cor.withValues(alpha: 0.18),
        Colors.white.withValues(alpha: 0.05)
      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [cor.withValues(alpha: 0.28), Colors.transparent],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                  bottom: BorderSide(color: cor.withValues(alpha: 0.28))),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 22,
                  decoration: BoxDecoration(
                    color: cor,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                          color: cor.withValues(alpha: 0.8), blurRadius: 10)
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: GoogleFonts.poppins(
                              color: cor,
                              fontSize: r.fs(18),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1)),
                      Text(subtitulo,
                          style: GoogleFonts.poppins(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cor.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                          color: cor.withValues(alpha: 0.3), blurRadius: 8)
                    ],
                  ),
                  child: Text('${pend.length}',
                      style: GoogleFonts.poppins(
                          color: cor,
                          fontSize: r.fs(17),
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
          // Itens
          Expanded(
            child: pend.isEmpty
                ? Center(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: cor.withValues(alpha: 0.4), size: r.icon(44)),
                      const SizedBox(height: 8),
                      Text('Nada pendente',
                          style: GoogleFonts.poppins(
                              color: Colors.white38, fontSize: 15)),
                    ],
                  ))
                : ListView.builder(
                    controller: ctrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: pend.length,
                    itemBuilder: (_, i) => _itemCard(pend[i], cor, r),
                  ),
          ),
        ],
      ),
    );
  }

  // ── CARD DE ITEM — FONTE GRANDE E VISÍVEL ─────────────────────────────────
  Widget _itemCard(ItemAgenda item, Color corTema, R r) {
    final isEv = item.tipo == TipoItem.evento;
    final marc = _marcando.contains(item.id);
    final conc = item.concluido;
    final corItem = isEv ? _verde : _amarelo;

    return GestureDetector(
      onTap: isEv ? null : () => _alternarTarefa(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: conc
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: conc
                ? Colors.white.withValues(alpha: 0.07)
                : corItem.withValues(alpha: 0.50),
            width: conc ? 1 : 1.5,
          ),
          boxShadow: conc
              ? null
              : [
                  BoxShadow(
                      color: corItem.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ],
        ),
        child: Row(
          children: [
            // Checkbox ou ícone evento
            if (!isEv)
              GestureDetector(
                onTap: () => _alternarTarefa(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: conc
                        ? _verde.withValues(alpha: 0.2)
                        : Colors.transparent,
                    border: Border.all(
                      color:
                          conc ? _verde : Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
                    boxShadow: conc
                        ? [
                            BoxShadow(
                                color: _verde.withValues(alpha: 0.4),
                                blurRadius: 8)
                          ]
                        : null,
                  ),
                  child: marc
                      ? Padding(
                          padding: const EdgeInsets.all(5),
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _verde.withValues(alpha: 0.8)))
                      : conc
                          ? Icon(Icons.check_rounded,
                              color: _verde, size: r.icon(16))
                          : null,
                ),
              )
            else
              Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _verde.withValues(alpha: 0.12),
                  border: Border.all(color: _verde.withValues(alpha: 0.4)),
                ),
                child:
                    Icon(Icons.event_rounded, color: _verde, size: r.icon(16)),
              ),

            // Texto — GRANDE e legível de longe
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.titulo,
                      style: GoogleFonts.poppins(
                        color: conc
                            ? Colors.white.withValues(alpha: 0.35)
                            : Colors.white,
                        fontSize: r.fs(18), // fonte grande
                        fontWeight: FontWeight.w700,
                        decoration: conc ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.white.withValues(alpha: 0.3),
                        shadows: conc
                            ? null
                            : [
                                Shadow(
                                    color: corItem.withValues(alpha: 0.3),
                                    blurRadius: 8)
                              ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (item.horario != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(children: [
                        Icon(Icons.schedule_rounded,
                            size: 14, color: corItem.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(item.horario!,
                            style: GoogleFonts.poppins(
                                color: corItem.withValues(alpha: 0.9),
                                fontSize: r.fs(14),
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                ],
              ),
            ),

            // Badge tipo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: corItem.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: corItem.withValues(alpha: 0.4)),
              ),
              child: Text(isEv ? 'EVENTO' : 'TAREFA',
                  style: GoogleFonts.poppins(
                      color: corItem,
                      fontSize: r.fs(10),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
            ),
          ],
        ),
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────
  Widget _secao(String texto, Color cor, R r) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(texto,
            style: GoogleFonts.poppins(
                color: cor,
                fontSize: r.fs(11),
                fontWeight: FontWeight.w800,
                letterSpacing: 2)),
      );

  Widget _card({
    required Widget child,
    Gradient? gradient,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: PerformanceManager.instance.sigmaBlur(16),
          sigmaY: PerformanceManager.instance.sigmaBlur(16),
        ),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _dot(Color cor, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cor,
          boxShadow: [
            BoxShadow(color: cor.withValues(alpha: 0.8), blurRadius: 6)
          ],
        ),
      );

  Widget _legenda(Color cor, String label, R r, {double? fontSize}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dot(cor, fontSize != null ? fontSize * 0.75 : 10),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: fontSize ?? r.fs(12),
                  fontWeight: FontWeight.w600)),
        ],
      );
}

// ─── ÍCONE GOOGLE CALENDAR ────────────────────────────────────────────────────
Widget _googleCalIcon(double size) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.18),
    child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Fundo branco
          Container(color: Colors.white),
          // Quadrante sup-esq: azul
          Positioned(
            left: 0,
            top: 0,
            child: Container(
                width: size * 0.5,
                height: size * 0.5,
                color: const Color(0xFF4285F4)),
          ),
          // Quadrante sup-dir: amarelo
          Positioned(
            right: 0,
            top: 0,
            child: Container(
                width: size * 0.5,
                height: size * 0.5,
                color: const Color(0xFFFBBC04)),
          ),
          // Quadrante inf-esq: verde
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
                width: size * 0.5,
                height: size * 0.5,
                color: const Color(0xFF34A853)),
          ),
          // Quadrante inf-dir: vermelho
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
                width: size * 0.5,
                height: size * 0.5,
                color: const Color(0xFFEA4335)),
          ),
          // Número "31" centralizado
          Center(
            child: Text(
              '31',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.40,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── AURORA BOREAL ────────────────────────────────────────────────────────────
class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0D0221), Color(0xFF0A1045), Color(0xFF050818)],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

    final p = Paint()..style = PaintingStyle.fill;
    _w(
        canvas,
        s,
        p,
        const Color(0xFF00E676),
        0.16,
        s.height * (0.12 + math.sin(t * math.pi) * 0.07),
        s.height * 0.20,
        0.6,
        t * math.pi);
    _w(
        canvas,
        s,
        p,
        const Color(0xFF18FFFF),
        0.13,
        s.height * (0.22 + math.cos(t * math.pi * 0.7) * 0.05),
        s.height * 0.24,
        0.5,
        t * math.pi * 1.3 + 1.0);
    _w(
        canvas,
        s,
        p,
        const Color(0xFFE040FB),
        0.11,
        s.height * (0.32 + math.sin(t * math.pi * 1.2) * 0.06),
        s.height * 0.22,
        0.4,
        t * math.pi * 0.9 + 2.1);
    _w(
        canvas,
        s,
        p,
        const Color(0xFF448AFF),
        0.14,
        s.height * (0.42 + math.cos(t * math.pi * 0.8) * 0.04),
        s.height * 0.26,
        0.55,
        t * math.pi * 1.1 + 0.5);
  }

  void _w(Canvas c, Size s, Paint p, Color cor, double op, double yO,
      double amp, double freq, double phase) {
    final path = Path()..moveTo(0, s.height);
    for (double x = 0; x <= s.width; x += 2) {
      path.lineTo(
          x, yO + amp * math.sin(freq * (x / s.width) * 2 * math.pi + phase));
    }
    path.lineTo(s.width, s.height);
    path.close();
    p.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [cor.withValues(alpha: op), cor.withValues(alpha: op * 0.2)],
    ).createShader(Rect.fromLTWH(0, yO - amp, s.width, amp * 2 + s.height));
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}
