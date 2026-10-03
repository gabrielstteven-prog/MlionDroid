import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config_manager.dart';
import 'responsive.dart';
import 'services/football_service.dart';
import 'services/news_service.dart';
import 'times.dart';
import 'util.dart';
import 'widgets/tela_noticias.dart';

/// Notícias do time do coração (ge.globo) + resumo: posição no
/// Brasileirão, último resultado e próximo jogo.
/// (O nome "TelaPalmeiras" ficou por compatibilidade — vale para qualquer time.)
class TelaPalmeiras extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaPalmeiras({super.key, required this.aoTerminar});

  @override
  State<TelaPalmeiras> createState() => _TelaPalmeirasState();
}

class _TelaPalmeirasState extends State<TelaPalmeiras> {
  final _cfg = ConfigManager();
  LinhaTabela? _linhaBrasileirao;
  Partida? _ultimo;
  Partida? _proximo;

  TimeInfo get _time => FootballService.instance.timeAtual;
  Color get _corDestaque => parseCor(_cfg.get('palmeiras', 'cor_destaque'), 0xFFC1A163);

  @override
  void initState() {
    super.initState();
    _carregarResumo();
  }

  Future<void> _carregarResumo() async {
    final svc = FootballService.instance;
    final id = _time.espnId;
    final resultados = await Future.wait([
      svc.tabela('bra.1'),
      svc.ultimosResultados(limite: 1),
      svc.proximosJogos(),
    ]);
    if (!mounted) return;
    final tabela = resultados[0] as ComIdade<List<GrupoTabela>>?;
    final ultimos = resultados[1] as ComIdade<List<Partida>>?;
    final proximos = resultados[2] as ComIdade<List<Partida>>?;
    setState(() {
      for (final g in tabela?.valor ?? const <GrupoTabela>[]) {
        for (final l in g.linhas) {
          if (l.timeId == id) _linhaBrasileirao = l;
        }
      }
      _ultimo = (ultimos?.valor.isNotEmpty ?? false) ? ultimos!.valor.first : null;
      _proximo = (proximos?.valor.isNotEmpty ?? false) ? proximos!.valor.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final time = _time;
    return TelaNoticias(
      aoTerminar: widget.aoTerminar,
      corDestaque: _corDestaque,
      tituloLeitor: 'GE — ${time.nome.toUpperCase()}',
      iconeSemImagem: Icons.sports_soccer,
      velocidadePxSeg: _cfg.getInt('palmeiras', 'duracao_scroll_px_seg', 35),
      pausaFinalSeg: _cfg.getInt('palmeiras', 'pausa_final_seg', 10),
      fundo: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          parseCor(_cfg.get('palmeiras', 'cor_gradiente_top'), 0xFF00441B),
          parseCor(_cfg.get('palmeiras', 'cor_gradiente_bottom'), 0xFF000000),
        ],
      ),
      carregar: () => NewsService.instance.buscar(
        [FonteRss('https://ge.globo.com/rss/ge/futebol/times/${time.nomeRss}/', '')],
        validade: _cfg.getIntervaloAtualizacao('palmeiras'),
        porFonte: _cfg.getInt('palmeiras', 'qtd_noticias', 8).clamp(2, 30),
      ),
      cabecalho: (context, r, manual) => _cabecalho(r, time),
    );
  }

  Widget _cabecalho(R r, TimeInfo time) {
    return Padding(
      padding: EdgeInsets.only(top: r.sp(20), bottom: r.sp(8)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EscudoTime(time: time, tamanho: r.icon(60)),
              const SizedBox(width: 14),
              Text(
                time.nome.toUpperCase(),
                style: GoogleFonts.rajdhani(
                    fontSize: r.fs(40),
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2),
              ),
            ],
          ),
          SizedBox(height: r.sp(10)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.sp(24)),
            child: Row(
              children: [
                Expanded(child: _cardBrasileirao(r)),
                SizedBox(width: r.sp(10)),
                Expanded(child: _cardUltimo(r)),
                SizedBox(width: r.sp(10)),
                Expanded(child: _cardProximo(r)),
              ],
            ),
          ),
          Container(
            width: r.dividerWidth(),
            height: 2,
            color: _corDestaque,
            margin: EdgeInsets.only(top: r.sp(12)),
          ),
        ],
      ),
    );
  }

  Widget _cardResumo(R r, String titulo, String valor, String sub, {Color? corValor}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(12), vertical: r.sp(10)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _corDestaque.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(titulo,
              style: GoogleFonts.rajdhani(
                  color: _corDestaque,
                  fontSize: r.fs(13),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5)),
          SizedBox(height: r.sp(4)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(valor,
                style: GoogleFonts.rajdhani(
                    color: corValor ?? Colors.white,
                    fontSize: r.fs(24),
                    fontWeight: FontWeight.w900)),
          ),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.rajdhani(color: Colors.white60, fontSize: r.fs(14))),
        ],
      ),
    );
  }

  Widget _cardBrasileirao(R r) {
    final l = _linhaBrasileirao;
    if (l == null) return _cardResumo(r, 'BRASILEIRÃO', '—', 'sem dados');
    return _cardResumo(r, 'BRASILEIRÃO', '${l.posicao}º lugar',
        '${l.pontos} pts • ${l.jogos} jogos');
  }

  Widget _cardUltimo(R r) {
    final p = _ultimo;
    if (p == null) return _cardResumo(r, 'ÚLTIMO JOGO', '—', '');
    final id = _time.espnId;
    final res = p.resultadoPara(id);
    final cor = switch (res) {
      'V' => Colors.greenAccent,
      'D' => Colors.redAccent,
      _ => Colors.amberAccent,
    };
    final rotulo = switch (res) { 'V' => 'Vitória', 'D' => 'Derrota', _ => 'Empate' };
    return _cardResumo(
      r,
      'ÚLTIMO JOGO',
      '${p.mandante.abreviacao} ${p.mandante.gols ?? '-'} x ${p.visitante.gols ?? '-'} ${p.visitante.abreviacao}',
      '$rotulo • ${p.competicao}',
      corValor: cor,
    );
  }

  Widget _cardProximo(R r) {
    final p = _proximo;
    if (p == null) return _cardResumo(r, 'PRÓXIMO JOGO', '—', '');
    final adv = p.adversarioDe(_time.espnId);
    final quando = p.aoVivo
        ? 'AO VIVO ${p.relogio}'
        : '${diaSemanaCurto(p.data)} ${doisDigitos(p.data.day)}/${doisDigitos(p.data.month)} • ${horaMinuto(p.data)}';
    return _cardResumo(r, 'PRÓXIMO JOGO', 'x ${adv.nome}', quando,
        corValor: p.aoVivo ? Colors.redAccent : null);
  }
}

/// Escudo do time: usa o asset local se existir, senão o PNG da ESPN
/// (que existe para todos os times), com cache.
class EscudoTime extends StatelessWidget {
  final TimeInfo time;
  final double tamanho;
  const EscudoTime({super.key, required this.time, required this.tamanho});

  @override
  Widget build(BuildContext context) {
    final rede = CachedNetworkImage(
      imageUrl: time.escudoUrl,
      width: tamanho,
      height: tamanho,
      fit: BoxFit.contain,
      errorWidget: (_, __, ___) =>
          Icon(Icons.shield_rounded, color: Colors.white54, size: tamanho * 0.8),
    );
    if (time.escudoAsset.isEmpty) return rede;
    return Image.asset(time.escudoAsset,
        width: tamanho,
        height: tamanho,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => rede);
  }
}
