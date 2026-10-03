import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'performance_manager.dart';
import 'responsive.dart';
import 'services/football_service.dart';
import 'services/tv_service.dart';
import 'tela_palmeiras.dart' show EscudoTime;
import 'times.dart';
import 'util.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Fundo animado — linhas de campo + partículas. O painter recebe a animação
//  em `repaint:`; só ele é redesenhado a cada quadro, o resto da tela não.
// ─────────────────────────────────────────────────────────────────────────────
class _CampoPainter extends CustomPainter {
  final Animation<double> anim;
  final Color cor1;
  final Color cor2;

  _CampoPainter(this.anim, this.cor1, this.cor2) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size s) {
    final t = anim.value;
    final rect = Offset.zero & s;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cor1.withValues(alpha: 0.95), Color.lerp(cor1, Colors.black, 0.65)!],
          ).createShader(rect));

    final linha = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final c = Offset(s.width * 0.5, s.height * 0.42);
    final pulso = 1.0 + math.sin(t * math.pi * 2) * 0.03;
    for (int i = 1; i <= 4; i++) {
      linha.color = cor2.withValues(alpha: 0.04 + (4 - i) * 0.02);
      canvas.drawCircle(c, s.width * 0.12 * i * pulso, linha);
    }
    linha
      ..strokeWidth = 0.8
      ..color = cor2.withValues(alpha: 0.07);
    for (int i = 0; i < 5; i++) {
      final y = s.height * 0.1 + s.height * 0.8 * i / 4;
      canvas.drawLine(Offset(s.width * 0.05, y), Offset(s.width * 0.95, y), linha);
    }
    final rng = math.Random(42);
    final p = Paint();
    for (int i = 0; i < 18; i++) {
      final bx = rng.nextDouble() * s.width;
      final by = rng.nextDouble() * s.height;
      final off = math.sin(t * math.pi * 2 + i * 0.7) * 6;
      final sz = rng.nextDouble() * 2.5 + 0.5;
      p.color = cor2.withValues(alpha: 0.12 + rng.nextDouble() * 0.08);
      canvas.drawCircle(Offset(bx, by + off), sz, p);
    }
  }

  @override
  bool shouldRepaint(_CampoPainter old) =>
      old.cor1 != cor1 || old.cor2 != cor2 || old.anim != anim;
}

class TelaTabela extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaTabela({super.key, required this.aoTerminar});

  @override
  State<TelaTabela> createState() => _TelaTabelaState();
}

class _TelaTabelaState extends State<TelaTabela>
    with SingleTickerProviderStateMixin {
  final _cfg = ConfigManager();
  late final AnimationController _bgCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  bool _carregando = true;
  List<Partida> _proximos = [];
  List<Partida> _ultimos = [];
  DateTime? _atualizadoEm;
  JogoNaTv? _tv;
  bool _buscandoTv = false;
  Timer? _saidaTimer;
  Timer? _aoVivoTimer;

  TimeInfo get _time => FootballService.instance.timeAtual;
  Color get _corPrimaria => parseCor(_time.corTop, 0xFF006B2E);
  Color get _corAcento => parseCor(_time.corDestaque, 0xFFC1A163);

  @override
  void initState() {
    super.initState();
    if (PerformanceManager.instance.animacoesDecorativasAtivas) {
      _bgCtrl.repeat(reverse: true);
    }
    _carregar();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _saidaTimer?.cancel();
    _aoVivoTimer?.cancel();
    super.dispose();
  }

  Future<void> _carregar({bool forcar = false}) async {
    final svc = FootballService.instance;
    final r = await Future.wait([
      svc.proximosJogos(forcar: forcar),
      svc.ultimosResultados(limite: 5),
    ]);
    if (!mounted) return;
    final prox = r[0];
    final ult = r[1];
    setState(() {
      _proximos = prox?.valor ?? [];
      _ultimos = ult?.valor ?? [];
      _atualizadoEm = prox?.atualizadoEm;
      _carregando = false;
    });
    _buscarCanais();

    final jogo = _jogo;
    if (_saidaTimer == null) {
      // Jogo rolando: fica mais tempo na tela e atualiza o placar.
      final seg = jogo != null && jogo.aoVivo
          ? 60
          : _cfg.getInt('proxima_partida', 'duracao_seg', 20).clamp(5, 120);
      _saidaTimer = Timer(Duration(seconds: seg), () {
        if (mounted) widget.aoTerminar();
      });
    }
    if (jogo != null && jogo.aoVivo && _aoVivoTimer == null) {
      _aoVivoTimer = Timer.periodic(
          const Duration(seconds: 30), (_) => _carregar(forcar: true));
    }
  }

  Future<void> _buscarCanais() async {
    final jogo = _jogo;
    if (jogo == null || _tv != null || _buscandoTv) return;
    if (!_cfg.getBool('proxima_partida', 'mostrar_canais', true)) return;
    _buscandoTv = true;
    final adv = jogo.adversarioDe(_time.espnId);
    final advInfo = timesDisponiveis.values
        .where((t) => t.espnId == adv.id)
        .firstOrNull;
    final tv = await TvService.instance.buscarJogo(
      data: jogo.data,
      nomesTime: _time.todosOsNomes,
      nomesAdversario: [adv.nome, ...?advInfo?.todosOsNomes],
    );
    _buscandoTv = false;
    if (mounted && tv != null) setState(() => _tv = tv);
  }

  Partida? get _jogo => _proximos.isNotEmpty ? _proximos.first : null;

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _CampoPainter(_bgCtrl, _corPrimaria, _corAcento),
            ),
          ),
          SafeArea(
            child: _carregando
                ? _buildCarregando(r)
                : _jogo == null
                    ? _buildVazio(r)
                    : _buildJogo(r, _jogo!),
          ),
        ],
      ),
    );
  }

  Widget _buildCarregando(R r) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _corAcento, strokeWidth: 2),
            SizedBox(height: r.sp(16)),
            Text('Buscando próximo jogo...',
                style: GoogleFonts.rajdhani(color: Colors.white54, fontSize: r.fs(18))),
          ],
        ),
      );

  Widget _buildVazio(R r) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_soccer, color: _corAcento.withValues(alpha: 0.4), size: r.icon(60)),
            SizedBox(height: r.sp(16)),
            Text('Nenhum jogo agendado — ou sem conexão no momento',
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                    color: Colors.white54, fontSize: r.fs(20), fontWeight: FontWeight.w600)),
            if (_ultimos.isNotEmpty) ...[
              SizedBox(height: r.sp(24)),
              _buildForma(r),
            ],
          ],
        ),
      );

  Widget _buildJogo(R r, Partida jogo) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.sp(24), r.sp(14), r.sp(24), r.sp(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTitulo(r, jogo),
          SizedBox(height: r.sp(12)),
          Expanded(child: _buildConfronto(r, jogo)),
          SizedBox(height: r.sp(12)),
          _buildInfoGrid(r, jogo),
          SizedBox(height: r.sp(10)),
          Row(
            children: [
              Expanded(child: _buildForma(r)),
              if (_proximos.length > 1) ...[
                SizedBox(width: r.sp(12)),
                Expanded(child: _buildDepois(r)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTitulo(R r, Partida jogo) {
    final aoVivo = jogo.aoVivo;
    return Row(
      children: [
        EscudoTime(time: _time, tamanho: r.sp(56)),
        SizedBox(width: r.sp(14)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(aoVivo ? 'AO VIVO' : 'PRÓXIMA PARTIDA',
                  style: GoogleFonts.rajdhani(
                    color: aoVivo ? Colors.redAccent : Colors.white,
                    fontSize: r.fs(r.isCompact ? 22 : 30),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  )),
              Text(
                _atualizadoEm != null
                    ? '${_time.nome.toUpperCase()} • atualizado ${descreverIdade(_atualizadoEm!)}'
                    : _time.nome.toUpperCase(),
                style: GoogleFonts.poppins(
                  color: _corAcento,
                  fontSize: r.fs(r.isCompact ? 11 : 13),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        _selo(r, jogo.competicao),
      ],
    );
  }

  Widget _selo(R r, String texto, {Color? cor}) {
    final c = cor ?? _corAcento;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(14), vertical: r.sp(7)),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Text(texto,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.rajdhani(
              color: c, fontSize: r.fs(15), fontWeight: FontWeight.w700, letterSpacing: 1)),
    );
  }

  Widget _buildConfronto(R r, Partida jogo) {
    final meio = jogo.aoVivo || jogo.encerrada
        ? _placar(r, jogo)
        : _vs(r, jogo);
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(r.radius(22)),
        border: Border.all(color: _corAcento.withValues(alpha: 0.20), width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(child: _timeCard(r, jogo.mandante, 'MANDANTE')),
          meio,
          Expanded(child: _timeCard(r, jogo.visitante, 'VISITANTE')),
        ],
      ),
    );
  }

  Widget _timeCard(R r, TimePartida t, String papel) {
    final nosso = t.id == _time.espnId;
    final tamanho = r.sp(r.isCompact ? 90 : 120);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: tamanho,
          height: tamanho,
          child: t.escudo.isEmpty
              ? Icon(Icons.shield_rounded, color: _corAcento, size: tamanho * 0.7)
              : CachedNetworkImage(
                  imageUrl: t.escudo,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) =>
                      Icon(Icons.shield_rounded, color: _corAcento, size: tamanho * 0.7),
                ),
        ),
        SizedBox(height: r.sp(12)),
        Text(t.nome,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.rajdhani(
              color: nosso ? _corAcento : Colors.white,
              fontSize: r.fs(r.isCompact ? 26 : 34),
              fontWeight: FontWeight.w800,
            )),
        SizedBox(height: r.sp(4)),
        Text(papel,
            style: GoogleFonts.poppins(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: r.fs(13),
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            )),
      ],
    );
  }

  Widget _vs(R r, Partida jogo) {
    final etiqueta = etiquetaDias(jogo.data);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.sp(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('VS',
              style: GoogleFonts.orbitron(
                color: _corAcento,
                fontSize: r.fs(r.isCompact ? 32 : 46),
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                shadows: [Shadow(color: _corAcento.withValues(alpha: 0.6), blurRadius: 26)],
              )),
          SizedBox(height: r.sp(10)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: r.sp(14), vertical: r.sp(6)),
            decoration: BoxDecoration(
              color: _corAcento.withValues(alpha: etiqueta == 'HOJE' ? 0.35 : 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(etiqueta,
                style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: r.fs(r.isCompact ? 14 : 18),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
          ),
        ],
      ),
    );
  }

  Widget _placar(R r, Partida jogo) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.sp(10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${jogo.mandante.gols ?? 0}  x  ${jogo.visitante.gols ?? 0}',
              style: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: r.fs(r.isCompact ? 40 : 58),
                fontWeight: FontWeight.w900,
              )),
          SizedBox(height: r.sp(8)),
          _selo(r, jogo.aoVivo ? '🔴 ${jogo.relogio}' : 'Encerrado',
              cor: jogo.aoVivo ? Colors.redAccent : Colors.white70),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(R r, Partida jogo) {
    final d = jogo.data;
    final local = [jogo.estadio, jogo.cidade].where((s) => s.isNotEmpty).join(' • ');
    final canais = _tv?.canais ?? const <String>[];
    final hojeOuAmanha = soData(d).difference(soData(DateTime.now())).inDays <= 1;
    final textoCanais = canais.isNotEmpty
        ? canais.join(' • ')
        : (hojeOuAmanha ? 'Não informado' : 'Divulgado na véspera');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
              child: _infoCell(r, Icons.calendar_today_rounded,
                  '${diaSemanaLongo(d)}, ${d.day} ${mesesCurtos[d.month - 1]}', 'DATA')),
          SizedBox(width: r.sp(10)),
          Expanded(
              child: _infoCell(r, Icons.access_time_rounded, horaMinuto(d), 'HORÁRIO')),
          SizedBox(width: r.sp(10)),
          Expanded(
              flex: 2,
              child: _infoCell(r, Icons.stadium_rounded,
                  local.isEmpty ? 'A confirmar' : local, 'ESTÁDIO')),
          if (_cfg.getBool('proxima_partida', 'mostrar_canais', true)) ...[
            SizedBox(width: r.sp(10)),
            Expanded(
                flex: 2,
                child: _infoCell(r, Icons.live_tv_rounded, textoCanais, 'ONDE ASSISTIR',
                    destaque: canais.isNotEmpty)),
          ],
        ],
      ),
    );
  }

  Widget _infoCell(R r, IconData icon, String valor, String label,
      {bool destaque = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(12), vertical: r.sp(12)),
      decoration: BoxDecoration(
        color: destaque
            ? _corAcento.withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(r.radius(16)),
        border: Border.all(
            color: _corAcento.withValues(alpha: destaque ? 0.7 : 0.28), width: 1.2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _corAcento, size: r.icon(r.isCompact ? 24 : 28)),
          SizedBox(height: r.sp(6)),
          Text(valor,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.rajdhani(
                color: Colors.white,
                fontSize: r.fs(r.isCompact ? 16 : 20),
                fontWeight: FontWeight.w800,
                height: 1.15,
              )),
          SizedBox(height: r.sp(4)),
          Text(label,
              style: GoogleFonts.poppins(
                color: _corAcento,
                fontSize: r.fs(11),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              )),
        ],
      ),
    );
  }

  /// Últimos resultados como bolinhas V/E/D (mais antigo → mais recente).
  Widget _buildForma(R r) {
    final id = _time.espnId;
    final lista = _ultimos.reversed.toList();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(14), vertical: r.sp(10)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(r.radius(14)),
      ),
      child: Row(
        children: [
          Text('ÚLTIMOS',
              style: GoogleFonts.rajdhani(
                  color: Colors.white60,
                  fontSize: r.fs(14),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
          SizedBox(width: r.sp(10)),
          for (final p in lista)
            Padding(
              padding: EdgeInsets.only(right: r.sp(6)),
              child: Tooltip(
                message:
                    '${p.mandante.nome} ${p.mandante.gols} x ${p.visitante.gols} ${p.visitante.nome}',
                child: _bolinha(r, p.resultadoPara(id) ?? '-'),
              ),
            ),
          if (lista.isNotEmpty) ...[
            SizedBox(width: r.sp(6)),
            Flexible(
              child: Text(
                '${_ultimos.first.mandante.abreviacao} ${_ultimos.first.mandante.gols} x '
                '${_ultimos.first.visitante.gols} ${_ultimos.first.visitante.abreviacao}',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: r.fs(15)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bolinha(R r, String res) {
    final cor = switch (res) {
      'V' => Colors.green,
      'D' => Colors.red,
      'E' => Colors.amber.shade700,
      _ => Colors.grey,
    };
    return Container(
      width: r.sp(26),
      height: r.sp(26),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
      child: Text(res,
          style: GoogleFonts.rajdhani(
              color: Colors.white, fontSize: r.fs(14), fontWeight: FontWeight.w800)),
    );
  }

  /// Os jogos seguintes ao próximo.
  Widget _buildDepois(R r) {
    final id = _time.espnId;
    final seguintes = _proximos.skip(1).take(2).toList();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(14), vertical: r.sp(10)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(r.radius(14)),
      ),
      child: Row(
        children: [
          Text('DEPOIS',
              style: GoogleFonts.rajdhani(
                  color: Colors.white60,
                  fontSize: r.fs(14),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
          SizedBox(width: r.sp(10)),
          Expanded(
            child: Text(
              seguintes
                  .map((p) =>
                      '${doisDigitos(p.data.day)}/${doisDigitos(p.data.month)} ${p.mandanteEh(id) ? 'x' : '@'} ${p.adversarioDe(id).nome}')
                  .join('   •   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: r.fs(15)),
            ),
          ),
        ],
      ),
    );
  }
}
