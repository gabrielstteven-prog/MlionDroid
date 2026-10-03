import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'barra_info.dart';
import 'config_manager.dart';
import 'info_hub.dart';
import 'performance_manager.dart';
import 'rodizio.dart';
import 'services/google_auth_service.dart';
import 'sistema.dart';
import 'tela_bom_dia.dart';
import 'tela_brasil.dart';
import 'tela_calendario.dart';
import 'tela_classificacao.dart';
import 'tela_clima.dart';
import 'tela_compras.dart';
import 'tela_config.dart';
import 'tela_fotos.dart';
import 'tela_noite.dart';
import 'tela_palmeiras.dart';
import 'tela_regiao.dart';
import 'tela_spotify.dart';
import 'tela_tabela.dart';
import 'update_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await initializeDateFormatting('pt_BR', null);
  await ConfigManager().carregar();
  PerformanceManager.instance.carregar();

  unawaited(Sistema.manterTelaLigada(
      ConfigManager().getBool('geral', 'manter_tela_ligada', true)));
  // O tablet fica ligado o dia todo: verifica atualização ao abrir e
  // periodicamente, sem depender de fechar/abrir o app.
  unawaited(UpdateManager.instance.iniciarVerificacaoPeriodica());
  InfoHub.instance.iniciar();
  unawaited(SpotifyManager.instance.iniciar());
  unawaited(GoogleAuthService.instance.verificar());

  runApp(
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
  );
}

class MlionDroidMaster extends StatefulWidget {
  const MlionDroidMaster({super.key});

  @override
  State<MlionDroidMaster> createState() => _MlionDroidMasterState();
}

class _MlionDroidMasterState extends State<MlionDroidMaster>
    with TickerProviderStateMixin {
  final config = ConfigManager();

  String? _telaAtual;
  bool _isManualMode = false;
  bool _showConfig = false;
  bool _transitioning = false;
  bool _spotifyInjetado = false; // tela de música aberta fora da sequência
  int _renderKeyCounter = 0;

  bool _modoNoite = false;
  DateTime? _noiteDispensadaAte;

  Timer? _manualResetTimer;
  Timer? _watchdogTimer;
  DateTime _ultimaTrocaDeTela = DateTime.now();

  /// Tempo máximo que cada tela pode ficar antes do "watchdog" forçar a
  /// troca (rede travada, tela que esqueceu de chamar aoTerminar...).
  static const Map<String, int> _tempoMaximoTela = {
    'bom_dia': 330,
    'clima': 150,
    'palmeiras': 330,
    'proxima_partida': 90,
    'classificacao': 240,
    'calendario': 150,
    'compras': 150,
    'brasil': 330,
    'regiao': 330,
    'fotos': 150,
    'spotify': 120,
  };

  late final AnimationController _transCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideHorizAnim;
  late final Animation<Offset> _slideVertAnim;
  late final Animation<double> _scaleAnim;

  int get _tempoManualSeg =>
      config.getInt('geral', 'tempo_modo_manual', 45).clamp(10, 600);

  Duration get _duracaoTransicao => PerformanceManager.instance.duracaoTransicao(
      Duration(milliseconds: config.getInt('geral', 'transicao_ms', 800)));
  int get _pausaMs => config.getInt('geral', 'pausa_preta_ms', 300);
  String get _transicaoTipo =>
      config.getString('geral', 'transicao_tipo', 'fade');

  // ── Sequência ────────────────────────────────────────────────────────────
  List<String> get _ordem {
    final seq = config.getStringList('geral', 'sequencia');
    return seq.isEmpty ? ConfigManager.sequenciaPadrao : seq;
  }

  /// Telas que podem aparecer AGORA (ativas e dentro das suas condições).
  Set<String> get _elegiveis {
    final ativas = config.getStringList('geral', 'telas_ativas').toSet();
    final hora = DateTime.now().hour;
    if (!horaNaJanela(hora, config.getInt('bom_dia', 'hora_inicio', 4),
        config.getInt('bom_dia', 'hora_fim', 10))) {
      ativas.remove('bom_dia');
    }
    // Spotify só entra no rodízio com música tocando de verdade.
    if (!SpotifyManager.instance.estaTocando) ativas.remove('spotify');
    return ativas;
  }

  String get _telaExibida {
    if (_spotifyInjetado) return 'spotify';
    return _telaAtual ?? 'clima';
  }

  @override
  void initState() {
    super.initState();
    _transCtrl = AnimationController(duration: _duracaoTransicao, vsync: this)
      ..value = 1.0;
    _fadeAnim = CurvedAnimation(parent: _transCtrl, curve: Curves.easeInOut);
    final cubic = CurvedAnimation(parent: _transCtrl, curve: Curves.easeOutCubic);
    _slideHorizAnim =
        Tween(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(cubic);
    _slideVertAnim =
        Tween(begin: const Offset(0.0, 1.0), end: Offset.zero).animate(cubic);
    _scaleAnim = Tween(begin: 0.85, end: 1.0).animate(cubic);

    _telaAtual = proximaTela(_ordem, _elegiveis, null);
    _iniciarWatchdog();
    _avaliarModoNoite();
    InfoHub.instance.relogio.addListener(_avaliarModoNoite);
    SpotifyManager.instance.onFaixaTrocada = _onFaixaSpotifyTrocada;
  }

  @override
  void dispose() {
    InfoHub.instance.relogio.removeListener(_avaliarModoNoite);
    _transCtrl.dispose();
    _manualResetTimer?.cancel();
    _watchdogTimer?.cancel();
    SpotifyManager.instance.onFaixaTrocada = null;
    super.dispose();
  }

  // ── Modo Noite ───────────────────────────────────────────────────────────
  void _avaliarModoNoite() {
    final ativo = config.getBool('noite', 'ativo', true);
    final agora = DateTime.now();
    final naJanela = horaNaJanela(agora.hour,
        config.getInt('noite', 'hora_inicio', 23), config.getInt('noite', 'hora_fim', 6));
    final dispensada =
        _noiteDispensadaAte != null && agora.isBefore(_noiteDispensadaAte!);
    final deveFicar = ativo && naJanela && !dispensada && !_showConfig;
    if (deveFicar == _modoNoite) return;
    setState(() => _modoNoite = deveFicar);
    // Escurece a tela de verdade (brilho da janela) durante a noite.
    Sistema.brilho(deveFicar ? 0.05 : null);
    if (!deveFicar) {
      _ultimaTrocaDeTela = DateTime.now();
    }
  }

  void _acordarDaNoite() {
    _noiteDispensadaAte = DateTime.now().add(const Duration(minutes: 10));
    _avaliarModoNoite();
  }

  // ── Spotify ──────────────────────────────────────────────────────────────
  void _onFaixaSpotifyTrocada() {
    if (!mounted || _showConfig || _modoNoite) return;
    if (!config.getBool('spotify', 'aparecer_por_evento', true)) return;
    if (_telaExibida == 'spotify') {
      setState(() => _renderKeyCounter++);
      return;
    }
    if (_isManualMode || _transitioning) return;
    _transicionar(() => _spotifyInjetado = true);
  }

  // ── Navegação ────────────────────────────────────────────────────────────
  void _iniciarWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _showConfig || _isManualMode || _modoNoite) return;
      final maxSeg = _tempoMaximoTela[_telaExibida] ?? 180;
      final seg = DateTime.now().difference(_ultimaTrocaDeTela).inSeconds;
      if (seg >= maxSeg) {
        _transitioning = false; // destrava se uma transição ficou presa
        irParaProximaPagina();
      }
    });
  }

  /// Chamado pelas telas quando terminam (aoTerminar).
  void irParaProximaPagina() {
    if (!mounted || _showConfig || _modoNoite) return;
    if (_isManualMode) {
      // Alguém está mexendo na tela: segue quando o modo manual acabar.
      _terminouDuranteManual = true;
      return;
    }
    if (_transitioning) return;
    _avancar(1);
  }

  bool _terminouDuranteManual = false;

  void _avancar(int passo) {
    _terminouDuranteManual = false;
    final proxima = proximaTela(_ordem, _elegiveis, _telaAtual, passo: passo);
    _transicionar(() {
      _spotifyInjetado = false;
      _telaAtual = proxima ?? _telaAtual;
    });
  }

  void _transicionar(VoidCallback aplicar) {
    if (_transitioning) return;
    _transitioning = true;
    _transCtrl.duration = _duracaoTransicao;
    _transCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        aplicar();
        _renderKeyCounter++;
        _ultimaTrocaDeTela = DateTime.now();
      });
      Future.delayed(Duration(milliseconds: _pausaMs), () {
        if (!mounted) return;
        _transCtrl.forward().whenComplete(() => _transitioning = false);
      });
    });
  }

  void _entrarModoManual() {
    if (!_isManualMode) setState(() => _isManualMode = true);
    _manualResetTimer?.cancel();
    _manualResetTimer = Timer(Duration(seconds: _tempoManualSeg), () {
      if (!mounted) return;
      setState(() => _isManualMode = false);
      _ultimaTrocaDeTela = DateTime.now();
      if (_terminouDuranteManual) irParaProximaPagina();
    });
  }

  void _onSwipe(DragEndDetails details) {
    if (_showConfig) return;
    final vel = details.primaryVelocity ?? 0;
    if (vel.abs() < 250 || _transitioning) return;
    _entrarModoManual();
    _avancar(vel < 0 ? 1 : -1);
  }

  Future<void> _fecharConfig() async {
    await ConfigManager().carregar();
    PerformanceManager.instance.carregar();
    unawaited(Sistema.manterTelaLigada(
        config.getBool('geral', 'manter_tela_ligada', true)));
    if (!SpotifyManager.instance.autenticado) {
      unawaited(SpotifyManager.instance.iniciar());
    }
    if (!mounted) return;
    _transCtrl.duration = _duracaoTransicao;
    setState(() {
      _showConfig = false;
      _spotifyInjetado = false;
      _telaAtual = proximaTela(_ordem, _elegiveis, null);
      _renderKeyCounter++;
      _isManualMode = false;
      _transitioning = false;
      _ultimaTrocaDeTela = DateTime.now();
    });
    _transCtrl.value = 1.0;
    _avaliarModoNoite();
  }

  void _abrirConfig() {
    setState(() => _showConfig = true);
    if (_modoNoite) {
      setState(() => _modoNoite = false);
      Sistema.brilho(null);
    }
  }

  Widget _buildTela() {
    final k = _renderKeyCounter;
    final fim = irParaProximaPagina;
    switch (_telaExibida) {
      case 'bom_dia':
        return TelaBomDia(key: ValueKey('bom_dia_$k'), aoTerminar: fim);
      case 'palmeiras':
        return TelaPalmeiras(key: ValueKey('palmeiras_$k'), aoTerminar: fim);
      case 'proxima_partida':
        return TelaTabela(key: ValueKey('tabela_$k'), aoTerminar: fim);
      case 'calendario':
        return TelaCalendario(key: ValueKey('calendario_$k'), aoTerminar: fim);
      case 'classificacao':
        return TelaClassificacao(key: ValueKey('classif_$k'), aoTerminar: fim);
      case 'compras':
        return TelaCompras(key: ValueKey('compras_$k'), aoTerminar: fim);
      case 'brasil':
        return TelaBrasil(key: ValueKey('brasil_$k'), aoTerminar: fim);
      case 'regiao':
        return TelaRegiao(key: ValueKey('regiao_$k'), aoTerminar: fim);
      case 'fotos':
        return TelaFotos(key: ValueKey('fotos_$k'), aoTerminar: fim);
      case 'spotify':
        return TelaSpotify(key: ValueKey('spotify_$k'), aoTerminar: fim);
      case 'clima':
      default:
        return TelaClima(key: ValueKey('clima_$k'), aoTerminar: fim);
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

  @override
  Widget build(BuildContext context) {
    if (_modoNoite) {
      return TelaNoite(aoTocar: _acordarDaNoite);
    }
    if (_showConfig) {
      return TelaConfig(aoSalvar: _fecharConfig);
    }

    // A TelaBomDia já mostra relógio e clima em destaque — a barra
    // superior ficaria redundante nela.
    return MlionShell(
      modoManual: _isManualMode,
      telaAtual: _telaExibida,
      mostrarBarra: _telaExibida != 'bom_dia',
      aoAbrirConfig: _abrirConfig,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onHorizontalDragEnd: _onSwipe,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _entrarModoManual(),
            child: _aplicarTransicao(_buildTela()),
          ),
        ),
      ),
    );
  }
}
