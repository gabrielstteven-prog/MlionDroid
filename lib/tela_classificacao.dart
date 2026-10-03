import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'responsive.dart';
import 'services/football_service.dart';
import 'util.dart';

/// Classificação do Brasileirão e (se ativado) da Libertadores, via ESPN.
class TelaClassificacao extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaClassificacao({super.key, required this.aoTerminar});

  @override
  State<TelaClassificacao> createState() => _TelaClassificacaoState();
}

class _Pagina {
  final String titulo;
  final List<GrupoTabela> grupos;
  final bool ehLiga; // true = pontos corridos (zonas G4/Z4)
  const _Pagina(this.titulo, this.grupos, this.ehLiga);
}

class _TelaClassificacaoState extends State<TelaClassificacao> {
  final _cfg = ConfigManager();
  final _scroll = ScrollController();

  bool _carregando = true;
  final List<_Pagina> _paginas = [];
  int _pagina = 0;
  DateTime? _atualizadoEm;
  bool _encerrada = false;

  int get _timeId => FootballService.instance.timeAtual.espnId;
  Color get _corTop => parseCor(_cfg.get('palmeiras', 'cor_gradiente_top'), 0xFF00441B);
  Color get _corDestaque => parseCor(_cfg.get('palmeiras', 'cor_destaque'), 0xFFC1A163);

  /// Velocidade em px/s. Configurações antigas guardavam 0.8 (px por tick),
  /// por isso o clamp.
  double get _velocidade =>
      _cfg.getDouble('classificacao', 'scroll_velocidade', 30).clamp(10, 120);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _encerrada = true;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final svc = FootballService.instance;
    final bra = await svc.tabela('bra.1');
    ComIdade<List<GrupoTabela>>? lib;
    if (_cfg.getBool('classificacao', 'mostrar_libertadores', true)) {
      lib = await svc.tabela('conmebol.libertadores');
    }
    if (!mounted) return;

    setState(() {
      if (bra != null && bra.valor.isNotEmpty) {
        _paginas.add(_Pagina('BRASILEIRÃO', bra.valor, true));
        _atualizadoEm = bra.atualizadoEm;
      }
      if (lib != null && lib.valor.isNotEmpty) {
        // O grupo do nosso time vem primeiro.
        final grupos = [...lib.valor]..sort((a, b) {
            final aTem = a.linhas.any((l) => l.timeId == _timeId) ? 0 : 1;
            final bTem = b.linhas.any((l) => l.timeId == _timeId) ? 0 : 1;
            return aTem.compareTo(bTem);
          });
        _paginas.add(_Pagina('LIBERTADORES', grupos, false));
      }
      _carregando = false;
    });
    _rodarPaginas();
  }

  Future<void> _rodarPaginas() async {
    if (_paginas.isEmpty) {
      await Future.delayed(const Duration(seconds: 8));
      if (!_encerrada) widget.aoTerminar();
      return;
    }
    for (var i = 0; i < _paginas.length; i++) {
      if (_encerrada) return;
      if (i > 0) setState(() => _pagina = i);
      await Future.delayed(const Duration(seconds: 3));
      if (_encerrada || !_scroll.hasClients) continue;
      _scroll.jumpTo(0);
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) {
        await _scroll.animateTo(max,
            duration: Duration(milliseconds: (max / _velocidade * 1000).round()),
            curve: Curves.linear);
      }
      await Future.delayed(
          Duration(seconds: _cfg.getInt('classificacao', 'pausa_troca_seg', 3).clamp(1, 30)));
    }
    if (!_encerrada) widget.aoTerminar();
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_corTop, _corTop.withValues(alpha: 0.4), Colors.black],
          ),
        ),
        child: SafeArea(
          child: _carregando
              ? Center(child: CircularProgressIndicator(color: _corDestaque))
              : _paginas.isEmpty
                  ? Center(
                      child: Text('Classificação indisponível no momento',
                          style: GoogleFonts.rajdhani(
                              color: Colors.white70, fontSize: r.fs(22))))
                  : _buildPagina(r, _paginas[_pagina]),
        ),
      ),
    );
  }

  Widget _buildPagina(R r, _Pagina p) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(top: r.sp(14), bottom: r.sp(6)),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Text(p.titulo,
                key: ValueKey(p.titulo),
                style: GoogleFonts.rajdhani(
                  fontSize: r.fs(34),
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 3,
                )),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _paginas.length; i++)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _pagina ? _corDestaque : Colors.white30,
                ),
              ),
            if (_atualizadoEm != null) ...[
              const SizedBox(width: 12),
              Text('atualizado ${descreverIdade(_atualizadoEm!)}',
                  style: GoogleFonts.rajdhani(color: Colors.white38, fontSize: r.fs(14))),
            ],
          ],
        ),
        SizedBox(height: r.sp(10)),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(r.sp(12), 0, r.sp(12), r.sp(30)),
            children: [
              for (final g in p.grupos) ...[
                _buildGrupo(r, g, p.ehLiga),
                SizedBox(height: r.sp(14)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrupo(R r, GrupoTabela g, bool ehLiga) {
    final fs = r.fs(16);
    final total = g.linhas.length;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _corDestaque.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Color.lerp(_corTop, Colors.black, 0.2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                SizedBox(width: 32, child: _cab('#', fs)),
                const SizedBox(width: 38),
                Expanded(child: _cab(ehLiga ? 'Time' : g.nome, fs, alinhar: TextAlign.left)),
                for (final c in ['P', 'J', 'V', 'E', 'D', 'SG']) SizedBox(width: 40, child: _cab(c, fs)),
              ],
            ),
          ),
          for (var i = 0; i < g.linhas.length; i++)
            _linha(r, g.linhas[i], i, total, ehLiga, fs),
        ],
      ),
    );
  }

  Widget _cab(String t, double fs, {TextAlign alinhar = TextAlign.center}) => Text(t,
      textAlign: alinhar,
      style: GoogleFonts.rajdhani(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fs));

  Widget _linha(R r, LinhaTabela l, int i, int total, bool ehLiga, double fs) {
    final nosso = l.timeId == _timeId;
    Color zona = Colors.transparent;
    if (ehLiga) {
      if (l.posicao <= 4) {
        zona = const Color(0xFF00C853);
      } else if (l.posicao <= 6) {
        zona = const Color(0xFF69F0AE);
      } else if (l.posicao > total - 4) {
        zona = const Color(0xFFFF5252);
      }
    } else if (l.posicao <= 2) {
      zona = const Color(0xFF00C853);
    }
    final corTexto = nosso ? _corDestaque : Colors.white;
    TextStyle st({bool bold = false}) => GoogleFonts.rajdhani(
        color: corTexto,
        fontSize: fs,
        fontWeight: bold || nosso ? FontWeight.w800 : FontWeight.w500);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: nosso
            ? _corDestaque.withValues(alpha: 0.18)
            : (i.isEven ? const Color(0xFF151515) : const Color(0xFF1d1d1d)),
        border: Border(left: BorderSide(width: 4, color: zona)),
      ),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('${l.posicao}', style: st(bold: true))),
          SizedBox(
            width: 38,
            child: l.escudo.isEmpty
                ? const Icon(Icons.shield, size: 26, color: Colors.white38)
                : CachedNetworkImage(
                    imageUrl: l.escudo,
                    height: 26,
                    width: 26,
                    memCacheHeight: 80,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.shield, size: 26, color: Colors.white38),
                  ),
          ),
          Expanded(child: Text(l.time, overflow: TextOverflow.ellipsis, style: st())),
          for (final v in [l.pontos, l.jogos, l.vitorias, l.empates, l.derrotas])
            SizedBox(width: 40, child: Text('$v', textAlign: TextAlign.center, style: st())),
          SizedBox(
            width: 40,
            child: Text(l.saldo > 0 ? '+${l.saldo}' : '${l.saldo}',
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                  fontSize: fs,
                  fontWeight: FontWeight.w800,
                  color: l.saldo > 0
                      ? const Color(0xFF00C853)
                      : l.saldo < 0
                          ? const Color(0xFFFF5252)
                          : Colors.white54,
                )),
          ),
        ],
      ),
    );
  }
}
