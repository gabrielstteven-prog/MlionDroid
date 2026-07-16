import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'config_manager.dart';
import 'cache_manager.dart';
import 'responsive.dart';

class TelaRegiao extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaRegiao({super.key, required this.aoTerminar});

  @override
  State<TelaRegiao> createState() => _TelaRegiaoState();
}

class _TelaRegiaoState extends State<TelaRegiao> {
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

  // ── Todas as cidades disponíveis ──────────────────────────────────────────
  static const Map<String, Map<String, String>> _todasCidades = {
    'hortolandia': {'nome': 'Hortolândia', 'cor': '0xFF00BCD4'},
    'campinas': {'nome': 'Campinas', 'cor': '0xFFFFD54F'},
    'sumare': {'nome': 'Sumaré', 'cor': '0xFF80DEEA'},
    'americana': {'nome': 'Americana', 'cor': '0xFFA5D6A7'},
    'santa-barbara': {'nome': "Sta. Bárbara d'Oeste", 'cor': '0xFFCE93D8'},
    'indaiatuba': {'nome': 'Indaiatuba', 'cor': '0xFFFFAB91'},
    'paulinia': {'nome': 'Paulínia', 'cor': '0xFFF48FB1'},
  };

  static const String _feedUrl =
      'https://g1.globo.com/rss/g1/sp/campinas-regiao/';

  // ── Lê configurações do ConfigManager ─────────────────────────────────────
  List<String> get _cidadesSelecionadas {
    try {
      final raw = _cfg.get('regiao', 'cidades_selecionadas');
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return ['hortolandia'];
  }

  Color get _corTop =>
      _parseColor(_cfg.get('regiao', 'cor_gradiente_top'), 0xFF1a237e);

  Color get _corBottom =>
      _parseColor(_cfg.get('regiao', 'cor_gradiente_bottom'), 0xFF000000);

  int get _scrollVelocidade =>
      (_cfg.get('regiao', 'duracao_scroll_px_seg') as num?)?.toInt() ?? 35;

  int get _pausaFinal =>
      (_cfg.get('regiao', 'pausa_final_seg') as num?)?.toInt() ?? 10;

  int get _qtdPorCidade =>
      (_cfg.get('regiao', 'qtd_noticias') as num?)?.toInt() ?? 2;

  Color _parseColor(dynamic raw, int fallback) {
    try {
      if (raw is String) return Color(int.parse(raw));
    } catch (_) {}
    return Color(fallback);
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white);

    _carregarNoticias();
    _updateTimer = Timer.periodic(
        _cfg.getIntervaloAtualizacao('regiao'), (_) => _buscarNoticias());
    // Anti-travamento: sai em até 5 minutos mesmo se tudo falhar
    Timer(const Duration(minutes: 5), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _startTimer?.cancel();
    _manualResetTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get _chaveCache =>
      'regiao_noticias_${_cidadesSelecionadas.join("-")}_$_qtdPorCidade';

  Future<void> _carregarNoticias() async {
    final cache = await CacheManager.instance.obter<List<dynamic>>(
      _chaveCache,
      validade: _cfg.getIntervaloAtualizacao('regiao'),
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
    final selecionadas = _cidadesSelecionadas;
    final lista = <Map<String, String>>[];

    try {
      final res = await http
          .get(Uri.parse(_feedUrl))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 && mounted) {
        final doc = XmlDocument.parse(utf8.decode(res.bodyBytes));
        final todosItens = doc.findAllElements('item').toList();

        // Distribui notícias entre as cidades selecionadas
        int idxGlobal = 0;
        for (final cidadeKey in selecionadas) {
          final cidadeInfo = _todasCidades[cidadeKey];
          if (cidadeInfo == null) continue;

          int count = 0;
          while (count < _qtdPorCidade && idxGlobal < todosItens.length) {
            final node = todosItens[idxGlobal++];
            final desc = node.findElements('description').first.innerText;
            final img =
                RegExp(r'src="([^"]+)"').firstMatch(desc)?.group(1) ?? '';
            lista.add({
              'title': node.findElements('title').first.innerText,
              'desc': desc.replaceAll(RegExp(r'<[^>]*>|&nbsp;'), '').trim(),
              'link': node.findElements('link').first.innerText,
              'image': img,
              'cidade': cidadeInfo['nome']!,
              'cor': cidadeInfo['cor']!,
            });
            count++;
          }
        }
      }
    } catch (e) {
      debugPrint('TelaRegiao erro: $e');
    }

    if (mounted) {
      setState(() {
        _newsList = lista;
        _carregando = false;
      });
      _agendarScroll();
    }
    if (lista.isNotEmpty) {
      await CacheManager.instance.salvar(_chaveCache, lista);
    }
  }

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
    if (max < 400) {
      // Antes: tentava de novo pra sempre a cada 2s. Se as notícias já
      // couberam na tela sem precisar rolar (poucas cidades/notícias
      // configuradas), isso nunca terminava — a tela ficava presa aqui
      // até o timer de segurança de 5 minutos entrar em ação.
      _tentativasScrollCurtas++;
      if (_tentativasScrollCurtas < 3) {
        await Future.delayed(const Duration(seconds: 2));
        _autoScroll();
        return;
      }
      // Depois de 3 tentativas (6s), assume que o conteúdo realmente é
      // curto e não precisa de scroll — espera o tempo normal e segue.
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
    // último card) — não incluímos esse vão no alvo do scroll, senão a
    // tela "passa" da última notícia e trava num espaço em branco.
    final alvo = (max - 120).clamp(0.0, max).toDouble();
    final dur = (max / _scrollVelocidade).clamp(25, 90).toInt();
    await _scrollCtrl.animateTo(alvo,
        duration: Duration(seconds: dur), curve: Curves.linear);

    if (_pausaFinal > 0) {
      await Future.delayed(Duration(seconds: _pausaFinal));
    }

    if (mounted && !_isManualMode && _selectedUrl == null) {
      if (_scrollCtrl.offset >= alvo - 50) widget.aoTerminar();
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
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(30),
            ),
            child: _selectedUrl == null ? _buildNewsList(r) : _buildLeitor(r),
          ),
        ),
      ),
    );
  }

  Widget _buildNewsList(R r) {
    if (_carregando) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent));
    }
    return Column(
      children: [
        _buildHeader(r),
        Expanded(
          child: ListView.builder(
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

  Widget _buildHeader(R r) {
    final cidades = _cidadesSelecionadas;
    return Padding(
      padding: EdgeInsets.only(top: r.sp(36), bottom: r.sp(16)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_city,
                  color: Colors.cyanAccent, size: r.icon(46)),
              SizedBox(width: 12),
              Text('REGIÃO',
                  style: TextStyle(
                      fontSize: r.fs(40),
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 8),
          // Badges das cidades selecionadas
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: cidades.map((key) {
              final info = _todasCidades[key];
              if (info == null) return const SizedBox.shrink();
              final cor = Color(int.tryParse(info['cor']!) ?? 0xFF00BCD4);
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cor.withValues(alpha: 0.4)),
                ),
                child: Text(info['nome']!,
                    style: TextStyle(
                        color: cor,
                        fontSize: r.fs(12),
                        fontWeight: FontWeight.bold)),
              );
            }).toList(),
          ),
          Container(
            width: r.dividerWidth(),
            height: 2,
            color: Colors.cyanAccent,
            margin: const EdgeInsets.symmetric(vertical: 10),
          ),
          Text(
            _isManualMode ? '• NAVEGAÇÃO MANUAL •' : 'Notícias da Região 📰',
            style: TextStyle(
                color: _isManualMode ? Colors.orangeAccent : Colors.cyanAccent,
                fontSize: r.fs(18),
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, String> news, R r) {
    final cor = Color(int.tryParse(news['cor'] ?? '0xFF00BCD4') ?? 0xFF00BCD4);

    return GestureDetector(
      onTap: () {
        _ativarManual();
        _webCtrl.loadRequest(Uri.parse(news['link']!));
        setState(() => _selectedUrl = news['link']);
      },
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: r.sp(20), vertical: r.sp(8)),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(25)),
              child: SizedBox(
                width: r.w(0.27),
                child: news['image'] != ''
                    ? CachedNetworkImage(
                        imageUrl: news['image']!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: Colors.white10),
                        errorWidget: (_, __, ___) => Icon(Icons.newspaper,
                            color: Colors.white24, size: r.icon(50)),
                      )
                    : Icon(Icons.newspaper,
                        color: Colors.white24, size: r.icon(50)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(r.sp(20)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge cidade
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: r.sp(10), vertical: r.sp(3)),
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: cor.withValues(alpha: 0.55), width: 1),
                      ),
                      child: Text(
                        news['cidade']!.toUpperCase(),
                        style: GoogleFonts.rajdhani(
                          color: cor,
                          fontSize: r.fs(13),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    SizedBox(height: r.sp(8)),
                    // Título — grande e responsivo
                    Text(
                      news['title']!,
                      style: GoogleFonts.rajdhani(
                        color: Colors.white,
                        fontSize: r.fs(r.isCompact ? 18 : 22),
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: r.sp(7)),
                    // Descrição — 3 linhas, fonte maior, cor totalmente legível
                    Text(
                      news['desc']!,
                      style: GoogleFonts.rajdhani(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: r.fs(r.isCompact ? 15 : 18),
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                Icon(Icons.location_city,
                    color: Colors.cyanAccent, size: r.icon(20)),
                SizedBox(width: 8),
                Text('G1 - REGIÃO',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ]),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => setState(() => _selectedUrl = null),
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
