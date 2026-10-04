import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../performance_manager.dart';
import 'tema.dart';

/// Aurora: três manchas de luz grandes e suaves que passeiam devagar sobre o
/// céu (uma volta a cada ~4 min, atualizada 8x por segundo para não pesar). As
/// cores mudam com o período do dia — verde e
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

class _AuroraState extends State<Aurora> {
  // Relógio ÚNICO para a aurora inteira: se a tela for recriada (sair das
  // Configurações, trocar de modo), as luzes continuam de onde estavam em
  // vez de pular para a posição inicial.
  static final Stopwatch _relogio = Stopwatch()..start();
  static const _cicloSeg = 240.0; // uma volta completa a cada 4 minutos

  final ValueNotifier<double> _fase = ValueNotifier(0);
  Timer? _timer;

  double get _agora => (_relogio.elapsedMilliseconds / 1000.0 % _cicloSeg) / _cicloSeg;

  @override
  void initState() {
    super.initState();
    _fase.value = _agora;
    // 8 quadros por segundo: o movimento é tão lento que o olho não vê
    // diferença de 60 — e o tablet não engasga redesenhando a tela inteira.
    if (PerformanceManager.instance.animacoesDecorativasAtivas) {
      _timer = Timer.periodic(const Duration(milliseconds: 125), (_) => _fase.value = _agora);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PintorAurora(_fase, widget.cores),
        size: Size.infinite,
      ),
    );
  }
}

class _PintorAurora extends CustomPainter {
  final ValueListenable<double> anim;
  final List<Color> cores;
  _PintorAurora(this.anim, this.cores) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value * 2 * math.pi;
    final w = size.width;
    final h = size.height;
    // Cada mancha percorre uma curva própria (Lissajous) devagar.
    final caminhos = [
      Offset(0.25 + 0.12 * math.sin(t), 0.25 + 0.08 * math.cos(t)),
      Offset(0.75 + 0.10 * math.cos(t + 1.3), 0.35 + 0.10 * math.sin(t + 0.4)),
      Offset(0.5 + 0.15 * math.sin(t + 2.1), 0.8 + 0.06 * math.cos(t + 0.9)),
    ];
    final raios = [0.55, 0.5, 0.6];
    final intensidade = [0.17, 0.14, 0.12]; // suave: sem "ponto de luz" forte
    for (var i = 0; i < 3; i++) {
      final centro = Offset(caminhos[i].dx * w, caminhos[i].dy * h);
      final raio = raios[i] * math.max(w, h) * (0.95 + 0.05 * math.sin(t + i));
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
  bool shouldRepaint(_PintorAurora old) => !listEquals(old.cores, cores);
}
