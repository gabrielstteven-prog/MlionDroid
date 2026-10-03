import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
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

  List<Color> _coresFundo(int code, bool ehDia) {
    if (!ehDia) return [const Color(0xff0b1026), const Color(0xff1b2a4a)];
    if (code == 0) return [const Color(0xff1e3c72), const Color(0xff2a5298)];
    if (code <= 3) return [const Color(0xff232526), const Color(0xff414345)];
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
      return [const Color(0xff0f2027), const Color(0xff203a43), const Color(0xff2c5364)];
    }
    return [const Color(0xff141e30), const Color(0xff243b55)];
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final dados = _dados;
    final code = dados?.codigo ?? 0;
    final ehDia = dados?.ehDia ?? true;

    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(seconds: 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _coresFundo(code, ehDia),
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0.12,
            child: CachedNetworkImage(
              imageUrl:
                  'https://images.unsplash.com/photo-1504608524841-42fe6f032b4b?q=70&w=1600',
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.32)),
        SafeArea(
          child: Center(
            child: Container(
              width: r.panelWidth,
              height: r.panelHeight,
              padding: EdgeInsets.symmetric(horizontal: r.sp(20), vertical: r.sp(14)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const _PontoPulsante(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Clima em ${_cfg.getString('clima', 'cidade', 'Hortolândia')}',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: r.fs(19),
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (dados != null)
                        Text(
                          'Atualizado ${descreverIdade(dados.atualizadoEm)}',
                          style: GoogleFonts.poppins(
                              color: Colors.white54, fontSize: r.fs(13)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 1.3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.cyanAccent,
                        Colors.blueAccent.withValues(alpha: 0.3)
                      ]),
                    ),
                  ),
                  SizedBox(height: r.sp(15)),
                  Expanded(
                    child: r.useSideBySide
                        ? Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: _buildMapa(),
                                ),
                              ),
                              SizedBox(width: r.sp(24)),
                              Expanded(flex: 2, child: _buildPainel(r)),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(
                                flex: 4,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: _buildMapa(),
                                ),
                              ),
                              SizedBox(height: r.sp(16)),
                              Expanded(flex: 5, child: _buildPainel(r)),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPainel(R r) {
    final dados = _dados;
    if (dados == null) {
      return Center(
        child: _carregando
            ? const CircularProgressIndicator(color: Colors.white54)
            : Text('Sem conexão com o serviço de clima.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: r.fs(18))),
      );
    }

    final chuva = dados.chuvaRestanteHoje();
    final vaiChover = chuva.horarios.isNotEmpty;
    final alertaCor = vaiChover ? Colors.redAccent : Colors.greenAccent;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          children: [
            Text(descricaoClima(dados.codigo),
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: r.fs(18))),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${dados.temp}',
                      style: GoogleFonts.poppins(
                        fontSize: r.fs(r.isCompact ? 76 : 102),
                        color: Colors.white,
                        fontWeight: FontWeight.w200,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: r.sp(28)),
                  child: Text('°C',
                      style: GoogleFonts.poppins(fontSize: r.fs(32), color: Colors.white60)),
                ),
                SizedBox(width: r.sp(5)),
                _icone(dados.codigo, dados.ehDia, r.icon(r.isCompact ? 70 : 99)),
              ],
            ),
            _linhaInfo(Icons.thermostat, Colors.orangeAccent,
                'Sensação: ${dados.sensacao}°C', r),
            SizedBox(height: r.sp(6)),
            if (dados.hoje != null)
              _linhaInfo(Icons.swap_vert_rounded, Colors.white70,
                  'Mín ${dados.hoje!.min}°  •  Máx ${dados.hoje!.max}°', r),
            SizedBox(height: r.sp(6)),
            _linhaInfo(Icons.water_drop, Colors.lightBlueAccent,
                '${chuva.maxima}% chance de chuva', r),
          ],
        ),
        Column(
          children: [
            Text('Próximos dias',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: r.fs(17), fontWeight: FontWeight.w600)),
            SizedBox(height: r.sp(10)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: dados.proximosDias.take(4).map((d) {
                return Column(
                  children: [
                    Text(diaSemanaCurto(d.dia),
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: r.fs(16),
                            fontWeight: FontWeight.w600)),
                    // Os ícones pequenos ficam parados: 4 animações Lottie
                    // simultâneas pesavam bastante em tablets simples.
                    _icone(d.codigo, true, r.icon(54), animar: false),
                    Text('${d.max}°',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: r.fs(24),
                            fontWeight: FontWeight.w600)),
                    Text('${d.min}°',
                        style: GoogleFonts.poppins(
                            color: Colors.white54, fontSize: r.fs(15))),
                    Row(children: [
                      Icon(Icons.water_drop,
                          color: Colors.lightBlueAccent, size: r.icon(15)),
                      Text('${d.chanceChuva}%',
                          style: GoogleFonts.poppins(
                              color: Colors.lightBlueAccent, fontSize: r.fs(15))),
                    ]),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 90),
          padding: EdgeInsets.symmetric(horizontal: r.sp(20), vertical: r.sp(18)),
          decoration: BoxDecoration(
            color: alertaCor.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: alertaCor.withValues(alpha: 0.7), width: 3),
          ),
          child: Row(
            children: [
              Icon(vaiChover ? Icons.umbrella : Icons.check_circle,
                  color: alertaCor, size: r.icon(48)),
              SizedBox(width: r.sp(14)),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vaiChover ? 'ATENÇÃO! CHUVA PREVISTA!' : 'TEMPO LIMPO NO RADAR!',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: r.fs(20),
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: r.sp(4)),
                    Text(
                      vaiChover
                          ? 'Risco de chuva: ${chuva.horarios.take(4).map(horaMinuto).join(', ')}'
                          : 'Sem previsão de chuva nas próximas horas.',
                      style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.90), fontSize: r.fs(16)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linhaInfo(IconData icone, Color cor, String texto, R r) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icone, color: cor, size: 22),
        const SizedBox(width: 6),
        Text(texto,
            style: GoogleFonts.poppins(
                color: cor, fontSize: r.fs(18), fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Ponto "ao vivo" piscando — isolado num widget próprio para que só ele
/// seja redesenhado (antes um setState a cada 3s refazia a tela inteira,
/// inclusive o mapa).
class _PontoPulsante extends StatefulWidget {
  const _PontoPulsante();

  @override
  State<_PontoPulsante> createState() => _PontoPulsanteState();
}

class _PontoPulsanteState extends State<_PontoPulsante>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2500));

  @override
  void initState() {
    super.initState();
    if (PerformanceManager.instance.animacoesDecorativasAtivas) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(_ctrl),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.cyanAccent,
          boxShadow: [
            BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.8), blurRadius: 12),
          ],
        ),
      ),
    );
  }
}
