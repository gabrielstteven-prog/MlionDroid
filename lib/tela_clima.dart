import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'design/icones.dart';
import 'design/tema.dart';
import 'responsive.dart';
import 'services/avisos_service.dart';
import 'services/weather_service.dart';
import 'util.dart';
import 'widgets/card_avisos.dart';

/// Os três jeitos de ver o tempo no mapa.
enum ModoMapa { radar, previsao, temperatura }

extension on ModoMapa {
  String get rotulo => switch (this) {
        ModoMapa.radar => 'Radar ao vivo',
        ModoMapa.previsao => 'Previsão de chuva',
        ModoMapa.temperatura => 'Temperatura',
      };

  IconData get icone => switch (this) {
        ModoMapa.radar => Icons.radar_rounded,
        ModoMapa.previsao => Icons.thunderstorm_rounded,
        ModoMapa.temperatura => Icons.device_thermostat_rounded,
      };

  /// Radar: RainViewer mostra a chuva OBSERVADA nas últimas 2 horas,
  /// animada — é o que deixa ver a tempestade chegando.
  /// Previsão/Temperatura: Windy, com a linha do tempo dos próximos dias.
  /// Zoom 10: a cidade no centro e as vizinhas em volta (no 8 a cidade
  /// sumia no meio da região).
  String url(String lat, String lon) => switch (this) {
        ModoMapa.radar => 'https://www.rainviewer.com/map.html?loc=$lat,$lon,10'
            '&oFa=0&oC=1&oU=0&oCS=1&oF=0&oAP=1&c=3&o=83&lm=1&layer=radar&sm=1&sn=1',
        ModoMapa.previsao => _windy(lat, lon, 'rain'),
        ModoMapa.temperatura => _windy(lat, lon, 'temp'),
      };

  static String _windy(String lat, String lon, String overlay) =>
      'https://embed.windy.com/embed2.html?lat=$lat&lon=$lon'
      '&detailLat=$lat&detailLon=$lon&zoom=10&level=surface&overlay=$overlay'
      '&product=ecmwf&menu=&message=true&marker=true&calendar=now&pressure='
      '&type=map&location=coordinates&detail=&metricWind=km%2Fh&metricTemp=%C2%B0C';
}

// ═══════════════════════════════════════════════════════════════════════
//  MapaClimaManager — um WebView por mapa, vivo durante todo o app.
//  Cada mapa carrega UMA vez; trocar de modo só mostra o que já está
//  pronto (nada de recarregar a cada troca do rodízio). Recarrega só
//  quando os dados envelhecem: radar a cada 10 min, previsão e
//  temperatura a cada 1 h (o modelo do tempo muda devagar) — ou se a
//  cidade mudar ou der erro.
// ═══════════════════════════════════════════════════════════════════════
class _MapaVivo {
  final WebViewController controller = WebViewController();
  String? url;
  DateTime? carregadoEm;
  Completer<void>? carregando;
  Timer? timeout;
  bool erro = false;
  bool pronto = false;
}

class MapaClimaManager extends ChangeNotifier {
  MapaClimaManager._() {
    for (final m in ModoMapa.values) {
      final v = _MapaVivo();
      v.controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) => _marcarPronto(v),
            onWebResourceError: (e) {
              if (e.isForMainFrame != false) _falhar(v);
            },
          ),
        );
      _mapas[m] = v;
    }
  }
  static final MapaClimaManager instance = MapaClimaManager._();

  /// Desligado só em prévias renderizadas no PC (WebView não existe lá).
  static bool habilitado = true;

  final Map<ModoMapa, _MapaVivo> _mapas = {};

  /// Quanto tempo cada mapa vale antes de recarregar.
  static Duration validade(ModoMapa m) => m == ModoMapa.radar
      ? const Duration(minutes: 10)
      : const Duration(hours: 1);

  WebViewController controller(ModoMapa m) => _mapas[m]!.controller;
  bool comErro(ModoMapa m) => _mapas[m]!.erro;
  bool pronto(ModoMapa m) => _mapas[m]!.pronto;

  /// Já foi carregado alguma vez (o WebView dele entra na tela).
  bool iniciado(ModoMapa m) => _mapas[m]!.url != null;

  void _marcarPronto(_MapaVivo v) {
    v.timeout?.cancel();
    v.erro = false;
    v.pronto = true;
    v.carregadoEm = DateTime.now();
    if (v.carregando?.isCompleted == false) v.carregando!.complete();
    notifyListeners();
  }

  void _falhar(_MapaVivo v) {
    v.timeout?.cancel();
    v.erro = true;
    v.url = null;
    if (v.carregando?.isCompleted == false) v.carregando!.complete();
    notifyListeners();
  }

  Future<void> mostrar(String lat, String lon, ModoMapa modo,
      {bool forcar = false}) {
    final v = _mapas[modo]!;
    final url = modo.url(lat, lon);
    final velho = v.carregadoEm == null ||
        DateTime.now().difference(v.carregadoEm!) > validade(modo);
    if (!forcar && v.url == url && !v.erro && !velho) {
      return v.carregando?.future ?? Future.value();
    }
    // Recarregando por idade: o mapa antigo continua na tela até o novo
    // ficar pronto (não pisca a tela de "carregando").
    v.pronto = v.pronto && v.url == url && !forcar;
    v.url = url;
    v.erro = false;
    v.carregando = Completer<void>();
    v.controller.loadRequest(Uri.parse(url));
    v.timeout?.cancel();
    v.timeout = Timer(const Duration(seconds: 25), () {
      if (v.carregando?.isCompleted == false) _falhar(v);
    });
    notifyListeners();
    return v.carregando!.future;
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
  ModoMapa? _modo;
  List<Aviso> _avisos = [];
  bool _mapaPronto = false;
  Timer? _saidaTimer;
  bool _tempoCumprido = false;

  /// Rodízio dos mapas: cada um fica [_segPorMapa] s. Um toque num botão
  /// pausa o rodízio por 1 minuto; depois ele volta sozinho.
  /// A duração configurada da tela é dividida entre os três mapas (mínimo 15 s).
  int get _segPorMapa => (_duracaoSeg ~/ ModoMapa.values.length).clamp(15, 60);
  Timer? _rodizio;
  DateTime _manualAte = DateTime(2000);
  bool _avisosVistos = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _saidaTimer?.cancel();
    _rodizio?.cancel();
    super.dispose();
  }

  /// Mapas que já ficaram o tempo todo na tela. A tela só sai depois dos três.
  final Set<ModoMapa> _vistos = {};
  int _segNoMapa = 0;

  /// Roda a cada segundo. O tempo de cada mapa só conta depois que ele
  /// CARREGOU (mapa carregando não perde a vez); com erro, é pulado.
  void _relogioDoRodizio() {
    if (!mounted || _modo == null || DateTime.now().isBefore(_manualAte)) return;
    final modo = _modo!;
    final erro = MapaClimaManager.habilitado && MapaClimaManager.instance.comErro(modo);
    if (_mapaPronto || erro || !MapaClimaManager.habilitado) _segNoMapa++;
    if (_segNoMapa < _segPorMapa && !erro) return;
    _segNoMapa = 0;
    _vistos.add(modo);
    if (_vistos.length >= ModoMapa.values.length) {
      // Os três já passaram: fica mais um pouco e segue.
      _rodizio?.cancel();
      _saidaTimer?.cancel();
      _saidaTimer = Timer(const Duration(seconds: 8), () {
        _tempoCumprido = true;
        _tentarSair();
      });
      return;
    }
    final i = ModoMapa.values.indexOf(modo);
    _trocarModo(ModoMapa.values[(i + 1) % ModoMapa.values.length]);
  }

  /// Toque num botão do mapa: fica nele por 1 minuto; depois o rodízio volta.
  void _escolherMapa(ModoMapa m) {
    _manualAte = DateTime.now().add(const Duration(minutes: 1));
    _segNoMapa = 0;
    _trocarModo(m);
  }

  Future<void> _carregar() async {
    final dados = await WeatherService.instance.obter();
    if (!mounted) return;
    setState(() {
      _dados = dados;
      _carregando = false;
    });
    if (dados != null) {
      // Avisos da previsão na hora; os oficiais (INMET) chegam em seguida.
      setState(() => _avisos = AvisosService.daPrevisao(dados, DateTime.now()));
      AvisosService.instance.avisos().then((a) {
        if (mounted) {
          setState(() {
            _avisos = a;
            _avisosVistos = false; // lista nova: o ciclo recomeça
          });
        }
      });
    }
    // Com chance de chuva, abre direto no radar; senão, na previsão.
    final chuva = dados?.chuvaRestanteHoje().maxima ?? 0;
    final chovendo = (dados?.codigo ?? 0) >= 51;
    _trocarModo(chuva >= 30 || chovendo ? ModoMapa.radar : ModoMapa.previsao);
    if (dados == null) {
      // Sem dados do tempo: não segura a tela.
      _saidaTimer = Timer(const Duration(seconds: 6), () {
        _tempoCumprido = true;
        _tentarSair(semAvisos: true);
      });
      return;
    }
    // A saída acontece depois que os três mapas passaram (veja
    // _relogioDoRodizio). O app ainda tem um limite de segurança geral.
    _rodizio = Timer.periodic(const Duration(seconds: 1), (_) => _relogioDoRodizio());
  }

  /// A tela só segue quando o tempo dela acabou E todos os avisos já
  /// passaram pelo card — com 4 avisos, ninguém perde o terceiro.
  void _tentarSair({bool semAvisos = false}) {
    if (!mounted || !_tempoCumprido) return;
    if (_avisosVistos || semAvisos) widget.aoTerminar();
  }

  void _trocarModo(ModoMapa modo, {bool forcar = false}) {
    if (!MapaClimaManager.habilitado) {
      setState(() => _modo = modo);
      return;
    }
    final mapas = MapaClimaManager.instance;
    setState(() {
      _modo = modo;
      // Já carregado: aparece na hora (sem tela de "carregando").
      _mapaPronto = mapas.pronto(modo) && !forcar;
    });
    mapas.mostrar(_lat, _lon, modo, forcar: forcar).then((_) {
      if (mounted && _modo == modo) setState(() => _mapaPronto = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final dados = _dados;
    return EstruturaTela(
      icone: Icons.cloud_rounded,
      marca: dados == null
          ? null
          : IconeClima(
              codigo: dados.codigo, ehDia: dados.ehDia, tamanho: r.icon(60)),
      titulo: 'Clima em ${_cfg.getString('clima', 'cidade', 'Hortolândia')}',
      subtitulo: dados == null ? null : descricaoClima(dados.codigo),
      destaque: Destaques.clima,
      rodapeDireita: dados == null
          ? null
          : 'Atualizado ${descreverIdade(dados.atualizadoEm)}',
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
                    Expanded(flex: 9, child: _painel(r, dados)),
                    SizedBox(width: r.sp(28)),
                    Expanded(flex: 11, child: _mapa(r)),
                  ],
                )
              : Column(
                  children: [
                    Expanded(flex: 5, child: _painel(r, dados)),
                    SizedBox(height: r.sp(16)),
                    Expanded(flex: 5, child: _mapa(r)),
                  ],
                ),
    );
  }

  // ── Painel: agora, avisos e próximos dias (as horas de chuva já vêm no aviso) ──────────────────
  Widget _painel(R r, DadosClima d) {
    final t = Tipo(r);
    final hoje = d.hoje;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('${d.temp}°', style: t.heroi()),
            SizedBox(width: r.sp(20)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sensação de ${d.sensacao}°', style: t.subtitulo()),
                  if (hoje != null)
                    Text('Mínima ${hoje.min}°, máxima ${hoje.max}°',
                        style: t.corpo(cor: Cores.textoSecundario)),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: r.sp(30)), // respiro entre a temperatura e o card
        CardAvisos(
          aoCompletarCiclo: () {
            _avisosVistos = true;
            _tentarSair();
          },
          avisos: _avisos.isNotEmpty
              ? _avisos
              : const [
                  Aviso(
                      'Sem alertas para hoje',
                      'Tempo firme pelo resto do dia',
                      NivelAviso.tranquilo,
                      Icons.wb_sunny_rounded,
                      'Previsão'),
                ],
        ),
        // Título e dias juntos, centralizados no espaço que sobra.
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Próximos dias', style: t.legenda()),
              SizedBox(height: r.sp(12)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final dia in d.proximosDias.take(4))
                    Expanded(
                      // scaleDown: em telas mais baixas o dia encolhe em vez de cortar.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: Column(
                          children: [
                            Text(diaSemanaCurto(dia.dia),
                                style: t.corpo(peso: FontWeight.w700)),
                            IconeClima(
                                codigo: dia.codigo,
                                tamanho: r.icon(88),
                                animar: false),
                            // Máxima forte, mínima apagada: lê-se de longe.
                            Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '${dia.max}°  ', style: t.subtitulo()),
                              TextSpan(
                                  text: '${dia.min}°',
                                  style: t.subtitulo(cor: Cores.textoApagado)),
                            ])),
                            if (dia.chanceChuva >= 20)
                              Text('${dia.chanceChuva}% chuva',
                                  style: t.legenda(cor: Cores.chuva)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Mapa com seletor de modo ──────────────────────────────────────────────
  Widget _mapa(R r) {
    final t = Tipo(r);
    if (!MapaClimaManager.habilitado) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(r.sp(28)),
        child: ColoredBox(
            color: const Color(0xFF2B5C8A),
            child: Center(
                child:
                    Text('[ mapa: ${_modo?.rotulo} ]', style: t.subtitulo()))),
      );
    }
    final mapas = MapaClimaManager.instance;
    final atual = _modo ?? ModoMapa.radar;
    final erro = mapas.comErro(atual);
    return ClipRRect(
      borderRadius: BorderRadius.circular(r.sp(28)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Os mapas já carregados ficam vivos; só o atual aparece.
          for (final m in ModoMapa.values)
            if (m == atual || mapas.iniciado(m))
              Offstage(
                offstage: m != atual,
                child: WebViewWidget(
                    key: ValueKey(m), controller: mapas.controller(m)),
              ),
          if (!_mapaPronto || erro)
            ColoredBox(
              color: const Color(0xFF10284A),
              child: erro
                  ? GestureDetector(
                      onTap: () =>
                          _trocarModo(_modo ?? ModoMapa.radar, forcar: true),
                      child: const AvisoTela(
                        icone: Icons.map_outlined,
                        titulo: 'Mapa indisponível',
                        texto: 'Toque para tentar de novo.',
                      ),
                    )
                  : const Carregando(cor: Destaques.clima),
            ),
          Positioned(
            left: r.sp(14),
            top: r.sp(14),
            child: Row(
              children: [
                for (final m in ModoMapa.values)
                  Padding(
                    padding: EdgeInsets.only(right: r.sp(8)),
                    child: GestureDetector(
                      onTap: () => _escolherMapa(m),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: r.sp(14), vertical: r.sp(9)),
                        decoration: BoxDecoration(
                          color: m == _modo
                              ? Cores.texto
                              : const Color(0xFF0B1B33).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(r.sp(30)),
                        ),
                        child: Row(children: [
                          Icon(m.icone,
                              size: r.icon(20),
                              color: m == _modo ? Colors.black : Cores.texto),
                          SizedBox(width: r.sp(6)),
                          Text(m.rotulo,
                              style: t.apoio(
                                  cor: m == _modo ? Colors.black : Cores.texto,
                                  peso: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
