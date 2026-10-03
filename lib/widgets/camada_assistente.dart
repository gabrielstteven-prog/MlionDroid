import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tema.dart';
import '../services/assistente_service.dart';
import '../services/jarvis_service.dart';
import '../sistema.dart';

/// Camada que fica por cima de todas as telas:
///  • balão do assistente (o que você falou e a resposta);
///  • aviso de tela cheia quando um temporizador termina.
/// Sem nada para mostrar, não intercepta toques.
class CamadaAssistente extends StatelessWidget {
  const CamadaAssistente({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AssistenteService.instance,
      builder: (context, _) {
        final a = AssistenteService.instance;
        final tocando = a.temporizadores.where((t) => t.tocando).toList();
        if (tocando.isNotEmpty) return _AlarmeTela(t: tocando.first);
        if (a.estado == EstadoAssistente.parado) return const SizedBox.shrink();
        return _Balao(a: a);
      },
    );
  }
}

class _Balao extends StatelessWidget {
  final AssistenteService a;
  const _Balao({required this.a});

  @override
  Widget build(BuildContext context) {
    final t = Tipo.de(context);
    final r = t.r;
    final status = switch (a.estado) {
      EstadoAssistente.ouvindo => 'Ouvindo...',
      EstadoAssistente.pensando => 'Pensando...',
      _ => '',
    };
    final nome = JarvisService.instance.nomeAssistente.toUpperCase();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: a.fechar,
      child: ColoredBox(
        color: const Color(0xE6060B16),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(r.sp(40)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: r.sp(1100)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OrbeJarvis(estado: a.estado, tamanho: r.sp(240)),
                  SizedBox(height: r.sp(18)),
                  Text(nome,
                      style: t.legenda(cor: _corDoEstado(a.estado)).copyWith(
                          letterSpacing: 6, fontWeight: FontWeight.w800)),
                  if (a.ultimaFala.isNotEmpty) ...[
                    SizedBox(height: r.sp(18)),
                    Text('“${a.ultimaFala}”',
                        textAlign: TextAlign.center,
                        style: t.corpo(cor: Cores.textoSecundario)),
                  ],
                  if (status.isNotEmpty) ...[
                    SizedBox(height: r.sp(12)),
                    Text(status, style: t.subtitulo()),
                  ],
                  if (a.ultimaResposta.isNotEmpty) ...[
                    SizedBox(height: r.sp(18)),
                    Text(a.ultimaResposta,
                        textAlign: TextAlign.center, style: t.subtitulo()),
                  ],
                  SizedBox(height: r.sp(24)),
                  Text('Toque para fechar', style: t.legenda()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _corDoEstado(EstadoAssistente e) => switch (e) {
      EstadoAssistente.ouvindo => const Color(0xFF4FD8FF),
      EstadoAssistente.pensando => const Color(0xFF9C8CFF),
      EstadoAssistente.respondendo => const Color(0xFF5CF2C8),
      EstadoAssistente.parado => const Color(0xFF4FD8FF),
    };

/// Orbe do Jarvis: núcleo luminoso, anéis de HUD girando e, quando fala,
/// um anel que ondula. A cor e o ritmo mudam com o estado.
class OrbeJarvis extends StatefulWidget {
  final EstadoAssistente estado;
  final double tamanho;
  const OrbeJarvis({super.key, required this.estado, required this.tamanho});

  @override
  State<OrbeJarvis> createState() => _OrbeJarvisState();
}

class _OrbeJarvisState extends State<OrbeJarvis>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.tamanho,
        child: AnimatedBuilder(
          animation: Listenable.merge([_c, Sistema.volumeVoz]),
          builder: (_, __) => CustomPaint(
            painter: _PintorOrbe(
                _c.value,
                widget.estado,
                _corDoEstado(widget.estado),
                widget.estado == EstadoAssistente.ouvindo ? Sistema.volumeVoz.value : 0),
          ),
        ),
      ),
    );
  }
}

class _PintorOrbe extends CustomPainter {
  final double t; // 0..1, volta a cada 6 s
  final EstadoAssistente estado;
  final Color cor;
  final double volume; // 0..1, voz de quem fala (só ouvindo)
  _PintorOrbe(this.t, this.estado, this.cor, this.volume);

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final raio = size.shortestSide / 2;
    final ang = t * 2 * math.pi;

    // Ritmo da "respiração": rápido ouvindo, médio falando, lento parado.
    final freq = switch (estado) {
      EstadoAssistente.ouvindo => 6.0,
      EstadoAssistente.respondendo => 9.0,
      EstadoAssistente.pensando => 3.0,
      EstadoAssistente.parado => 2.0,
    };
    final pulso = math.max((math.sin(ang * freq) + 1) / 2 * (1 - volume), volume); // 0..1

    // Halo
    canvas.drawCircle(
      centro,
      raio,
      Paint()
        ..shader = RadialGradient(colors: [
          cor.withValues(alpha: 0.35 + 0.15 * pulso),
          cor.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: centro, radius: raio)),
    );

    // Anéis de HUD com arcos girando em sentidos opostos.
    void anel(double f, double largura, double velocidade, int segmentos,
        double alpha) {
      final rr = raio * f;
      final rect = Rect.fromCircle(center: centro, radius: rr);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = largura
        ..strokeCap = StrokeCap.round
        ..color = cor.withValues(alpha: alpha);
      final passo = 2 * math.pi / segmentos;
      for (var i = 0; i < segmentos; i++) {
        canvas.drawArc(
            rect, ang * velocidade + i * passo, passo * 0.62, false, p);
      }
    }

    final girar = estado == EstadoAssistente.pensando ? 3.0 : 1.0;
    anel(0.92, 2, 1 * girar, 3, 0.55);
    anel(0.80, 4, -1.6 * girar, 5, 0.75);
    anel(0.68, 1.5, 2.2 * girar, 12, 0.5);

    // Falando: anel que ondula como uma onda sonora.
    if (estado == EstadoAssistente.respondendo ||
        estado == EstadoAssistente.ouvindo) {
      final onda = Path();
      const pontos = 120;
      final amp =
          raio * (estado == EstadoAssistente.respondendo ? 0.05 : 0.025);
      for (var i = 0; i <= pontos; i++) {
        final a = i / pontos * 2 * math.pi;
        final rr = raio * 0.56 +
            amp *
                math.sin(a * 6 + ang * 8) *
                (0.5 + 0.5 * math.sin(a * 2 - ang * 3));
        final pt = centro + Offset(math.cos(a) * rr, math.sin(a) * rr);
        i == 0 ? onda.moveTo(pt.dx, pt.dy) : onda.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
          onda,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = cor.withValues(alpha: 0.9));
    }

    // Núcleo
    final nucleo = raio * (0.40 + 0.05 * pulso);
    canvas.drawCircle(
      centro,
      nucleo,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white,
          Color.lerp(Colors.white, cor, 0.55)!,
          cor.withValues(alpha: 0.25),
        ], stops: const [
          0,
          0.45,
          1
        ]).createShader(Rect.fromCircle(center: centro, radius: nucleo)),
    );
  }

  @override
  bool shouldRepaint(_PintorOrbe old) =>
      old.t != t || old.estado != estado || old.cor != cor || old.volume != volume;
}

class _AlarmeTela extends StatelessWidget {
  final Temporizador t;
  const _AlarmeTela({required this.t});

  @override
  Widget build(BuildContext context) {
    final tipo = Tipo.de(context);
    final r = tipo.r;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AssistenteService.instance.dispensar(t.id),
      child: ColoredBox(
        color: const Color(0xF20E1628),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.alarm_on_rounded,
                  color: Cores.aviso, size: r.icon(96)),
              SizedBox(height: r.sp(16)),
              Text('Temporizador de ${t.rotulo} terminou',
                  textAlign: TextAlign.center, style: tipo.titulo()),
              SizedBox(height: r.sp(12)),
              Text('Toque em qualquer lugar para parar o alarme',
                  style: tipo.corpo(cor: Cores.textoSecundario)),
            ],
          ),
        ),
      ),
    );
  }
}
