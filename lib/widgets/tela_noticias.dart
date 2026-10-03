import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../cache_manager.dart';
import '../design/tema.dart';
import '../responsive.dart';
import '../services/news_service.dart';

/// Tela genérica de notícias usada por Time, Brasil e Região.
///
/// Mesmo esqueleto das demais telas (título à esquerda, atualização à
/// direita). Concentra a lista com rolagem automática, pausa no fim, modo
/// manual ao tocar e o leitor da notícia (WebView criado só quando alguém
/// abre uma notícia).
class TelaNoticias extends StatefulWidget {
  final VoidCallback aoTerminar;
  final Future<({List<Noticia> noticias, DateTime? atualizadoEm})> Function() carregar;

  final IconData icone;
  final String titulo;
  final String? subtitulo;
  final Color destaque;
  final Widget? marca;

  /// Bloco opcional entre o título e a lista (ex.: resumo do time).
  final Widget? extra;

  final Color Function(Noticia n)? corDoRotulo;
  final int velocidadePxSeg;
  final int pausaFinalSeg;

  const TelaNoticias({
    super.key,
    required this.aoTerminar,
    required this.carregar,
    required this.icone,
    required this.titulo,
    required this.destaque,
    this.subtitulo,
    this.extra,
    this.marca,
    this.corDoRotulo,
    this.velocidadePxSeg = 35,
    this.pausaFinalSeg = 10,
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
  Noticia? _aberta;
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
    _inicioTimer = Timer(const Duration(seconds: 5), _autoScroll);
  }

  bool get _podeAutomatico => mounted && !_manual && _aberta == null;

  Future<void> _autoScroll() async {
    if (!_podeAutomatico) return;
    if (_noticias.isEmpty) return _terminarEm(const Duration(seconds: 6));
    if (!_scroll.hasClients) return _terminarEm(Duration(seconds: widget.pausaFinalSeg.clamp(5, 60)));
    final max = _scroll.position.maxScrollExtent;
    if (max < 50) {
      return _terminarEm(Duration(seconds: (widget.pausaFinalSeg + 12).clamp(10, 60)));
    }
    final alvo = (max - 80).clamp(0.0, max);
    final vel = widget.velocidadePxSeg.clamp(10, 200);
    final dur = ((alvo - _scroll.offset) / vel).clamp(5, 120).toInt();
    _rolando = true;
    await _scroll.animateTo(alvo, duration: Duration(seconds: dur), curve: Curves.linear);
    _rolando = false;
    if (_podeAutomatico) _terminarEm(Duration(seconds: widget.pausaFinalSeg.clamp(0, 60)));
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
      _scroll.jumpTo(_scroll.offset);
      _rolando = false;
    }
    if (!_manual) setState(() => _manual = true);
    _manualTimer?.cancel();
    _manualTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      setState(() {
        _manual = false;
        _aberta = null;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _inicioTimer = Timer(const Duration(seconds: 3), _autoScroll);
    });
  }

  void _abrir(Noticia n) {
    _ativarManual();
    _web ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white);
    _web!.loadRequest(Uri.parse(n.link));
    setState(() => _aberta = n);
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _ativarManual(),
      child: EstruturaTela(
        icone: widget.icone,
        marca: widget.marca,
        titulo: widget.titulo,
        subtitulo: _aberta == null ? widget.subtitulo : _aberta!.titulo,
        destaque: widget.destaque,
        rodapeDireita: _aberta != null
            ? null
            : _manual
                ? 'Toque numa notícia para ler'
                : (_atualizadoEm != null ? 'Atualizado ${descreverIdade(_atualizadoEm!)}' : null),
        acaoDireita: _aberta == null
            ? null
            : TextButton.icon(
                onPressed: () => setState(() => _aberta = null),
                icon: Icon(Icons.close_rounded, color: widget.destaque),
                label: Text('Fechar notícia',
                    style: Tipo(r).corpo(cor: widget.destaque, peso: FontWeight.w700)),
              ),
        child: _aberta != null ? _buildLeitor(r) : _buildLista(r),
      ),
    );
  }

  Widget _buildLista(R r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.extra != null) ...[widget.extra!, SizedBox(height: r.sp(20))],
        Expanded(
          child: _carregando
              ? Carregando(cor: widget.destaque)
              : _noticias.isEmpty
                  ? const AvisoTela(
                      icone: Icons.wifi_off_rounded,
                      titulo: 'Sem notícias no momento',
                      texto: 'Verifique a internet. A tela tenta de novo na próxima passagem.',
                    )
                  : ListView.separated(
                      controller: _scroll,
                      physics: _manual
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.only(bottom: r.sp(80)),
                      itemCount: _noticias.length,
                      separatorBuilder: (_, __) => Divider(
                          height: r.sp(36), thickness: 1, color: Cores.contorno),
                      itemBuilder: (_, i) => _buildItem(_noticias[i], r),
                    ),
        ),
      ],
    );
  }

  Widget _buildItem(Noticia n, R r) {
    final t = Tipo(r);
    final cor = widget.corDoRotulo?.call(n) ?? widget.destaque;
    final largura = r.w(0.22);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _abrir(n),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(r.sp(18)),
            child: SizedBox(
              width: largura,
              height: largura * 0.62,
              child: n.imagem.isEmpty
                  ? ColoredBox(
                      color: Cores.superficie,
                      child: Icon(widget.icone, color: Cores.textoApagado, size: r.icon(40)),
                    )
                  : CachedNetworkImage(
                      imageUrl: n.imagem,
                      fit: BoxFit.cover,
                      memCacheWidth: 600,
                      placeholder: (_, __) => ColoredBox(color: Cores.superficie),
                      errorWidget: (_, __, ___) => ColoredBox(
                        color: Cores.superficie,
                        child: Icon(widget.icone, color: Cores.textoApagado, size: r.icon(40)),
                      ),
                    ),
            ),
          ),
          SizedBox(width: r.sp(24)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n.rotulo.isNotEmpty) ...[
                  Selo(n.rotulo, cor: cor),
                  SizedBox(height: r.sp(10)),
                ],
                Text(n.titulo,
                    style: t.subtitulo(), maxLines: 3, overflow: TextOverflow.ellipsis),
                if (n.descricao.isNotEmpty && n.descricao != n.titulo) ...[
                  SizedBox(height: r.sp(8)),
                  Text(n.descricao,
                      style: t.apoio(), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeitor(R r) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(r.sp(24)),
      child: WebViewWidget(controller: _web!),
    );
  }
}
