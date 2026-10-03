import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config_manager.dart';
import 'services/news_service.dart';
import 'services/weather_service.dart';

/// Hub das informações sempre visíveis na barra superior (relógio, clima,
/// ticker de frases/notícias e música tocando).
///
/// Desempenho: o relógio é um ValueNotifier separado que só dispara quando
/// o MINUTO muda (a barra mostra HH:mm). Antes o hub inteiro notificava a
/// cada segundo e a barra toda era reconstruída 86.400 vezes por dia.
class InfoHub extends ChangeNotifier {
  InfoHub._();
  static final InfoHub instance = InfoHub._();

  final _cfg = ConfigManager();

  /// Hora atual, truncada no minuto.
  final ValueNotifier<DateTime> relogio = ValueNotifier(_minutoAtual());

  static DateTime _minutoAtual() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, n.hour, n.minute);
  }

  // ── Clima ─────────────────────────────────────────────────────────────────
  DadosClima? get clima => WeatherService.instance.atual;
  bool get climaCarregando => clima == null && !_climaFalhou;
  bool _climaFalhou = false;
  String get cidadeLabel => _cfg.getString('clima', 'cidade', 'Hortolândia');
  String get estadoLabel => _cfg.getString('clima', 'estado', 'SP');

  // ── Ticker ────────────────────────────────────────────────────────────────
  List<String> tickerItens = [];
  int _indiceTicker = 0;

  String get tickerAtual {
    if (spotifyTocando) return tickerSpotify;
    if (tickerItens.isEmpty) return 'MlionDroid Center • Painel inteligente';
    return tickerItens[_indiceTicker % tickerItens.length];
  }

  // ── Spotify ───────────────────────────────────────────────────────────────
  String _spotifyTitulo = '';
  String _spotifyArtista = '';

  bool get spotifyTocando => _spotifyTitulo.isNotEmpty;
  String get spotifyTitulo => _spotifyTitulo;
  String get spotifyArtista => _spotifyArtista;
  String get tickerSpotify => '🎵 $_spotifyTitulo  •  $_spotifyArtista';

  void atualizarSpotify({required String titulo, required String artista}) {
    if (titulo == _spotifyTitulo && artista == _spotifyArtista) return;
    _spotifyTitulo = titulo;
    _spotifyArtista = artista;
    notifyListeners();
  }

  /// A capa do álbum terminou de carregar — redesenha o ticker.
  void capaMudou() => notifyListeners();

  void limparSpotify() {
    if (_spotifyTitulo.isEmpty) return;
    _spotifyTitulo = '';
    _spotifyArtista = '';
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  Timer? _relogioTimer;
  Timer? _climaTimer;
  Timer? _tickerRotateTimer;
  Timer? _tickerFetchTimer;
  bool _iniciado = false;

  void iniciar() {
    if (_iniciado) return;
    _iniciado = true;

    _agendarRelogio();
    WeatherService.instance.addListener(notifyListeners);
    _cfg.revisao.addListener(_configMudou);
    _reagendarTimers();
    buscarClima();
    _carregarTicker();
  }

  void encerrar() {
    _relogioTimer?.cancel();
    _climaTimer?.cancel();
    _tickerRotateTimer?.cancel();
    _tickerFetchTimer?.cancel();
    WeatherService.instance.removeListener(notifyListeners);
    _cfg.revisao.removeListener(_configMudou);
    _iniciado = false;
  }

  /// Acorda exatamente na virada de cada minuto.
  void _agendarRelogio() {
    final agora = DateTime.now();
    final proximo = DateTime(
        agora.year, agora.month, agora.day, agora.hour, agora.minute + 1);
    _relogioTimer = Timer(proximo.difference(agora), () {
      relogio.value = _minutoAtual();
      _agendarRelogio();
    });
  }

  /// Os intervalos vêm das Configurações. Antes eram lidos só uma vez, ao
  /// abrir o app — mudar nas configurações exigia reiniciar.
  void _reagendarTimers() {
    _climaTimer?.cancel();
    final climaMin = _cfg.getInt('barra_info', 'intervalo_clima_min', 10);
    _climaTimer = Timer.periodic(
        Duration(minutes: climaMin.clamp(5, 60)), (_) => buscarClima());

    _tickerFetchTimer?.cancel();
    _tickerFetchTimer =
        Timer.periodic(const Duration(minutes: 30), (_) => _carregarTicker());

    _tickerRotateTimer?.cancel();
    final rotSeg = _cfg.getInt('barra_info', 'rotacao_ticker_seg', 12);
    _tickerRotateTimer = Timer.periodic(
        Duration(seconds: rotSeg.clamp(6, 60)), (_) => _rotacionarTicker());
  }

  void _configMudou() {
    _reagendarTimers();
    _carregarTicker();
    notifyListeners();
  }

  void _rotacionarTicker() {
    if (spotifyTocando || tickerItens.length <= 1) return;
    _indiceTicker = (_indiceTicker + 1) % tickerItens.length;
    notifyListeners();
  }

  Future<void> buscarClima() async {
    if (!_cfg.getBool('barra_info', 'mostrar_clima', true)) return;
    final climaMin = _cfg.getInt('barra_info', 'intervalo_clima_min', 10);
    final dados = await WeatherService.instance
        .obter(maxIdade: Duration(minutes: climaMin.clamp(5, 60)));
    _climaFalhou = dados == null;
    notifyListeners();
  }

  Future<void> _carregarTicker() async {
    if (!_cfg.getBool('barra_info', 'mostrar_ticker', true)) return;

    final tipo = _cfg.getString('barra_info', 'tipo_ticker', 'misturado');
    final itens = <String>[];

    if (tipo == 'frase' || tipo == 'misturado') {
      itens.add('💡 ${fraseDoDia()}');
    }
    if (tipo == 'noticias' || tipo == 'misturado') {
      final r = await NewsService.instance.buscar(const [
        FonteRss('https://g1.globo.com/rss/g1/sp/campinas-regiao/', 'Região'),
        FonteRss('https://g1.globo.com/rss/g1/', 'Brasil'),
      ], validade: const Duration(minutes: 30), porFonte: 3);
      itens.addAll(r.noticias.take(6).map((n) => '📰 ${n.titulo}'));
    }

    if (itens.isEmpty) {
      itens.add('MlionDroid Center • Informações em tempo real');
    }

    tickerItens = itens;
    _indiceTicker = 0;
    notifyListeners();
  }
}

/// Banco de frases em português — uma por dia, sem depender de API.
/// Compartilhado pela barra superior e pela tela Bom Dia.
const frasesDoDia = [
  '"Comece cada dia com um sorriso e termine com alegria." — Anônimo',
  '"O segredo é começar. Isso é tudo." — Mark Twain',
  '"Cada amanhecer é uma nova oportunidade de mudar sua vida." — Anônimo',
  '"Acredite que você pode — e você já está na metade do caminho." — Theodore Roosevelt',
  '"A persistência é o caminho do êxito." — Charles Chaplin',
  '"Não é o quanto fazemos, mas quanto amor colocamos no que fazemos." — Madre Teresa de Calcutá',
  '"O otimista vê a oportunidade em toda dificuldade." — Winston Churchill',
  '"A vida é a arte do encontro, embora haja tanto desencontro pela vida." — Vinícius de Moraes',
  '"Feliz aquele que transfere o que sabe e aprende o que ensina." — Cora Coralina',
  '"O que vale na vida não é o ponto de partida e sim a caminhada." — Cora Coralina',
  '"Não temos mais tempo de sermos os mesmos." — Paulo Freire',
  '"Que os dias difíceis te ensinem, e os bons te façam grato." — Anônimo',
  '"Comece fazendo o que é necessário, depois o que é possível, e de repente você estará fazendo o impossível." — São Francisco de Assis',
  '"A jornada de mil milhas começa com um único passo." — Lao Tzu',
  '"O sucesso é a soma de pequenos esforços repetidos dia após dia." — Robert Collier',
  '"Comece onde você está. Use o que você tem. Faça o que você pode." — Arthur Ashe',
  '"A felicidade não é algo pronto. Ela vem das suas próprias ações." — Dalai Lama',
  '"Bom mesmo é ir à luta com determinação, abraçar a vida com paixão, perder com classe e vencer com ousadia." — Charles Chaplin',
];

String fraseDoDia([DateTime? data]) {
  final d = data ?? DateTime.now();
  final idx = d.difference(DateTime(d.year)).inDays;
  return frasesDoDia[idx % frasesDoDia.length];
}
