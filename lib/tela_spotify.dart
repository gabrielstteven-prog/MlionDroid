import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'config_manager.dart';
import 'info_hub.dart';
import 'design/tema.dart';
import 'responsive.dart';
import 'services/musica_service.dart';

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
  });
}

class InfoMusicaManager extends ChangeNotifier {
  InfoMusicaManager._();
  static final InfoMusicaManager instance = InfoMusicaManager._();

  String _ultimaFaixaId = '';
  MusicInfo? info;
  bool carregando = false;

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
  // Adaptativo: a cada 3s com música tocando (para pegar a troca de faixa
  // rápido) e a cada 20s quando nada toca. Antes eram 3s o dia inteiro
  // (~28 mil requisições por dia, mesmo com o Spotify fechado).
  void _agendarProximaConsulta() {
    _pollingTimer?.cancel();
    final tocando = faixaAtual?.tocando ?? false;
    _pollingTimer = Timer(Duration(seconds: tocando ? 3 : 20), () async {
      await _buscarFaixaAtual();
      if (autenticado) _agendarProximaConsulta();
    });
  }

  void _iniciarPolling() {
    _agendarProximaConsulta();

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

  Future<void> _buscarFaixaAtual({bool jaRenovou = false}) async {
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
          notifyListeners();
        }
        InfoHub.instance.limparSpotify();
        return;
      }

      if (res.statusCode == 401) {
        // Tenta renovar UMA vez. Antes, se a API seguisse respondendo 401
        // mesmo com token novo, a função chamava a si mesma sem fim.
        if (!jaRenovou && await _renovarToken()) {
          await _buscarFaixaAtual(jaRenovou: true);
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

      // A faixa só ocupa o ticker da barra enquanto está tocando de fato.
      if (track.tocando) {
        InfoHub.instance
            .atualizarSpotify(titulo: track.titulo, artista: track.artista);
      } else {
        InfoHub.instance.limparSpotify();
      }

      if (trocou) {
        await _carregarCapa(track.capaUrl);
        // Informações extras da música (gravadora, gêneros...) em paralelo
        InfoMusicaManager.instance
            .buscarInfo(track)
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
        InfoHub.instance.capaMudou(); // mini-capa no ticker da barra
      }
    } catch (e) {
      debugPrint('SpotifyManager._carregarCapa: $e');
    }
  }

  /// Próxima música da fila ("Título, de Artista"), ou null.
  Future<String?> proximaNaFila() async {
    if (_accessToken.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/queue'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final fila = (jsonDecode(res.body)['queue'] as List?) ?? [];
      if (fila.isEmpty) return null;
      final p = fila.first as Map<String, dynamic>;
      final artistas = ((p['artists'] as List?) ?? [])
          .map((a) => (a as Map)['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .join(', ');
      final nome = p['name'] as String? ?? '';
      if (nome.isEmpty) return null;
      return artistas.isEmpty ? nome : '$nome, de $artistas';
    } catch (_) {
      return null;
    }
  }

  int get progressoAtualMs => _progressoLocal;
  String get accessToken => _accessToken; // para InfoMusicaManager

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
    if (faixaAtual?.tocando ?? false) {
      await pause();
    } else {
      await play();
    }
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
    InfoMusicaManager.instance.limpar();
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

class _TelaSpotifyState extends State<TelaSpotify> {
  final _spotify = SpotifyManager.instance;
  final _cfg = ConfigManager();

  Timer? _saidaTimer;

  // Dados extras da faixa atual
  String? _faixaId;
  Letra? _letra;
  bool _buscandoLetra = false;
  Color? _corCapa;
  Uint8List? _bytesCor;
  String? _proxima;

  @override
  void initState() {
    super.initState();
    _spotify.addListener(_onUpdate);
    _iniciarTimerSaida();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onUpdate());
  }

  @override
  void dispose() {
    _saidaTimer?.cancel();
    _spotify.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    final faixa = _spotify.faixaAtual;
    if (faixa != null && faixa.id != _faixaId) {
      _faixaId = faixa.id;
      _letra = null;
      _proxima = null;
      _carregarExtras(faixa);
    }
    final bytes = _spotify.albumArtBytes;
    if (bytes != null && !identical(bytes, _bytesCor)) {
      _bytesCor = bytes;
      MusicaService.corDaCapa(bytes).then((c) {
        if (mounted && c != null) setState(() => _corCapa = c);
      });
    }
    setState(() {});
  }

  Future<void> _carregarExtras(SpotifyTrack faixa) async {
    _buscandoLetra = true;
    final letra = await MusicaService.instance.letra(
      id: faixa.id,
      titulo: faixa.titulo,
      artista: faixa.artista,
      album: faixa.album,
      duracaoMs: faixa.duracaoMs,
    );
    final proxima = await _spotify.proximaNaFila();
    if (InfoMusicaManager.instance.info == null) {
      unawaited(InfoMusicaManager.instance.buscarInfo(faixa));
    }
    if (!mounted || faixa.id != _faixaId) return;
    setState(() {
      _letra = letra;
      _proxima = proxima;
      _buscandoLetra = false;
    });
  }

  void _iniciarTimerSaida() {
    _saidaTimer?.cancel();
    final seg = _cfg.getInt('spotify', 'duracao_tela_seg', 30);
    _saidaTimer = Timer(Duration(seconds: seg), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cfg.getString('spotify', 'client_id', '').isEmpty) {
      return _telaConfigurar();
    }
    if (!_spotify.autenticado) return _telaLogin();

    final track = _spotify.faixaAtual;
    final r = R(context);
    final cor = _corCapa ?? const Color(0xFF14361F);

    return GestureDetector(
      onTap: _iniciarTimerSaida,
      child: AnimatedContainer(
        duration: const Duration(seconds: 2),
        // Fundo na cor da capa do álbum (antes: blur sigma 90, o efeito
        // mais caro do app inteiro).
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cor, Color.lerp(cor, Colors.black, 0.65)!],
          ),
        ),
        child: track == null
            ? const AvisoTela(
                icone: Icons.music_off_rounded,
                titulo: 'Nenhuma música tocando',
                texto: 'Toque algo no Spotify em qualquer aparelho e a música aparece aqui.',
                cor: Destaques.musica,
              )
            : Padding(
                padding: EdgeInsets.fromLTRB(r.sp(40), r.sp(28), r.sp(40), r.sp(24)),
                child: Column(
                  children: [
                    Expanded(flex: 6, child: _topo(r, track)),
                    SizedBox(height: r.sp(20)),
                    Expanded(flex: 4, child: _painelLetra(r)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _topo(R r, SpotifyTrack track) {
    final t = Tipo(r);
    final bytes = _spotify.albumArtBytes;
    final posMs = _spotify.progressoAtualMs;
    final durMs = track.duracaoMs;
    final progresso = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final info = InfoMusicaManager.instance.info;
    final detalhes = [
      if (track.album.isNotEmpty) track.album,
      if (info != null && info.releaseDate.isNotEmpty) info.releaseDate,
      if (info != null && info.gravadora.isNotEmpty) info.gravadora,
    ].join(', ');

    return LayoutBuilder(builder: (context, box) {
      final capa = box.maxHeight;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(r.sp(24)),
            child: SizedBox(
              width: capa,
              height: capa,
              child: bytes != null
                  ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                  : ColoredBox(
                      color: Cores.superficie,
                      child: Icon(Icons.album_rounded, color: Cores.textoApagado, size: capa * 0.4),
                    ),
            ),
          ),
          SizedBox(width: r.sp(36)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Icon(Icons.music_note_rounded, color: Destaques.musica, size: r.icon(22)),
                  SizedBox(width: r.sp(8)),
                  Text(track.tocando ? 'Tocando no Spotify' : 'Pausado', style: t.apoio()),
                ]),
                SizedBox(height: r.sp(10)),
                Text(track.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titulo().copyWith(fontSize: r.fs(46))),
                SizedBox(height: r.sp(6)),
                Text(track.artista,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.subtitulo(cor: Cores.textoSecundario).copyWith(fontWeight: FontWeight.w500)),
                if (detalhes.isNotEmpty) ...[
                  SizedBox(height: r.sp(4)),
                  Text(detalhes,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.apoio(cor: Cores.textoApagado)),
                ],
                SizedBox(height: r.sp(22)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progresso,
                    minHeight: r.sp(6),
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation(Cores.texto),
                  ),
                ),
                SizedBox(height: r.sp(6)),
                Row(children: [
                  Text(_t(posMs), style: t.legenda()),
                  const Spacer(),
                  Text(_t(durMs), style: t.legenda()),
                ]),
                SizedBox(height: r.sp(12)),
                Row(
                  children: [
                    _botao(r, Icons.skip_previous_rounded, _spotify.faixaAnterior),
                    SizedBox(width: r.sp(14)),
                    _botao(r, track.tocando ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        _spotify.togglePlayPause,
                        principal: true),
                    SizedBox(width: r.sp(14)),
                    _botao(r, Icons.skip_next_rounded, _spotify.proximaFaixa),
                    SizedBox(width: r.sp(24)),
                    if (_proxima != null)
                      Expanded(
                        child: Text('A seguir: $_proxima',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.apoio()),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _botao(R r, IconData icone, Future<void> Function() acao, {bool principal = false}) {
    final tamanho = r.sp(principal ? 68 : 54);
    return GestureDetector(
      onTap: () {
        _iniciarTimerSaida();
        acao();
      },
      child: Container(
        width: tamanho,
        height: tamanho,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: principal ? Cores.texto : Colors.white.withValues(alpha: 0.14),
        ),
        child: Icon(icone,
            color: principal ? Colors.black : Cores.texto, size: tamanho * 0.55),
      ),
    );
  }

  /// Letra sincronizada: a linha cantada agora em destaque, com as vizinhas
  /// mais apagadas. Sem letra disponível, mostra uma mensagem discreta.
  Widget _painelLetra(R r) {
    final t = Tipo(r);
    final letra = _letra;
    if (letra == null) {
      return Center(
        child: Text(
          _buscandoLetra ? 'Procurando a letra...' : 'Letra não encontrada para esta música.',
          style: t.apoio(cor: Cores.textoApagado),
        ),
      );
    }
    if (!letra.sincronizada) {
      return SingleChildScrollView(
        child: Text(letra.simples,
            style: t.corpo(cor: Cores.textoSecundario), textAlign: TextAlign.left),
      );
    }
    // Compensa ~0,4s da consulta ao Spotify para a letra não ficar atrasada.
    final pos = Duration(milliseconds: _spotify.progressoAtualMs + 400);
    final atual = letra.indiceEm(pos);
    final linhas = <Widget>[];
    for (var d = -1; d <= 2; d++) {
      final i = atual + d;
      if (i < 0 || i >= letra.linhas.length) {
        linhas.add(SizedBox(height: r.sp(d == 0 ? 52 : 34)));
        continue;
      }
      final texto = letra.linhas[i].texto.isEmpty ? '♪' : letra.linhas[i].texto;
      linhas.add(AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 300),
        style: d == 0
            ? t.titulo().copyWith(fontSize: r.fs(38))
            : t.subtitulo(cor: Colors.white.withValues(alpha: d < 0 ? 0.30 : 0.45))
                .copyWith(fontWeight: FontWeight.w500),
        child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis),
      ));
      linhas.add(SizedBox(height: r.sp(6)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: linhas,
    );
  }

  Widget _telaConfigurar() => Container(
        color: Colors.black,
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.settings_rounded, color: Colors.white38, size: 52),
          const SizedBox(height: 16),
          Text('Configure o Client ID do Spotify\nnas Configurações do app',
              textAlign: TextAlign.center,
              style: GoogleFonts.figtree(
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
            const Icon(Icons.music_note_rounded,
                color: Color(0xFF1DB954), size: 28),
            const SizedBox(width: 12),
            Text('Conectar ao Spotify',
                style: GoogleFonts.figtree(
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

