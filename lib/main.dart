import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'barra_info.dart';
import 'cache_manager.dart';
import 'config_manager.dart';
import 'info_hub.dart';
import 'performance_manager.dart';
import 'rodizio.dart';
import 'services/voz_service.dart';
import 'services/assistente_service.dart';
import 'services/football_service.dart';
import 'services/google_auth_service.dart';
import 'services/jarvis_service.dart';
import 'widgets/camada_assistente.dart';
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
import 'util.dart';

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
  FootballService.instance.iniciarMonitor();

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
    AssistenteService.instance.pedidoDeTela.addListener(_pedidoDoAssistente);
    FootballService.instance.ultimoLance.addListener(_lanceDoJogo);
    Sistema.acordouPorSensor.addListener(_acordouPorSensor);
    Sistema.presenca.addListener(_presenca);
    AssistenteService.instance.ausente.addListener(_modoAusente);
    Sistema.iniciarEventos();
    AssistenteService.instance.sincronizarPalavra(); // "Jarvis" sem tocar
    AssistenteService.instance.addListener(_assistenteMudou);
    Sistema.inverterOlhar(config.getBool('assistente', 'inverter_olhar', false));
  }

  // ── Câmera enquanto o Jarvis está na tela: os olhos seguem a pessoa ──────
  bool _cameraPeloAssistente = false;

  bool get _cameraEmUsoPorOutro =>
      _aguardandoBomDia ||
      _aguardandoNoite ||
      _modoNoite ||
      (_noiteDispensadaAte != null && DateTime.now().isBefore(_noiteDispensadaAte!));

  void _assistenteMudou() {
    final ativo = AssistenteService.instance.estado != EstadoAssistente.parado;
    if (ativo && !_cameraPeloAssistente) {
      if (!config.getBool('assistente', 'olhar_pessoa', true)) return;
      _cameraPeloAssistente = true;
      if (!_cameraEmUsoPorOutro) Sistema.observarPresenca();
    } else if (!ativo && _cameraPeloAssistente) {
      _cameraPeloAssistente = false;
      if (!_cameraEmUsoPorOutro) Sistema.pararDescanso();
    }
  }

  @override
  void dispose() {
    InfoHub.instance.relogio.removeListener(_avaliarModoNoite);
    _transCtrl.dispose();
    _manualResetTimer?.cancel();
    _watchdogTimer?.cancel();
    SpotifyManager.instance.onFaixaTrocada = null;
    AssistenteService.instance.pedidoDeTela.removeListener(_pedidoDoAssistente);
    FootballService.instance.ultimoLance.removeListener(_lanceDoJogo);
    Sistema.acordouPorSensor.removeListener(_acordouPorSensor);
    AssistenteService.instance.removeListener(_assistenteMudou);
    Sistema.presenca.removeListener(_presenca);
    AssistenteService.instance.ausente.removeListener(_modoAusente);
    super.dispose();
  }

  // ── Modo Noite ───────────────────────────────────────────────────────────
  void _avaliarModoNoite() {
    _checarBomDia();
    _checarResumoNoite();
    final agora = DateTime.now();
    final noite = config.getBool('noite', 'ativo', true) &&
        horaNaJanela(agora.hour, config.getInt('noite', 'hora_inicio', 23),
            config.getInt('noite', 'hora_fim', 6));
    final ausenteAgenda = config.getBool('ausente', 'agenda_ativa', false) &&
        emAusenciaAgendada(
          agora,
          config.getStringList('ausente', 'dias').map(int.tryParse).whereType<int>().toList(),
          config.getInt('ausente', 'hora_inicio', 8),
          config.getInt('ausente', 'hora_fim', 18),
        );
    final emDescanso = noite || ausenteAgenda || _ausenteManual;
    // Começou o horário de descanso (noite ou ausência agendada): antes de
    // apagar, a câmera confere se tem alguém em casa. Com movimento (dia de
    // home office, acordado à meia-noite) a tela fica acesa; sem ninguém
    // pelo tempo configurado, apaga. "Estou saindo" apaga na hora.
    if (emDescanso && !_estavaEmDescanso) {
      _estavaEmDescanso = true;
      if (!_ausenteManual &&
          config.getBool('noite', 'conferir_presenca', true) &&
          config.getBool('noite', 'acordar_com_camera', true)) {
        _noiteDispensadaAte = agora.add(_tempoAcordadoPorSensor);
        Sistema.observarPresenca();
      }
    } else if (!emDescanso) {
      _estavaEmDescanso = false;
    }
    final dispensada =
        _noiteDispensadaAte != null && agora.isBefore(_noiteDispensadaAte!);
    final deveFicar = emDescanso && !dispensada && !_showConfig;
    // Ausente (agenda ou "estou saindo") sempre apaga; a noite só apaga se
    // a opção estiver ligada (senão mostra o relógio escuro).
    final apagar = _ausenteManual || ausenteAgenda || config.getBool('noite', 'desligar_tela', false);
    if (deveFicar == _modoNoite && (!deveFicar || apagar == _telaDesligada)) return;
    setState(() {
      _modoNoite = deveFicar;
      if (deveFicar) _telaDesligada = apagar;
    });
    // Noite sem apagar: relógio escuro com brilho baixo. Descanso: tela
    // preta no brilho mínimo, sem bloquear o tablet.
    Sistema.brilho(deveFicar ? (apagar ? 0.0 : 0.05) : null);
    if (deveFicar && apagar) {
      final fim = _ausenteManual
          ? agora.add(const Duration(hours: 12)) // "estou saindo": só acorda com alguém
          : proximaHoraCheia(
              agora,
              ausenteAgenda && !noite
                  ? config.getInt('ausente', 'hora_fim', 18)
                  : config.getInt('noite', 'hora_fim', 6));
      Sistema.desligarTela(
        acordarEm: fim,
        luz: config.getBool('noite', 'acordar_com_luz', true),
        proximidade: config.getBool('noite', 'acordar_com_proximidade', false),
        camera: config.getBool('noite', 'acordar_com_camera', true),
      );
    }
    if (!deveFicar) {
      _ultimaTrocaDeTela = DateTime.now();
      if (_telaDesligada) {
        _telaDesligada = false;
        if (!dispensada) {
          // Fim do horário: acende e para de vigiar.
          Sistema.acordarTela();
        }
        // Acordou por sensor (dispensada): a câmera segue de olho para ver se
        // ainda há alguém na frente — ela para quando a tela apagar de novo
        // ou quando o horário acabar.
        Sistema.manterTelaLigada(config.getBool('geral', 'manter_tela_ligada', true));
      }
      if (!emDescanso) Sistema.pararDescanso();
    }
  }

  /// Já estava no horário de descanso na última avaliação (detecta a entrada).
  bool _estavaEmDescanso = false;

  /// "Jarvis, estou saindo": tela em descanso até alguém chegar.
  bool _ausenteManual = false;

  void _modoAusente() {
    final saindo = AssistenteService.instance.ausente.value;
    if (saindo == _ausenteManual) return;
    _ausenteManual = saindo;
    _noiteDispensadaAte = null;
    _avaliarModoNoite();
  }

  /// A câmera ainda vê alguém depois de acender: adia o próximo apagão.
  void _presenca() {
    _adiarApagao();
    _dispararBomDia();
    _dispararResumoNoite();
  }

  // ── Bom dia ao ver alguém ────────────────────────────────────────────────
  // No horário do Bom Dia, a câmera fica de olho; na primeira vez que vê
  // alguém (ou no primeiro toque), abre o Bom Dia e o Jarvis fala o
  // briefing — uma vez por dia.
  bool _aguardandoBomDia = false;
  String _bomDiaChecadoEm = '';

  String get _chaveBomDiaFalado {
    final h = DateTime.now();
    return 'bom_dia_falado_${h.year}_${h.month}_${h.day}';
  }

  Future<void> _checarBomDia() async {
    if (!config.getBool('bom_dia', 'falar_ao_ver', true)) return;
    final agora = DateTime.now();
    final naJanela = horaNaJanela(agora.hour, config.getInt('bom_dia', 'hora_inicio', 4),
        config.getInt('bom_dia', 'hora_fim', 10));
    if (!naJanela) {
      _aguardandoBomDia = false;
      return;
    }
    final hoje = '${agora.year}-${agora.month}-${agora.day}';
    if (_bomDiaChecadoEm == hoje || _modoNoite) return;
    _bomDiaChecadoEm = hoje;
    if (await CacheManager.instance.obterEntrada<bool>(_chaveBomDiaFalado) != null) return;
    _aguardandoBomDia = true;
    Sistema.observarPresenca();
  }

  // ── Resumo da noite ao ver alguém ────────────────────────────────────────
  // Mesma ideia do Bom Dia, no horário da noite (padrão 18h–22h): na primeira
  // vez que vê alguém, o Jarvis fala o que vem amanhã (agenda, contas,
  // clima, jogo) — uma vez por dia.
  bool _aguardandoNoite = false;
  String _noiteChecadaEm = '';

  String get _chaveNoiteFalada {
    final h = DateTime.now();
    return 'resumo_noite_falado_${h.year}_${h.month}_${h.day}';
  }

  Future<void> _checarResumoNoite() async {
    if (!config.getBool('resumo_noite', 'ativo', true)) return;
    final agora = DateTime.now();
    if (!horaNaJanela(agora.hour, config.getInt('resumo_noite', 'hora_inicio', 18),
        config.getInt('resumo_noite', 'hora_fim', 22))) {
      _aguardandoNoite = false;
      return;
    }
    final hoje = '${agora.year}-${agora.month}-${agora.day}';
    if (_noiteChecadaEm == hoje || _modoNoite) return;
    _noiteChecadaEm = hoje;
    if (await CacheManager.instance.obterEntrada<bool>(_chaveNoiteFalada) != null) return;
    _aguardandoNoite = true;
    Sistema.observarPresenca();
  }

  Future<void> _dispararResumoNoite() async {
    if (!_aguardandoNoite || _modoNoite || !mounted) return;
    _aguardandoNoite = false;
    await CacheManager.instance.salvar(_chaveNoiteFalada, true);
    if (_noiteDispensadaAte == null || DateTime.now().isAfter(_noiteDispensadaAte!)) {
      Sistema.pararDescanso();
    }
    final texto = await JarvisService.instance.resumoDaNoite();
    if (texto != null && mounted) AssistenteService.instance.anunciar(texto);
  }

  void _dispararBomDia() {
    if (!_aguardandoBomDia || _modoNoite || !mounted) return;
    _aguardandoBomDia = false;
    // Fora do descanso, a câmera já cumpriu o papel: desliga.
    if (_noiteDispensadaAte == null || DateTime.now().isAfter(_noiteDispensadaAte!)) {
      Sistema.pararDescanso();
    }
    TelaBomDia.falarAoAbrir = true;
    _irParaTela('bom_dia', manual: false);
  }

  /// A tela foi apagada pelo Modo Noite (opção "desligar a tela").
  bool _telaDesligada = false;

  /// Luz acesa ou alguém perto: o painel fica aceso por alguns minutos e,
  /// sem ninguém mexendo, apaga de novo (o sensor volta a vigiar).
  void _acordouPorSensor() {
    final motivo = Sistema.acordouPorSensor.value;
    if (motivo == null) return;
    _dispararBomDia();
    _dispararResumoNoite();
    if (_ausenteManual) {
      // Chegou em casa: sai do modo ausente, para de vigiar e dá as boas-vindas.
      AssistenteService.instance.ausente.value = false;
      Sistema.pararDescanso();
      AssistenteService.instance.boasVindas();
      return;
    }
    // Toque = a pessoa quer usar o painel: 10 min. Luz/movimento: o tempo
    // configurado (padrão 2 min).
    _noiteDispensadaAte = DateTime.now().add(motivo.startsWith('toque')
        ? const Duration(minutes: 10)
        : _tempoAcordadoPorSensor);
    _avaliarModoNoite();
  }

  Duration get _tempoAcordadoPorSensor =>
      Duration(minutes: config.getInt('noite', 'minutos_acordado', 2).clamp(1, 30));

  /// Toque com o painel aceso de madrugada: adia o próximo apagão.
  void _adiarApagao() {
    final ate = _noiteDispensadaAte;
    if (ate == null || DateTime.now().isAfter(ate)) return;
    final novo = DateTime.now().add(_tempoAcordadoPorSensor);
    if (novo.isAfter(ate)) _noiteDispensadaAte = novo;
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

  /// Telas exibidas desde a última vez que a Próxima Partida apareceu.
  int _telasDesdeJogo = 99;

  /// "Mostra o clima" falado ao assistente.
  void _pedidoDoAssistente() {
    final tela = AssistenteService.instance.pedidoDeTela.value;
    if (tela == null || !mounted) return;
    AssistenteService.instance.pedidoDeTela.value = null;
    _irParaTela(tela);
  }

  /// Gol ou fim de jogo: mostra a partida na hora e, se configurado, fala.
  void _lanceDoJogo() {
    final lance = FootballService.instance.ultimoLance.value;
    if (lance == null || !mounted || _modoNoite || _showConfig) return;
    if (config.getBool('proxima_partida', 'falar_gols', true)) {
      VozService.instance.falar(lance); // gol narrado com a voz premium
    }
    if (!_isManualMode && _telaExibida != 'proxima_partida') {
      _irParaTela('proxima_partida', manual: false);
    }
  }

  void _irParaTela(String tela, {bool manual = true}) {
    if (manual) _entrarModoManual();
    _transitioning = false;
    _transicionar(() {
      _spotifyInjetado = tela == 'spotify';
      if (tela != 'spotify') _telaAtual = tela;
    });
  }

  void _avancar(int passo) {
    _terminouDuranteManual = false;
    var proxima = proximaTela(_ordem, _elegiveis, _telaAtual, passo: passo);
    // Dia de jogo: perto do horário ou com a bola rolando, a Próxima
    // Partida volta a cada duas telas (mesmo que esteja fora do rodízio).
    _telasDesdeJogo++;
    if (passo > 0 &&
        FootballService.instance.jogoDoMomento.value != null &&
        _telasDesdeJogo >= 2 &&
        _telaAtual != 'proxima_partida') {
      proxima = 'proxima_partida';
    }
    if (proxima == 'proxima_partida') _telasDesdeJogo = 0;
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

  /// Deslocamento horizontal acumulado do deslize atual.
  double _arrasto = 0;

  /// Troca de tela pelo deslize. Vale pela distância (mais de 120 px) OU
  /// pela velocidade: só a velocidade falhava quando o dedo parava um
  /// instante antes de soltar (velocidade final medida = zero).
  void _onSwipe(DragEndDetails details) {
    final dx = _arrasto;
    _arrasto = 0;
    if (_showConfig || _transitioning) return;
    final vel = details.primaryVelocity ?? 0;
    final int passo;
    if (dx.abs() >= 120) {
      passo = dx < 0 ? 1 : -1;
    } else if (vel.abs() >= 250) {
      passo = vel < 0 ? 1 : -1;
    } else {
      return;
    }
    _entrarModoManual();
    _avancar(passo);
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
    if (_telaDesligada) {
      _telaDesligada = false;
      Sistema.manterTelaLigada(config.getBool('geral', 'manter_tela_ligada', true));
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
    final Widget conteudo;
    if (_modoNoite) {
      conteudo = TelaNoite(aoTocar: _acordarDaNoite, apagada: _telaDesligada);
    } else if (_showConfig) {
      conteudo = TelaConfig(aoSalvar: _fecharConfig);
    } else {
      // A TelaBomDia já mostra relógio e clima em destaque — a barra
      // superior ficaria redundante nela.
      conteudo = MlionShell(
        modoManual: _isManualMode,
        telaAtual: _telaExibida,
        mostrarBarra: _telaExibida != 'bom_dia',
        aoAbrirConfig: _abrirConfig,
        telasRodizio: _ordem.where(_elegiveis.contains).toList(),
        child: Scaffold(
          backgroundColor: Colors.transparent, // o céu do app aparece atrás
          body: GestureDetector(
            // opaque: o deslize vale na tela toda, inclusive nas áreas vazias.
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _arrasto = 0,
            onHorizontalDragUpdate: (d) => _arrasto += d.delta.dx,
            onHorizontalDragEnd: _onSwipe,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _dispararBomDia();
                _dispararResumoNoite();
                _adiarApagao();
                _entrarModoManual();
              },
              child: _aplicarTransicao(_buildTela()),
            ),
          ),
        ),
      );
    }
    // O assistente e o alarme do temporizador ficam por cima de tudo —
    // inclusive do Modo Noite.
    return Stack(
      children: [
        Positioned.fill(child: conteudo),
        const Positioned.fill(child: CamadaAssistente()),
      ],
    );
  }
}
