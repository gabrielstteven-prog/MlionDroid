import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'design/tema.dart';
import 'performance_manager.dart';
import 'responsive.dart';
import 'services/weather_service.dart';
import 'util.dart';

// ═══════════════════════════════════════════════════════════════════════
//  MapaClimaManager — mantém o WebView do mapa do Windy sempre "morno".
//  Um único controller vivo durante todo o app; só recarrega quando a
//  localização muda ou quando a última tentativa falhou.
// ═══════════════════════════════════════════════════════════════════════
class MapaClimaManager extends ChangeNotifier {
  MapaClimaManager._() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _marcarPronto(),
          onWebResourceError: _tratarErro,
        ),
      );
  }
  static final MapaClimaManager instance = MapaClimaManager._();

  late final WebViewController _controller;
  WebViewController get controller => _controller;

  String? _localizacaoAtual;
  Completer<void>? _carregandoCompleter;
  Timer? _timeoutTimer;
  bool _comErro = false;
  bool get comErro => _comErro;

  void _marcarPronto() {
    _timeoutTimer?.cancel();
    _comErro = false;
    final c = _carregandoCompleter;
    if (c != null && !c.isCompleted) c.complete();
    notifyListeners();
  }

  void _tratarErro(WebResourceError erro) {
    // Erro numa tile do mapa não derruba o mapa inteiro.
    if (erro.isForMainFrame == false) return;
    _falhar();
  }

  void _falhar() {
    _timeoutTimer?.cancel();
    _comErro = true;
    _localizacaoAtual = null; // próxima visita tenta de novo
    final c = _carregandoCompleter;
    if (c != null && !c.isCompleted) c.complete();
    notifyListeners();
  }

  Future<void> garantirLocalizacao(String lat, String lon) {
    final chave = '$lat,$lon';
    if (_localizacaoAtual == chave && !_comErro) {
      return _carregandoCompleter?.future ?? Future.value();
    }
    _localizacaoAtual = chave;
    _comErro = false;
    _carregandoCompleter = Completer<void>();
    _controller.loadRequest(Uri.parse(
        'https://embed.windy.com/embed2.html?lat=$lat&lon=$lon&zoom=12&level=surface&overlay=rain&product=ecmwf'));
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      final c = _carregandoCompleter;
      if (c != null && !c.isCompleted) _falhar();
    });
    return _carregandoCompleter!.future;
  }

  Future<void> tentarNovamente(String lat, String lon) {
    _localizacaoAtual = null;
    return garantirLocalizacao(lat, lon);
  }
}

class TelaClima extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaClima({super.key, required this.aoTerminar});

  @override
  State<TelaClima> createState() => _TelaClimaState();
}

class _TelaClimaState extends State<TelaClima> {
  final _cfg = ConfigManager();

  String get _lat => _cfg.getString('clima', 'lat', '-22.889');
  String get _lon => _cfg.getString('clima', 'lon', '-47.222');
  int get _duracaoSeg => _cfg.getInt('clima', 'duracao_seg', 20).clamp(5, 300);

  DadosClima? _dados = WeatherService.instance.atual;
  bool _carregando = WeatherService.instance.atual == null;
  bool _mapaPronto = false;
  bool _mapaComErro = false;
  Timer? _saidaTimer;

  @override
  void initState() {
    super.initState();
    MapaClimaManager.instance.garantirLocalizacao(_lat, _lon).then((_) {
      if (!mounted) return;
      setState(() {
        _mapaPronto = true;
        _mapaComErro = MapaClimaManager.instance.comErro;
      });
    });
    _carregar();
  }

  Future<void> _carregar() async {
    final dados = await WeatherService.instance.obter();
    if (!mounted) return;
    setState(() {
      _dados = dados;
      _carregando = false;
    });
    _saidaTimer?.cancel();
    _saidaTimer = Timer(Duration(seconds: dados == null ? 6 : _duracaoSeg), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _saidaTimer?.cancel();
    super.dispose();
  }

  void _tentarMapaDeNovo() {
    setState(() {
      _mapaPronto = false;
      _mapaComErro = false;
    });
    MapaClimaManager.instance.tentarNovamente(_lat, _lon).then((_) {
      if (!mounted) return;
      setState(() {
        _mapaPronto = true;
        _mapaComErro = MapaClimaManager.instance.comErro;
      });
    });
  }

  Widget _buildMapa() {
    if (_mapaComErro) {
      return Container(
        color: const Color(0xFF0d1b2a),
        child: Center(
          child: GestureDetector(
            onTap: _tentarMapaDeNovo,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, color: Colors.white54, size: 40),
                const SizedBox(height: 10),
                const Text('Mapa indisponível no momento',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 6),
                Text('Toque para tentar novamente',
                    style: TextStyle(
                      color: Colors.cyanAccent.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: MapaClimaManager.instance.controller),
        AnimatedOpacity(
          opacity: _mapaPronto ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 400),
          child: const IgnorePointer(
            child: ColoredBox(
              color: Color(0xFF0d1b2a),
              child: Center(child: CircularProgressIndicator(color: Colors.white54)),
            ),
          ),
        ),
      ],
    );
  }

  /// Animação Lottie por código WMO, respeitando dia/noite. Códigos que
  /// não têm animação própria (ex.: neve) caem em "nublado", não em "noite".
  String _animacao(int code, bool ehDia) {
    if (code == 0 || code == 1) {
      return ehDia ? 'assets/weather/sunny.json' : 'assets/weather/night.json';
    }
    if (code <= 3) return 'assets/weather/cloudy.json';
    if (code <= 48) return 'assets/weather/fog.json';
    if (code >= 95) return 'assets/weather/storm.json';
    if (code <= 67 || (code >= 80 && code <= 82)) return 'assets/weather/rain.json';
    return 'assets/weather/cloudy.json';
  }

  Widget _icone(int code, bool ehDia, double size, {bool animar = true}) {
    return Lottie.asset(
      _animacao(code, ehDia),
      width: size,
      height: size,
      fit: BoxFit.contain,
      animate: animar && PerformanceManager.instance.animacoesDecorativasAtivas,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final dados = _dados;
    return EstruturaTela(
      icone: Icons.cloud_rounded,
      titulo: 'Clima em ${_cfg.getString('clima', 'cidade', 'Hortolândia')}',
      subtitulo: dados == null ? null : descricaoClima(dados.codigo),
      destaque: Destaques.clima,
      rodapeDireita:
          dados == null ? null : 'Atualizado ${descreverIdade(dados.atualizadoEm)}',
      child: dados == null
          ? (_carregando
              ? const Carregando(cor: Destaques.clima)
              : const AvisoTela(
                  icone: Icons.cloud_off_rounded,
                  titulo: 'Sem dados de clima',
                  texto: 'Não foi possível falar com o serviço de previsão. '
                      'A tela tenta de novo na próxima passagem.',
                ))
          : r.useSideBySide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: _buildPainel(r, dados)),
                    SizedBox(width: r.sp(28)),
                    Expanded(
                      flex: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(r.sp(24)),
                        child: _buildMapa(),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Expanded(flex: 5, child: _buildPainel(r, dados)),
                    SizedBox(height: r.sp(16)),
                    Expanded(
                      flex: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(r.sp(24)),
                        child: _buildMapa(),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPainel(R r, DadosClima dados) {
    final t = Tipo(r);
    final chuva = dados.chuvaRestanteHoje();
    final vaiChover = chuva.horarios.isNotEmpty;
    final hoje = dados.hoje;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Agora ──────────────────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('${dados.temp}°', style: t.heroi()),
            SizedBox(width: r.sp(12)),
            _icone(dados.codigo, dados.ehDia, r.icon(r.isCompact ? 80 : 110)),
          ],
        ),
        SizedBox(height: r.sp(4)),
        Text(
          hoje == null
              ? 'Sensação de ${dados.sensacao}°'
              : 'Sensação de ${dados.sensacao}°. Hoje entre ${hoje.min}° e ${hoje.max}°.',
          style: t.corpo(cor: Cores.textoSecundario),
        ),
        SizedBox(height: r.sp(16)),
        // ── Chuva: uma frase direta, com a cor dizendo a gravidade ─────────
        Superficie(
          tinta: vaiChover ? Cores.chuva : Cores.positivo,
          padding: EdgeInsets.symmetric(horizontal: r.sp(20), vertical: r.sp(14)),
          child: Row(
            children: [
              Icon(vaiChover ? Icons.umbrella_rounded : Icons.wb_sunny_outlined,
                  color: vaiChover ? Cores.chuva : Cores.positivo, size: r.icon(32)),
              SizedBox(width: r.sp(14)),
              Expanded(
                child: Text(
                  vaiChover
                      ? 'Chuva possível hoje às ${chuva.horarios.take(3).map((h) => '${h.hour}h').join(', ')} (até ${chuva.maxima}%). Leve guarda-chuva.'
                      : 'Sem chuva prevista para o resto do dia.',
                  style: t.corpo(peso: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // ── Próximos dias ──────────────────────────────────────────────────
        Text('Próximos dias', style: t.legenda()),
        SizedBox(height: r.sp(10)),
        Row(
          children: [
            for (final d in dados.proximosDias.take(4))
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(diaSemanaCurto(d.dia), style: t.corpo(peso: FontWeight.w700)),
                    // Ícones pequenos parados: 4 animações Lottie ao mesmo
                    // tempo pesavam em tablets simples.
                    _icone(d.codigo, true, r.icon(52), animar: false),
                    Text('${d.max}°', style: t.subtitulo()),
                    Text('${d.min}°', style: t.apoio()),
                    if (d.chanceChuva >= 20)
                      Text('${d.chanceChuva}% chuva', style: t.legenda(cor: Cores.chuva)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

