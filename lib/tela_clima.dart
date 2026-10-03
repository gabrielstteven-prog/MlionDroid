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
  /// Zoom regional (8): mostra o que está vindo das cidades vizinhas.
  String url(String lat, String lon) => switch (this) {
        ModoMapa.radar => 'https://www.rainviewer.com/map.html?loc=$lat,$lon,8'
            '&oFa=0&oC=1&oU=0&oCS=1&oF=0&oAP=1&c=3&o=83&lm=1&layer=radar&sm=1&sn=1',
        ModoMapa.previsao => _windy(lat, lon, 'rain'),
        ModoMapa.temperatura => _windy(lat, lon, 'temp'),
      };

  static String _windy(String lat, String lon, String overlay) =>
      'https://embed.windy.com/embed2.html?lat=$lat&lon=$lon'
      '&detailLat=$lat&detailLon=$lon&zoom=8&level=surface&overlay=$overlay'
      '&product=ecmwf&menu=&message=true&marker=true&calendar=now&pressure='
      '&type=map&location=coordinates&detail=&metricWind=km%2Fh&metricTemp=%C2%B0C';
}

// ═══════════════════════════════════════════════════════════════════════
//  MapaClimaManager — um único WebView vivo durante todo o app, para o
//  mapa aparecer pronto. Só recarrega quando a localização ou o modo mudam.
// ═══════════════════════════════════════════════════════════════════════
class MapaClimaManager extends ChangeNotifier {
  MapaClimaManager._() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _marcarPronto(),
          onWebResourceError: (e) {
            if (e.isForMainFrame != false) _falhar();
          },
        ),
      );
  }
  static final MapaClimaManager instance = MapaClimaManager._();

  /// Desligado só em prévias renderizadas no PC (WebView não existe lá).
  static bool habilitado = true;

  late final WebViewController _controller;
  WebViewController get controller => _controller;

  String? _carregado;
  Completer<void>? _carregando;
  Timer? _timeout;
  bool _comErro = false;
  bool get comErro => _comErro;

  void _marcarPronto() {
    _timeout?.cancel();
    _comErro = false;
    if (_carregando?.isCompleted == false) _carregando!.complete();
    notifyListeners();
  }

  void _falhar() {
    _timeout?.cancel();
    _comErro = true;
    _carregado = null;
    if (_carregando?.isCompleted == false) _carregando!.complete();
    notifyListeners();
  }

  Future<void> mostrar(String lat, String lon, ModoMapa modo, {bool forcar = false}) {
    final url = modo.url(lat, lon);
    if (!forcar && _carregado == url && !_comErro) {
      return _carregando?.future ?? Future.value();
    }
    _carregado = url;
    _comErro = false;
    _carregando = Completer<void>();
    _controller.loadRequest(Uri.parse(url));
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 20), () {
      if (_carregando?.isCompleted == false) _falhar();
    });
    return _carregando!.future;
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

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _saidaTimer?.cancel();
    super.dispose();
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
        if (mounted) setState(() => _avisos = a);
      });
    }
    // Com chance de chuva, abre direto no radar; senão, na previsão.
    final chuva = dados?.chuvaRestanteHoje().maxima ?? 0;
    final chovendo = (dados?.codigo ?? 0) >= 51;
    _trocarModo(chuva >= 30 || chovendo ? ModoMapa.radar : ModoMapa.previsao);
    _saidaTimer = Timer(Duration(seconds: dados == null ? 6 : _duracaoSeg), () {
      if (mounted) widget.aoTerminar();
    });
  }

  void _trocarModo(ModoMapa modo, {bool forcar = false}) {
    if (!MapaClimaManager.habilitado) {
      setState(() => _modo = modo);
      return;
    }
    setState(() {
      _modo = modo;
      _mapaPronto = false;
    });
    MapaClimaManager.instance.mostrar(_lat, _lon, modo, forcar: forcar).then((_) {
      if (mounted) setState(() => _mapaPronto = true);
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
          : IconeClima(codigo: dados.codigo, ehDia: dados.ehDia, tamanho: r.icon(60)),
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

  // ── Painel: agora, aviso, próximas horas, próximos dias ──────────────────
  Widget _painel(R r, DadosClima d) {
    final t = Tipo(r);
    final hoje = d.hoje;
    final horas = d.proximasHoras(6);

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
        SizedBox(height: r.sp(14)),
        CardAvisos(
          avisos: _avisos.isNotEmpty
              ? _avisos
              : const [
                  Aviso('Sem alertas para hoje', 'Tempo firme pelo resto do dia',
                      NivelAviso.tranquilo, Icons.wb_sunny_rounded, 'Previsão'),
                ],
        ),
        SizedBox(height: r.sp(22)),
        if (horas.isNotEmpty) ...[
          Text('Próximas horas', style: t.legenda()),
          SizedBox(height: r.sp(8)),
          Row(
            children: [
              for (final h in horas)
                Expanded(
                  child: Column(
                    children: [
                      Text('${h.hora.hour}h', style: t.apoio(cor: Cores.texto)),
                      IconeClima(
                          codigo: h.codigo, ehDia: h.hora.hour >= 6 && h.hora.hour < 18,
                          tamanho: r.icon(56), animar: false),
                      Text('${h.temp}°', style: t.corpo(peso: FontWeight.w700)),
                      Text(h.chuva >= 20 ? '${h.chuva}%' : ' ',
                          style: t.legenda(cor: Cores.chuva)),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: r.sp(18)),
        ],
        Text('Próximos dias', style: t.legenda()),
        SizedBox(height: r.sp(8)),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final dia in d.proximosDias.take(4))
                Expanded(
                  child: Column(
                    children: [
                      Text(diaSemanaCurto(dia.dia), style: t.corpo(peso: FontWeight.w700)),
                      IconeClima(codigo: dia.codigo, tamanho: r.icon(72), animar: false),
                      Text('${dia.max}° / ${dia.min}°', style: t.subtitulo().copyWith(fontWeight: FontWeight.w500)),
                      if (dia.chanceChuva >= 20)
                        Text('${dia.chanceChuva}% chuva', style: t.legenda(cor: Cores.chuva)),
                    ],
                  ),
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
            child: Center(child: Text('[ mapa: ${_modo?.rotulo} ]', style: t.subtitulo()))),
      );
    }
    final erro = MapaClimaManager.instance.comErro;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r.sp(28)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: MapaClimaManager.instance.controller),
          if (!_mapaPronto || erro)
            ColoredBox(
              color: const Color(0xFF10284A),
              child: erro
                  ? GestureDetector(
                      onTap: () => _trocarModo(_modo ?? ModoMapa.radar, forcar: true),
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
                      onTap: () => _trocarModo(m),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: r.sp(14), vertical: r.sp(9)),
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
