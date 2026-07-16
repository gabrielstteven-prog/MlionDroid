import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config_manager.dart';
import 'info_hub.dart';
import 'responsive.dart';
import 'performance_manager.dart';
import 'update_manager.dart';
import 'update_banner.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Paleta por tela
// ─────────────────────────────────────────────────────────────────────────────
class _TelaTheme {
  final Color acento;
  final Color fundo;
  final IconData icone;
  final String label;
  const _TelaTheme({
    required this.acento,
    required this.fundo,
    required this.icone,
    required this.label,
  });
}

const Map<String, _TelaTheme> _temas = {
  'bom_dia': _TelaTheme(
      acento: Color(0xFFFFD700),
      fundo: Color(0xFF1a1200),
      icone: Icons.wb_sunny_rounded,
      label: 'Bom dia'),
  'clima': _TelaTheme(
      acento: Color(0xFF18FFFF),
      fundo: Color(0xFF001a2e),
      icone: Icons.cloud_rounded,
      label: 'Clima'),
  'palmeiras': _TelaTheme(
      acento: Color(0xFFC1A163),
      fundo: Color(0xFF001a0a),
      icone: Icons.sports_soccer_rounded,
      label: 'Palmeiras'),
  'proxima_partida': _TelaTheme(
      acento: Color(0xFF69F0AE),
      fundo: Color(0xFF001a0a),
      icone: Icons.emoji_events_rounded,
      label: 'Próxima Partida'),
  'classificacao': _TelaTheme(
      acento: Color(0xFF00C853),
      fundo: Color(0xFF001a0a),
      icone: Icons.leaderboard_rounded,
      label: 'Classificação'),
  'calendario': _TelaTheme(
      acento: Color(0xFF40C4FF),
      fundo: Color(0xFF001020),
      icone: Icons.calendar_month_rounded,
      label: 'Calendário'),
  'compras': _TelaTheme(
      acento: Color(0xFF00E676),
      fundo: Color(0xFF001a0a),
      icone: Icons.shopping_cart_rounded,
      label: 'Compras'),
  'brasil': _TelaTheme(
      acento: Color(0xFFFFDF00),
      fundo: Color(0xFF060910),
      icone: Icons.public_rounded,
      label: 'Brasil'),
  'regiao': _TelaTheme(
      acento: Color(0xFF00BCD4),
      fundo: Color(0xFF0a0a2e),
      icone: Icons.location_city_rounded,
      label: 'Região'),
  'fotos': _TelaTheme(
      acento: Color(0xFFE040FB),
      fundo: Color(0xFF1a0020),
      icone: Icons.photo_library_rounded,
      label: 'Memórias'),
};

const _temaDefault = _TelaTheme(
  acento: Color(0xFF18FFFF),
  fundo: Color(0xFF001a2e),
  icone: Icons.dashboard_rounded,
  label: 'MlionDroid',
);

// ─────────────────────────────────────────────────────────────────────────────
//  Aurora Painter
// ─────────────────────────────────────────────────────────────────────────────
class _AuroraBarraPainter extends CustomPainter {
  final double t;
  final Color cor1;
  final Color cor2;
  final Color cor3;

  const _AuroraBarraPainter(this.t, this.cor1, this.cor2, this.cor3);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..style = PaintingStyle.fill;
    _onda(
        canvas,
        s,
        p,
        cor1,
        0.18,
        s.height * (0.1 + math.sin(t * math.pi) * 0.08),
        s.height * 0.55,
        0.7,
        t * math.pi);
    _onda(
        canvas,
        s,
        p,
        cor2,
        0.13,
        s.height * (0.2 + math.cos(t * math.pi * 0.7) * 0.06),
        s.height * 0.45,
        0.5,
        t * math.pi * 1.3 + 1.0);
    _onda(
        canvas,
        s,
        p,
        cor3,
        0.10,
        s.height * (0.35 + math.sin(t * math.pi * 1.2) * 0.07),
        s.height * 0.50,
        0.4,
        t * math.pi * 0.9 + 2.1);
  }

  void _onda(Canvas c, Size s, Paint p, Color cor, double op, double yOffset,
      double amp, double freq, double phase) {
    final path = Path()..moveTo(0, s.height);
    for (double x = 0; x <= s.width; x += 3) {
      path.lineTo(x,
          yOffset + amp * math.sin(freq * (x / s.width) * 2 * math.pi + phase));
    }
    path.lineTo(s.width, s.height);
    path.close();
    p.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [cor.withValues(alpha: op), cor.withValues(alpha: op * 0.15)],
    ).createShader(
        Rect.fromLTWH(0, yOffset - amp, s.width, amp * 2 + s.height));
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_AuroraBarraPainter old) => old.t != t || old.cor1 != cor1;
}

// ─────────────────────────────────────────────────────────────────────────────
//  BarraInfo
// ─────────────────────────────────────────────────────────────────────────────
class BarraInfo extends StatefulWidget {
  final bool modoManual;
  final String telaAtual;
  final VoidCallback? aoAbrirConfig; // ← NOVO: callback para abrir config

  const BarraInfo({
    super.key,
    this.modoManual = false,
    this.telaAtual = 'clima',
    this.aoAbrirConfig, // ← NOVO
  });

  static double alturaTotal(BuildContext context) {
    final sh = MediaQuery.of(context).size.height;
    return (sh * 0.14).clamp(100.0, 160.0);
  }

  @override
  State<BarraInfo> createState() => _BarraInfoState();
}

class _BarraInfoState extends State<BarraInfo> with TickerProviderStateMixin {
  late AnimationController _temaCtrl;
  late Animation<Color?> _acentoAnim;
  late Animation<Color?> _fundoAnim;
  late AnimationController _auroraCtrl;

  // ── Engrenagem: rotação ao pressionar ─────────────────────────────────────
  late AnimationController _gearCtrl;

  _TelaTheme _anterior = _temaDefault;
  _TelaTheme _atual = _temaDefault;

  final _cfg = ConfigManager();
  bool get _auroraAtiva => _cfg.getBool('barra_info', 'aurora_ativa', true);

  @override
  void initState() {
    super.initState();
    _atual = _temas[widget.telaAtual] ?? _temaDefault;
    _anterior = _atual;

    _temaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _auroraCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 8));
    // Aurora é puramente decorativa — só roda em loop no modo visual completo.
    if (!PerformanceManager.instance.modoEconomico) {
      _auroraCtrl.repeat(reverse: true);
    }
    _gearCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));

    _acentoAnim = ColorTween(begin: _atual.acento, end: _atual.acento)
        .animate(CurvedAnimation(parent: _temaCtrl, curve: Curves.easeInOut));
    _fundoAnim = ColorTween(begin: _atual.fundo, end: _atual.fundo)
        .animate(CurvedAnimation(parent: _temaCtrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(BarraInfo old) {
    super.didUpdateWidget(old);
    if (old.telaAtual != widget.telaAtual) {
      _anterior = _temas[old.telaAtual] ?? _temaDefault;
      _atual = _temas[widget.telaAtual] ?? _temaDefault;
      _acentoAnim = ColorTween(begin: _anterior.acento, end: _atual.acento)
          .animate(CurvedAnimation(parent: _temaCtrl, curve: Curves.easeInOut));
      _fundoAnim = ColorTween(begin: _anterior.fundo, end: _atual.fundo)
          .animate(CurvedAnimation(parent: _temaCtrl, curve: Curves.easeInOut));
      _temaCtrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
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
    final sh = MediaQuery.of(context).size.height;
    final alturaTotal = (sh * 0.14).clamp(100.0, 160.0);
    final alturaTicker = (alturaTotal * 0.28).clamp(32.0, 50.0);
    final alturaLinhaPrincipal = alturaTotal - alturaTicker;

    return AnimatedBuilder(
      animation:
          Listenable.merge([_temaCtrl, _auroraCtrl, UpdateManager.instance]),
      builder: (context, _) {
        final acento = _acentoAnim.value ?? _atual.acento;
        final fundo = _fundoAnim.value ?? _atual.fundo;

        return ListenableBuilder(
          listenable: InfoHub.instance,
          builder: (context, __) {
            final hub = InfoHub.instance;
            return SizedBox(
              height: alturaTotal,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
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
                    if (_auroraAtiva &&
                        !PerformanceManager.instance.modoEconomico)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: alturaLinhaPrincipal,
                        child: CustomPaint(
                          painter: _AuroraBarraPainter(
                            _auroraCtrl.value,
                            acento,
                            _atual.acento == acento
                                ? acento.withValues(alpha: 0.6)
                                : _anterior.acento,
                            fundo,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: alturaLinhaPrincipal,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: r.sp(20)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _blocoRelogio(hub, r, acento,
                                alturaDisponivel: alturaLinhaPrincipal),
                            if (UpdateManager.instance.disponivel) ...[
                              SizedBox(width: r.sp(10)),
                              _botaoAtualizacao(r),
                            ],
                            _divisor(r, acento),
                            Expanded(
                                child: _blocoClima(hub, r, acento,
                                    alturaDisponivel: alturaLinhaPrincipal)),
                            _divisor(r, acento),
                            _blocoIcones(r, acento,
                                alturaDisponivel: alturaLinhaPrincipal),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: alturaTicker,
                      child: _ticker(hub, r, acento),
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
      },
    );
  }

  // ── Relógio ────────────────────────────────────────────────────────────────
  Widget _blocoRelogio(InfoHub hub, R r, Color acento,
      {double alturaDisponivel = 80}) {
    final tamHora = (alturaDisponivel * 0.42).clamp(24.0, 46.0);
    return SizedBox(
      width: r.sp(r.isCompact ? 175 : 230),
      height: alturaDisponivel,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hub.hora,
              style: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: tamHora,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
                decoration: TextDecoration.none,
                shadows: [
                  Shadow(color: acento.withValues(alpha: 0.70), blurRadius: 18),
                  Shadow(color: acento.withValues(alpha: 0.25), blurRadius: 36),
                ],
              ),
            ),
            SizedBox(height: r.sp(3)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: r.sp(7), vertical: r.sp(2)),
                  decoration: BoxDecoration(
                    color: acento.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: acento.withValues(alpha: 0.40), width: 1),
                  ),
                  child: Text(
                    hub.diaSemanaCompleto.toUpperCase(),
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
                  hub.dataCompleta,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: r.fs(15),
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Ícone de atualização — só aparece quando há versão nova disponível ────
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
          boxShadow: [
            BoxShadow(
              color: _corAtualizacao.withValues(alpha: 0.35),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(Icons.system_update_rounded,
            color: _corAtualizacao, size: r.icon(20)),
      ),
    );
  }

  // ── Divisor ────────────────────────────────────────────────────────────────
  Widget _divisor(R r, Color acento) {
    return Container(
      width: 1.2,
      height: r.sp(50),
      margin: EdgeInsets.symmetric(horizontal: r.sp(14)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            acento.withValues(alpha: 0.50),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  // ── Clima ──────────────────────────────────────────────────────────────────
  Widget _blocoClima(InfoHub hub, R r, Color acento,
      {double alturaDisponivel = 80}) {
    if (hub.climaCarregando) {
      return Center(
        child: SizedBox(
          width: r.icon(22),
          height: r.icon(22),
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: acento.withValues(alpha: 0.7)),
        ),
      );
    }

    final emoji = hub.emojiClima(hub.weatherCode);
    final temChuva = hub.chanceChuva >= 30;
    final partes = hub.cidadeLabel.split(' • ');
    final cidade = partes.isNotEmpty ? partes[0] : hub.cidadeLabel;
    final estado = partes.length > 1 ? partes[1] : '';

    return SizedBox(
      height: alturaDisponivel,
      child: ClipRect(
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── 1. Cidade + estado ──────────────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.place_rounded,
                      color: acento.withValues(alpha: 0.55), size: r.icon(14)),
                  SizedBox(height: r.sp(2)),
                  Text(
                    estado.isNotEmpty ? '$cidade - $estado' : cidade,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: r.fs(r.isCompact ? 14 : 17),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),

              SizedBox(width: r.sp(20)),

              // ── 2. Emoji + temperatura ──────────────────────────────────────
              Text(emoji,
                  style: TextStyle(
                      fontSize: r.fs(r.isCompact ? 26 : 34),
                      decoration: TextDecoration.none)),
              SizedBox(width: r.sp(8)),
              Text(
                '${hub.temp}°C',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: r.fs(r.isCompact ? 28 : 38),
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  decoration: TextDecoration.none,
                ),
              ),

              SizedBox(width: r.sp(16)),

              // ── 3. Sensação térmica ──────────────────────────────────────────
              Icon(Icons.thermostat_rounded,
                  color: acento.withValues(alpha: 0.85), size: r.icon(16)),
              SizedBox(width: r.sp(4)),
              Text(
                'Sensação ${hub.sensacao}°C',
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: r.fs(r.isCompact ? 12 : 15),
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.none,
                ),
              ),

              // ── 4. Chance de chuva — maior, já que tem espaço sobrando ──────
              if (temChuva) ...[
                SizedBox(width: r.sp(20)),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: r.sp(16), vertical: r.sp(9)),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.blueAccent.withValues(alpha: 0.40)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🌧',
                          style: TextStyle(
                              fontSize: r.fs(20),
                              decoration: TextDecoration.none)),
                      SizedBox(width: r.sp(8)),
                      Text(
                        '${hub.chanceChuva}% chuva',
                        style: GoogleFonts.poppins(
                          color: Colors.lightBlueAccent,
                          fontSize: r.fs(17),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Ícones: tela atual + badge MANUAL + engrenagem ─────────────────────────
  Widget _blocoIcones(R r, Color acento, {double alturaDisponivel = 80}) {
    final tema = _temas[widget.telaAtual] ?? _temaDefault;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Badge MANUAL — fica à esquerda, antes dos dois ícones circulares
        if (widget.modoManual) ...[
          _badgeManual(r),
          SizedBox(width: r.sp(10)),
        ],

        // Ícone da tela atual
        Container(
          width: r.sp(46),
          height: r.sp(46),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: acento.withValues(alpha: 0.12),
            border:
                Border.all(color: acento.withValues(alpha: 0.45), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: acento.withValues(alpha: 0.22),
                blurRadius: 12,
              ),
            ],
          ),
          child: Icon(tema.icone, color: acento, size: r.icon(21)),
        ),

        // ── Engrenagem — sempre ao lado do ícone de tela ──────────────────
        if (widget.aoAbrirConfig != null) ...[
          SizedBox(width: r.sp(10)),
          _botaoEngrenagem(r, acento),
        ],
      ],
    );
  }

  // ── Botão engrenagem nativo da barra ──────────────────────────────────────
  Widget _botaoEngrenagem(R r, Color acento) {
    return GestureDetector(
      onTap: _tocarEngrenagem,
      child: AnimatedBuilder(
        animation: _gearCtrl,
        builder: (_, child) => Transform.rotate(
          angle: _gearCtrl.value * math.pi * 0.75, // gira 135° ao tocar
          child: child,
        ),
        child: Container(
          width: r.sp(46),
          height: r.sp(46),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.07),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: acento.withValues(alpha: 0.12),
                blurRadius: 10,
              ),
            ],
          ),
          child: Icon(
            Icons.settings_rounded,
            color: Colors.white.withValues(alpha: 0.75),
            size: r.icon(21),
          ),
        ),
      ),
    );
  }

  Widget _badgeManual(R r) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(11), vertical: r.sp(6)),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colors.orangeAccent.withValues(alpha: 0.55), width: 1.2),
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

  // ── Ticker ─────────────────────────────────────────────────────────────────
  Widget _ticker(InfoHub hub, R r, Color acento) {
    final isFrase = hub.tickerAtual.startsWith('💡');
    final icone =
        isFrase ? Icons.format_quote_rounded : Icons.newspaper_rounded;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: acento.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(color: acento.withValues(alpha: 0.20), width: 1),
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.sp(14)),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Icon(icone,
                  key: ValueKey(icone),
                  color: acento.withValues(alpha: 0.85),
                  size: r.icon(19)),
            ),
          ),
          Container(
              width: 1,
              height: r.sp(18),
              color: acento.withValues(alpha: 0.25)),
          SizedBox(width: r.sp(10)),
          Expanded(
            child: _MarqueeText(
              key: ValueKey(hub.tickerAtual),
              text: hub.tickerAtual,
              style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: r.fs(r.isCompact ? 12 : 14),
                fontWeight: FontWeight.w400,
                letterSpacing: 0.2,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          SizedBox(width: r.sp(14)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Marquee
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
  late AnimationController _ctrl;
  double _textWidth = 0;
  double _viewWidth = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _medir());
  }

  @override
  void didUpdateWidget(_MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _medir());
    }
  }

  void _medir() {
    if (!mounted) return;
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    _textWidth = tp.width;
    _viewWidth = box.size.width;
    _ctrl.stop();
    _ctrl.reset();
    if (_textWidth <= _viewWidth - 16) {
      setState(() {});
      return;
    }
    final dur = ((_textWidth + _viewWidth) / 60).clamp(8.0, 25.0).round();
    _ctrl.duration = Duration(seconds: dur);
    _ctrl.repeat();
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_textWidth <= _viewWidth - 16 || !_ctrl.isAnimating) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(widget.text,
            style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final offset = _ctrl.value * (_textWidth + _viewWidth);
        return ClipRect(
          child: Stack(children: [
            Positioned(
              left: _viewWidth - offset,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(widget.text, style: widget.style, maxLines: 1),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MlionShell
// ─────────────────────────────────────────────────────────────────────────────
class MlionShell extends StatelessWidget {
  final Widget child;
  final bool modoManual;
  final bool mostrarBarra;
  final String telaAtual;
  final VoidCallback? aoAbrirConfig; // ← NOVO

  const MlionShell({
    super.key,
    required this.child,
    this.modoManual = false,
    this.mostrarBarra = true,
    this.telaAtual = 'clima',
    this.aoAbrirConfig, // ← NOVO
  });

  @override
  Widget build(BuildContext context) {
    if (!mostrarBarra) return child;
    return Column(
      children: [
        BarraInfo(
          modoManual: modoManual,
          telaAtual: telaAtual,
          aoAbrirConfig: aoAbrirConfig, // ← repassa para BarraInfo
        ),
        Expanded(child: child),
      ],
    );
  }
}
