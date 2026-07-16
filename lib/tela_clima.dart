import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config_manager.dart';
import 'cache_manager.dart';
import 'responsive.dart';

// ═══════════════════════════════════════════════════════════════════════
//  MapaClimaManager — mantém o WebView do mapa do Windy sempre "morno".
//
//  Antes, a TelaClima criava um WebViewController novo a cada vez que
//  aparecia na rotação — isso forçava o app a recarregar a página do
//  Windy (HTML/JS/tiles) do zero todo santo ciclo, e por isso o mapa
//  parecia "carregar uma página da web" visivelmente.
//
//  Agora existe um único controller, vivo durante todo o app. Ele só
//  recarrega a página quando a localização realmente muda (troca de
//  cidade nas configurações). Nas demais vezes, o mapa já está pronto
//  e aparece instantâneo.
// ═══════════════════════════════════════════════════════════════════════
class MapaClimaManager extends ChangeNotifier {
  MapaClimaManager._() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _marcarPronto(),
          onWebResourceError: (erro) => _tratarErro(erro),
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

  /// true quando a última tentativa de carregar o mapa falhou. A tela
  /// de clima usa isso para mostrar uma mensagem de erro em vez de
  /// deixar a "página não disponível" do WebView visível pro usuário.
  bool get comErro => _comErro;

  void _marcarPronto() {
    _timeoutTimer?.cancel();
    _comErro = false;
    final c = _carregandoCompleter;
    if (c != null && !c.isCompleted) c.complete();
    notifyListeners();
  }

  void _tratarErro(WebResourceError erro) {
    // Erros de sub-recursos (ex: uma tile do mapa que falhou) não devem
    // derrubar o mapa inteiro — só tratamos como falha real quando é
    // o frame principal que não carregou.
    if (erro.isForMainFrame == false) return;
    _timeoutTimer?.cancel();
    _comErro = true;
    // Libera a localização: a PRÓXIMA vez que a tela de clima chamar
    // garantirLocalizacao (ex: quando reaparecer na sequência), o app
    // vai tentar carregar de novo em vez de ficar preso na falha antiga.
    _localizacaoAtual = null;
    final c = _carregandoCompleter;
    if (c != null && !c.isCompleted) c.complete();
    notifyListeners();
  }

  /// Garante que o mapa está mostrando a localização certa. Se já estiver
  /// nessa mesma localização E tiver carregado com sucesso, não recarrega
  /// nada — só retorna na hora. Se a última tentativa falhou, tenta de
  /// novo automaticamente.
  Future<void> garantirLocalizacao(String lat, String lon) {
    final chave = '$lat,$lon';
    if (_localizacaoAtual == chave && !_comErro) {
      return _carregandoCompleter?.future ?? Future.value();
    }

    _localizacaoAtual = chave;
    _comErro = false;
    _carregandoCompleter = Completer<void>();
    _controller.loadRequest(Uri.parse(
        "https://embed.windy.com/embed2.html?lat=$lat&lon=$lon&zoom=12&level=surface&overlay=rain&product=ecmwf"));

    // Timeout de segurança: se em 15s a página não terminar de carregar
    // nem disparar onWebResourceError claramente (acontece em alguns
    // casos de rede instável sem uma falha "limpa"), trata como erro e
    // libera nova tentativa na próxima visita à tela.
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      final c = _carregandoCompleter;
      if (c != null && !c.isCompleted) {
        _comErro = true;
        _localizacaoAtual = null;
        c.complete();
        notifyListeners();
      }
    });

    return _carregandoCompleter!.future;
  }

  /// Força uma nova tentativa imediatamente (ex: usuário tocou no mapa
  /// com erro pra tentar de novo na hora, sem esperar a tela reaparecer).
  Future<void> tentarNovamente(String lat, String lon) {
    _localizacaoAtual = null;
    return garantirLocalizacao(lat, lon);
  }
}

class TelaClima extends StatefulWidget {
  final VoidCallback aoTerminar;

  const TelaClima({
    super.key,
    required this.aoTerminar,
  });

  @override
  State<TelaClima> createState() => _TelaClimaState();
}

class _TelaClimaState extends State<TelaClima> {
  final _cfg = ConfigManager();

  String get _lat => _cfg.getString('clima', 'lat', '-22.889');
  String get _lon => _cfg.getString('clima', 'lon', '-47.222');
  int get _duracaoSeg => _cfg.getInt('clima', 'duracao_seg', 20);

  String tempAtual = "--";
  String sensacaoTermica = "--";
  String chanceChuvaHoje = "0";
  String msgSistema = "Sincronizando clima...";
  String horarioChuva = "";

  bool vaiChoverHoje = false;
  bool carregando = true;
  bool _isLightOn = true;
  bool _mapaPronto = false;
  bool _mapaComErro = false;

  int weatherCodeAtual = 0;
  List<dynamic> forecastData = [];

  Timer? _luzTimer;
  Timer? _climaUpdateTimer;
  Timer? _transicaoTimer;

  @override
  void initState() {
    super.initState();

    _luzTimer = Timer.periodic(const Duration(seconds: 3), (t) {
      if (mounted) setState(() => _isLightOn = !_isLightOn);
    });

    MapaClimaManager.instance.garantirLocalizacao(_lat, _lon).then((_) {
      if (mounted) {
        setState(() {
          _mapaPronto = true;
          _mapaComErro = MapaClimaManager.instance.comErro;
        });
      }
    });

    _carregarClima();

    _climaUpdateTimer = Timer.periodic(
        _cfg.getIntervaloAtualizacao('clima'), (t) => fetchWeatherData());
  }

  @override
  void dispose() {
    _luzTimer?.cancel();
    _climaUpdateTimer?.cancel();
    _transicaoTimer?.cancel();
    super.dispose();
  }

  // Inclui lat/lon na chave: ao trocar de cidade nas configurações, o
  // cache antigo (de outra cidade) deixa de bater automaticamente, sem
  // precisar esperar o intervalo configurado vencer.
  String get _chaveCache => 'clima_dados_${_lat}_$_lon';

  /// Verifica o cache antes de ir para a internet. Se já existir um dado
  /// salvo dentro do intervalo configurado pelo usuário, usa ele na hora
  /// (tela aparece sem spinner, sem gastar internet). Só busca de novo se
  /// não tiver cache ou se ele já tiver expirado.
  Future<void> _carregarClima() async {
    final cache = await CacheManager.instance.obter<Map<String, dynamic>>(
      _chaveCache,
      validade: _cfg.getIntervaloAtualizacao('clima'),
    );
    if (cache != null) {
      if (!mounted) return;
      _aplicarDados(cache);
      _iniciarTimerSaida(segundos: _duracaoSeg);
      return;
    }
    await fetchWeatherData();
  }

  Future<void> fetchWeatherData() async {
    try {
      final url = Uri.parse('https://api.open-meteo.com/v1/forecast'
          '?latitude=$_lat'
          '&longitude=$_lon'
          '&current=temperature_2m,apparent_temperature,weather_code'
          '&hourly=precipitation_probability,weathercode'
          '&daily=temperature_2m_max,precipitation_probability_max,weathercode'
          '&timezone=America%2FSao_Paulo');

      // Antes: sem timeout algum — se a conexão travasse sem dar erro
      // claro, o spinner de carregando ficava girando pra sempre.
      final response = await http.get(url).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          _aplicarDados(data);
          _iniciarTimerSaida(segundos: _duracaoSeg);
        }
        await CacheManager.instance.salvar(_chaveCache, data);
      } else {
        // Antes: uma resposta que não fosse 200 (erro do servidor,
        // limite de requisições, etc.) não fazia NADA — nem mostrava
        // erro nem desligava o spinner. Ficava travado pra sempre.
        debugPrint('TelaClima: resposta ${response.statusCode} da API');
        if (mounted) {
          setState(() {
            msgSistema = "Falha ao sincronizar clima.";
            carregando = false;
          });
          _iniciarTimerSaida(segundos: 5);
        }
      }
    } catch (e) {
      debugPrint('TelaClima fetchWeatherData: $e');
      if (mounted) {
        // Antes: mostrava a mensagem de erro mas esquecia de desligar
        // o "carregando" — a tela continuava presa no spinner mesmo
        // com o erro já detectado.
        setState(() {
          msgSistema = "Falha ao sincronizar clima.";
          carregando = false;
        });
        _iniciarTimerSaida(segundos: 5);
      }
    }
  }

  /// Aplica um Map de dados (vindo da API ou do cache) ao estado da tela.
  void _aplicarDados(Map<String, dynamic> data) {
    final hourlyTimes = data['hourly']['time'] as List;
    final hourlyRain = data['hourly']['precipitation_probability'] as List;
    final DateTime agora = DateTime.now();
    final DateTime fimDoDia =
        DateTime(agora.year, agora.month, agora.day, 23, 59);

    List<String> horariosComChuva = [];
    int chuvaDiaInteiro = 0;

    for (int i = 0; i < hourlyTimes.length; i++) {
      DateTime horaPrevisao = DateTime.parse(hourlyTimes[i]);
      int probabilidade = hourlyRain[i] ?? 0;

      if (horaPrevisao.isAfter(agora) && horaPrevisao.isBefore(fimDoDia)) {
        if (probabilidade > chuvaDiaInteiro) {
          chuvaDiaInteiro = probabilidade;
        }
        if (probabilidade >= 30) {
          horariosComChuva.add(DateFormat('HH:mm').format(horaPrevisao));
        }
      }
    }

    final current = data['current'];
    final temp =
        (current['temperature_2m'] as num?)?.round().toString() ?? '--';
    final sensacao =
        (current['apparent_temperature'] as num?)?.round().toString() ?? '--';
    final wCode = current['weather_code'] ?? 0;

    setState(() {
      weatherCodeAtual = wCode;
      tempAtual = temp;
      sensacaoTermica = sensacao;
      chanceChuvaHoje = chuvaDiaInteiro.toString();
      vaiChoverHoje = horariosComChuva.isNotEmpty;

      if (vaiChoverHoje) {
        msgSistema = "Atenção! Chuva prevista!";
        horarioChuva = "Risco de chuva: ${horariosComChuva.take(4).join(', ')}";
      } else {
        msgSistema = "Tempo limpo no radar!";
        horarioChuva = "Sem previsão de chuva nas próximas horas.";
      }

      forecastData = List.generate(4, (i) {
        return {
          'temp': data['daily']['temperature_2m_max'][i + 1].round().toString(),
          'pop':
              data['daily']['precipitation_probability_max'][i + 1].toString(),
          'code': data['daily']['weathercode'][i + 1],
          'dia': i + 1,
        };
      });
      carregando = false;
    });
  }

  /// Mapa do clima — usa o controller compartilhado (sempre "morno").
  /// Só mostra o overlay de carregando na primeira vez de verdade; nas
  /// próximas visitas o mapa já está pronto e aparece direto.
  Widget _buildMapa() {
    if (_mapaComErro) {
      return Container(
        color: const Color(0xFF0d1b2a),
        child: Center(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _mapaPronto = false;
                _mapaComErro = false;
              });
              MapaClimaManager.instance.tentarNovamente(_lat, _lon).then((_) {
                if (mounted) {
                  setState(() {
                    _mapaPronto = true;
                    _mapaComErro = MapaClimaManager.instance.comErro;
                  });
                }
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded,
                    color: Colors.white54, size: 40),
                const SizedBox(height: 10),
                const Text(
                  'Mapa indisponível no momento',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  'Toque para tentar novamente',
                  style: TextStyle(
                    color: Colors.cyanAccent.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
          child: IgnorePointer(
            child: Container(
              color: const Color(0xFF0d1b2a),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white54),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _iniciarTimerSaida({required int segundos}) {
    _transicaoTimer?.cancel();
    _transicaoTimer = Timer(Duration(seconds: segundos), () {
      if (mounted) widget.aoTerminar();
    });
  }

  String _getWeatherAnimation(int code) {
    if (code == 0) return 'assets/weather/sunny.json';
    if (code >= 1 && code <= 3) return 'assets/weather/cloudy.json';
    if (code == 45 || code == 48) return 'assets/weather/fog.json';
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
      return 'assets/weather/rain.json';
    }
    if (code >= 95 && code <= 99) return 'assets/weather/storm.json';
    return 'assets/weather/night.json';
  }

  Widget _getModernIcon(int code, {double size = 80}) {
    return Lottie.asset(
      _getWeatherAnimation(code),
      width: size,
      height: size,
      fit: BoxFit.contain,
      repeat: true,
    );
  }

  List<Color> _getBackgroundColors() {
    if (weatherCodeAtual == 0) {
      return [const Color(0xff1e3c72), const Color(0xff2a5298)];
    }
    if (weatherCodeAtual >= 1 && weatherCodeAtual <= 3) {
      return [const Color(0xff232526), const Color(0xff414345)];
    }
    if ((weatherCodeAtual >= 51 && weatherCodeAtual <= 67) ||
        (weatherCodeAtual >= 80 && weatherCodeAtual <= 82)) {
      return [
        const Color(0xff0f2027),
        const Color(0xff203a43),
        const Color(0xff2c5364)
      ];
    }
    return [const Color(0xff141e30), const Color(0xff243b55)];
  }

  @override
  Widget build(BuildContext context) {
    final Color alertaCor =
        vaiChoverHoje ? Colors.redAccent : Colors.greenAccent;
    final Color glowColor = _isLightOn
        ? Colors.cyanAccent
        : Colors.cyanAccent.withValues(alpha: 0.15);

    final r = R(context);
    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(seconds: 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _getBackgroundColors(),
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0.12,
            child: Image.network(
              "https://images.unsplash.com/photo-1504608524841-42fe6f032b4b?q=80&w=2000",
              fit: BoxFit.cover,
            ),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.32)),
        SafeArea(
          child: Center(
            child: Container(
              width: r.panelWidth,
              height: r.panelHeight,
              padding: EdgeInsets.symmetric(
                  horizontal: r.sp(20), vertical: r.sp(14)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: 1),
                ],
              ),
              child: Column(
                children: [
                  // ── Header ──────────────────────────────────────────────────
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 2500),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: glowColor,
                          boxShadow: [
                            BoxShadow(
                                color: glowColor.withValues(alpha: 0.8),
                                blurRadius: 15,
                                spreadRadius: 3),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Monitoramento Climático Inteligente ⚡",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: r.fs(19),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 1.3,
                    width: double.infinity,
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
                              Expanded(
                                flex: 2,
                                child: _buildPainelClima(r, alertaCor),
                              ),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                SizedBox(
                                  height: r.isCompact ? r.h(0.28) : r.h(0.32),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: _buildMapa(),
                                  ),
                                ),
                                SizedBox(height: r.sp(16)),
                                SizedBox(
                                  height: r.isCompact ? r.h(0.52) : r.h(0.48),
                                  child: _buildPainelClima(r, alertaCor),
                                ),
                              ],
                            ),
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

  Widget _buildPainelClima(R r, Color alertaCor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── Bloco superior: Temperatura + sensação + chuva ────────────────
        Column(
          children: [
            Text(
              "Temperatura Atual",
              style: GoogleFonts.poppins(
                color: Colors.white70,
                // MAIOR: era r.fs(15), agora r.fs(18)
                fontSize: r.fs(18),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tempAtual,
                      style: GoogleFonts.poppins(
                        // MAIOR: era r.fs(r.isCompact ? 64 : 90), agora +12
                        fontSize: r.fs(r.isCompact ? 76 : 102),
                        color: Colors.white,
                        fontWeight: FontWeight.w200,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: r.sp(28)),
                  child: Text(
                    "°C",
                    style: GoogleFonts.poppins(
                      // MAIOR: era r.fs(26), agora r.fs(32)
                      fontSize: r.fs(32),
                      color: Colors.white60,
                    ),
                  ),
                ),
                SizedBox(width: r.sp(5)),
                _getModernIcon(
                  weatherCodeAtual,
                  // MAIOR: era r.icon(r.isCompact ? 56 : 85), agora +14
                  size: r.icon(r.isCompact ? 70 : 99),
                ),
              ],
            ),

            // ── Sensação térmica ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.thermostat,
                    // MAIOR: era size 17, agora 22
                    color: Colors.orangeAccent,
                    size: 22),
                const SizedBox(width: 6),
                Text(
                  "Sensação: $sensacaoTermica°C",
                  style: GoogleFonts.poppins(
                    color: Colors.orangeAccent,
                    // MAIOR: era 14, agora r.fs(18)
                    fontSize: r.fs(18),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            SizedBox(height: r.sp(8)),

            // ── Chance de chuva ───────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.water_drop,
                    // MAIOR: era size 17, agora 22
                    color: Colors.lightBlueAccent,
                    size: 22),
                const SizedBox(width: 6),
                Text(
                  "$chanceChuvaHoje% chance de chuva",
                  style: GoogleFonts.poppins(
                    color: Colors.lightBlueAccent,
                    // MAIOR: era 14, agora r.fs(18)
                    fontSize: r.fs(18),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),

        // ── Próximos dias ─────────────────────────────────────────────────
        // Removido espaçamento extra; o mainAxisAlignment.spaceBetween
        // já distribui — essa seção fica naturalmente mais próxima do bloco
        // de temperatura acima.
        Column(
          children: [
            Text(
              "Próximos dias",
              style: GoogleFonts.poppins(
                color: Colors.white,
                // MAIOR: era 14, agora r.fs(17)
                fontSize: r.fs(17),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: r.sp(10)),
            if (!carregando)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: forecastData.map((d) {
                  return Column(
                    children: [
                      // Dia da semana — MAIOR: era r.fs(13), agora r.fs(16)
                      Text(
                        [
                          "Dom",
                          "Seg",
                          "Ter",
                          "Qua",
                          "Qui",
                          "Sex",
                          "Sáb"
                        ][DateTime.now().add(Duration(days: d['dia'])).weekday %
                            7],
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: r.fs(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // Ícone — MAIOR: era r.icon(42), agora r.icon(54)
                      _getModernIcon(d['code'], size: r.icon(54)),
                      // Temperatura — MAIOR: era fontSize 20, agora r.fs(24)
                      Text(
                        "${d['temp']}°",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: r.fs(24),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // % chuva — MAIOR: era r.fs(12), agora r.fs(15)
                      Row(
                        children: [
                          Icon(Icons.water_drop,
                              color: Colors.lightBlueAccent, size: r.icon(15)),
                          Text(
                            "${d['pop']}%",
                            style: GoogleFonts.poppins(
                              color: Colors.lightBlueAccent,
                              fontSize: r.fs(15),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }).toList(),
              ),
          ],
        ),

        // ── Card de alerta — MUITO MAIOR e mais chamativo ─────────────────
        Container(
          width: double.infinity,
          // Altura mínima garantida para ser visto de longe
          constraints: const BoxConstraints(minHeight: 90),
          padding: EdgeInsets.symmetric(
            // MAIOR: era r.sp(16)/r.sp(10), agora r.sp(20)/r.sp(18)
            horizontal: r.sp(20),
            vertical: r.sp(18),
          ),
          decoration: BoxDecoration(
            color: alertaCor.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: alertaCor.withValues(alpha: 0.7),
              // MAIOR: era width 2, agora 3
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: alertaCor.withValues(alpha: vaiChoverHoje ? 0.35 : 0.20),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                vaiChoverHoje ? Icons.umbrella : Icons.check_circle,
                color: alertaCor,
                // MAIOR: era r.icon(30), agora r.icon(48)
                size: r.icon(48),
              ),
              SizedBox(width: r.sp(14)),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msgSistema.toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        // MAIOR: era r.fs(14), agora r.fs(20)
                        fontSize: r.fs(20),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: r.sp(4)),
                    Text(
                      horarioChuva,
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.90),
                        // MAIOR: era r.fs(12), agora r.fs(16)
                        fontSize: r.fs(16),
                        fontWeight: FontWeight.w400,
                      ),
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
}
