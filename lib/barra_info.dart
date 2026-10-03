import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config_manager.dart';
import 'info_hub.dart';
import 'performance_manager.dart';
import 'responsive.dart';
import 'services/weather_service.dart';
import 'tela_spotify.dart' show SpotifyManager;
import 'update_banner.dart';
import 'update_manager.dart';
import 'util.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Paleta por tela
// ─────────────────────────────────────────────────────────────────────────────
class _TelaTheme {
  final Color acento;
  final Color fundo;
  final IconData icone;
  const _TelaTheme(this.acento, this.fundo, this.icone);
}

const Map<String, _TelaTheme> _temas = {
  'bom_dia': _TelaTheme(Color(0xFFFFD700), Color(0xFF1a1200), Icons.wb_sunny_rounded),
  'clima': _TelaTheme(Color(0xFF18FFFF), Color(0xFF001a2e), Icons.cloud_rounded),
  'palmeiras': _TelaTheme(Color(0xFFC1A163), Color(0xFF001a0a), Icons.sports_soccer_rounded),
  'proxima_partida': _TelaTheme(Color(0xFF69F0AE), Color(0xFF001a0a), Icons.emoji_events_rounded),
  'classificacao': _TelaTheme(Color(0xFF00C853), Color(0xFF001a0a), Icons.leaderboard_rounded),
  'calendario': _TelaTheme(Color(0xFF40C4FF), Color(0xFF001020), Icons.calendar_month_rounded),
  'compras': _TelaTheme(Color(0xFF00E676), Color(0xFF001a0a), Icons.shopping_cart_rounded),
  'brasil': _TelaTheme(Color(0xFFFFDF00), Color(0xFF060910), Icons.public_rounded),
  'regiao': _TelaTheme(Color(0xFF00BCD4), Color(0xFF0a0a2e), Icons.location_city_rounded),
  'fotos': _TelaTheme(Color(0xFFE040FB), Color(0xFF1a0020), Icons.photo_library_rounded),
  'spotify': _TelaTheme(Color(0xFF1DB954), Color(0xFF0a1a0a), Icons.music_note_rounded),
};

const _temaDefault =
    _TelaTheme(Color(0xFF18FFFF), Color(0xFF001a2e), Icons.dashboard_rounded);

// ─────────────────────────────────────────────────────────────────────────────
//  Aurora — desenhada num RepaintBoundary próprio. O painter recebe a
//  animação como `repaint:`, então a cada quadro só ele é repintado; nenhum
//  widget é reconstruído (antes a barra inteira era refeita 60x/s).
// ─────────────────────────────────────────────────────────────────────────────
class _AuroraBarraPainter extends CustomPainter {
  final Animation<double> anim;
  final Color cor1, cor2, cor3;

  _AuroraBarraPainter(this.anim, this.cor1, this.cor2, this.cor3)
      : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size s) {
    final t = anim.value;
    final p = Paint()..style = PaintingStyle.fill;
    _onda(canvas, s, p, cor1, 0.18,
        s.height * (0.1 + math.sin(t * math.pi) * 0.08), s.height * 0.55, 0.7, t * math.pi);
    _onda(canvas, s, p, cor2, 0.13,
        s.height * (0.2 + math.cos(t * math.pi * 0.7) * 0.06), s.height * 0.45, 0.5,
        t * math.pi * 1.3 + 1.0);
    _onda(canvas, s, p, cor3, 0.10,
        s.height * (0.35 + math.sin(t * math.pi * 1.2) * 0.07), s.height * 0.50, 0.4,
        t * math.pi * 0.9 + 2.1);
  }

  void _onda(Canvas c, Size s, Paint p, Color cor, double op, double yOffset,
      double amp, double freq, double phase) {
    final path = Path()..moveTo(0, s.height);
    // Passo de 8px: a onda é suave o bastante e o custo cai pela metade.
    for (double x = 0; x <= s.width + 8; x += 8) {
      path.lineTo(x,
          yOffset + amp * math.sin(freq * (x / s.width) * 2 * math.pi + phase));
    }
    path.lineTo(s.width, s.height);
    path.close();
    p.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [cor.withValues(alpha: op), cor.withValues(alpha: op * 0.15)],
    ).createShader(Rect.fromLTWH(0, yOffset - amp, s.width, amp * 2 + s.height));
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_AuroraBarraPainter old) =>
      old.cor1 != cor1 || old.cor2 != cor2 || old.cor3 != cor3 || old.anim != anim;
}

// ─────────────────────────────────────────────────────────────────────────────
//  BarraInfo
// ─────────────────────────────────────────────────────────────────────────────
class BarraInfo extends StatefulWidget {
  final bool modoManual;
  final String telaAtual;
  final VoidCallback? aoAbrirConfig;

  const BarraInfo({
    super.key,
    this.modoManual = false,
    this.telaAtual = 'clima',
    this.aoAbrirConfig,
  });

  static double alturaTotal(BuildContext context) {
    final sh = MediaQuery.of(context).size.height;
    return (sh * 0.14).clamp(100.0, 160.0);
  }

  @override
  State<BarraInfo> createState() => _BarraInfoState();
}

class _BarraInfoState extends State<BarraInfo> with TickerProviderStateMixin {
  late final AnimationController _temaCtrl;
  late final AnimationController _auroraCtrl;
  late final AnimationController _gearCtrl;
  late Animation<Color?> _acentoAnim;
  late Animation<Color?> _fundoAnim;

  _TelaTheme _anterior = _temaDefault;
  _TelaTheme _atual = _temaDefault;

  final _cfg = ConfigManager();
  bool get _auroraAtiva =>
      _cfg.getBool('barra_info', 'aurora_ativa', true) &&
      !PerformanceManager.instance.modoEconomico;

  @override
  void initState() {
    super.initState();
    _atual = _temas[widget.telaAtual] ?? _temaDefault;
    _anterior = _atual;

    _temaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _auroraCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 8));
    _gearCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _criarTweens();
    _atualizarAurora();
    PerformanceManager.instance.addListener(_atualizarAurora);
  }

  void _atualizarAurora() {
    if (_auroraAtiva) {
      if (!_auroraCtrl.isAnimating) _auroraCtrl.repeat(reverse: true);
    } else {
      _auroraCtrl.stop();
    }
    if (mounted) setState(() {});
  }

  void _criarTweens() {
    final curva = CurvedAnimation(parent: _temaCtrl, curve: Curves.easeInOut);
    _acentoAnim = ColorTween(begin: _anterior.acento, end: _atual.acento).animate(curva);
    _fundoAnim = ColorTween(begin: _anterior.fundo, end: _atual.fundo).animate(curva);
  }

  @override
  void didUpdateWidget(BarraInfo old) {
    super.didUpdateWidget(old);
    if (old.telaAtual != widget.telaAtual) {
      _anterior = _temas[old.telaAtual] ?? _temaDefault;
      _atual = _temas[widget.telaAtual] ?? _temaDefault;
      _criarTweens();
      _temaCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    PerformanceManager.instance.removeListener(_atualizarAurora);
    _temaCtrl.dispose();
    _auroraCtrl.dispose();
    _gearCtrl.dispose();
    super.dispose();
  }

  void _tocarEngrenagem() {
    _gearCtrl.forward(from: 0).then((_) {
      if (mounted) widget.aoAbrirConfig?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final alturaTotal = BarraInfo.alturaTotal(context);
    final alturaTicker = (alturaTotal * 0.28).clamp(32.0, 50.0);
    final alturaLinha = alturaTotal - alturaTicker;

    // Só este builder depende da animação de troca de tema (700ms ao trocar
    // de tela). Relógio, clima e ticker têm seus próprios builders.
    return AnimatedBuilder(
      animation: _temaCtrl,
      builder: (context, _) {
        final acento = _acentoAnim.value ?? _atual.acento;
        final fundo = _fundoAnim.value ?? _atual.fundo;
        return SizedBox(
          height: alturaTotal,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(Colors.black, fundo, 0.65)!
                              .withValues(alpha: 0.95),
                          Colors.black.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_auroraAtiva)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: alturaLinha,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _AuroraBarraPainter(
                          _auroraCtrl,
                          acento,
                          _anterior.acento == acento
                              ? acento.withValues(alpha: 0.6)
                              : _anterior.acento,
                          fundo,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: alturaLinha,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: r.sp(20)),
                    child: Row(
                      children: [
                        _BlocoRelogio(acento: acento, altura: alturaLinha),
                        ListenableBuilder(
                          listenable: UpdateManager.instance,
                          builder: (context, _) => UpdateManager.instance.disponivel
                              ? Padding(
                                  padding: EdgeInsets.only(left: r.sp(10)),
                                  child: _botaoAtualizacao(r),
                                )
                              : const SizedBox.shrink(),
                        ),
                        _divisor(r, acento),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: InfoHub.instance,
                            builder: (context, _) =>
                                _blocoClima(InfoHub.instance, r, acento, alturaLinha),
                          ),
                        ),
                        _divisor(r, acento),
                        _blocoIcones(r, acento),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: alturaTicker,
                  child: ListenableBuilder(
                    listenable: InfoHub.instance,
                    builder: (context, _) => _ticker(InfoHub.instance, r, acento),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          acento.withValues(alpha: 0.70),
                          acento.withValues(alpha: 0.70),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.15, 0.85, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _corAtualizacao = Color(0xFF00D4FF);

  Widget _botaoAtualizacao(R r) {
    return GestureDetector(
      onTap: () => abrirFolhaAtualizacao(context),
      child: Container(
        width: r.sp(42),
        height: r.sp(42),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _corAtualizacao.withValues(alpha: 0.16),
          border: Border.all(
              color: _corAtualizacao.withValues(alpha: 0.65), width: 1.5),
        ),
        child: Icon(Icons.system_update_rounded,
            color: _corAtualizacao, size: r.icon(20)),
      ),
    );
  }

  Widget _divisor(R r, Color acento) {
    return Container(
      width: 1.2,
      height: r.sp(50),
      margin: EdgeInsets.symmetric(horizontal: r.sp(14)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, acento.withValues(alpha: 0.50), Colors.transparent],
        ),
      ),
    );
  }

  Widget _blocoClima(InfoHub hub, R r, Color acento, double altura) {
    final clima = hub.clima;
    if (clima == null) {
      return Center(
        child: hub.climaCarregando
            ? SizedBox(
                width: r.icon(22),
                height: r.icon(22),
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: acento.withValues(alpha: 0.7)),
              )
            : Icon(Icons.cloud_off_rounded, color: Colors.white38, size: r.icon(22)),
      );
    }

    final chuva = clima.chuvaRestanteHoje().maxima;
    final temChuva = chuva >= 30;
    final style = GoogleFonts.poppins(decoration: TextDecoration.none);

    return SizedBox(
      height: altura,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.place_rounded,
                    color: acento.withValues(alpha: 0.55), size: r.icon(14)),
                SizedBox(height: r.sp(2)),
                Text(
                  '${hub.cidadeLabel} - ${hub.estadoLabel}',
                  style: style.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: r.fs(r.isCompact ? 14 : 17),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(width: r.sp(20)),
            Text(emojiClima(clima.codigo, ehDia: clima.ehDia),
                style: TextStyle(
                    fontSize: r.fs(r.isCompact ? 26 : 34),
                    decoration: TextDecoration.none)),
            SizedBox(width: r.sp(8)),
            Text(
              '${clima.temp}°C',
              style: style.copyWith(
                color: Colors.white,
                fontSize: r.fs(r.isCompact ? 28 : 38),
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            SizedBox(width: r.sp(16)),
            Icon(Icons.thermostat_rounded,
                color: acento.withValues(alpha: 0.85), size: r.icon(16)),
            SizedBox(width: r.sp(4)),
            Text(
              'Sensação ${clima.sensacao}°C',
              style: style.copyWith(
                color: Colors.white.withValues(alpha: 0.60),
                fontSize: r.fs(r.isCompact ? 12 : 15),
              ),
            ),
            if (temChuva) ...[
              SizedBox(width: r.sp(20)),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: r.sp(16), vertical: r.sp(9)),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.40)),
                ),
                child: Text(
                  '🌧 $chuva% chuva',
                  style: style.copyWith(
                    color: Colors.lightBlueAccent,
                    fontSize: r.fs(17),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _blocoIcones(R r, Color acento) {
    final tema = _temas[widget.telaAtual] ?? _temaDefault;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.modoManual) ...[
          _badgeManual(r),
          SizedBox(width: r.sp(10)),
        ],
        Container(
          width: r.sp(46),
          height: r.sp(46),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: acento.withValues(alpha: 0.12),
            border: Border.all(color: acento.withValues(alpha: 0.45), width: 1.5),
          ),
          child: Icon(tema.icone, color: acento, size: r.icon(21)),
        ),
        if (widget.aoAbrirConfig != null) ...[
          SizedBox(width: r.sp(10)),
          GestureDetector(
            onTap: _tocarEngrenagem,
            child: RotationTransition(
              turns: Tween(begin: 0.0, end: 0.375).animate(_gearCtrl),
              child: Container(
                width: r.sp(46),
                height: r.sp(46),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22), width: 1.5),
                ),
                child: Icon(Icons.settings_rounded,
                    color: Colors.white.withValues(alpha: 0.75), size: r.icon(21)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _badgeManual(R r) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(11), vertical: r.sp(6)),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, color: Colors.orangeAccent, size: r.icon(16)),
          SizedBox(width: r.sp(5)),
          Text(
            'MANUAL',
            style: GoogleFonts.poppins(
              color: Colors.orangeAccent,
              fontSize: r.fs(11),
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ticker(InfoHub hub, R r, Color acento) {
    final texto = hub.tickerAtual;
    final spotify = hub.spotifyTocando;
    final cor = spotify ? const Color(0xFF1DB954) : acento;
    final capa = spotify ? SpotifyManager.instance.albumArtBytes : null;

    Widget icone;
    if (spotify) {
      icone = Container(
        width: r.sp(30),
        height: r.sp(30),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: cor.withValues(alpha: 0.6), width: 1.5),
        ),
        child: ClipOval(
          child: capa != null
              ? Image.memory(capa, fit: BoxFit.cover, gaplessPlayback: true)
              : Icon(Icons.music_note_rounded, color: cor, size: r.icon(16)),
        ),
      );
    } else {
      final ehFrase = texto.startsWith('💡');
      icone = Icon(ehFrase ? Icons.format_quote_rounded : Icons.newspaper_rounded,
          color: cor.withValues(alpha: 0.85), size: r.icon(19));
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cor.withValues(alpha: spotify ? 0.08 : 0.05),
        border: Border(top: BorderSide(color: cor.withValues(alpha: 0.20), width: 1)),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.sp(12)),
            child: icone,
          ),
          Container(width: 1, height: r.sp(18), color: cor.withValues(alpha: 0.25)),
          SizedBox(width: r.sp(10)),
          Expanded(
            child: RepaintBoundary(
              child: _MarqueeText(
                key: ValueKey(texto),
                text: texto,
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: r.fs(r.isCompact ? 12 : 14),
                  letterSpacing: 0.2,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          SizedBox(width: r.sp(14)),
        ],
      ),
    );
  }
}

/// Relógio isolado: só reconstrói quando o minuto muda.
class _BlocoRelogio extends StatelessWidget {
  final Color acento;
  final double altura;
  const _BlocoRelogio({required this.acento, required this.altura});

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final tamHora = (altura * 0.42).clamp(24.0, 46.0);
    return SizedBox(
      width: r.sp(r.isCompact ? 175 : 230),
      height: altura,
      child: ValueListenableBuilder<DateTime>(
        valueListenable: InfoHub.instance.relogio,
        builder: (context, agora, _) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                horaMinuto(agora),
                style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: tamHora,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                  decoration: TextDecoration.none,
                  shadows: [
                    Shadow(color: acento.withValues(alpha: 0.70), blurRadius: 18),
                  ],
                ),
              ),
              SizedBox(height: r.sp(3)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: r.sp(7), vertical: r.sp(2)),
                    decoration: BoxDecoration(
                      color: acento.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: acento.withValues(alpha: 0.40)),
                    ),
                    child: Text(
                      diaSemanaLongo(agora).toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: acento,
                        fontSize: r.fs(14),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  SizedBox(width: r.sp(7)),
                  Text(
                    '${doisDigitos(agora.day)}/${doisDigitos(agora.month)}/${agora.year}',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.60),
                      fontSize: r.fs(15),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Marquee — texto rolando quando não cabe na largura.
// ─────────────────────────────────────────────────────────────────────────────
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeText({super.key, required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);
  double _textWidth = 0;
  double _viewWidth = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _medir());
  }

  void _medir() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    _textWidth = tp.width;
    _viewWidth = box.size.width;
    _ctrl.stop();
    _ctrl.reset();
    if (_textWidth > _viewWidth - 16 &&
        !PerformanceManager.instance.modoEconomico) {
      final dur = ((_textWidth + _viewWidth) / 60).clamp(8.0, 25.0).round();
      _ctrl.duration = Duration(seconds: dur);
      _ctrl.repeat();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ctrl.isAnimating) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(widget.text,
            style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return ClipRect(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.translate(
          offset: Offset(_viewWidth - _ctrl.value * (_textWidth + _viewWidth), 0),
          child: child,
        ),
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MlionShell — barra superior + tela atual
// ─────────────────────────────────────────────────────────────────────────────
class MlionShell extends StatelessWidget {
  final Widget child;
  final bool modoManual;
  final bool mostrarBarra;
  final String telaAtual;
  final VoidCallback? aoAbrirConfig;

  const MlionShell({
    super.key,
    required this.child,
    this.modoManual = false,
    this.mostrarBarra = true,
    this.telaAtual = 'clima',
    this.aoAbrirConfig,
  });

  @override
  Widget build(BuildContext context) {
    if (!mostrarBarra) return child;
    return Column(
      children: [
        BarraInfo(
          modoManual: modoManual,
          telaAtual: telaAtual,
          aoAbrirConfig: aoAbrirConfig,
        ),
        Expanded(child: child),
      ],
    );
  }
}
