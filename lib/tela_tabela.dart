import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'design/icones.dart';
import 'design/tema.dart';
import 'responsive.dart';
import 'services/football_service.dart';
import 'services/tv_service.dart';
import 'tela_palmeiras.dart' show EscudoTime;
import 'times.dart';
import 'util.dart';

/// Próxima partida do time — e, no dia do jogo, o centro das atenções:
/// contagem regressiva, escalação, placar ao vivo e onde assistir.
class TelaTabela extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaTabela({super.key, required this.aoTerminar});

  @override
  State<TelaTabela> createState() => _TelaTabelaState();
}

class _TelaTabelaState extends State<TelaTabela> {
  final _cfg = ConfigManager();

  bool _carregando = true;
  List<Partida> _proximos = [];
  List<Partida> _ultimos = [];
  List<Escalacao> _escalacao = [];
  DateTime? _atualizadoEm;
  JogoNaTv? _tv;
  bool _buscouTv = false;
  Timer? _saidaTimer;
  Timer? _atualizarTimer;

  TimeInfo get _time => FootballService.instance.timeAtual;
  Color get _cor => Destaques.partida;
  Partida? get _jogo => _proximos.firstOrNull;

  /// Jogo começa em até 2h ou já está rolando.
  bool get _diaDeJogo {
    final j = _jogo;
    if (j == null) return false;
    return j.aoVivo || j.data.difference(DateTime.now()).inMinutes <= 120;
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _saidaTimer?.cancel();
    _atualizarTimer?.cancel();
    super.dispose();
  }

  Future<void> _carregar({bool forcar = false}) async {
    final svc = FootballService.instance;
    final prox = await svc.proximosJogos(forcar: forcar);
    final ult = await svc.ultimosResultados(limite: 5);
    if (!mounted) return;
    setState(() {
      _proximos = prox?.valor ?? [];
      _ultimos = ult?.valor ?? [];
      _atualizadoEm = prox?.atualizadoEm;
      _carregando = false;
    });

    final jogo = _jogo;
    if (jogo != null) {
      if (!_buscouTv) _buscarCanais(jogo);
      if (_diaDeJogo) {
        final esc = await svc.escalacao(jogo.id);
        if (mounted) setState(() => _escalacao = esc);
      }
    }

    // No dia do jogo a tela fica mais tempo e o placar se atualiza.
    _saidaTimer ??= Timer(
        Duration(
            seconds: _diaDeJogo
                ? 60
                : _cfg.getInt('proxima_partida', 'duracao_seg', 20).clamp(5, 120)),
        () {
      if (mounted) widget.aoTerminar();
    });
    if (jogo != null && jogo.aoVivo) {
      _atualizarTimer ??= Timer.periodic(
          const Duration(seconds: 30), (_) => _carregar(forcar: true));
    }
  }

  Future<void> _buscarCanais(Partida jogo) async {
    _buscouTv = true;
    if (!_cfg.getBool('proxima_partida', 'mostrar_canais', true)) return;
    final adv = jogo.adversarioDe(_time.espnId);
    final advInfo =
        timesDisponiveis.values.where((t) => t.espnId == adv.id).firstOrNull;
    final tv = await TvService.instance.buscarJogo(
      data: jogo.data,
      nomesTime: _time.todosOsNomes,
      nomesAdversario: [adv.nome, ...?advInfo?.todosOsNomes],
    );
    if (mounted && tv != null) setState(() => _tv = tv);
  }

  @override
  Widget build(BuildContext context) {
    final jogo = _jogo;
    return EstruturaTela(
      icone: jogo?.aoVivo == true ? Icons.sensors_rounded : Icons.stadium_rounded,
      marca: EscudoTime(time: _time, tamanho: R(context).sp(56)),
      titulo: jogo == null
          ? 'Próxima partida'
          : jogo.aoVivo
              ? 'Ao vivo'
              : jogo.encerrada
                  ? 'Fim de jogo'
                  : 'Próxima partida',
      subtitulo: jogo?.competicao,
      destaque: jogo?.aoVivo == true ? Cores.alerta : _cor,
      rodapeDireita:
          _atualizadoEm != null ? 'Atualizado ${descreverIdade(_atualizadoEm!)}' : null,
      child: _carregando
          ? Carregando(cor: _cor)
          : jogo == null
              ? const AvisoTela(
                  icone: Icons.event_busy_rounded,
                  titulo: 'Nenhum jogo encontrado',
                  texto: 'Sem jogo agendado ou sem conexão no momento.',
                )
              : _buildJogo(R(context), jogo),
    );
  }

  Widget _buildJogo(R r, Partida jogo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: _confronto(r, jogo)),
        SizedBox(height: r.sp(16)),
        _faixaInformacoes(r, jogo),
        SizedBox(height: r.sp(16)),
        Expanded(
          flex: 3,
          child: _escalacao.isNotEmpty ? _blocoEscalacao(r) : _blocoForma(r),
        ),
      ],
    );
  }

  // ── Confronto: escudos e o número principal (hora ou placar) ─────────────
  Widget _confronto(R r, Partida jogo) {
    final t = Tipo(r);
    final logo = LogoCompeticao(
        slug: jogo.ligaSlug, logoId: jogo.ligaLogoId, tamanho: r.sp(84));
    final Widget centro;
    if (jogo.aoVivo || jogo.encerrada) {
      centro = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          logo,
          SizedBox(height: r.sp(10)),
          Text('${jogo.mandante.gols ?? 0} – ${jogo.visitante.gols ?? 0}', style: t.heroi()),
          SizedBox(height: r.sp(8)),
          Selo(jogo.aoVivo ? 'Ao vivo, ${jogo.relogio}' : 'Encerrado',
              cor: jogo.aoVivo ? Cores.alerta : Cores.textoSecundario,
              icone: jogo.aoVivo ? Icons.circle : null),
        ],
      );
    } else {
      final minutos = jogo.data.difference(DateTime.now()).inMinutes;
      final quando = minutos <= 120 && minutos > 0
          ? 'Começa em ${minutos >= 60 ? '${minutos ~/ 60}h${doisDigitos(minutos % 60)}' : '$minutos min'}'
          : _quandoPorExtenso(jogo.data);
      centro = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          logo,
          SizedBox(height: r.sp(10)),
          Text(horaMinuto(jogo.data), style: t.heroi()),
          SizedBox(height: r.sp(4)),
          Text(quando, style: t.subtitulo(cor: _cor)),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: _escudoENome(r, jogo.mandante)),
        Expanded(flex: 2, child: FittedBox(fit: BoxFit.scaleDown, child: centro)),
        Expanded(child: _escudoENome(r, jogo.visitante)),
      ],
    );
  }

  String _quandoPorExtenso(DateTime d) {
    final e = etiquetaDias(d);
    if (e == 'HOJE') return 'Hoje';
    if (e == 'AMANHÃ') return 'Amanhã';
    return '${diaSemanaLongo(d)}, ${d.day} de ${mesesLongos[d.month - 1]}';
  }

  Widget _escudoENome(R r, TimePartida tp) {
    final t = Tipo(r);
    final nosso = tp.id == _time.espnId;
    final tamanho = r.sp(r.isCompact ? 96 : 132);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: tamanho,
          height: tamanho,
          child: tp.escudo.isEmpty
              ? Icon(Icons.shield_rounded, color: Cores.textoApagado, size: tamanho * 0.7)
              : CachedNetworkImage(
                  imageUrl: tp.escudo,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) =>
                      Icon(Icons.shield_rounded, color: Cores.textoApagado, size: tamanho * 0.7),
                ),
        ),
        SizedBox(height: r.sp(12)),
        Text(tp.nome,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.subtitulo(cor: nosso ? corDoTime(_time) : Cores.texto)),
      ],
    );
  }

  // ── Data, estádio e onde assistir ────────────────────────────────────────
  Widget _faixaInformacoes(R r, Partida jogo) {
    final t = Tipo(r);
    final d = jogo.data;
    final local = [jogo.estadio, jogo.cidade].where((s) => s.isNotEmpty).join(', ');
    final canais = (_tv?.canais ?? const <String>[]).map(nomeDoCanal).toList();
    final mostrarCanais = _cfg.getBool('proxima_partida', 'mostrar_canais', true);

    Widget item(IconData icone, String rotulo, String valor, {Color? cor}) => Expanded(
          child: Row(
            children: [
              Icon(icone, color: cor ?? _cor, size: r.icon(28)),
              SizedBox(width: r.sp(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rotulo, style: t.legenda()),
                    Text(valor,
                        style: t.corpo(peso: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        );

    return Superficie(
      padding: EdgeInsets.symmetric(horizontal: r.sp(24), vertical: r.sp(16)),
      child: Row(
        children: [
          item(Icons.event_rounded, 'Quando',
              '${diaSemanaLongo(d)}, ${d.day}/${d.month} às ${horaMinuto(d)}'),
          item(Icons.place_rounded, 'Onde', local.isEmpty ? 'A confirmar' : local),
          if (mostrarCanais)
            item(
              Icons.live_tv_rounded,
              'Onde assistir',
              canais.isNotEmpty
                  ? canais.join(', ')
                  : 'A confirmar',
              cor: canais.isNotEmpty ? Cores.aviso : null,
            ),
        ],
      ),
    );
  }

  // ── Escalação (dia de jogo) ──────────────────────────────────────────────
  Widget _blocoEscalacao(R r) {
    final t = Tipo(r);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in _escalacao.take(2)) ...[
          Expanded(
            child: Superficie(
              padding: EdgeInsets.all(r.sp(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      e.formacao.isEmpty ? 'Escalação do ${e.time}' : 'Escalação do ${e.time} (${e.formacao})',
                      style: t.corpo(
                          cor: e.timeId == _time.espnId ? corDoTime(_time) : Cores.texto,
                          peso: FontWeight.w700)),
                  SizedBox(height: r.sp(8)),
                  Expanded(
                    child: Wrap(
                      spacing: r.sp(16),
                      runSpacing: r.sp(4),
                      children: [
                        for (final j in e.titulares)
                          Text('${j.camisa}  ${j.nome}', style: t.apoio()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (e != _escalacao.take(2).last) SizedBox(width: r.sp(16)),
        ],
      ],
    );
  }

  // ── Forma recente e próximos jogos ───────────────────────────────────────
  Widget _blocoForma(R r) {
    final t = Tipo(r);
    final id = _time.espnId;
    final seguintes = _proximos.skip(1).take(3).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Últimos jogos', style: t.legenda()),
              SizedBox(height: r.sp(10)),
              for (final p in _ultimos.take(3))
                Padding(
                  padding: EdgeInsets.only(bottom: r.sp(6)),
                  child: Row(children: [
                    _bolinha(r, p.resultadoPara(id) ?? '-'),
                    SizedBox(width: r.sp(12)),
                    Expanded(
                      child: Text(
                        '${p.mandante.nome} ${p.mandante.gols} x ${p.visitante.gols} ${p.visitante.nome}',
                        style: t.apoio(cor: Cores.texto),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        SizedBox(width: r.sp(32)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Próximas partidas', style: t.legenda()),
              SizedBox(height: r.sp(10)),
              for (final p in seguintes)
                Padding(
                  padding: EdgeInsets.only(bottom: r.sp(6)),
                  child: Text(
                    '${p.data.day}/${p.data.month}  ${p.mandante.nome} x ${p.visitante.nome}, ${p.competicao}',
                    style: t.apoio(cor: Cores.texto),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bolinha(R r, String res) {
    final cor = switch (res) {
      'V' => Cores.positivo,
      'D' => Cores.alerta,
      'E' => Cores.aviso,
      _ => Cores.textoApagado,
    };
    return Container(
      width: r.sp(28),
      height: r.sp(28),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
      child: Text(res,
          style: Tipo(r).legenda(cor: Colors.black).copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

/// O site escreve os canais em maiúsculas ("GLOBO", "PREMIERE 2"); na tela
/// fica mais fácil de ler com a grafia de cada marca.
String nomeDoCanal(String s) {
  const marcas = {
    'sportv': 'SporTV',
    'ge tv': 'ge TV',
    'cazetv': 'CazéTV',
    'espn': 'ESPN',
    'tnt': 'TNT',
    'hbo max': 'HBO Max',
    'max': 'Max',
    'record': 'Record',
    'sbt': 'SBT',
    'band': 'Band',
    'paramount+': 'Paramount+',
    'disney+': 'Disney+',
    'amazon prime video': 'Prime Video',
    'prime video': 'Prime Video',
  };
  final baixo = s.trim().toLowerCase();
  for (final e in marcas.entries) {
    if (baixo == e.key) return e.value;
    if (baixo.startsWith('${e.key} ')) return '${e.value}${s.trim().substring(e.key.length)}';
  }
  return baixo
      .split(' ')
      .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}
