import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'config_manager.dart';
import 'cache_manager.dart';
import 'responsive.dart';
import 'performance_manager.dart';

class TelaBrasil extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaBrasil({super.key, required this.aoTerminar});

  @override
  State<TelaBrasil> createState() => _TelaBrasilState();
}

class _TelaBrasilState extends State<TelaBrasil> {
  final _cfg = ConfigManager();
  final ScrollController _scrollCtrl = ScrollController();
  List<Map<String, String>> _noticias = [];
  bool _carregando = true;
  String? _urlAberta;

  late final WebViewController _webCtrl;
  bool _modoManual = false;

  Timer? _updateTimer;
  Timer? _startTimer;
  Timer? _manualTimer;

  int get _scrollVelocidade =>
      (_cfg.get('brasil', 'duracao_scroll_px_seg') as num?)?.toInt() ?? 35;

  int get _pausaFinal =>
      (_cfg.get('brasil', 'pausa_final_seg') as num?)?.toInt() ?? 10;

  int get _qtdNoticias =>
      (_cfg.get('brasil', 'qtd_noticias') as num?)?.toInt() ?? 3;

  List<String> get _categoriasSelecionadas =>
      _cfg.getStringList('brasil', 'categorias_selecionadas');

  static const _feeds = [
    {
      'key': 'politica',
      'url': 'https://g1.globo.com/rss/g1/politica/',
      'cat': 'Política'
    },
    {
      'key': 'economia',
      'url': 'https://g1.globo.com/rss/g1/economia/',
      'cat': 'Economia'
    },
    {
      'key': 'tecnologia',
      'url': 'https://g1.globo.com/rss/g1/tecnologia/',
      'cat': 'Tecnologia'
    },
    {
      'key': 'saude',
      'url': 'https://g1.globo.com/rss/g1/saude/',
      'cat': 'Saúde'
    },
    {'key': 'geral', 'url': 'https://g1.globo.com/rss/g1/', 'cat': 'Geral'},
  ];

  static const Map<String, Color> _coresCat = {
    'Política': Color(0xFFEF5350),
    'Economia': Color(0xFF66BB6A),
    'Tecnologia': Color(0xFF00D4FF),
    'Saúde': Color(0xFFEC407A),
    'Geral': Color(0xFFFFB300),
  };

  @override
  void initState() {
    super.initState();
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white);
    _carregarNoticias();
    _updateTimer = Timer.periodic(
        _cfg.getIntervaloAtualizacao('brasil'), (_) => _buscarNoticias());
    // Anti-travamento: sai em até 5 minutos mesmo se tudo falhar
    Timer(const Duration(minutes: 5), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _startTimer?.cancel();
    _manualTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get _chaveCache =>
      'brasil_noticias_${_categoriasSelecionadas.join("-")}_$_qtdNoticias';

  Future<void> _carregarNoticias() async {
    final cache = await CacheManager.instance.obter<List<dynamic>>(
      _chaveCache,
      validade: _cfg.getIntervaloAtualizacao('brasil'),
    );
    if (cache != null && mounted) {
      setState(() {
        _noticias =
            cache.map((e) => Map<String, String>.from(e as Map)).toList();
        _carregando = false;
      });
      _agendarScroll();
      return;
    }
    await _buscarNoticias();
  }

  Future<void> _buscarNoticias() async {
    final lista = <Map<String, String>>[];
    // Só busca das categorias que o usuário selecionou em Configurações —
    // igual já funciona em Notícias Região com as cidades.
    final feedsAtivos = _feeds
        .where((f) => _categoriasSelecionadas.contains(f['key']))
        .toList();
    final feedsParaBuscar = feedsAtivos.isEmpty ? _feeds : feedsAtivos;

    for (final feed in feedsParaBuscar) {
      try {
        final res = await http
            .get(Uri.parse(feed['url']!))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final doc = XmlDocument.parse(utf8.decode(res.bodyBytes));
          // "Quantidade" agora significa notícias POR categoria — igual o
          // "por cidade" da tela Região. Cada categoria selecionada
          // contribui exatamente esse número, não é mais um total global.
          final itens =
              doc.findAllElements('item').take(_qtdNoticias).map((node) {
            final desc = node.findElements('description').first.innerText;
            final img =
                RegExp(r'src="([^"]+)"').firstMatch(desc)?.group(1) ?? '';
            return {
              'title': node.findElements('title').first.innerText,
              'desc': desc.replaceAll(RegExp(r'<[^>]*>|&nbsp;'), '').trim(),
              'link': node.findElements('link').first.innerText,
              'image': img,
              'cat': feed['cat']!,
            };
          }).toList();
          lista.addAll(itens);
        }
      } catch (e) {
        debugPrint('TelaBrasil feed ${feed['cat']}: $e');
      }
    }
    lista.shuffle();
    if (mounted) {
      setState(() {
        _noticias = lista;
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
      if (mounted && !_modoManual && _urlAberta == null) _autoScroll();
    });
  }

  int _tentativasScrollCurtas = 0;

  Future<void> _autoScroll() async {
    if (!mounted || _modoManual || _urlAberta != null) return;
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max < 400) {
      // Antes: tentava de novo pra sempre a cada 2s se o conteúdo não
      // precisasse de scroll (poucas notícias configuradas) — travava
      // a tela até o timer de segurança de 5 minutos.
      _tentativasScrollCurtas++;
      if (_tentativasScrollCurtas < 3) {
        await Future.delayed(const Duration(seconds: 2));
        _autoScroll();
        return;
      }
      _tentativasScrollCurtas = 0;
      final espera = _pausaFinal > 0 ? _pausaFinal : 8;
      await Future.delayed(Duration(seconds: espera));
      if (mounted && !_modoManual && _urlAberta == null) {
        widget.aoTerminar();
      }
      return;
    }
    _tentativasScrollCurtas = 0;
    // O ListView tem 100px de padding vazio no fundo (respiro visual do
    // último card) — não incluímos esse vão no alvo do scroll, senão a
    // tela "passa" da última notícia e trava num espaço em branco.
    final alvo = (max - 100).clamp(0.0, max).toDouble();
    final dur = (max / _scrollVelocidade).clamp(25, 90).toInt();
    await _scrollCtrl.animateTo(alvo,
        duration: Duration(seconds: dur), curve: Curves.linear);
    // Antes: pausa fixa de 10s, ignorava a configuração do usuário.
    // Agora respeita 'pausa_final_seg' de verdade — inclusive 0 (sem espera).
    if (_pausaFinal > 0) {
      await Future.delayed(Duration(seconds: _pausaFinal));
    }
    if (mounted && !_modoManual && _urlAberta == null) {
      if (_scrollCtrl.offset >= alvo - 50) widget.aoTerminar();
    }
  }

  void _ativarManual() {
    _startTimer?.cancel();
    setState(() => _modoManual = true);
    _manualTimer?.cancel();
    _manualTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        setState(() => _modoManual = false);
        if (_urlAberta == null) {
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
      child: Scaffold(
        backgroundColor: const Color(0xFF060910),
        body: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _BgPainterBrasil())),
            SafeArea(
              child: Center(
                child: SizedBox(
                  width: r.panelWidth,
                  height: r.panelHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: PerformanceManager.instance.sigmaBlur(12),
                        sigmaY: PerformanceManager.instance.sigmaBlur(12),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: _urlAberta == null
                            ? _buildLista(r)
                            : _buildLeitor(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista(R r) {
    if (_carregando) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFB300)));
    }
    return Column(
      children: [
        _buildHeader(r),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            physics: _modoManual
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: _noticias.length,
            itemBuilder: (_, i) => _buildCard(_noticias[i], r),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(R r) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.sp(32), r.sp(28), r.sp(32), r.sp(14)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🇧🇷', style: TextStyle(fontSize: r.fs(38))),
              const SizedBox(width: 16),
              Text('BRASIL',
                  style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontSize: r.fs(40),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: _coresCat.entries.map((e) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: e.value.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: e.value.withValues(alpha: 0.3)),
                ),
                child: Text(e.key,
                    style: GoogleFonts.rajdhani(
                        color: e.value,
                        fontSize: r.fs(13),
                        fontWeight: FontWeight.w700)),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Container(
            height: 1.5,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
                Color(0xFF009C3B),
                Color(0xFFFFDF00),
                Color(0xFF002776),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _modoManual
                ? '• NAVEGAÇÃO MANUAL •'
                : 'Principais Notícias do Brasil  •  G1',
            style: GoogleFonts.rajdhani(
                color:
                    _modoManual ? Colors.orangeAccent : const Color(0xFFFFB300),
                fontSize: r.fs(15),
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, String> n, R r) {
    final cor = _coresCat[n['cat']] ?? const Color(0xFFFFB300);
    return GestureDetector(
      onTap: () {
        _ativarManual();
        _webCtrl.loadRequest(Uri.parse(n['link']!));
        setState(() => _urlAberta = n['link']);
      },
      child: Container(
        // Removido o 'height' fixo truncado para usar padding interno responsivo (assim como a região)
        margin: EdgeInsets.symmetric(horizontal: r.sp(20), vertical: r.sp(8)),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(
              25), // Cantos levemente mais arredondados da Região
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            // Imagem adaptada com a largura proporcional ideal da Região
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(25)),
              child: SizedBox(
                width: r.w(
                    0.27), // Aumentado de 0.25 para 0.27 para melhor proporção em telas maiores
                child: n['image'] != ''
                    ? CachedNetworkImage(
                        imageUrl: n['image']!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                            color: Colors.white.withValues(alpha: 0.05)),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          child: Icon(Icons.article_rounded,
                              color: Colors.white24, size: r.icon(50)),
                        ),
                      )
                    : Container(
                        color: Colors.white.withValues(alpha: 0.05),
                        child: Icon(Icons.article_rounded,
                            color: Colors.white24, size: r.icon(50)),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(
                    r.sp(20)), // Padding maior e mais confortável
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge da Categoria / Assunto
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: r.sp(10), vertical: r.sp(3)),
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cor.withValues(alpha: 0.55)),
                      ),
                      child: Text(n['cat']!.toUpperCase(),
                          style: GoogleFonts.rajdhani(
                              color: cor,
                              fontSize: r.fs(13),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4)),
                    ),
                    SizedBox(height: r.sp(8)),
                    // Título — Copiado o conceito de tamanho grande e responsivo da região
                    Text(
                      n['title']!,
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
                    // Descrição — Alterado para 3 linhas, fonte maior e opacidade mais visível de longe
                    Text(
                      n['desc']!,
                      style: GoogleFonts.rajdhani(
                        color: Colors.white.withValues(
                            alpha:
                                0.82), // Muito mais legível à distância do que o 0.45 anterior
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

  Widget _buildLeitor() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF0a1628),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Row(
            children: [
              const Text('🇧🇷', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text('G1 - BRASIL',
                  style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => setState(() => _urlAberta = null),
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(28)),
            child: WebViewWidget(controller: _webCtrl),
          ),
        ),
      ],
    );
  }
}

class _BgPainterBrasil extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = const Color(0xFF060910);
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), p);

    void orb(Offset c, double r, Color cor, double op) {
      p.shader = RadialGradient(
              colors: [cor.withValues(alpha: op), Colors.transparent])
          .createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, p);
    }

    orb(Offset(s.width * 0.15, s.height * 0.15), s.width * 0.25,
        const Color(0xFF009C3B), 0.08);
    orb(Offset(s.width * 0.85, s.height * 0.5), s.width * 0.25,
        const Color(0xFF002776), 0.08);
    orb(Offset(s.width * 0.5, s.height * 0.85), s.width * 0.2,
        const Color(0xFFFFDF00), 0.06);
  }

  @override
  bool shouldRepaint(_) => false;
}
