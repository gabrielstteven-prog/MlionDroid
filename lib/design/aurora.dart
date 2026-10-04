import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../performance_manager.dart';
import 'tema.dart';

/// Aurora: três manchas de luz grandes e suaves que passeiam devagar sobre o
/// céu (um ciclo a cada ~70 s). As cores mudam com o período do dia — verde e
/// violeta de madrugada, como uma aurora boreal; laranja e magenta no fim da
/// tarde. Com o Spotify, as cores saem da capa do disco.
///
/// Nasceu de um "acidente bonito": a transição lenta das cores da capa para
/// o céu parecia uma aurora. Agora é de propósito.
class Aurora extends StatefulWidget {
  final List<Color> cores;
  const Aurora({super.key, required this.cores});

  /// Paleta da aurora para cada período do dia.
  static List<Color> paleta(Periodo p) => switch (p) {
        Periodo.madrugada => const [Color(0xFF16E0A8), Color(0xFF5B5BD6), Color(0xFF8E44D9)],
        Periodo.manha => const [Color(0xFF3FC3F2), Color(0xFFFFB25C), Color(0xFFF07FB0)],
        Periodo.tarde => const [Color(0xFF3CCFE0), Color(0xFF6E7FE8), Color(0xFF6FE0C2)],
        Periodo.fimDeTarde => const [Color(0xFFFF7E57), Color(0xFFB45ED0), Color(0xFFFFC54D)],
        Periodo.noite => const [Color(0xFF00E39C), Color(0xFF7A4DFF), Color(0xFF18D8FF)],
      };

  /// Paleta a partir de uma cor (capa do disco no Spotify): a cor e duas
  /// vizinhas no círculo cromático.
  static List<Color> daCor(Color c) {
    final h = HSLColor.fromColor(c);
    Color girar(double graus) => h
        .withHue((h.hue + graus) % 360)
        .withSaturation(math.max(h.saturation, 0.55))
        .withLightness(0.55)
        .toColor();
    return [girar(0), girar(40), girar(-50)];
  }

  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 70));

  @override
  void initState() {
    super.initState();
    if (PerformanceManager.instance.animacoesDecorativasAtivas) {
      _c.repeat();
    } else {
      _c.value = 0.3; // parada, mas presente
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PintorAurora(_c, widget.cores),
        size: Size.infinite,
      ),
    );
  }
}

class _PintorAurora extends CustomPainter {
  final Animation<double> anim;
  final List<Color> cores;
  _PintorAurora(this.anim, this.cores) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value * 2 * math.pi;
    final w = size.width;
    final h = size.height;
    // Cada mancha percorre uma curva própria (Lissajous) devagar.
    final caminhos = [
      Offset(0.25 + 0.18 * math.sin(t), 0.25 + 0.12 * math.cos(t * 2)),
      Offset(0.75 + 0.15 * math.cos(t + 1.3), 0.35 + 0.18 * math.sin(t * 1.5 + 0.4)),
      Offset(0.5 + 0.25 * math.sin(t * 0.7 + 2.1), 0.8 + 0.1 * math.cos(t + 0.9)),
    ];
    final raios = [0.55, 0.5, 0.6];
    final intensidade = [0.26, 0.22, 0.18];
    for (var i = 0; i < 3; i++) {
      final centro = Offset(caminhos[i].dx * w, caminhos[i].dy * h);
      final raio = raios[i] * math.max(w, h) * (0.9 + 0.1 * math.sin(t * 2 + i));
      final cor = cores[i % cores.length];
      canvas.drawCircle(
        centro,
        raio,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(colors: [
            cor.withValues(alpha: intensidade[i]),
            cor.withValues(alpha: intensidade[i] * 0.35),
            cor.withValues(alpha: 0),
          ], stops: const [0, 0.45, 1])
              .createShader(Rect.fromCircle(center: centro, radius: raio)),
      );
    }
  }

  @override
  bool shouldRepaint(_PintorAurora old) => old.cores != cores;
}
