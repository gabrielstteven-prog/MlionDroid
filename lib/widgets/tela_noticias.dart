import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../cache_manager.dart';
import '../responsive.dart';
import '../services/news_service.dart';

/// Tela genérica de notícias usada por Time, Brasil e Região.
///
/// Concentra o que antes estava copiado nas três telas: lista com scroll
/// automático, pausa no fim, modo manual ao tocar, leitor da notícia
/// (WebView criado só quando alguém abre uma notícia) e "atualizado há".
class TelaNoticias extends StatefulWidget {
  final VoidCallback aoTerminar;

  /// Busca as notícias (normalmente via NewsService, com cache).
  final Future<({List<Noticia> noticias, DateTime? atualizadoEm})> Function()
      carregar;

  /// Cabeçalho (título, escudo, filtros...).
  final Widget Function(BuildContext context, R r, bool modoManual) cabecalho;

  final Color corDestaque;
  final Color Function(Noticia n)? corDoRotulo;
  final Gradient fundo;
  final String tituloLeitor;
  final int velocidadePxSeg;
  final int pausaFinalSeg;
  final IconData iconeSemImagem;

  const TelaNoticias({
    super.key,
    required this.aoTerminar,
    required this.carregar,
    required this.cabecalho,
    required this.corDestaque,
    required this.fundo,
    required this.tituloLeitor,
    this.corDoRotulo,
    this.velocidadePxSeg = 35,
    this.pausaFinalSeg = 10,
    this.iconeSemImagem = Icons.article_rounded,
  });

  @override
  State<TelaNoticias> createState() => _TelaNoticiasState();
}

class _TelaNoticiasState extends State<TelaNoticias> {
  final _scroll = ScrollController();
  List<Noticia> _noticias = [];
  DateTime? _atualizadoEm;
  bool _carregando = true;
  bool _manual = false;
  String? _urlAberta;
  WebViewController? _web;

  Timer? _inicioTimer;
  Timer? _manualTimer;
  Timer? _saidaTimer;
  bool _rolando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _inicioTimer?.cancel();
    _manualTimer?.cancel();
    _saidaTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final r = await widget.carregar();
    if (!mounted) return;
    setState(() {
      _noticias = r.noticias;
      _atualizadoEm = r.atualizadoEm;
      _carregando = false;
    });
    _agendarScroll();
  }

  void _agendarScroll() {
    _inicioTimer?.cancel();
    _inicioTimer = Timer(const Duration(seconds: 5), _autoScroll);
  }

  bool get _podeAutomatico => mounted && !_manual && _urlAberta == null;

  Future<void> _autoScroll() async {
    if (!_podeAutomatico) return;
    if (_noticias.isEmpty) {
      _terminarEm(const Duration(seconds: 6));
      return;
    }
    if (!_scroll.hasClients) {
      _terminarEm(Duration(seconds: widget.pausaFinalSeg.clamp(5, 60)));
      return;
    }
    final max = _scroll.position.maxScrollExtent;
    if (max < 50) {
      // Conteúdo cabe na tela: mostra por um tempo e segue.
      _terminarEm(Duration(seconds: (widget.pausaFinalSeg + 12).clamp(10, 60)));
      return;
    }
    // O ListView tem um respiro vazio no fim; não rola até ele.
    final alvo = (max - 100).clamp(0.0, max);
    final vel = widget.velocidadePxSeg.clamp(10, 200);
    final dur = ((alvo - _scroll.offset) / vel).clamp(5, 120).toInt();
    _rolando = true;
    await _scroll.animateTo(alvo, duration: Duration(seconds: dur), curve: Curves.linear);
    _rolando = false;
    if (!_podeAutomatico) return;
    _terminarEm(Duration(seconds: widget.pausaFinalSeg.clamp(0, 60)));
  }

  void _terminarEm(Duration d) {
    _saidaTimer?.cancel();
    _saidaTimer = Timer(d, () {
      if (_podeAutomatico) widget.aoTerminar();
    });
  }

  void _ativarManual() {
    _inicioTimer?.cancel();
    _saidaTimer?.cancel();
    if (_rolando && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.offset); // interrompe a animação
      _rolando = false;
    }
    if (!_manual) setState(() => _manual = true);
    _manualTimer?.cancel();
    _manualTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      setState(() {
        _manual = false;
        _urlAberta = null;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _agendarScroll();
    });
  }

  void _abrir(Noticia n) {
    _ativarManual();
    _web ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white);
    _web!.loadRequest(Uri.parse(n.link));
    setState(() => _urlAberta = n.link);
  }

  void _fecharLeitor() {
    setState(() => _urlAberta = null);
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _ativarManual(),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: widget.fundo),
        child: Center(
          child: Container(
            width: r.panelWidth,
            height: r.panelHeight,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: _urlAberta == null ? _buildLista(r) : _buildLeitor(r),
          ),
        ),
      ),
    );
  }

  Widget _buildLista(R r) {
    return Column(
      children: [
        widget.cabecalho(context, r, _manual),
        if (_atualizadoEm != null && !_carregando)
          Padding(
            padding: EdgeInsets.only(bottom: r.sp(6)),
            child: Text(
              _manual
                  ? '• NAVEGAÇÃO MANUAL — toque numa notícia para ler •'
                  : 'Atualizado ${descreverIdade(_atualizadoEm!)}',
              style: GoogleFonts.rajdhani(
                color: _manual ? Colors.orangeAccent : Colors.white38,
                fontSize: r.fs(14),
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        Expanded(
          child: _carregando
              ? Center(child: CircularProgressIndicator(color: widget.corDestaque))
              : _noticias.isEmpty
                  ? Center(
                      child: Text('Sem notícias no momento',
                          style: GoogleFonts.rajdhani(
                              color: Colors.white54, fontSize: r.fs(20))))
                  : ListView.builder(
                      controller: _scroll,
                      physics: _manual
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 110),
                      itemCount: _noticias.length,
                      itemBuilder: (_, i) => _buildCard(_noticias[i], r),
                    ),
        ),
      ],
    );
  }

  Widget _buildCard(Noticia n, R r) {
    final cor = widget.corDoRotulo?.call(n) ?? widget.corDestaque;
    final semImagem = ColoredBox(
      color: Colors.white.withValues(alpha: 0.05),
      child: Icon(widget.iconeSemImagem, color: Colors.white24, size: r.icon(50)),
    );
    return GestureDetector(
      onTap: () => _abrir(n),
      child: Container(
        constraints: BoxConstraints(minHeight: r.newsCardHeight(0.17)),
        margin: EdgeInsets.symmetric(horizontal: r.sp(20), vertical: r.sp(8)),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
                child: SizedBox(
                  width: r.w(0.25),
                  child: n.imagem.isEmpty
                      ? semImagem
                      : CachedNetworkImage(
                          imageUrl: n.imagem,
                          fit: BoxFit.cover,
                          memCacheWidth: 600,
                          placeholder: (_, __) =>
                              ColoredBox(color: Colors.white.withValues(alpha: 0.05)),
                          errorWidget: (_, __, ___) => semImagem,
                        ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(r.sp(18)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (n.rotulo.isNotEmpty)
                        Container(
                          margin: EdgeInsets.only(bottom: r.sp(8)),
                          padding: EdgeInsets.symmetric(
                              horizontal: r.sp(10), vertical: r.sp(3)),
                          decoration: BoxDecoration(
                            color: cor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cor.withValues(alpha: 0.55)),
                          ),
                          child: Text(n.rotulo.toUpperCase(),
                              style: GoogleFonts.rajdhani(
                                  color: cor,
                                  fontSize: r.fs(13),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4)),
                        ),
                      Text(
                        n.titulo,
                        style: GoogleFonts.rajdhani(
                          color: Colors.white,
                          fontSize: r.fs(r.isCompact ? 18 : 22),
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (n.descricao.isNotEmpty && n.descricao != n.titulo) ...[
                        SizedBox(height: r.sp(6)),
                        Text(
                          n.descricao,
                          style: GoogleFonts.rajdhani(
                            color: Colors.white.withValues(alpha: 0.80),
                            fontSize: r.fs(r.isCompact ? 15 : 18),
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
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
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Row(
            children: [
              Icon(Icons.article_rounded, color: widget.corDestaque, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.tituloLeitor,
                    style: GoogleFonts.rajdhani(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: 1)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: _fecharLeitor,
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
            child: WebViewWidget(controller: _web!),
          ),
        ),
      ],
    );
  }
}
