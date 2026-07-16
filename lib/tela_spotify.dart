import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'config_manager.dart';
import 'info_hub.dart';
import 'responsive.dart';
import 'performance_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SpotifyTrack
// ─────────────────────────────────────────────────────────────────────────────
class SpotifyTrack {
  final String id;
  final String titulo;
  final String artista;
  final String album;
  final String capaUrl;
  final int duracaoMs;
  final int progressoMs;
  final bool tocando;

  const SpotifyTrack({
    required this.id,
    required this.titulo,
    required this.artista,
    required this.album,
    required this.capaUrl,
    required this.duracaoMs,
    required this.progressoMs,
    required this.tocando,
  });

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    final item = json['item'] as Map<String, dynamic>? ?? {};
    final artists = (item['artists'] as List?)
            ?.map((a) => a['name'] as String? ?? '')
            .join(', ') ??
        '';
    final images = (item['album']?['images'] as List?) ?? [];
    final capaUrl =
        images.isNotEmpty ? (images.first['url'] as String? ?? '') : '';
    return SpotifyTrack(
      id: item['id'] as String? ?? '',
      titulo: item['name'] as String? ?? '—',
      artista: artists,
      album: item['album']?['name'] as String? ?? '',
      capaUrl: capaUrl,
      duracaoMs: item['duration_ms'] as int? ?? 0,
      progressoMs: json['progress_ms'] as int? ?? 0,
      tocando: json['is_playing'] as bool? ?? false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MusicInfoManager — busca dados ricos da música via Spotify Web API
// ─────────────────────────────────────────────────────────────────────────────
class MusicInfo {
  final String releaseDate;
  final int popularidade;
  final int totalFaixas;
  final int numMercados;
  final String gravadora;
  final bool explicit;
  final String albumType;
  final int trackNumber;
  final List<String> generos;

  // mantidos por compatibilidade com _buildCard
  final double danceability;
  final double energy;
  final double valence;
  final double acousticness;
  final int bpm;
  final String key;

  const MusicInfo({
    this.releaseDate = '',
    this.popularidade = 0,
    this.totalFaixas = 0,
    this.numMercados = 0,
    this.gravadora = '',
    this.explicit = false,
    this.albumType = '',
    this.trackNumber = 0,
    this.generos = const [],
    this.danceability = 0,
    this.energy = 0,
    this.valence = 0,
    this.acousticness = 0,
    this.bpm = 0,
    this.key = '',
  });
}

class GeniusManager extends ChangeNotifier {
  GeniusManager._();
  static final GeniusManager instance = GeniusManager._();

  String _ultimaFaixaId = '';
  MusicInfo? info;
  bool carregando = false;

  // Getter mantido por compatibilidade
  String get letra => '';

  static const _notas = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B'
  ];

  Future<void> buscarLetra(SpotifyTrack track) async {
    await buscarInfo(track);
  }

  Future<void> buscarInfo(SpotifyTrack track) async {
    if (track.id == _ultimaFaixaId || track.id.isEmpty) return;
    _ultimaFaixaId = track.id;
    carregando = true;
    info = null;
    notifyListeners();

    try {
      final token = SpotifyManager.instance.accessToken;
      if (token.isEmpty) {
        carregando = false;
        notifyListeners();
        return;
      }
      final headers = {'Authorization': 'Bearer $token'};

      // Busca dados do track
      final trackRes = await http
          .get(
            Uri.parse('https://api.spotify.com/v1/tracks/${track.id}'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 8));

      if (trackRes.statusCode != 200) {
        debugPrint('Track error: ${trackRes.statusCode}');
        carregando = false;
        notifyListeners();
        return;
      }

      final t = jsonDecode(trackRes.body) as Map<String, dynamic>;
      final popularidade = (t['popularity'] as int?) ?? 0;
      final explicit = (t['explicit'] as bool?) ?? false;
      final numMercados = ((t['available_markets'] as List?)?.length) ?? 0;
      final discNumber = (t['disc_number'] as int?) ?? 1;
      final trackNumber = (t['track_number'] as int?) ?? 0;
      final album = t['album'] as Map<String, dynamic>? ?? {};
      final releaseDate = album['release_date'] as String? ?? '';
      final totalFaixas = (album['total_tracks'] as int?) ?? 0;
      final albumType = album['album_type'] as String? ?? '';
      final albumId = album['id'] as String? ?? '';

      // Busca álbum para pegar gravadora e gêneros
      String gravadora = '';
      List<String> generos = [];

      if (albumId.isNotEmpty) {
        final albRes = await http
            .get(
              Uri.parse('https://api.spotify.com/v1/albums/$albumId'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 6));

        if (albRes.statusCode == 200) {
          final alb = jsonDecode(albRes.body) as Map<String, dynamic>;
          gravadora = alb['label'] as String? ?? '';
          generos = ((alb['genres'] as List?)?.cast<String>()) ?? [];
        }
      }

      // Busca artista principal para gêneros (se album não tiver)
      if (generos.isEmpty) {
        final artistId = ((t['artists'] as List?)?.first
                as Map<String, dynamic>?)?['id'] as String? ??
            '';
        if (artistId.isNotEmpty) {
          final artRes = await http
              .get(
                Uri.parse('https://api.spotify.com/v1/artists/$artistId'),
                headers: headers,
              )
              .timeout(const Duration(seconds: 6));
          if (artRes.statusCode == 200) {
            generos = ((jsonDecode(artRes.body)['genres'] as List?)
                    ?.cast<String>()) ??
                [];
          }
        }
      }

      info = MusicInfo(
        releaseDate: _formatDate(releaseDate),
        popularidade: popularidade,
        totalFaixas: totalFaixas,
        numMercados: numMercados,
        gravadora: gravadora,
        explicit: explicit,
        albumType: albumType,
        trackNumber: trackNumber,
        generos: generos.take(3).toList(),
      );

      debugPrint('=== MusicInfo ===');
      debugPrint('pop: $popularidade');
      debugPrint('gravadora: $gravadora');
      debugPrint('generos: $generos');
      debugPrint('numMercados: $numMercados');
      debugPrint('totalFaixas: $totalFaixas');
      debugPrint('trackNumber: $trackNumber');
      debugPrint('explicit: $explicit');
      debugPrint('releaseDate: $releaseDate');
      debugPrint('=================');
    } catch (e) {
      debugPrint('buscarInfo ERRO: $e');
    }

    carregando = false;
    notifyListeners();
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    try {
      final parts = raw.split('-');
      const meses = [
        '',
        'Jan',
        'Fev',
        'Mar',
        'Abr',
        'Mai',
        'Jun',
        'Jul',
        'Ago',
        'Set',
        'Out',
        'Nov',
        'Dez'
      ];
      if (parts.length == 3) {
        final m = int.tryParse(parts[1]) ?? 0;
        final mes = m >= 1 && m <= 12 ? meses[m] : '';
        return '${parts[2]} $mes ${parts[0]}';
      }
      return parts[0];
    } catch (_) {
      return raw;
    }
  }

  void limpar() {
    _ultimaFaixaId = '';
    info = null;
    carregando = false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SpotifyManager — Web API, PKCE S256, refresh token automático
// ─────────────────────────────────────────────────────────────────────────────
class SpotifyManager extends ChangeNotifier {
  SpotifyManager._();
  static final SpotifyManager instance = SpotifyManager._();

  final _cfg = ConfigManager();

  SpotifyTrack? faixaAtual;
  bool autenticado = false;
  bool carregando = false;
  Uint8List? albumArtBytes;

  /// True só quando existe uma faixa carregada E ela está de fato tocando
  /// (não pausada). Usado pelo MlionShell pra decidir se a TelaSpotify
  /// pode aparecer na rotação automática.
  bool get estaTocando => faixaAtual != null && faixaAtual!.tocando;

  VoidCallback? onFaixaTrocada;

  String _accessToken = '';
  String _refreshToken = '';
  DateTime? _tokenExpira;
  String _ultimoId = '';
  String _codeVerifier = '';

  Timer? _pollingTimer;
  Timer? _progressoTimer;
  int _progressoLocal = 0;
  DateTime? _progressoBase;

  static const _kAccess = 'spotify_access_token';
  static const _kRefresh = 'spotify_refresh_token';
  static const _kExpira = 'spotify_token_expira';

  String get _clientId => _cfg.getString('spotify', 'client_id', '');
  String get _redirectUri => _cfg.getString('spotify', 'redirect_uri', '');

  static const _scopes =
      'user-read-playback-state user-modify-playback-state user-read-currently-playing user-read-private';

  // ── Inicializar ────────────────────────────────────────────────────────────
  Future<void> iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_kAccess) ?? '';
    _refreshToken = prefs.getString(_kRefresh) ?? '';
    final expStr = prefs.getString(_kExpira) ?? '';
    if (expStr.isNotEmpty) _tokenExpira = DateTime.tryParse(expStr);

    if (_accessToken.isNotEmpty) {
      // Verifica se já expirou e tenta renovar antes de qualquer coisa
      if (_tokenExpira != null && DateTime.now().isAfter(_tokenExpira!)) {
        final renovado = await _renovarToken();
        if (!renovado) return;
      }
      autenticado = true;
      notifyListeners();
      await _buscarFaixaAtual();
      _iniciarPolling();
    }
  }

  // ── PKCE S256 ──────────────────────────────────────────────────────────────
  String _gerarCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = Random.secure();
    return List.generate(128, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _gerarCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  String gerarUrlAutorizacao() {
    _codeVerifier = _gerarCodeVerifier();
    final challenge = _gerarCodeChallenge(_codeVerifier);
    final params = Uri(queryParameters: {
      'client_id': _clientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': _scopes,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'show_dialog': 'false',
    }).query;
    return 'https://accounts.spotify.com/authorize?$params';
  }

  // ── Troca code por tokens ──────────────────────────────────────────────────
  Future<bool> trocarCodePorToken(String code) async {
    try {
      final res = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redirectUri,
          'client_id': _clientId,
          'code_verifier': _codeVerifier,
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        debugPrint('trocarCodePorToken erro: ${res.statusCode} ${res.body}');
        return false;
      }

      await _salvarTokens(jsonDecode(res.body));
      autenticado = true;
      carregando = false;
      notifyListeners();
      await _buscarFaixaAtual();
      _iniciarPolling();
      return true;
    } catch (e) {
      debugPrint('trocarCodePorToken: $e');
      return false;
    }
  }

  // ── Renovar token automaticamente (refresh) ────────────────────────────────
  Future<bool> _renovarToken() async {
    if (_refreshToken.isEmpty || _clientId.isEmpty) return false;
    try {
      final res = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
          'client_id': _clientId,
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        debugPrint('_renovarToken erro: ${res.statusCode}');
        // Token expirado permanentemente — pede login de novo
        autenticado = false;
        _accessToken = '';
        notifyListeners();
        return false;
      }

      await _salvarTokens(jsonDecode(res.body));
      autenticado = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('_renovarToken: $e');
      return false;
    }
  }

  Future<void> _salvarTokens(Map<String, dynamic> data) async {
    _accessToken = data['access_token'] as String? ?? _accessToken;
    // refresh_token pode não vir em renovações — manter o anterior
    if (data['refresh_token'] != null) {
      _refreshToken = data['refresh_token'] as String;
    }
    final expiresIn = data['expires_in'] as int? ?? 3600;
    _tokenExpira = DateTime.now().add(Duration(seconds: expiresIn - 120));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, _accessToken);
    await prefs.setString(_kRefresh, _refreshToken);
    await prefs.setString(_kExpira, _tokenExpira!.toIso8601String());
  }

  // ── Polling ────────────────────────────────────────────────────────────────
  void _iniciarPolling() {
    _pollingTimer?.cancel();
    _pollingTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _buscarFaixaAtual());

    _progressoTimer?.cancel();
    _progressoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (faixaAtual == null || !faixaAtual!.tocando) return;
      if (_progressoBase == null) return;
      final elapsed = DateTime.now().difference(_progressoBase!).inMilliseconds;
      _progressoLocal =
          (_progressoLocal + elapsed).clamp(0, faixaAtual!.duracaoMs);
      _progressoBase = DateTime.now();
      notifyListeners();
    });
  }

  Future<void> _buscarFaixaAtual() async {
    if (_accessToken.isEmpty) return;

    // Auto-renova token se estiver perto de expirar
    if (_tokenExpira != null &&
        DateTime.now()
            .isAfter(_tokenExpira!.subtract(const Duration(minutes: 2)))) {
      await _renovarToken();
      if (!autenticado) return;
    }

    try {
      final res = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 204 || res.body.isEmpty) {
        if (faixaAtual != null) {
          faixaAtual = null;
          InfoHub.instance.limparSpotify();
          notifyListeners();
        }
        return;
      }

      if (res.statusCode == 401) {
        // Tenta renovar antes de deslogar
        final renovado = await _renovarToken();
        if (renovado) {
          await _buscarFaixaAtual();
        }
        return;
      }

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final track = SpotifyTrack.fromJson(data);

      _progressoLocal = track.progressoMs;
      _progressoBase = DateTime.now();

      final trocou = track.id != _ultimoId && track.id.isNotEmpty;
      _ultimoId = track.id;
      faixaAtual = track;

      InfoHub.instance.atualizarSpotify(
        titulo: track.titulo,
        artista: track.artista,
        albumArtUrl: track.capaUrl,
      );

      if (trocou) {
        await _carregarCapa(track.capaUrl);
        // Busca letra em paralelo
        GeniusManager.instance
            .buscarLetra(track)
            .then((_) => notifyListeners());
        onFaixaTrocada?.call();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('SpotifyManager._buscarFaixaAtual: $e');
    }
  }

  Future<void> _carregarCapa(String url) async {
    if (url.isEmpty) {
      albumArtBytes = null;
      return;
    }
    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        albumArtBytes = res.bodyBytes;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('SpotifyManager._carregarCapa: $e');
    }
  }

  int get progressoAtualMs => _progressoLocal;
  String get accessToken => _accessToken; // para GeniusManager

  // ── Controles ──────────────────────────────────────────────────────────────
  Future<void> _comando(String endpoint, String method) async {
    if (_accessToken.isEmpty) return;
    try {
      final uri = Uri.parse('https://api.spotify.com/v1/me/player/$endpoint');
      final req = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer $_accessToken'
        ..headers['Content-Length'] = '0';
      await req.send().timeout(const Duration(seconds: 5));
      await Future.delayed(const Duration(milliseconds: 500));
      await _buscarFaixaAtual();
    } catch (e) {
      debugPrint('SpotifyManager._comando $endpoint: $e');
    }
  }

  Future<void> play() => _comando('play', 'PUT');
  Future<void> pause() => _comando('pause', 'PUT');
  Future<void> proximaFaixa() => _comando('next', 'POST');
  Future<void> faixaAnterior() => _comando('previous', 'POST');

  Future<void> togglePlayPause() async {
    if (faixaAtual?.tocando ?? false)
      await pause();
    else
      await play();
  }

  void deslogar() async {
    _pollingTimer?.cancel();
    _progressoTimer?.cancel();
    _accessToken = _refreshToken = '';
    _tokenExpira = null;
    _ultimoId = '';
    faixaAtual = null;
    albumArtBytes = null;
    autenticado = false;
    InfoHub.instance.limparSpotify();
    GeniusManager.instance.limpar();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kExpira);
    notifyListeners();
  }

  void encerrar() {
    _pollingTimer?.cancel();
    _progressoTimer?.cancel();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TelaSpotify

// ─────────────────────────────────────────────────────────────────────────────
//  TelaSpotify — layout landscape premium
// ─────────────────────────────────────────────────────────────────────────────
class TelaSpotify extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaSpotify({super.key, required this.aoTerminar});
  @override
  State<TelaSpotify> createState() => _TelaSpotifyState();
}

class _TelaSpotifyState extends State<TelaSpotify>
    with TickerProviderStateMixin {
  final _spotify = SpotifyManager.instance;
  final _cfg = ConfigManager();

  late AnimationController _entradaCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _vizCtrl; // visualizador de áudio
  late Animation<double> _fadeIn;
  late Animation<double> _pulse;
  late Animation<double> _vizAnim; // fase das ondas

  final ScrollController _letraScroll = ScrollController();
  Timer? _letraScrollTimer;
  Timer? _saidaTimer;
  int _infoCardIndex = 0; // card atual do painel de infos
  Timer? _infoCardTimer; // rotação automática dos cards

  @override
  void initState() {
    super.initState();
    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeIn = CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOut);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _pulse = Tween(begin: 1.0, end: 1.06)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _vizCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _vizAnim = Tween(begin: 0.0, end: 1.0).animate(_vizCtrl);
    // Pulso do álbum e visualizador de áudio são decorativos — só rodam
    // em loop no modo visual completo. No modo econômico ficam parados.
    if (!PerformanceManager.instance.modoEconomico) {
      _pulseCtrl.repeat(reverse: true);
      _vizCtrl.repeat();
    }
    _entradaCtrl.forward();
    _spotify.addListener(_onUpdate);
    _iniciarTimerSaida();
    // Busca informações da faixa atual se já houver uma tocando
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final faixa = _spotify.faixaAtual;
      if (faixa != null && GeniusManager.instance.info == null) {
        GeniusManager.instance.buscarInfo(faixa).then((_) {
          if (mounted) {
            setState(() {});
            _iniciarRotacaoCards();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _entradaCtrl.dispose();
    _pulseCtrl.dispose();
    _vizCtrl.dispose();
    _letraScroll.dispose();
    _letraScrollTimer?.cancel();
    _infoCardTimer?.cancel();
    _saidaTimer?.cancel();
    _spotify.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    // Inicia rotação se info acabou de chegar
    if (GeniusManager.instance.info != null && _infoCardTimer == null) {
      _iniciarRotacaoCards();
    }
  }

  void _iniciarRotacaoCards() {
    _infoCardTimer?.cancel();
    _infoCardIndex = 0;
    final info = GeniusManager.instance.info;
    if (info == null) return;
    _infoCardTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      final total = _totalCards();
      setState(() => _infoCardIndex = (_infoCardIndex + 1) % total);
    });
  }

  int _totalCards() {
    final info = GeniusManager.instance.info;
    if (info == null) return 1;
    int t = 0;
    if (info.releaseDate.isNotEmpty) t++;
    t++; // popularidade sempre
    t++; // genero sempre (com fallback)
    if (info.gravadora.isNotEmpty) t++;
    if (info.totalFaixas > 0) t++;
    if (info.numMercados > 0) t++;
    if (info.explicit) t++;
    return t.clamp(1, 99);
  }

  void _iniciarTimerSaida() {
    _saidaTimer?.cancel();
    final seg = _cfg.getInt('spotify', 'duracao_tela_seg', 30);
    _saidaTimer = Timer(Duration(seconds: seg), () {
      if (mounted) widget.aoTerminar();
    });
  }

  void _toqueInteragiu() => _iniciarTimerSaida();

  void _iniciarScrollLetra() {
    _letraScrollTimer?.cancel();
    _letraScrollTimer = Timer(const Duration(seconds: 4), () {
      if (!_letraScroll.hasClients) return;
      final max = _letraScroll.position.maxScrollExtent;
      if (max > 0)
        _letraScroll.animateTo(max,
            duration: const Duration(seconds: 35), curve: Curves.linear);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cfg.getString('spotify', 'client_id', '').isEmpty)
      return _telaConfigurar();
    if (!_spotify.autenticado) return _telaLogin();

    final track = _spotify.faixaAtual;
    final bytes = _spotify.albumArtBytes;
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;

    return FadeTransition(
      opacity: _fadeIn,
      child: GestureDetector(
        onTap: _toqueInteragiu,
        child: Stack(fit: StackFit.expand, children: [
          // Fundo: capa borrada (o blur sigma 90 é o efeito mais caro do
          // app inteiro — no modo econômico usamos a imagem sem blur; o
          // overlay escuro logo abaixo já cobre boa parte do detalhe).
          if (bytes != null)
            PerformanceManager.instance.modoEconomico
                ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                    child: Image.memory(bytes,
                        fit: BoxFit.cover, gaplessPlayback: true),
                  )
          else
            Container(color: const Color(0xFF080808)),

          // Overlay gradiente escuro
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.72),
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.68),
                ],
              ),
            ),
          ),

          // Visualizador de áudio animado no fundo
          if (_spotify.faixaAtual != null)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _vizAnim,
                builder: (context, _) {
                  final tocando = _spotify.faixaAtual?.tocando ?? false;
                  return CustomPaint(
                    painter: _AudioVisualizerPainter(
                      fase: _vizAnim.value,
                      tocando: tocando,
                    ),
                  );
                },
              ),
            ),

          // Conteúdo
          Column(children: [
            const SizedBox(height: 4),
            Expanded(
                child: track == null
                    ? _semMusica()
                    : _layoutPrincipal(track, bytes, sw, sh)),
          ]),
        ]),
      ),
    );
  }

  Widget _semMusica() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.music_off_rounded, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          Text('Nenhuma música tocando',
              style: GoogleFonts.poppins(
                  color: Colors.white38,
                  fontSize: 18,
                  decoration: TextDecoration.none)),
        ]),
      );

  Widget _layoutPrincipal(
      SpotifyTrack track, Uint8List? bytes, double sw, double sh) {
    final isPaused = !track.tocando;
    final posMs = _spotify.progressoAtualMs;
    final durMs = track.duracaoMs;
    final progresso = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final letra = GeniusManager.instance.letra;
    final capaSize = (sh * 0.60).clamp(160.0, 360.0);

    return Column(children: [
      // ── Capa + Infos lado a lado ──────────────────────────────────────────
      Expanded(
        flex: letra.isNotEmpty ? 58 : 100,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Capa grande à esquerda
            SizedBox(
              width: sw * 0.44,
              child: Center(child: _capa(capaSize, bytes)),
            ),

            // Infos à direita com glassmorphism
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: sw * 0.04, top: 12, bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: PerformanceManager.instance.sigmaBlur(20),
                      sigmaY: PerformanceManager.instance.sigmaBlur(20),
                    ),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                          sw * 0.025, sh * 0.018, sw * 0.025, sh * 0.015),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Logo Spotify
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(Icons.music_note_rounded,
                                    color: const Color(0xFF1DB954),
                                    size: (sw * 0.028).clamp(22.0, 32.0)),
                                const SizedBox(width: 8),
                                Text('Spotify',
                                    style: GoogleFonts.poppins(
                                        color: const Color(0xFF1DB954),
                                        fontSize:
                                            (sw * 0.020).clamp(14.0, 22.0),
                                        fontWeight: FontWeight.w800,
                                        decoration: TextDecoration.none)),
                                const SizedBox(width: 6),
                                Flexible(
                                    child: Text('| by MlionDroid',
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(
                                            color: Colors.white24,
                                            fontSize:
                                                (sw * 0.010).clamp(9.0, 12.0),
                                            decoration: TextDecoration.none))),
                              ]),
                          SizedBox(height: sh * 0.015),
                          Text(track.titulo,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: (sw * 0.036).clamp(18.0, 34.0),
                                  fontWeight: FontWeight.w800,
                                  decoration: TextDecoration.none,
                                  height: 1.1)),
                          const SizedBox(height: 6),
                          Text(track.artista,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.70),
                                  fontSize: (sw * 0.022).clamp(13.0, 21.0),
                                  decoration: TextDecoration.none)),
                          if (track.album.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(track.album,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                    color: Colors.white.withValues(alpha: 0.38),
                                    fontSize: (sw * 0.015).clamp(10.0, 15.0),
                                    decoration: TextDecoration.none)),
                          ],
                          SizedBox(height: sh * 0.018),
                          _barraProgresso(progresso, _t(posMs), _t(durMs), sw),
                          SizedBox(height: sh * 0.022),
                          _controles(sw, sh, isPaused),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Letra ─────────────────────────────────────────────────────────────
      Expanded(
        flex: 42,
        child: _painelLetra(letra, sw),
      ),
    ]);
  }

  Widget _capa(double size, Uint8List? bytes) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.85),
              blurRadius: 55,
              spreadRadius: 6,
              offset: const Offset(0, 14)),
          BoxShadow(
              color: const Color(0xFF1DB954).withValues(alpha: 0.18),
              blurRadius: 60,
              spreadRadius: 8),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
            : Container(
                color: const Color(0xFF1a1a2e),
                child: const Icon(Icons.album_rounded,
                    color: Colors.white24, size: 80)),
      ),
    );
  }

  Widget _barraProgresso(double progresso, String pos, String dur, double sw) {
    return Column(children: [
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3.5,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
          thumbColor: Colors.white,
        ),
        child: Slider(value: progresso.toDouble(), onChanged: null),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(pos,
              style: GoogleFonts.poppins(
                  color: Colors.white38,
                  fontSize: (sw * 0.012).clamp(9.0, 13.0),
                  decoration: TextDecoration.none)),
          Text(dur,
              style: GoogleFonts.poppins(
                  color: Colors.white38,
                  fontSize: (sw * 0.012).clamp(9.0, 13.0),
                  decoration: TextDecoration.none)),
        ]),
      ),
    ]);
  }

  Widget _controles(double sw, double sh, bool isPaused) {
    final btnSize = (sh * 0.088).clamp(34.0, 54.0);
    final playSize = (sh * 0.128).clamp(50.0, 74.0);
    return Row(children: [
      _btn(Icons.skip_previous_rounded, btnSize, () {
        _spotify.faixaAnterior();
        _toqueInteragiu();
      }),
      SizedBox(width: sw * 0.025),
      GestureDetector(
        onTap: () {
          _spotify.togglePlayPause();
          _toqueInteragiu();
        },
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (c, child) => Transform.scale(
              scale: isPaused ? _pulse.value : 1.0, child: child),
          child: Container(
            width: playSize,
            height: playSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.28),
                    blurRadius: 22,
                    spreadRadius: 2)
              ],
            ),
            child: Icon(
                isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: Colors.black,
                size: playSize * 0.52),
          ),
        ),
      ),
      SizedBox(width: sw * 0.025),
      _btn(Icons.skip_next_rounded, btnSize, () {
        _spotify.proximaFaixa();
        _toqueInteragiu();
      }),
    ]);
  }

  Widget _btn(IconData icon, double size, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.10),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.22), width: 1.2),
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.52),
        ),
      );

  Widget _painelLetra(String letra, double sw) {
    // Redireciona para o novo painel de informações
    return _painelInfoMusica(sw);
  }

  Widget _painelInfoMusica(double sw) {
    final genius = GeniusManager.instance;
    final MusicInfo? info = genius.info;
    final temToken = _cfg.getString('spotify', 'genius_token', '').isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: PerformanceManager.instance.sigmaBlur(18),
            sigmaY: PerformanceManager.instance.sigmaBlur(18),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(children: [
              // ── Header ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 9, 18, 4),
                child: Row(children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: Color(0xFF1DB954), size: 14),
                  const SizedBox(width: 7),
                  Text('Sobre a musica',
                      style: GoogleFonts.poppins(
                          color: const Color(0xFF1DB954),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none)),
                  const Spacer(),
                  // Indicadores de cards (bolinhas)
                  if (info != null)
                    Row(
                      children: List.generate(
                          _totalCards(),
                          (i) => Container(
                                width: i == _infoCardIndex ? 16 : 6,
                                height: 6,
                                margin: const EdgeInsets.only(left: 3),
                                decoration: BoxDecoration(
                                  color: i == _infoCardIndex
                                      ? const Color(0xFF1DB954)
                                      : Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              )),
                    ),
                  if (genius.carregando) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Color(0xFF1DB954))),
                  ],
                ]),
              ),

              // ── Conteúdo do card ──────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                  child: info == null
                      ? Center(
                          child: Text(
                            temToken
                                ? genius.carregando
                                    ? 'Buscando informacoes...'
                                    : 'Informacoes nao encontradas'
                                : 'Configure o Genius Token em Configuracoes > Spotify',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                color: Colors.white30,
                                fontSize: 13,
                                decoration: TextDecoration.none),
                          ),
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 600),
                          transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                        begin: const Offset(0.08, 0),
                                        end: Offset.zero)
                                    .animate(anim),
                                child: child,
                              )),
                          child: _buildCard(info, sw),
                        ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(MusicInfo info, double sw) {
    final cards = <Map<String, dynamic>>[];

    if (info.releaseDate.isNotEmpty) {
      cards.add({
        'emoji': '📅',
        'icon': Icons.calendar_today_rounded,
        'cor': const Color(0xFF00d4ff),
        'label': 'Lançamento',
        'valor': info.releaseDate,
        'extra': 'Quando o mundo conheceu essa musica',
        'tipo': 'texto',
      });
    }
    if (info.popularidade >= 0) {
      // sempre mostrar
      final emoji = info.popularidade >= 80
          ? '🔥'
          : info.popularidade >= 60
              ? '⭐'
              : info.popularidade >= 40
                  ? '🎵'
                  : '💎';
      cards.add({
        'emoji': emoji,
        'icon': Icons.trending_up_rounded,
        'cor': const Color(0xFFFFD700),
        'label': 'Popularidade no Spotify',
        'valor': '${info.popularidade} / 100',
        'barra': info.popularidade / 100.0,
        'extra': _descPopularidade(info.popularidade),
        'tipo': 'barra',
      });
    }
    if (true) {
      // sempre mostrar gênero (com fallback)
      cards.add({
        'emoji': '🎼',
        'icon': Icons.queue_music_rounded,
        'cor': const Color(0xFFE040FB),
        'label': 'Estilo musical',
        'valor': info.generos.isNotEmpty
            ? info.generos.map((g) => _capitalizar(g)).join(' · ')
            : 'Nao classificado pelo Spotify',
        'extra': 'Genero identificado pelo Spotify',
        'tipo': 'texto',
      });
    }
    if (info.gravadora.isNotEmpty) {
      cards.add({
        'emoji': '🏢',
        'icon': Icons.business_rounded,
        'cor': const Color(0xFFFFD700),
        'label': 'Gravadora',
        'valor': info.gravadora,
        'extra': 'Selo responsavel pelo lancamento',
        'tipo': 'texto',
      });
    }
    if (info.totalFaixas > 0) {
      final trackInfo = info.trackNumber > 0
          ? 'Faixa ${info.trackNumber} de ${info.totalFaixas}'
          : '${info.totalFaixas} faixas no album';
      cards.add({
        'emoji': '💿',
        'icon': Icons.album_rounded,
        'cor': const Color(0xFF00d4ff),
        'label': 'Sobre o album',
        'valor': trackInfo,
        'extra': info.albumType == 'album'
            ? 'Album de estudio completo'
            : info.albumType == 'single'
                ? 'Lancado como single'
                : 'EP ou colecao',
        'tipo': 'texto',
      });
    }
    if (info.numMercados > 0) {
      final desc = info.numMercados >= 180
          ? '🌍  Disponivel em praticamente todo o mundo'
          : info.numMercados >= 100
              ? '🌎  Ampla distribuicao internacional'
              : '🌐  Distribuicao regional selecionada';
      cards.add({
        'emoji': '🌍',
        'icon': Icons.public_rounded,
        'cor': const Color(0xFF1DB954),
        'label': 'Alcance global',
        'valor': '${info.numMercados} paises',
        'barra': (info.numMercados / 185).clamp(0.0, 1.0),
        'extra': desc,
        'tipo': 'barra',
      });
    }
    if (info.explicit) {
      cards.add({
        'emoji': '🔞',
        'icon': Icons.explicit_rounded,
        'cor': const Color(0xFFFF6B6B),
        'label': 'Classificacao',
        'valor': 'Conteudo Explicito',
        'extra': 'Esta musica contem linguagem adulta',
        'tipo': 'texto',
      });
    }

    if (cards.isEmpty) {
      return Center(
        key: const ValueKey('empty'),
        child: Text('Carregando informacoes...',
            style: GoogleFonts.poppins(
                color: Colors.white30,
                fontSize: 13,
                decoration: TextDecoration.none)),
      );
    }

    final idx = _infoCardIndex.clamp(0, cards.length - 1);
    final card = cards[idx];
    final cor = card['cor'] as Color;
    final tipo = card['tipo'] as String;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                  .animate(anim),
          child: child,
        ),
      ),
      child: Row(
        key: ValueKey(idx),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Emoji + Ícone grandes
          Container(
            width: (sw * 0.065).clamp(52.0, 72.0),
            height: (sw * 0.065).clamp(52.0, 72.0),
            margin: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                cor.withValues(alpha: 0.25),
                cor.withValues(alpha: 0.08),
              ]),
              border:
                  Border.all(color: cor.withValues(alpha: 0.45), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: cor.withValues(alpha: 0.20),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Center(
              child: Text(
                card['emoji'] as String,
                style: TextStyle(fontSize: (sw * 0.028).clamp(22.0, 32.0)),
              ),
            ),
          ),

          // Conteúdo
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Label
                Text(card['label'] as String,
                    style: GoogleFonts.poppins(
                        color: cor,
                        fontSize: (sw * 0.013).clamp(10.0, 14.0),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        decoration: TextDecoration.none)),
                const SizedBox(height: 5),

                // Valor principal — grande e bold
                Text(card['valor'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: (sw * 0.022).clamp(16.0, 26.0),
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        decoration: TextDecoration.none)),

                // Barra de progresso
                if (tipo == 'barra') ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (card['barra'] as double).clamp(0.0, 1.0),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(cor),
                      minHeight: 6,
                    ),
                  ),
                ],

                // Frase extra — o "tempero"
                if (card['extra'] != null) ...[
                  const SizedBox(height: 6),
                  Text(card['extra'] as String,
                      style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.50),
                          fontSize: (sw * 0.012).clamp(9.0, 13.0),
                          fontStyle: FontStyle.italic,
                          decoration: TextDecoration.none)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _descPopularidade(int v) {
    if (v >= 90) return '🔥  Top global — todo mundo ta ouvindo isso agora';
    if (v >= 80) return '🔥  Hit absoluto — esta dominando as playlists';
    if (v >= 70) return '⭐  Muito popular — nao tem como nao conhecer';
    if (v >= 60) return '⭐  Bastante ouvida no Spotify';
    if (v >= 40) return '🎵  Popularidade moderada — musica de bom gosto';
    return '💎  Underground — voce tem um otimo gosto musical';
  }

  String _capitalizar(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  Widget _telaConfigurar() => Container(
        color: Colors.black,
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.settings_rounded, color: Colors.white38, size: 52),
          const SizedBox(height: 16),
          Text('Configure o Client ID do Spotify\nnas Configurações do app',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: Colors.white54,
                  fontSize: 16,
                  decoration: TextDecoration.none)),
        ])),
      );

  Widget _telaLogin() {
    final redirectUri = _cfg.getString('spotify', 'redirect_uri', '');
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (req) {
        final url = req.url;
        if (redirectUri.isNotEmpty &&
            (url.startsWith(redirectUri) || url.startsWith('mliondroid://'))) {
          final code = Uri.parse(url).queryParameters['code'] ?? '';
          if (code.isNotEmpty) SpotifyManager.instance.trocarCodePorToken(code);
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      }))
      ..loadRequest(Uri.parse(SpotifyManager.instance.gerarUrlAutorizacao()));

    return ColoredBox(
      color: Colors.black,
      child: Column(children: [
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Icon(Icons.music_note_rounded,
                color: const Color(0xFF1DB954), size: 28),
            const SizedBox(width: 12),
            Text('Conectar ao Spotify',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none)),
            const Spacer(),
            GestureDetector(
                onTap: widget.aoTerminar,
                child: const Icon(Icons.close_rounded,
                    color: Colors.white54, size: 24)),
          ]),
        ),
        Expanded(child: WebViewWidget(controller: controller)),
      ]),
    );
  }

  String _t(int ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _AudioVisualizerPainter — barras de áudio pulsando no fundo
// ─────────────────────────────────────────────────────────────────────────────
class _AudioVisualizerPainter extends CustomPainter {
  final double fase; // 0.0 a 1.0, animado continuamente
  final bool tocando;

  const _AudioVisualizerPainter({
    required this.fase,
    required this.tocando,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!tocando) {
      _desenharOndas(canvas, size, 0.15); // ondas bem suaves quando pausado
      return;
    }
    _desenharBarras(canvas, size);
    _desenharOndas(canvas, size, 0.40);
  }

  void _desenharBarras(Canvas canvas, Size size) {
    const numBarras = 48;
    final barW = size.width / numBarras;
    final baseY = size.height;

    for (int i = 0; i < numBarras; i++) {
      // Cada barra tem uma frequência e amplitude únicas
      final freq1 = (i * 0.13 + fase * pi * 2);
      final freq2 = (i * 0.07 + fase * pi * 4.3);
      final freq3 = (i * 0.21 + fase * pi * 1.7);

      final altura = size.height *
          (0.10 +
              0.18 * ((sin(freq1) + 1) / 2) +
              0.12 * ((sin(freq2) + 1) / 2) +
              0.08 * ((sin(freq3) + 1) / 2));

      final x = i * barW;
      final rect = Rect.fromLTWH(x + 1, baseY - altura, barW - 2, altura);

      // Gradiente vertical: verde Spotify embaixo, ciano no topo
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFF1DB954).withOpacity(0.35),
            const Color(0xFF00d4ff).withOpacity(0.18),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.fill;

      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rr, paint);
    }
  }

  void _desenharOndas(Canvas canvas, Size size, double opacidade) {
    // Duas ondas senoidais sobrepostas — efeito de ondas de som
    for (int onda = 0; onda < 3; onda++) {
      final path = Path();
      final amplitude = size.height * (0.04 + onda * 0.025);
      final freqOffset = onda * 0.8;
      final yBase = size.height * (0.55 + onda * 0.12);
      final faseOnda = fase * pi * 2 + freqOffset;

      path.moveTo(0, yBase);
      for (double x = 0; x <= size.width; x += 2) {
        final y = yBase + amplitude * sin((x / size.width) * pi * 5 + faseOnda);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1DB954).withOpacity(opacidade * (1 - onda * 0.25)),
            Colors.transparent,
          ],
        ).createShader(
            Rect.fromLTWH(0, yBase - amplitude, size.width, amplitude * 2 + 10))
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_AudioVisualizerPainter old) =>
      old.fase != fase || old.tocando != tocando;
}
