import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'config_manager.dart';
import 'cache_manager.dart';
import 'responsive.dart';
import 'tela_config.dart' show timesDisponiveis;

class TelaPalmeiras extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaPalmeiras({super.key, required this.aoTerminar});

  @override
  State<TelaPalmeiras> createState() => _TelaPalmeirasState();
}

class _TelaPalmeirasState extends State<TelaPalmeiras> {
  final _cfg = ConfigManager();

  late ScrollController _scrollCtrl;
  List<Map<String, String>> _newsList = [];
  bool _carregando = true;

  late final WebViewController _webCtrl;
  String? _selectedUrl;
  bool _isManualMode = false;

  Timer? _updateTimer;
  Timer? _startTimer;
  Timer? _manualResetTimer;
  Timer? _fallbackExitTimer;

  // ── Dados de competições ─────────────────────────────────────────────────
  static const String _apiKey = '2fe5b44d83914bd5b4b44df54b718fd0';

  static const Map<String, Map<String, String>> _competicoes = {
    'BSA': {'nome': 'Brasileirão', 'logo': 'assets/brasileirao.png'},
    'CLI': {'nome': 'Libertadores', 'logo': 'assets/libertadores.png'},
    'CSA': {'nome': 'Sul-Americana', 'logo': 'assets/sulamericana.png'},
    'BRC': {'nome': 'Copa do Brasil', 'logo': 'assets/copabrasil.png'},
  };

  // Competições que possuem fase de grupos. As demais (ex.: Brasileirão,
  // que é disputado em pontos corridos) não devem exibir o campo "grupo".
  static const Set<String> _competicoesComGrupo = {'CLI', 'CSA'};

  bool _temFaseDeGrupos(String codigo) => _competicoesComGrupo.contains(codigo);

  // Resultado: competição → dados
  Map<String, Map<String, dynamic>> _statsCompet = {};
  bool _statsCarregando = true;

  // ── Getters de config ──────────────────────────────────────────────────────
  String get _nomeRss =>
      (_cfg.get('palmeiras', 'nome_rss') as String?) ?? 'palmeiras';

  String get _nomeTime =>
      (_cfg.get('palmeiras', 'nome_time') as String?) ?? 'Palmeiras';

  String get _timeKey =>
      (_cfg.get('time', 'time_key') as String?) ?? 'palmeiras';

  String get _escudoAsset =>
      (_cfg.get('palmeiras', 'escudo_asset') as String?) ??
      'assets/escudos/palmeiras.png';

  String get _escudoUrl =>
      (_cfg.get('palmeiras', 'escudo_url') as String?) ?? '';

  Color get _corTop =>
      _parseColor(_cfg.get('palmeiras', 'cor_gradiente_top'), 0xFF00441B);

  Color get _corBottom =>
      _parseColor(_cfg.get('palmeiras', 'cor_gradiente_bottom'), 0xFF000000);

  Color get _corDestaque =>
      _parseColor(_cfg.get('palmeiras', 'cor_destaque'), 0xFFC1A163);

  int get _scrollVelocidade =>
      (_cfg.get('palmeiras', 'duracao_scroll_px_seg') as num?)?.toInt() ?? 35;

  int get _pausaFinal =>
      (_cfg.get('palmeiras', 'pausa_final_seg') as num?)?.toInt() ?? 10;

  int get _qtdNoticias =>
      (_cfg.get('palmeiras', 'qtd_noticias') as num?)?.toInt() ?? 8;

  String get _rssUrl => 'https://ge.globo.com/rss/ge/futebol/times/$_nomeRss/';

  // Fonte única: lê o teamId diretamente do TimeInfo declarado em tela_config.dart
  // Assim qualquer time adicionado lá fica automaticamente disponível aqui,
  // sem precisar duplicar a lista de IDs em outro lugar (era exatamente essa
  // duplicação que tinha causado os IDs errados antes).
  //
  // IMPORTANTE: se o time não for encontrado, retornamos -1 (ID inválido)
  // de propósito — isso garante que o app nunca "acerte" por acidente o ID
  // de outro time só porque ele existe em algum mapa de reserva.
  int get _teamId {
    final viaConfig = timesDisponiveis[_timeKey]?.teamId ??
        timesDisponiveis[_nomeRss]?.teamId;
    if (viaConfig != null) return viaConfig;

    debugPrint(
        'TelaPalmeiras: não foi possível resolver o teamId para "$_timeKey" / "$_nomeRss". '
        'Verifique se o time está cadastrado em tela_config.dart (timesDisponiveis).');
    return -1;
  }

  // Remove acentos e normaliza para comparação de nomes (são paulo == sao paulo)
  String _normalizar(String s) {
    const comAcento = 'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ';
    const semAcento = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    var r = s;
    for (var i = 0; i < comAcento.length; i++) {
      r = r.replaceAll(comAcento[i], semAcento[i]);
    }
    return r.toLowerCase().trim();
  }

  Color _parseColor(dynamic raw, int fallback) {
    try {
      if (raw is String) return Color(int.parse(raw));
    } catch (_) {}
    return Color(fallback);
  }

  // ── Init / Dispose ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white);

    _carregarNoticias();
    _carregarStatsCompet();

    _updateTimer =
        Timer.periodic(_cfg.getIntervaloAtualizacao('palmeiras'), (_) {
      _buscarNoticias();
      _buscarStatsCompet();
    });

    _fallbackExitTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _startTimer?.cancel();
    _manualResetTimer?.cancel();
    _fallbackExitTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Cache + busca RSS ──────────────────────────────────────────────────────
  String get _chaveCacheNoticias =>
      'palmeiras_noticias_${_nomeRss}_$_qtdNoticias';

  /// Checa o cache antes de ir pra internet. Só busca de novo se não tiver
  /// cache válido dentro do intervalo configurado pelo usuário.
  Future<void> _carregarNoticias() async {
    final cache = await CacheManager.instance.obter<List<dynamic>>(
      _chaveCacheNoticias,
      validade: _cfg.getIntervaloAtualizacao('palmeiras'),
    );
    if (cache != null && mounted) {
      setState(() {
        _newsList =
            cache.map((e) => Map<String, String>.from(e as Map)).toList();
        _carregando = false;
      });
      _agendarScroll();
      return;
    }
    await _buscarNoticias();
  }

  Future<void> _buscarNoticias() async {
    try {
      final res = await http
          .get(Uri.parse(_rssUrl))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final doc = XmlDocument.parse(utf8.decode(res.bodyBytes));
        final itens =
            doc.findAllElements('item').take(_qtdNoticias).map((node) {
          final desc = node.findElements('description').first.innerText;
          final img = RegExp(r'src="([^"]+)"').firstMatch(desc)?.group(1) ?? '';
          return {
            'title': node.findElements('title').first.innerText,
            'desc': desc.replaceAll(RegExp(r'<[^>]*>|&nbsp;'), '').trim(),
            'link': node.findElements('link').first.innerText,
            'image': img,
          };
        }).toList();

        if (mounted) {
          setState(() {
            _newsList = itens;
            _carregando = false;
          });
          _agendarScroll();
        }
        await CacheManager.instance.salvar(_chaveCacheNoticias, itens);
      } else {
        if (mounted) setState(() => _carregando = false);
      }
    } catch (e) {
      debugPrint('TelaPalmeiras RSS erro: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  // ── Cache + busca classificação nas APIs (Não bloqueante + Anti Rate Limit)
  String get _chaveCacheStats => 'palmeiras_stats_$_nomeRss';

  Future<void> _carregarStatsCompet() async {
    final cache = await CacheManager.instance.obter<Map<String, dynamic>>(
      _chaveCacheStats,
      validade: _cfg.getIntervaloAtualizacao('palmeiras'),
    );
    if (cache != null && mounted) {
      setState(() {
        _statsCompet =
            cache.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
        _statsCarregando = false;
      });
      return;
    }
    await _buscarStatsCompet();
  }

  Future<void> _buscarStatsCompet() async {
    final stats = <String, Map<String, dynamic>>{};
    final teamIdAtual = _teamId; // -1 se não conseguimos identificar o time
    final nomeNorm = _normalizar(_nomeTime);

    for (final entry in _competicoes.entries) {
      if (!mounted) return;

      final codigo = entry.key;
      try {
        final res = await http.get(
          Uri.parse(
              'https://api.football-data.org/v4/competitions/$codigo/standings'),
          headers: {'X-Auth-Token': _apiKey},
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 429) {
          debugPrint('Football-Data Rate Limit atingido. Aguardando...');
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body);
        final standings = data['standings'] as List? ?? [];

        for (final grupo in standings) {
          final table = grupo['table'] as List? ?? [];
          for (final t in table) {
            final nomeTimeTable = _normalizar(
                (t['team']['shortName'] as String? ??
                    t['team']['name'] as String? ??
                    ''));
            final id = t['team']['id'] as int? ?? -1;

            // Match por ID só conta se o ID do time atual for válido (!= -1).
            // Isso evita que um time não identificado "herde" por acidente
            // os dados de outro time que por coincidência tenha o mesmo ID
            // (foi exatamente o bug do São Paulo puxando dados do Palmeiras).
            final matchPorId = teamIdAtual != -1 && id == teamIdAtual;
            final matchPorNome = nomeTimeTable.isNotEmpty &&
                nomeNorm.isNotEmpty &&
                (nomeTimeTable == nomeNorm ||
                    nomeTimeTable.contains(nomeNorm) ||
                    nomeNorm.contains(nomeTimeTable));

            if (matchPorId || matchPorNome) {
              stats[codigo] = {
                'posicao': t['position'],
                'pontos': t['points'],
                'jogos': t['playedGames'],
                // Só guardamos o "grupo" para competições que de fato têm
                // fase de grupos. Pra ligas de pontos corridos (Brasileirão)
                // a API pode retornar valores tipo "Matchday/Regular Season"
                // nesse campo, que não fazem sentido exibir como "grupo".
                'grupo': _temFaseDeGrupos(codigo) ? (grupo['group'] ?? '') : '',
              };
              break;
            }
          }
          if (stats.containsKey(codigo)) break;
        }

        await Future.delayed(const Duration(milliseconds: 1200));
      } catch (e) {
        debugPrint('TelaPalmeiras stats $codigo: $e');
      }
    }

    if (mounted) {
      setState(() {
        _statsCompet = stats;
        _statsCarregando = false;
      });
    }
    if (stats.isNotEmpty) {
      await CacheManager.instance.salvar(_chaveCacheStats, stats);
    }
  }

  // ── Scroll automático ──────────────────────────────────────────────────────
  void _agendarScroll() {
    _startTimer?.cancel();
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    _startTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isManualMode && _selectedUrl == null) _autoScroll();
    });
  }

  int _tentativasScrollCurtas = 0;

  Future<void> _autoScroll() async {
    if (!mounted || _isManualMode || _selectedUrl != null) return;
    if (!_scrollCtrl.hasClients) return;

    final max = _scrollCtrl.position.maxScrollExtent;
    if (max < 200) {
      // Antes: tentava de novo pra sempre a cada 2s se o conteúdo não
      // precisasse de scroll — travava a tela até o timer de segurança
      // de 5 minutos.
      _tentativasScrollCurtas++;
      if (_tentativasScrollCurtas < 3) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) _autoScroll();
        return;
      }
      _tentativasScrollCurtas = 0;
      final espera = _pausaFinal > 0 ? _pausaFinal : 8;
      await Future.delayed(Duration(seconds: espera));
      if (mounted && !_isManualMode && _selectedUrl == null) {
        widget.aoTerminar();
      }
      return;
    }
    _tentativasScrollCurtas = 0;

    // O ListView tem 120px de padding vazio no fundo (respiro visual do
    // último card). Rolar até o maxScrollExtent completo inclui esse
    // vão vazio, dando a sensação de "passar direto" da última notícia
    // e travar num espaço em branco. Paramos antes desse padding.
    final alvo = (max - 100).clamp(0.0, max).toDouble();

    final dur = (max / _scrollVelocidade).clamp(20, 90).toInt();
    await _scrollCtrl.animateTo(alvo,
        duration: Duration(seconds: dur), curve: Curves.linear);

    if (_pausaFinal > 0) {
      await Future.delayed(Duration(seconds: _pausaFinal));
    }

    if (mounted && !_isManualMode && _selectedUrl == null) {
      widget.aoTerminar();
    }
  }

  void _ativarManual() {
    _startTimer?.cancel();
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(_scrollCtrl.offset,
          duration: const Duration(milliseconds: 50), curve: Curves.easeOut);
    }
    setState(() => _isManualMode = true);
    _manualResetTimer?.cancel();
    _manualResetTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        setState(() => _isManualMode = false);
        if (_selectedUrl == null) {
          _scrollCtrl.jumpTo(0);
          _agendarScroll();
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _ativarManual(),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_corTop, _corBottom],
          ),
        ),
        child: Center(
          child: Container(
            width: r.panelWidth,
            height: r.panelHeight,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(30),
            ),
            child: _selectedUrl == null ? _buildNewsList(r) : _buildLeitor(r),
          ),
        ),
      ),
    );
  }

  // ── Lista de notícias ──────────────────────────────────────────────────────
  Widget _buildNewsList(R r) {
    return Column(
      children: [
        _buildHeader(r),
        Expanded(
          child: _carregando
              ? Center(child: CircularProgressIndicator(color: _corDestaque))
              : _newsList.isEmpty
                  ? Center(
                      child: Text('Sem notícias no momento',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 16)))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      physics: _isManualMode
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: _newsList.length,
                      itemBuilder: (_, i) => _buildCard(_newsList[i], r),
                    ),
        ),
      ],
    );
  }

  // ── Cabeçalho ──────────────────────────────────────────────────────────────
  Widget _buildHeader(R r) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildEscudo(size: r.icon(60)),
              const SizedBox(width: 14),
              Text(
                _nomeTime.toUpperCase(),
                style: TextStyle(
                    fontSize: r.fs(36),
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPainelCompeticoes(r),
          const SizedBox(height: 8),
          Container(
            width: r.dividerWidth(),
            height: 2,
            color: _corDestaque,
            margin: const EdgeInsets.symmetric(vertical: 6),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PRINCIPAIS NOTÍCIAS',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: r.fs(12),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5),
                ),
                Text(
                  _isManualMode ? '• NAVEGAÇÃO MANUAL •' : 'GE.globo.com',
                  style: TextStyle(
                      color: _isManualMode
                          ? Colors.orangeAccent
                          : _corDestaque.withOpacity(0.9),
                      fontSize: r.fs(13),
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ── Painel de competições (Visual idêntico ao da foto) ──────────────────────
  Widget _buildPainelCompeticoes(R r) {
    if (_statsCarregando) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFFC1A163)),
          ),
        ),
      );
    }
    if (_statsCompet.isEmpty) return const SizedBox(height: 4);

    final codigosDisponiveis = _statsCompet.keys.take(2).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'COMPETIÇÕES',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: r.fs(22),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 24),
          Container(
            width: 1,
            height: 50,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Row(
              children: codigosDisponiveis.map((codigo) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _buildCardCompet(codigo, _statsCompet[codigo]!, r),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card individual de competição (título maior e centralizado) ────────────
  Widget _buildCardCompet(String codigo, Map<String, dynamic> stats, R r) {
    final info = _competicoes[codigo];
    final nome = info?['nome'] ?? codigo;
    final logoAsset = info?['logo'] ?? '';
    final posicao = stats['posicao'] as int? ?? 0;
    final pontos = stats['pontos'] as int? ?? 0;
    final grupoBruto = stats['grupo'] as String? ?? '';
    // Só exibe "grupo" se a competição realmente tiver fase de grupos
    // (ex.: Libertadores/Sul-Americana). Brasileirão (pontos corridos) nunca.
    final grupoLabel =
        grupoBruto.replaceAll('GROUP_', '').replaceAll('GROUP', '').trim();
    final temGrupo = _temFaseDeGrupos(codigo) && grupoLabel.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Título centralizado, com a taça, em destaque
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: r.icon(30),
                height: r.icon(30),
                child: Image.asset(
                  logoAsset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.emoji_events,
                      color: _corDestaque, size: r.icon(26)),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'CLASSIFICAÇÃO ${nome.toString().toUpperCase()}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: r.fs(16),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (temGrupo)
                Column(
                  children: [
                    Text(
                      grupoLabel,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: r.fs(18),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'GRUPO',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: r.fs(9)),
                    ),
                  ],
                ),
              Column(
                children: [
                  Text(
                    '$posicaoº',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: r.fs(20),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    temGrupo ? 'LUGAR' : 'POSIÇÃO',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: r.fs(9)),
                  ),
                ],
              ),
              Column(
                children: [
                  Text(
                    '$pontos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: r.fs(20),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'PONTOS',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: r.fs(9)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Escudo com fallback ────────────────────────────────────────────────────
  Widget _buildEscudo({double size = 64}) {
    if (_escudoAsset.isNotEmpty) {
      return Image.asset(_escudoAsset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildEscudoUrl(size));
    }
    return _buildEscudoUrl(size);
  }

  Widget _buildEscudoUrl(double size) {
    if (_escudoUrl.isNotEmpty) {
      return Image.network(_escudoUrl,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.sports_soccer, color: _corDestaque, size: size));
    }
    return Icon(Icons.sports_soccer, color: _corDestaque, size: size);
  }

  // ── Card de notícia ────────────────────────────────────────────────────────
  Widget _buildCard(Map<String, String> news, R r) {
    return GestureDetector(
      onTap: () {
        _ativarManual();
        _webCtrl.loadRequest(Uri.parse(news['link']!));
        setState(() => _selectedUrl = news['link']);
      },
      child: Container(
        height: r.newsCardHeight(),
        margin: EdgeInsets.symmetric(horizontal: r.sp(24), vertical: r.sp(10)),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(22)),
              child: SizedBox(
                width: r.w(0.24),
                child: news['image'] != ''
                    ? CachedNetworkImage(
                        imageUrl: news['image']!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: Colors.white10),
                        errorWidget: (_, __, ___) => Icon(Icons.sports_soccer,
                            color: _corDestaque.withOpacity(0.3), size: 50),
                      )
                    : Icon(Icons.sports_soccer,
                        color: _corDestaque.withOpacity(0.3), size: 50),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(r.sp(16)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(news['title']!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(news['desc']!,
                        style: TextStyle(
                            color: Colors.white60, fontSize: r.fs(13)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WebView leitor ─────────────────────────────────────────────────────────
  Widget _buildLeitor(R r) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: _corTop,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                _buildEscudo(size: r.icon(26)),
                const SizedBox(width: 10),
                Text('GE - ${_nomeTime.toUpperCase()}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ]),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() => _selectedUrl = null);
                  _agendarScroll();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(30)),
            child: WebViewWidget(controller: _webCtrl),
          ),
        ),
      ],
    );
  }
}
