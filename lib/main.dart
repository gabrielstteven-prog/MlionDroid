// ═══════════════════════════════════════════════════════════════════════════════
//  PATCH — main.dart
//  Integrar SpotifyManager: evento de troca de faixa abre TelaSpotify
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';

import 'tela_clima.dart';
import 'tela_palmeiras.dart';
import 'tela_calendario.dart';
import 'tela_tabela.dart';
import 'tela_fotos.dart';
import 'tela_classificacao.dart';
import 'tela_regiao.dart';
import 'tela_brasil.dart';
import 'tela_compras.dart';
import 'tela_bom_dia.dart';
import 'tela_config.dart';
import 'tela_spotify.dart'; // ← NOVO
import 'config_manager.dart';
import 'performance_manager.dart';
import 'update_manager.dart';
import 'info_hub.dart';
import 'barra_info.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await ConfigManager().carregar();
  PerformanceManager.instance.carregar();
  // Verifica em segundo plano assim que abre, e continua verificando de
  // tempos em tempos enquanto o app estiver rodando (o tablet fica ligado
  // o dia inteiro, então não dá pra depender de fechar/abrir o app pra
  // descobrir que tem versão nova).
  UpdateManager.instance.iniciarVerificacaoPeriodica();
  InfoHub.instance.iniciar();

  // ── Inicia Spotify (carrega token salvo, se houver) ──────────────────────
  SpotifyManager.instance.iniciar();

  initializeDateFormatting('pt_BR', null).then(
    (_) => runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final scale = mq.textScaler.scale(1.0).clamp(0.85, 1.15);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const MlionDroidMaster(),
      ),
    ),
  );
}

class MlionDroidMaster extends StatefulWidget {
  const MlionDroidMaster({super.key});

  @override
  State<MlionDroidMaster> createState() => _MlionDroidMasterState();
}

class _MlionDroidMasterState extends State<MlionDroidMaster>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int _paginaAtual = 0;
  bool _isManualMode = false;
  bool _showConfig = false;
  int _renderKeyCounter = 0;
  bool _transitioning = false;

  // ── NOVO: flag para saber se estamos exibindo a tela de música por evento ──
  bool _spotifyEventoAtivo = false;
  bool _spotifyInjetado = false; // true quando injetado fora da sequência

  Timer? _manualResetTimer;
  Timer? _tapResetTimer;
  int _tapCount = 0;

  Timer? _watchdogTimer;
  DateTime _ultimaTrocaDeTela = DateTime.now();

  static const Map<String, int> _tempoMaximoTela = {
    'bom_dia': 120,
    'clima': 90,
    'palmeiras': 300,
    'proxima_partida': 60,
    'classificacao': 180,
    'calendario': 120,
    'compras': 90,
    'brasil': 300,
    'regiao': 300,
    'fotos': 120,
    'spotify': 60,
  };
  static const int _tempoMaximoPadrao = 180;

  late AnimationController _transCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideHorizAnim;
  late Animation<Offset> _slideVertAnim;
  late Animation<double> _scaleAnim;

  final config = ConfigManager();

  List<String> get _sequencia {
    final todas = config.getStringList('geral', 'sequencia');
    final ativas = config.getStringList('geral', 'telas_ativas');
    List<String> base;
    if (todas.isEmpty) {
      base = [
        'clima',
        'palmeiras',
        'proxima_partida',
        'classificacao',
        'calendario',
        'compras',
        'brasil',
        'regiao',
        'fotos',
      ];
    } else {
      base = todas.where((t) => ativas.contains(t)).toList();
    }
    // ── Remove 'bom_dia' da sequência se estiver fora do horário configurado.
    // Isso impede que a tela entre no rodízio e apareça como tela preta
    // (ela mesma se encerraria, mas só DEPOIS de já ter sido renderizada
    // por um frame — daí o flash preto). Filtrando aqui, ela nunca chega
    // a ser construída fora do horário.
    if (base.contains('bom_dia') && !_bomDiaNoHorario) {
      base = base.where((t) => t != 'bom_dia').toList();
    }
    // ── Remove 'spotify' da sequência se não tiver música tocando agora.
    // Sem isso, a tela aparecia no rodízio normal mostrando "Nenhuma
    // música tocando" — ela só deve aparecer quando há música de verdade.
    if (base.contains('spotify') && !SpotifyManager.instance.estaTocando) {
      base = base.where((t) => t != 'spotify').toList();
    }
    return base;
  }

  // ── Verifica se o horário atual está dentro da janela configurada da TelaBomDia
  bool get _bomDiaNoHorario {
    final hora = DateTime.now().hour;
    final inicio = config.getInt('bom_dia', 'hora_inicio', 4);
    final fim = config.getInt('bom_dia', 'hora_fim', 10);
    return hora >= inicio && hora < fim;
  }

  int get _totalPaginas => _sequencia.length;
  int get _transicaoMs => config.getInt('geral', 'transicao_ms', 800);
  int get _pausaMs => config.getInt('geral', 'pausa_preta_ms', 300);
  String get _transicaoTipo =>
      config.getString('geral', 'transicao_tipo', 'fade');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _transCtrl = AnimationController(
        duration: Duration(milliseconds: _transicaoMs), vsync: this);

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _transCtrl, curve: Curves.easeInOut));
    _slideHorizAnim =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
            CurvedAnimation(parent: _transCtrl, curve: Curves.easeOutCubic));
    _slideVertAnim =
        Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero).animate(
            CurvedAnimation(parent: _transCtrl, curve: Curves.easeOutCubic));
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _transCtrl, curve: Curves.easeOutCubic));

    _transCtrl.value = 1.0;
    _iniciarWatchdog();

    // ── Assinar evento de troca de faixa do Spotify ───────────────────────
    SpotifyManager.instance.onFaixaTrocada = _onFaixaSpotifyTrocada;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transCtrl.dispose();
    _manualResetTimer?.cancel();
    _tapResetTimer?.cancel();
    _watchdogTimer?.cancel();
    SpotifyManager.instance.onFaixaTrocada = null;
    super.dispose();
  }

  // ── Spotify ───────────────────────────────────────────────────────────────
  void _onFaixaSpotifyTrocada() {
    if (!mounted || _showConfig) return;

    final aparecerPorEvento =
        config.getBool('spotify', 'aparecer_por_evento', true);
    if (!aparecerPorEvento) return;

    final seq = _sequencia;
    final telaAtual =
        seq.isNotEmpty && _paginaAtual < seq.length ? seq[_paginaAtual] : '';
    if (telaAtual == 'spotify') {
      setState(() => _renderKeyCounter++);
      return;
    }

    if (_isManualMode) return;
    if (_transitioning) return;
    _transitioning = true;
    _spotifyEventoAtivo = true;

    final idxSpotify = seq.indexOf('spotify');
    if (idxSpotify >= 0) {
      _executarTransicao(idxSpotify, modoManual: false);
    } else {
      _transitioning = false;
      _spotifyEventoAtivo = false;
      _injetarTelaSpotifyTemporaria();
    }
  }

  void _injetarTelaSpotifyTemporaria() {
    if (_transitioning) return;
    _transitioning = true;
    _spotifyEventoAtivo = true;
    _executarTransicaoSpotify();
  }

  void _executarTransicaoSpotify() {
    _transCtrl.duration = Duration(milliseconds: _transicaoMs);
    _transCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _spotifyInjetado = true;
        _renderKeyCounter++;
        _ultimaTrocaDeTela = DateTime.now();
      });
      Future.delayed(Duration(milliseconds: _pausaMs), () {
        if (!mounted) return;
        _transCtrl.forward().then((_) => _transitioning = false);
      });
    });
  }

  void _iniciarWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _showConfig || _isManualMode) return;
      final seq = _sequencia;
      if (seq.isEmpty) return;
      final telaAtual = _paginaAtual < seq.length ? seq[_paginaAtual] : 'clima';
      final maxSeg = _tempoMaximoTela[telaAtual] ?? _tempoMaximoPadrao;
      final segsNaTela =
          DateTime.now().difference(_ultimaTrocaDeTela).inSeconds;
      if (segsNaTela >= maxSeg) {
        _transitioning = false;
        _avancarAutomatico();
      }
    });
  }

  void irParaProximaPagina() {
    if (!mounted || _isManualMode || _transitioning || _showConfig) return;
    if (_totalPaginas == 0) return;
    _spotifyEventoAtivo = false;

    if (_spotifyInjetado) {
      _spotifyInjetado = false;
      _avancarAutomatico();
      return;
    }
    _avancarAutomatico();
  }

  void _avancarAutomatico() {
    if (_transitioning || !mounted || _showConfig) return;
    _transitioning = true;
    final novaPagina = (_paginaAtual + 1) % _totalPaginas;
    _executarTransicao(novaPagina, modoManual: false);
  }

  void _navegarManual(int novaPagina) {
    if (_transitioning) return;
    _transitioning = true;
    _spotifyEventoAtivo = false;

    setState(() => _isManualMode = true);
    _manualResetTimer?.cancel();
    _manualResetTimer = Timer(const Duration(seconds: 45), () {
      if (mounted) setState(() => _isManualMode = false);
    });

    _executarTransicao(novaPagina, modoManual: true);
  }

  void _executarTransicao(int novaPagina, {required bool modoManual}) {
    _transCtrl.duration = Duration(milliseconds: _transicaoMs);
    _transCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _paginaAtual = novaPagina;
        _renderKeyCounter++;
        _ultimaTrocaDeTela = DateTime.now();
        if (!modoManual) _isManualMode = false;
      });
      Future.delayed(Duration(milliseconds: _pausaMs), () {
        if (!mounted) return;
        _transCtrl.forward().then((_) => _transitioning = false);
      });
    });
  }

  void _onSwipe(DragEndDetails details) {
    if (_showConfig) return;
    final vel = details.primaryVelocity ?? 0;
    if (vel.abs() < 250) return;
    if (_totalPaginas == 0) return;
    if (vel < 0) {
      _navegarManual((_paginaAtual + 1) % _totalPaginas);
    } else {
      _navegarManual((_paginaAtual - 1 + _totalPaginas) % _totalPaginas);
    }
  }

  void _detectarToqueGlobal() {
    if (_showConfig) return;
    if (!_isManualMode) setState(() => _isManualMode = true);
    _manualResetTimer?.cancel();
    _manualResetTimer = Timer(const Duration(seconds: 45), () {
      if (mounted) setState(() => _isManualMode = false);
    });
  }

  // ── Mantido para compatibilidade, mas a engrenagem substitui o uso normal ──
  void _detectarToqueConfig(TapDownDetails details) {
    if (details.localPosition.dx < 80 && details.localPosition.dy < 80) {
      _tapCount++;
      _tapResetTimer?.cancel();
      _tapResetTimer = Timer(const Duration(seconds: 2), () => _tapCount = 0);
      if (_tapCount >= 5) {
        _tapCount = 0;
        setState(() => _showConfig = true);
      }
    }
  }

  void _fecharConfig() async {
    await ConfigManager().carregar();
    PerformanceManager.instance.carregar();

    if (!SpotifyManager.instance.autenticado) {
      SpotifyManager.instance.iniciar();
    }

    if (!mounted) return;
    _transCtrl.duration = Duration(milliseconds: _transicaoMs);
    setState(() {
      _showConfig = false;
      _renderKeyCounter++;
      _paginaAtual = 0;
      _isManualMode = false;
      _transitioning = false;
      _ultimaTrocaDeTela = DateTime.now();
    });
    _transCtrl.value = 1.0;
  }

  Widget _buildTela() {
    if (_spotifyInjetado) {
      return TelaSpotify(
          key: ValueKey('spotify_injetado_$_renderKeyCounter'),
          aoTerminar: irParaProximaPagina);
    }

    final seq = _sequencia;
    if (seq.isEmpty) {
      return TelaClima(
          key: const ValueKey('clima_fallback'),
          aoTerminar: irParaProximaPagina);
    }
    final tela = _paginaAtual < seq.length ? seq[_paginaAtual] : 'clima';
    switch (tela) {
      case 'bom_dia':
        return TelaBomDia(
            key: ValueKey('bom_dia_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'clima':
        return TelaClima(
            key: ValueKey('clima_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'palmeiras':
        return TelaPalmeiras(
            key: ValueKey('palmeiras_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'proxima_partida':
        return TelaTabela(
            key: ValueKey('tabela_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'calendario':
        return TelaCalendario(
            key: ValueKey('calendario_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'classificacao':
        return TelaClassificacao(
            key: ValueKey('classificacao_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'compras':
        return TelaCompras(
            key: ValueKey('compras_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'brasil':
        return TelaBrasil(
            key: ValueKey('brasil_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'regiao':
        return TelaRegiao(
            key: ValueKey('regiao_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'fotos':
        return TelaFotos(
            key: ValueKey('fotos_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      case 'spotify':
        return TelaSpotify(
            key: ValueKey('spotify_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
      default:
        return TelaClima(
            key: ValueKey('clima_$_renderKeyCounter'),
            aoTerminar: irParaProximaPagina);
    }
  }

  Widget _aplicarTransicao(Widget child) {
    switch (_transicaoTipo) {
      case 'slide_horizontal':
        return SlideTransition(position: _slideHorizAnim, child: child);
      case 'slide_vertical':
        return SlideTransition(position: _slideVertAnim, child: child);
      case 'zoom':
        return ScaleTransition(
            scale: _scaleAnim,
            child: FadeTransition(opacity: _fadeAnim, child: child));
      default:
        return FadeTransition(opacity: _fadeAnim, child: child);
    }
  }

  String get _telaAtualKey {
    final seq = _sequencia;
    if (seq.isEmpty || _paginaAtual >= seq.length) return 'clima';
    return seq[_paginaAtual];
  }

  @override
  Widget build(BuildContext context) {
    // A TelaBomDia já mostra clima/data de um jeito mais bonito e grande —
    // a barra superior fica redundante e "suja" o visual nessa tela.
    // Escondemos a barra só aqui; nas outras telas ela continua normal.
    final ehTelaBomDia = !_showConfig && _telaAtualKey == 'bom_dia';

    return MlionShell(
      modoManual: _isManualMode,
      telaAtual: _telaAtualKey,
      mostrarBarra: !ehTelaBomDia,
      aoAbrirConfig:
          _showConfig ? null : () => setState(() => _showConfig = true),
      child: _showConfig
          ? TelaConfig(aoSalvar: _fecharConfig)
          : Scaffold(
              backgroundColor: Colors.black,
              body: GestureDetector(
                onTapDown: _detectarToqueConfig,
                onHorizontalDragEnd: _onSwipe,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _detectarToqueGlobal(),
                  child: _aplicarTransicao(_buildTela()),
                ),
              ),
            ),
    );
  }
}
