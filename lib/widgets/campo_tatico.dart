import 'package:flutter/material.dart';

import '../design/tema.dart';
import '../responsive.dart';
import '../services/football_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Campinho com o esquema tático (3-4-2-1, 4-3-3...): goleiro embaixo,
//  ataque em cima, cada jogador na sua linha e no seu lado do campo.
// ═══════════════════════════════════════════════════════════════════════════

/// Quão "à frente" joga cada posição da ESPN (0 = goleiro).
double _profundidade(String pos) {
  final p = pos.toUpperCase();
  if (p == 'G' || p == 'GK') return 0;
  if (p.startsWith('CD') || p == 'LB' || p == 'RB' || p == 'SW' || p == 'D') return 1;
  if (p.contains('WB')) return 1.5;
  if (p.startsWith('DM')) return 2;
  if (p.startsWith('CM') || p == 'LM' || p == 'RM' || p == 'M') return 3;
  if (p.startsWith('AM')) return 4;
  if (p == 'LW' || p == 'RW' || p == 'LF' || p == 'RF' || p.startsWith('CF-')) return 5;
  if (p == 'F' || p == 'CF' || p == 'ST' || p == 'FW') return 6;
  return 3;
}

/// Lado do campo: negativo = esquerda, positivo = direita.
double _lado(String pos) {
  final p = pos.toUpperCase();
  if (p.endsWith('-L')) return -1;
  if (p.endsWith('-R')) return 1;
  if (p.startsWith('L')) return -2;
  if (p.startsWith('R')) return 2;
  return 0;
}

/// Linhas do campo, do goleiro ao ataque; em cada linha, da esquerda para a
/// direita. Segue a formação ("3-4-2-1"); se ela não bater com os jogadores,
/// agrupa por posição. Função pura — testada.
List<List<Jogador>> linhasDoEsquema(String formacao, List<Jogador> titulares) {
  final ordenados = [...titulares]
    ..sort((a, b) => _profundidade(a.posicao).compareTo(_profundidade(b.posicao)));
  final goleiros = ordenados.where((j) => _profundidade(j.posicao) == 0).take(1).toList();
  final resto = ordenados.where((j) => !goleiros.contains(j)).toList();
  final numeros = formacao
      .split('-')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();
  final linhas = <List<Jogador>>[if (goleiros.isNotEmpty) goleiros];
  if (numeros.isNotEmpty && numeros.fold(0, (a, b) => a + b) == resto.length) {
    var i = 0;
    for (final n in numeros) {
      linhas.add(resto.sublist(i, i + n));
      i += n;
    }
  } else {
    // Sem formação confiável: uma linha por "profundidade".
    for (final j in resto) {
      if (linhas.length > goleiros.length &&
          _profundidade(linhas.last.first.posicao) == _profundidade(j.posicao)) {
        linhas.last.add(j);
      } else {
        linhas.add([j]);
      }
    }
  }
  for (final l in linhas) {
    l.sort((a, b) => _lado(a.posicao).compareTo(_lado(b.posicao)));
  }
  return linhas;
}

/// "417505" → Color. Vazio ou inválido → [padrao].
Color corHex(String hex, Color padrao) {
  final v = int.tryParse(hex.replaceAll('#', ''), radix: 16);
  if (v == null || hex.replaceAll('#', '').length != 6) return padrao;
  return Color(0xFF000000 | v);
}

class CampoTatico extends StatelessWidget {
  final Escalacao escalacao;
  final Color cor;
  const CampoTatico({super.key, required this.escalacao, required this.cor});

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final t = Tipo(r);
    final linhas = linhasDoEsquema(escalacao.formacao, escalacao.titulares);
    // Time verde (Palmeiras) some no gramado: camisa branca com número na
    // cor do time. Nos outros, camisa na cor do time.
    final verde = cor.g > cor.r * 1.2 && cor.g > cor.b * 1.2;
    final fundo = verde ? Colors.white : cor;
    final corNumero = verde ? cor : (cor.computeLuminance() > 0.5 ? Colors.black : Colors.white);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      final bola = (h / (linhas.length + 1) * 0.52).clamp(24.0, r.sp(58));
      return ClipRRect(
        borderRadius: BorderRadius.circular(r.sp(20)),
        child: CustomPaint(
          painter: _Gramado(),
          child: Stack(children: [
            for (var li = 0; li < linhas.length; li++)
              for (var ji = 0; ji < linhas[li].length; ji++)
                Builder(builder: (_) {
                  // Cada jogador ganha uma "vaga" da largura da linha: o nome
                  // diminui sozinho se não couber (nada de nomes encostados).
                  final n = linhas[li].length;
                  final vaga = (w / (n + 0.4)).clamp(0.0, r.sp(170));
                  return Positioned(
                    // Goleiro embaixo; cada linha sobe; jogadores espalhados.
                    left: w * (ji + 1) / (n + 1) - vaga / 2,
                    top: h * (1 - (li + 0.6) / (linhas.length + 0.2)) - bola / 2,
                    width: vaga,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: bola,
                          height: bola,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: fundo,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: verde ? cor : Colors.white.withValues(alpha: 0.9),
                                width: 2.5),
                            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                          ),
                          child: Text(linhas[li][ji].camisa,
                              style: t.legenda(cor: corNumero).copyWith(
                                  fontWeight: FontWeight.w900, fontSize: bola * 0.44)),
                        ),
                        SizedBox(height: r.sp(4)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            linhas[li][ji].nome,
                            maxLines: 1,
                            style: t.legenda(cor: Colors.white).copyWith(
                                fontWeight: FontWeight.w700,
                                shadows: const [Shadow(color: Colors.black, blurRadius: 5)]),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
          ]),
        ),
      );
    });
  }
}

/// Gramado com listras e as linhas do campo (meio-campo e as duas áreas).
class _Gramado extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    const faixas = 8;
    for (var i = 0; i < faixas; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, s.height * i / faixas, s.width, s.height / faixas),
        Paint()..color = i.isEven ? const Color(0xFF1B5E20) : const Color(0xFF1F6B25),
      );
    }
    final linha = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final m = s.width * 0.04;
    canvas.drawRect(Rect.fromLTWH(m, m, s.width - 2 * m, s.height - 2 * m), linha);
    // Meio-campo (em cima: o campo mostra só o lado de quem ataca).
    canvas.drawLine(Offset(m, m), Offset(s.width - m, m), linha);
    canvas.drawArc(Rect.fromCircle(center: Offset(s.width / 2, m), radius: s.width * 0.14), 0,
        3.1416, false, linha);
    // Grande área e pequena área embaixo.
    final ga = Rect.fromLTWH(s.width * 0.2, s.height - m - s.height * 0.17, s.width * 0.6,
        s.height * 0.17);
    canvas.drawRect(ga, linha);
    canvas.drawRect(
        Rect.fromLTWH(s.width * 0.36, s.height - m - s.height * 0.07, s.width * 0.28,
            s.height * 0.07),
        linha);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
