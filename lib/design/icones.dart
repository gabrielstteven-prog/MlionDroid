import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'tema.dart';
import 'package:lottie/lottie.dart';

import '../performance_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Ícones "de verdade" do painel: clima animado e marcas reconhecíveis à
//  distância (bandeira do Brasil, Google Agenda, Spotify) no lugar de
//  emojis e ícones genéricos.
// ─────────────────────────────────────────────────────────────────────────────

/// Animação de clima por código WMO, respeitando dia/noite.
String animacaoClima(int code, bool ehDia) {
  if (code <= 1) return ehDia ? 'assets/weather/sunny.json' : 'assets/weather/night.json';
  if (code <= 3) return 'assets/weather/cloudy.json';
  if (code <= 48) return 'assets/weather/fog.json';
  if (code >= 95) return 'assets/weather/storm.json';
  if (code <= 67 || (code >= 80 && code <= 82)) return 'assets/weather/rain.json';
  return 'assets/weather/cloudy.json';
}

class IconeClima extends StatelessWidget {
  final int codigo;
  final bool ehDia;
  final double tamanho;
  final bool animar;
  const IconeClima({
    super.key,
    required this.codigo,
    required this.tamanho,
    this.ehDia = true,
    this.animar = true,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Lottie.asset(
        animacaoClima(codigo, ehDia),
        width: tamanho,
        height: tamanho,
        fit: BoxFit.contain,
        animate: animar && PerformanceManager.instance.animacoesDecorativasAtivas,
      ),
    );
  }
}

/// Bandeira do Brasil desenhada (sem depender de emoji do sistema).
class BandeiraBrasil extends StatelessWidget {
  final double tamanho; // largura
  const BandeiraBrasil({super.key, required this.tamanho});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(tamanho * 0.12),
        child: CustomPaint(size: Size(tamanho, tamanho * 0.7), painter: _BandeiraPainter()),
      );
}

class _BandeiraPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF009C3B));
    final w = s.width, h = s.height, m = w * 0.085;
    final losango = Path()
      ..moveTo(w / 2, m)
      ..lineTo(w - m, h / 2)
      ..lineTo(w / 2, h - m)
      ..lineTo(m, h / 2)
      ..close();
    c.drawPath(losango, Paint()..color = const Color(0xFFFFDF00));
    final centro = Offset(w / 2, h / 2);
    final raio = h * 0.25;
    c.drawCircle(centro, raio, Paint()..color = const Color(0xFF002776));
    // Faixa branca curva
    final faixa = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = raio * 0.18;
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: centro, radius: raio)));
    c.drawArc(Rect.fromCircle(center: centro.translate(-raio * 0.2, raio * 1.6), radius: raio * 2.2),
        -2.1, 0.9, false, faixa);
    c.restore();
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Ícone do Google Agenda com o dia de hoje (como no celular).
class IconeGoogleAgenda extends StatelessWidget {
  final double tamanho;
  final int dia;
  const IconeGoogleAgenda({super.key, required this.tamanho, required this.dia});

  @override
  Widget build(BuildContext context) {
    final t = tamanho;
    final borda = t * 0.2;
    return SizedBox(
      width: t,
      height: t,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t * 0.16),
        child: Stack(children: [
          // Moldura nas cores do Google
          const Positioned.fill(child: ColoredBox(color: Color(0xFF4285F4))),
          Positioned(right: 0, top: 0, bottom: borda, width: borda,
              child: const ColoredBox(color: Color(0xFFFBBC04))),
          Positioned(left: 0, right: borda, bottom: 0, height: borda,
              child: const ColoredBox(color: Color(0xFF34A853))),
          Positioned(right: 0, bottom: 0, width: borda, height: borda,
              child: const ColoredBox(color: Color(0xFFEA4335))),
          Positioned(
            left: borda,
            top: borda,
            right: borda,
            bottom: borda,
            child: ColoredBox(
              color: Colors.white,
              child: Center(
                child: Text('$dia',
                    style: Tipo.texto(TextStyle(
                        color: const Color(0xFF1A73E8),
                        fontWeight: FontWeight.w800,
                        fontSize: t * 0.38,
                        height: 1,
                        decoration: TextDecoration.none))),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class IconeSpotify extends StatelessWidget {
  final double tamanho;
  const IconeSpotify({super.key, required this.tamanho});

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/icons/Spotify.png', width: tamanho, height: tamanho);
}

/// Logo da competição. As principais vêm dentro do app (assets/competicoes,
/// versão para fundo escuro); uma competição nova é baixada da ESPN uma
/// vez e fica guardada no aparelho (cache de imagens).
class LogoCompeticao extends StatelessWidget {
  final String slug;
  final String logoId;
  final double tamanho;
  const LogoCompeticao({
    super.key,
    required this.slug,
    required this.logoId,
    required this.tamanho,
  });

  static const _internos = {
    'bra.1', 'bra.2', 'bra.camp.carioca', 'bra.camp.paulista',
    'bra.copa_do_brazil', 'conmebol.libertadores', 'conmebol.recopa',
    'conmebol.sudamericana', 'fifa.cwc',
  };

  @override
  Widget build(BuildContext context) {
    final reserva = Icon(Icons.emoji_events_rounded,
        color: const Color(0xFFE2C47A), size: tamanho * 0.7);
    if (_internos.contains(slug)) {
      return Image.asset('assets/competicoes/$slug.png',
          width: tamanho, height: tamanho, errorBuilder: (_, __, ___) => reserva);
    }
    if (logoId.isEmpty) return SizedBox(width: tamanho, height: tamanho, child: reserva);
    return CachedNetworkImage(
      imageUrl: 'https://a.espncdn.com/i/leaguelogos/soccer/500-dark/$logoId.png',
      width: tamanho,
      height: tamanho,
      errorWidget: (_, __, ___) => reserva,
    );
  }
}
