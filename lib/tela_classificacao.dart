import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'design/tema.dart';
import 'responsive.dart';
import 'services/football_service.dart';

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
    final p = _paginas.isNotEmpty ? _paginas[_pagina] : null;
    return EstruturaTela(
      icone: Icons.leaderboard_rounded,
      titulo: p?.titulo ?? 'Classificação',
      subtitulo: _paginas.length > 1
          ? 'Classificação, tabela ${_pagina + 1} de ${_paginas.length}'
          : 'Classificação',
      destaque: Destaques.tabela,
      rodapeDireita:
          _atualizadoEm != null ? 'Atualizado ${descreverIdade(_atualizadoEm!)}' : null,
      child: _carregando
          ? const Carregando(cor: Destaques.tabela)
          : p == null
              ? const AvisoTela(
                  icone: Icons.wifi_off_rounded,
                  titulo: 'Classificação indisponível',
                  texto: 'Sem conexão com a fonte de dados. A tela tenta de novo na próxima passagem.',
                )
              : ListView(
                    key: ValueKey(p.titulo),
                    controller: _scroll,
                    padding: EdgeInsets.only(bottom: r.sp(40)),
                    children: [
                      for (final g in p.grupos) ...[
                        _buildGrupo(r, g, p.ehLiga),
                        SizedBox(height: r.sp(28)),
                      ],
                    ],
                  ),
    );
  }

  Widget _buildGrupo(R r, GrupoTabela g, bool ehLiga) {
    final t = Tipo(r);
    final total = g.linhas.length;
    final larguraNum = r.sp(56);
    Widget num(String s, {TextStyle? estilo}) => SizedBox(
        width: larguraNum,
        child: Text(s, textAlign: TextAlign.center, style: estilo ?? t.legenda()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(r.sp(16), 0, r.sp(16), r.sp(8)),
          child: Row(children: [
            SizedBox(
                width: r.sp(44),
                child: Text(ehLiga ? '' : g.nome.replaceFirst('Grupo ', ''),
                    style: t.legenda())),
            SizedBox(width: r.sp(48)),
            Expanded(child: Text(ehLiga ? 'Time' : g.nome, style: t.legenda())),
            for (final c in ['Pts', 'J', 'V', 'E', 'D', 'Saldo']) num(c),
          ]),
        ),
        for (var i = 0; i < g.linhas.length; i++) _linha(r, g.linhas[i], total, ehLiga),
      ],
    );
  }

  Widget _linha(R r, LinhaTabela l, int total, bool ehLiga) {
    final t = Tipo(r);
    final nosso = l.timeId == _timeId;
    Color? zona;
    if (ehLiga) {
      if (l.posicao <= 4) {
        zona = Cores.positivo;
      } else if (l.posicao <= 6) {
        zona = Cores.positivo.withValues(alpha: 0.5);
      } else if (l.posicao > total - 4) {
        zona = Cores.alerta;
      }
    } else if (l.posicao <= 2) {
      zona = Cores.positivo;
    }
    final corTexto = nosso ? corDoTime(FootballService.instance.timeAtual) : Cores.texto;
    final estilo = t.corpo(cor: corTexto, peso: nosso ? FontWeight.w800 : FontWeight.w500);
    final larguraNum = r.sp(56);
    Widget num(String s, {bool forte = false, Color? cor}) => SizedBox(
        width: larguraNum,
        child: Text(s,
            textAlign: TextAlign.center,
            style: estilo.copyWith(
                color: cor ?? estilo.color,
                fontWeight: forte || nosso ? FontWeight.w800 : FontWeight.w500)));

    return Container(
      margin: EdgeInsets.only(bottom: r.sp(4)),
      padding: EdgeInsets.symmetric(horizontal: r.sp(16), vertical: r.sp(8)),
      decoration: BoxDecoration(
        color: nosso ? Cores.superficieElevada : null,
        borderRadius: BorderRadius.circular(r.sp(14)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: r.sp(28),
            margin: EdgeInsets.only(right: r.sp(12)),
            decoration: BoxDecoration(
              color: zona ?? Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: r.sp(28), child: Text('${l.posicao}', style: estilo)),
          SizedBox(
            width: r.sp(48),
            child: l.escudo.isEmpty
                ? Icon(Icons.shield, size: r.icon(26), color: Cores.textoApagado)
                : CachedNetworkImage(
                    imageUrl: l.escudo,
                    height: r.icon(28),
                    width: r.icon(28),
                    memCacheHeight: 80,
                    errorWidget: (_, __, ___) =>
                        Icon(Icons.shield, size: r.icon(26), color: Cores.textoApagado),
                  ),
          ),
          Expanded(child: Text(l.time, overflow: TextOverflow.ellipsis, style: estilo)),
          num('${l.pontos}', forte: true),
          num('${l.jogos}'),
          num('${l.vitorias}'),
          num('${l.empates}'),
          num('${l.derrotas}'),
          num(l.saldo > 0 ? '+${l.saldo}' : '${l.saldo}',
              cor: l.saldo > 0
                  ? Cores.positivo
                  : l.saldo < 0
                      ? Cores.alerta
                      : Cores.textoApagado),
        ],
      ),
    );
  }
}
