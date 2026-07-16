// ═══════════════════════════════════════════════════════════════════════════════
//  PATCH — info_hub.dart
//  Adicionar suporte ao Spotify: ticker com ícone de álbum redondo + título
// ═══════════════════════════════════════════════════════════════════════════════
//
//  Adicione as propriedades e método abaixo na classe InfoHub.
//  Localização: logo após a declaração dos timers existentes (_tickerFetchTimer).
//
// ── NOVAS PROPRIEDADES (adicionar após _tickerFetchTimer) ──────────────────────
//
//   // ── Spotify ───────────────────────────────────────────────────────────────
//   String _spotifyTitulo = '';
//   String _spotifyArtista = '';
//   bool _spotifyAtivo = false;
//
//   bool get spotifyTocando => _spotifyAtivo && _spotifyTitulo.isNotEmpty;
//   String get spotifyTitulo => _spotifyTitulo;
//   String get spotifyArtista => _spotifyArtista;
//
//   // Texto formatado para o ticker quando Spotify estiver ativo
//   String get tickerSpotify =>
//       '🎵 $_spotifyTitulo  •  $_spotifyArtista';
//
// ── NOVO MÉTODO (adicionar após _rotacionarTicker) ────────────────────────────
//
//   /// Chamado pelo SpotifyManager sempre que a faixa muda.
//   void atualizarSpotify({
//     required String titulo,
//     required String artista,
//     String? albumArtUrl,
//   }) {
//     _spotifyTitulo = titulo;
//     _spotifyArtista = artista;
//     _spotifyAtivo = titulo.isNotEmpty;
//     notifyListeners();
//   }
//
//   void limparSpotify() {
//     _spotifyAtivo = false;
//     _spotifyTitulo = '';
//     _spotifyArtista = '';
//     notifyListeners();
//   }
//
// ═══════════════════════════════════════════════════════════════════════════════

// Abaixo está o info_hub.dart COMPLETO com o patch já aplicado.
// Substitua o arquivo original por este.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:xml/xml.dart';

import 'config_manager.dart';

/// Hub central de informações sempre visíveis (relógio, clima, ticker).
class InfoHub extends ChangeNotifier {
  InfoHub._();
  static final InfoHub instance = InfoHub._();

  final _cfg = ConfigManager();

  // ── Relógio ───────────────────────────────────────────────────────────────
  String hora = '--:--';
  String dataCurta = '';
  String dataCompleta = '';
  String diaSemana = '';
  String diaSemanaCompleto = '';

  // ── Clima ─────────────────────────────────────────────────────────────────
  String temp = '--';
  String sensacao = '--';
  String cidadeLabel = '';
  int weatherCode = 0;
  int chanceChuva = 0;
  bool climaCarregando = true;

  // ── Ticker (frases + notícias) ────────────────────────────────────────────
  List<String> tickerItens = [];
  int _indiceTicker = 0;

  String get tickerAtual {
    // Spotify tem prioridade quando estiver tocando
    if (spotifyTocando) return tickerSpotify;
    if (tickerItens.isEmpty) return 'MlionDroid Center • Painel inteligente';
    return tickerItens[_indiceTicker % tickerItens.length];
  }

  // ── Spotify ───────────────────────────────────────────────────────────────
  String _spotifyTitulo = '';
  String _spotifyArtista = '';
  bool _spotifyAtivo = false;

  bool get spotifyTocando => _spotifyAtivo && _spotifyTitulo.isNotEmpty;
  String get spotifyTitulo => _spotifyTitulo;
  String get spotifyArtista => _spotifyArtista;

  String get tickerSpotify => '🎵 $_spotifyTitulo  •  $_spotifyArtista';

  /// Chamado pelo SpotifyManager sempre que a faixa muda.
  void atualizarSpotify({
    required String titulo,
    required String artista,
    String? albumArtUrl,
  }) {
    _spotifyTitulo = titulo;
    _spotifyArtista = artista;
    _spotifyAtivo = titulo.isNotEmpty;
    notifyListeners();
  }

  void limparSpotify() {
    _spotifyAtivo = false;
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

  String get _lat => _cfg.getString('clima', 'lat', '-22.889');
  String get _lon => _cfg.getString('clima', 'lon', '-47.222');

  void iniciar() {
    if (_iniciado) return;
    _iniciado = true;

    _atualizarRelogio();
    _relogioTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _atualizarRelogio());

    buscarClima();
    final climaMin = _cfg.getInt('barra_info', 'intervalo_clima_min', 10);
    _climaTimer = Timer.periodic(
        Duration(minutes: climaMin.clamp(5, 60)), (_) => buscarClima());

    _carregarTicker();
    _tickerFetchTimer =
        Timer.periodic(const Duration(minutes: 30), (_) => _carregarTicker());

    final rotSeg = _cfg.getInt('barra_info', 'rotacao_ticker_seg', 12);
    _tickerRotateTimer = Timer.periodic(
        Duration(seconds: rotSeg.clamp(6, 60)), (_) => _rotacionarTicker());
  }

  void encerrar() {
    _relogioTimer?.cancel();
    _climaTimer?.cancel();
    _tickerRotateTimer?.cancel();
    _tickerFetchTimer?.cancel();
    _iniciado = false;
  }

  void _atualizarRelogio() {
    final agora = DateTime.now();
    final dias = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    final diasCompletos = [
      'Domingo',
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado'
    ];
    hora = DateFormat('HH:mm').format(agora);
    dataCurta = DateFormat("dd/MM").format(agora);
    dataCompleta = DateFormat("dd/MM/yyyy").format(agora);
    diaSemana = dias[agora.weekday % 7];
    diaSemanaCompleto = diasCompletos[agora.weekday % 7];
    notifyListeners();
  }

  void _rotacionarTicker() {
    // Não rotaciona enquanto o Spotify estiver tocando — a faixa já ocupa o ticker
    if (spotifyTocando) return;
    if (tickerItens.length <= 1) return;
    _indiceTicker = (_indiceTicker + 1) % tickerItens.length;
    notifyListeners();
  }

  Future<void> buscarClima() async {
    if (!_cfg.getBool('barra_info', 'mostrar_clima', true)) return;

    cidadeLabel =
        '${_cfg.getString('clima', 'cidade', 'Hortolândia')} • ${_cfg.getString('clima', 'estado', 'SP')}';

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_lat&longitude=$_lon'
        '&current=temperature_2m,apparent_temperature,weather_code'
        '&hourly=precipitation_probability'
        '&timezone=America%2FSao_Paulo',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;

      final data = json.decode(res.body);
      final current = data['current'];
      final hourlyRain =
          data['hourly']['precipitation_probability'] as List? ?? [];

      int maxChuva = 0;
      final agora = DateTime.now();
      final hourlyTimes = data['hourly']['time'] as List? ?? [];
      for (int i = 0; i < hourlyTimes.length; i++) {
        final h = DateTime.parse(hourlyTimes[i] as String);
        if (h.isAfter(agora) && h.day == agora.day) {
          final p = (hourlyRain[i] as num?)?.toInt() ?? 0;
          if (p > maxChuva) maxChuva = p;
        }
      }

      temp = (current['temperature_2m'] as num?)?.round().toString() ?? '--';
      sensacao =
          (current['apparent_temperature'] as num?)?.round().toString() ?? '--';
      weatherCode = current['weather_code'] as int? ?? 0;
      chanceChuva = maxChuva;
      climaCarregando = false;
      notifyListeners();
    } catch (e) {
      debugPrint('InfoHub clima: $e');
      climaCarregando = false;
      notifyListeners();
    }
  }

  Future<void> _carregarTicker() async {
    if (!_cfg.getBool('barra_info', 'mostrar_ticker', true)) return;

    final tipo = _cfg.getString('barra_info', 'tipo_ticker', 'misturado');
    final itens = <String>[];

    if (tipo == 'frase' || tipo == 'misturado') {
      itens.addAll(_frasesDoDia());
    }
    if (tipo == 'noticias' || tipo == 'misturado') {
      itens.addAll(await _buscarHeadlines());
    }

    if (itens.isEmpty) {
      itens.add('MlionDroid Center • Informações em tempo real');
    }

    tickerItens = itens;
    _indiceTicker = 0;
    notifyListeners();
  }

  List<String> _frasesDoDia() {
    const frases = [
      '💡 "A jornada de mil milhas começa com um único passo." — Lao Tzu',
      '💡 "Acredite que você pode e você já está na metade do caminho." — Roosevelt',
      '💡 "O sucesso é a soma de pequenos esforços repetidos dia após dia."',
      '💡 "Comece onde você está. Use o que você tem. Faça o que você pode."',
      '💡 "A felicidade não é algo pronto. Ela vem das suas próprias ações."',
      '💡 "Faça cada dia valer a pena."',
    ];
    final idx = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return [frases[idx % frases.length]];
  }

  Future<List<String>> _buscarHeadlines() async {
    final urls = [
      'https://g1.globo.com/rss/g1/sp/campinas-regiao/',
      'https://g1.globo.com/rss/g1/',
    ];
    final headlines = <String>[];

    for (final url in urls) {
      try {
        final res =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;

        final doc = XmlDocument.parse(utf8.decode(res.bodyBytes));
        for (final item in doc.findAllElements('item').take(3)) {
          final titles = item.findElements('title');
          if (titles.isEmpty) continue;
          final title = titles.first.innerText;
          if (title.isNotEmpty) {
            headlines.add('📰 $title');
          }
        }
        if (headlines.length >= 4) break;
      } catch (e) {
        debugPrint('InfoHub RSS $url: $e');
      }
    }
    return headlines.take(5).toList();
  }

  String emojiClima(int code) {
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 48) return '☁️';
    if (code <= 67) return '🌧️';
    if (code <= 82) return '🌦️';
    if (code >= 95) return '⛈️';
    return '🌤️';
  }
}
