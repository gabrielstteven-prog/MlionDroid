import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/assistente_service.dart';
import '../sistema.dart';

/// Emoções do rosto do Jarvis (estilo Stack-chan).
enum Emocao { neutro, feliz, triste, bravo, duvida, surpreso }

Emocao emocaoDeTexto(String? s) => switch ((s ?? '').toLowerCase()) {
      'feliz' || 'alegre' || 'animado' => Emocao.feliz,
      'triste' => Emocao.triste,
      'bravo' || 'irritado' || 'raiva' => Emocao.bravo,
      'duvida' || 'dúvida' || 'pensativo' => Emocao.duvida,
      'surpreso' || 'surpresa' => Emocao.surpreso,
      _ => Emocao.neutro,
    };

/// Rosto do Jarvis: dois olhos e uma boca brancos num visor escuro, no
/// estilo do robô Stack-chan. Está sempre "vivo": pisca, respira e olha para
/// os lados; ouvindo, os olhos crescem com o volume da voz; pensando, olha
/// para cima de lado; falando, a boca mexe. A [emocao] muda olhos e boca.
class RostoJarvis extends StatefulWidget {
  final EstadoAssistente estado;
  final Emocao emocao;
  final double tamanho; // largura do visor
  const RostoJarvis({
    super.key,
    required this.estado,
    this.emocao = Emocao.neutro,
    required this.tamanho,
  });

  @override
  State<RostoJarvis> createState() => _RostoJarvisState();
}

class _RostoJarvisState extends State<RostoJarvis> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(days: 1))..forward();
  final _rnd = math.Random();

  // Piscar e olhar em volta: sorteados para não parecer robótico.
  double _proximaPiscada = 2;
  double _inicioPiscada = -10;
  double _proximoOlhar = 1.5;
  Offset _olharAlvo = Offset.zero;
  Offset _olhar = Offset.zero;
  double _ultimo = 0;

  double get _segundos => _c.lastElapsedDuration == null
      ? 0
      : _c.lastElapsedDuration!.inMilliseconds / 1000.0;

  void _tique() {
    final t = _segundos;
    final dt = (t - _ultimo).clamp(0.0, 0.1);
    _ultimo = t;
    if (t >= _proximaPiscada) {
      _inicioPiscada = t;
      // De vez em quando, piscada dupla.
      _proximaPiscada = t + (_rnd.nextDouble() < 0.2 ? 0.35 : 2.5 + _rnd.nextDouble() * 3.5);
    }
    if (t >= _proximoOlhar) {
      final pensando = widget.estado == EstadoAssistente.pensando;
      _olharAlvo = pensando
          ? Offset(_rnd.nextBool() ? 0.6 : -0.6, -0.7) // olha para cima, de lado
          : (_rnd.nextDouble() < 0.45
              ? Offset.zero // volta a olhar para a pessoa
              : Offset(_rnd.nextDouble() * 1.6 - 0.8, _rnd.nextDouble() * 0.8 - 0.4));
      _proximoOlhar = t + 1.2 + _rnd.nextDouble() * (pensando ? 1.0 : 2.8);
    }
    // Movimento suave até o alvo (olhos "deslizam", não pulam).
    _olhar = Offset.lerp(_olhar, _olharAlvo, (dt * 7).clamp(0.0, 1.0))!;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.tamanho,
        height: widget.tamanho * 0.75,
        child: AnimatedBuilder(
          animation: Listenable.merge([_c, Sistema.volumeVoz]),
          builder: (_, __) {
            _tique();
            final t = _segundos;
            final piscando = (t - _inicioPiscada).clamp(0.0, 0.18);
            final fechado = piscando < 0.18 ? math.sin(piscando / 0.18 * math.pi) : 0.0;
            return CustomPaint(
              painter: _PintorRosto(
                t: t,
                estado: widget.estado,
                emocao: widget.emocao,
                olhar: _olhar,
                piscada: fechado,
                volume: widget.estado == EstadoAssistente.ouvindo ? Sistema.volumeVoz.value : 0,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PintorRosto extends CustomPainter {
  final double t;
  final EstadoAssistente estado;
  final Emocao emocao;
  final Offset olhar; // -1..1
  final double piscada; // 0 aberto .. 1 fechado
  final double volume; // 0..1 (ouvindo)

  _PintorRosto({
    required this.t,
    required this.estado,
    required this.emocao,
    required this.olhar,
    required this.piscada,
    required this.volume,
  });

  static const _branco = Color(0xFFF2F6FF);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final raioVisor = w * 0.16;

    // Visor: vidro escuro com um brilho leve na borda.
    final visor = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(raioVisor));
    canvas.drawRRect(
      visor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1420), Color(0xFF05080E)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      visor.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF7FE3FF).withValues(alpha: 0.25),
    );

    // Respiração: o rosto todo sobe e desce bem pouco.
    final respira = math.sin(t * 2 * math.pi / 3.8) * h * 0.012;
    final olharPx = Offset(olhar.dx * w * 0.07, olhar.dy * h * 0.07);
    final centro = Offset(w / 2, h * 0.46 + respira) + olharPx;

    final distOlhos = w * 0.22;
    var raioOlho = w * 0.072;
    if (emocao == Emocao.surpreso) raioOlho *= 1.3;
    if (estado == EstadoAssistente.ouvindo) raioOlho *= 1.08 + volume * 0.25;

    final paint = Paint()..color = _branco;
    final glow = Paint()
      ..color = _branco.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    for (final lado in [-1, 1]) {
      final c = centro + Offset(lado * distOlhos, 0);
      // Dúvida: um olho um pouco menor.
      final r = emocao == Emocao.duvida && lado == 1 ? raioOlho * 0.75 : raioOlho;
      _olho(canvas, c, r, lado, paint, glow);
    }
    _boca(canvas, centro + Offset(0, h * 0.24), w, paint);
  }

  void _olho(Canvas canvas, Offset c, double r, int lado, Paint paint, Paint glow) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    // Pálpebra (piscar + emoção) recorta o círculo do olho.
    final path = Path()..addOval(rect);
    final corte = Path();
    final topo = c.dy - r;
    final altura = 2 * r;
    // Piscar: fecha de cima para baixo.
    final fechar = piscada;
    switch (emocao) {
      case Emocao.feliz:
        // "^ ^": recorta a metade de baixo (olho sorrindo).
        corte.addRect(Rect.fromLTRB(c.dx - r * 1.5, c.dy + r * 0.15, c.dx + r * 1.5, c.dy + r * 1.5));
      case Emocao.triste:
        // Pálpebra caída para FORA (lado externo mais baixo).
        corte.addPolygon(
            _palpebra(c, r, topo, altura,
                esquerda: lado == -1 ? 0.55 : 0.15, direita: lado == -1 ? 0.15 : 0.55),
            true);
      case Emocao.bravo:
        // Sobrancelha em V: pálpebra caída para DENTRO (lado do nariz).
        corte.addPolygon(
            _palpebra(c, r, topo, altura,
                esquerda: lado == -1 ? 0.1 : 0.6, direita: lado == -1 ? 0.6 : 0.1),
            true);
      case Emocao.duvida:
        corte.addRect(Rect.fromLTRB(c.dx - r * 1.5, topo - r, c.dx + r * 1.5, topo + altura * 0.25));
      case Emocao.neutro:
      case Emocao.surpreso:
        break;
    }
    if (fechar > 0) {
      corte.addRect(Rect.fromLTRB(
          c.dx - r * 1.5, topo - r, c.dx + r * 1.5, topo + altura * (0.08 + 0.9 * fechar)));
    }
    final olho = Path.combine(PathOperation.difference, path, corte);
    canvas.drawPath(olho, glow);
    canvas.drawPath(olho, paint);
    canvas.restore();
  }

  /// Pálpebra inclinada: quadrilátero que corta o topo do olho, com a altura
  /// do corte (fração do olho) em cada lado. Pontos em ordem horária, para o
  /// polígono não "cruzar" sobre si mesmo.
  static List<Offset> _palpebra(Offset c, double r, double topo, double altura,
          {required double esquerda, required double direita}) =>
      [
        Offset(c.dx - r * 1.5, topo - r),
        Offset(c.dx + r * 1.5, topo - r),
        Offset(c.dx + r * 1.5, topo + altura * direita),
        Offset(c.dx - r * 1.5, topo + altura * esquerda),
      ];

  void _boca(Canvas canvas, Offset c, double w, Paint paint) {
    final larg = w * 0.16;
    final traco = Paint()
      ..color = _branco
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.022
      ..strokeCap = StrokeCap.round;

    if (estado == EstadoAssistente.respondendo) {
      // Falando: boca abre e fecha num ritmo irregular, como sílabas.
      final abre = (0.5 + 0.5 * math.sin(t * 14)) * (0.6 + 0.4 * math.sin(t * 5.3 + 1));
      final alt = w * (0.02 + 0.07 * abre);
      final larguraFala = emocao == Emocao.feliz ? larg * 1.1 : larg * 0.9;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: larguraFala, height: alt),
          Radius.circular(alt / 2),
        ),
        paint,
      );
      return;
    }
    switch (emocao) {
      case Emocao.feliz:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - larg / 2, c.dy - w * 0.012)
              ..quadraticBezierTo(c.dx, c.dy + w * 0.05, c.dx + larg / 2, c.dy - w * 0.012),
            traco);
      case Emocao.triste:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - larg / 2, c.dy + w * 0.025)
              ..quadraticBezierTo(c.dx, c.dy - w * 0.035, c.dx + larg / 2, c.dy + w * 0.025),
            traco);
      case Emocao.bravo:
        canvas.drawLine(Offset(c.dx - larg * 0.4, c.dy + w * 0.008),
            Offset(c.dx + larg * 0.4, c.dy - w * 0.008), traco);
      case Emocao.duvida:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - larg * 0.35, c.dy)
              ..quadraticBezierTo(c.dx, c.dy - w * 0.02, c.dx + larg * 0.4, c.dy + w * 0.012),
            traco);
      case Emocao.surpreso:
        canvas.drawOval(
            Rect.fromCenter(center: c, width: w * 0.06, height: w * 0.075), paint);
      case Emocao.neutro:
        canvas.drawLine(
            Offset(c.dx - larg * 0.45, c.dy), Offset(c.dx + larg * 0.45, c.dy), traco);
    }
  }

  @override
  bool shouldRepaint(_PintorRosto old) => true;
}
