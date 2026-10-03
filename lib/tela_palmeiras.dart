import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'config_manager.dart';
import 'design/tema.dart';
import 'responsive.dart';
import 'services/football_service.dart';
import 'services/news_service.dart';
import 'times.dart';
import 'util.dart';
import 'widgets/tela_noticias.dart';

/// Notícias do time do coração (ge.globo) com um resumo no topo: posição
/// no Brasileirão, último resultado e próximo jogo.
/// (O nome "TelaPalmeiras" ficou por compatibilidade — vale para qualquer time.)
class TelaPalmeiras extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaPalmeiras({super.key, required this.aoTerminar});

  @override
  State<TelaPalmeiras> createState() => _TelaPalmeirasState();
}

class _TelaPalmeirasState extends State<TelaPalmeiras> {
  final _cfg = ConfigManager();
  LinhaTabela? _linha;
  Partida? _ultimo;
  Partida? _proximo;

  TimeInfo get _time => FootballService.instance.timeAtual;
  Color get _cor => corDoTime(_time);

  @override
  void initState() {
    super.initState();
    _carregarResumo();
  }

  Future<void> _carregarResumo() async {
    final svc = FootballService.instance;
    final id = _time.espnId;
    final tabela = await svc.tabela('bra.1');
    final ultimos = await svc.ultimosResultados(limite: 1);
    final proximos = await svc.proximosJogos();
    if (!mounted) return;
    setState(() {
      for (final g in tabela?.valor ?? const <GrupoTabela>[]) {
        for (final l in g.linhas) {
          if (l.timeId == id) _linha = l;
        }
      }
      _ultimo = ultimos?.valor.firstOrNull;
      _proximo = proximos?.valor.firstOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final time = _time;
    return TelaNoticias(
      aoTerminar: widget.aoTerminar,
      icone: Icons.sports_soccer_rounded,
      titulo: time.nome,
      subtitulo: 'Notícias do ge',
      destaque: _cor,
      velocidadePxSeg: _cfg.getInt('palmeiras', 'duracao_scroll_px_seg', 35),
      pausaFinalSeg: _cfg.getInt('palmeiras', 'pausa_final_seg', 10),
      extra: _resumo(R(context)),
      carregar: () => NewsService.instance.buscar(
        [FonteRss('https://ge.globo.com/rss/ge/futebol/times/${time.nomeRss}/', '')],
        validade: _cfg.getIntervaloAtualizacao('palmeiras'),
        porFonte: _cfg.getInt('palmeiras', 'qtd_noticias', 8).clamp(2, 30),
      ),
    );
  }

  Widget _resumo(R r) {
    final t = Tipo(r);
    final id = _time.espnId;

    Widget bloco(String rotulo, String valor, String detalhe, {Color? cor}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: t.legenda()),
              SizedBox(height: r.sp(4)),
              Text(valor,
                  style: t.subtitulo(cor: cor ?? Cores.texto),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(detalhe, style: t.apoio(), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );

    final l = _linha;
    final u = _ultimo;
    final p = _proximo;
    final res = u?.resultadoPara(id);
    final corRes = switch (res) {
      'V' => Cores.positivo,
      'D' => Cores.alerta,
      'E' => Cores.aviso,
      _ => null,
    };
    final divisor = Container(
        width: 1, height: r.sp(56), color: Cores.contorno,
        margin: EdgeInsets.symmetric(horizontal: r.sp(20)));

    return Superficie(
      padding: EdgeInsets.symmetric(horizontal: r.sp(24), vertical: r.sp(16)),
      child: Row(
        children: [
          EscudoTime(time: _time, tamanho: r.sp(64)),
          SizedBox(width: r.sp(24)),
          bloco('Brasileirão', l == null ? '—' : '${l.posicao}º lugar',
              l == null ? 'Sem dados agora' : '${l.pontos} pontos em ${l.jogos} jogos'),
          divisor,
          bloco(
            'Último jogo',
            u == null
                ? '—'
                : '${u.mandante.abreviacao} ${u.mandante.gols ?? '-'} x ${u.visitante.gols ?? '-'} ${u.visitante.abreviacao}',
            u == null
                ? ''
                : '${switch (res) { 'V' => 'Vitória', 'D' => 'Derrota', _ => 'Empate' }}, ${u.competicao}',
            cor: corRes,
          ),
          divisor,
          bloco(
            'Próximo jogo',
            p == null ? '—' : '${p.mandanteEh(id) ? 'x' : '@'} ${p.adversarioDe(id).nome}',
            p == null
                ? ''
                : p.aoVivo
                    ? 'Ao vivo agora, ${p.relogio}'
                    : '${diaSemanaLongo(p.data)}, ${p.data.day}/${p.data.month} às ${horaMinuto(p.data)}',
            cor: p?.aoVivo == true ? Cores.alerta : null,
          ),
        ],
      ),
    );
  }
}

/// Escudo do time: asset local se existir, senão o PNG da ESPN (com cache).
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
          Icon(Icons.shield_rounded, color: Cores.textoApagado, size: tamanho * 0.8),
    );
    if (time.escudoAsset.isEmpty) return rede;
    return Image.asset(time.escudoAsset,
        width: tamanho,
        height: tamanho,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => rede);
  }
}
