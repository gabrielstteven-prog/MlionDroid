import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../responsive.dart';
import '../times.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Padrão visual do MlionDroid — "uma janela da casa".
//
//  Todas as telas ficam sobre o MESMO céu, cuja cor acompanha a hora real
//  do dia. As telas se diferenciam pelo conteúdo e por uma cor de destaque
//  própria — não por fundos, fontes e efeitos diferentes.
//
//  Regras:
//  • Uma família para números/títulos (Bricolage Grotesque) e uma para
//    texto (Figtree). Nada de outras fontes nas telas.
//  • Frases em caixa normal. Sem rótulos EM MAIÚSCULAS espaçados.
//  • Sem brilho neon, sombra ou blur: profundidade só por transparência.
//  • Um elemento principal por tela, grande, legível a 3 metros.
// ═══════════════════════════════════════════════════════════════════════════

/// Cores de texto e sinais (iguais em todas as telas).
class Cores {
  static const texto = Color(0xFFF4F6FA);
  static const textoSecundario = Color(0xFFB9C3D4);
  static const textoApagado = Color(0xFF7F8BA2);

  static const positivo = Color(0xFF6FD6A0);
  static const aviso = Color(0xFFFFB86B);
  static const alerta = Color(0xFFFF7A6B);
  static const chuva = Color(0xFF7CC6FF);

  /// Superfícies: o céu aparece através delas.
  static Color superficie = Colors.white.withValues(alpha: 0.07);
  static Color superficieElevada = Colors.white.withValues(alpha: 0.11);
  static Color contorno = Colors.white.withValues(alpha: 0.10);
}

/// Cor de destaque de cada tela.
class Destaques {
  static const clima = Color(0xFF7CC6FF);
  static const time = Color(0xFFE2C47A);
  static const partida = Color(0xFF6FD6A0);
  static const tabela = Color(0xFF9AD98B);
  static const agenda = Color(0xFF8FB4FF);
  static const compras = Color(0xFF6FD6A0);
  static const brasil = Color(0xFFFFD36B);
  static const regiao = Color(0xFF6FD3E0);
  static const fotos = Color(0xFFE7A3F0);
  static const musica = Color(0xFF1DB954);
  static const bomDia = Color(0xFFFFD36B);
}

/// Cor de destaque de um time. Cores quase brancas ou quase pretas
/// (Corinthians, Santos, Botafogo...) somem sobre o céu — nesses casos
/// usa o dourado padrão de futebol.
Color corDoTime(TimeInfo time) {
  Color c;
  try {
    c = Color(int.parse(time.corDestaque));
  } catch (_) {
    return Destaques.time;
  }
  final l = c.computeLuminance();
  return (l > 0.8 || l < 0.06) ? Destaques.time : c;
}

/// Momentos do dia que definem o céu.
enum Periodo { madrugada, manha, tarde, fimDeTarde, noite }

Periodo periodoDaHora(int hora) {
  if (hora < 5) return Periodo.madrugada;
  if (hora < 12) return Periodo.manha;
  if (hora < 17) return Periodo.tarde;
  if (hora < 19) return Periodo.fimDeTarde;
  return Periodo.noite;
}

/// O céu de cada momento. Todos escuros o bastante para texto claro.
List<Color> coresDoCeu(Periodo p) {
  switch (p) {
    case Periodo.madrugada:
      return const [Color(0xFF0A0F1E), Color(0xFF141C33)];
    case Periodo.manha:
      return const [Color(0xFF1B3756), Color(0xFF35627F)];
    case Periodo.tarde:
      return const [Color(0xFF15404F), Color(0xFF285F63)];
    case Periodo.fimDeTarde:
      return const [Color(0xFF2E2442), Color(0xFF6E3F4E)];
    case Periodo.noite:
      return const [Color(0xFF0E1628), Color(0xFF1B2843)];
  }
}

/// Fundo comum do app. Desenhado UMA vez atrás da barra e de todas as
/// telas; troca de cor suavemente quando muda o período do dia.
class CeuDeFundo extends StatelessWidget {
  final DateTime agora;
  final Widget child;
  const CeuDeFundo({super.key, required this.agora, required this.child});

  @override
  Widget build(BuildContext context) {
    final cores = coresDoCeu(periodoDaHora(agora.hour));
    return AnimatedContainer(
      duration: const Duration(seconds: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: cores,
        ),
      ),
      child: child,
    );
  }
}

/// Escala tipográfica. Tamanhos de referência para um tablet de 10"
/// em paisagem; [R] ajusta para outras telas.
class Tipo {
  final R r;
  Tipo(this.r);
  factory Tipo.de(BuildContext context) => Tipo(R(context));

  TextStyle _display(double size, FontWeight w, Color c, double h) =>
      GoogleFonts.bricolageGrotesque(
          fontSize: r.fs(size), fontWeight: w, color: c, height: h,
          decoration: TextDecoration.none);

  TextStyle _texto(double size, FontWeight w, Color c, double h) =>
      GoogleFonts.figtree(
          fontSize: r.fs(size), fontWeight: w, color: c, height: h,
          decoration: TextDecoration.none);

  /// Número protagonista (temperatura, placar, relógio grande).
  TextStyle heroi({Color cor = Cores.texto}) =>
      _display(104, FontWeight.w300, cor, 0.95);
  TextStyle numero({Color cor = Cores.texto}) =>
      _display(56, FontWeight.w500, cor, 1.0);
  TextStyle titulo({Color cor = Cores.texto}) =>
      _display(34, FontWeight.w600, cor, 1.1);
  TextStyle subtitulo({Color cor = Cores.texto}) =>
      _display(24, FontWeight.w600, cor, 1.2);
  TextStyle corpo({Color cor = Cores.texto, FontWeight peso = FontWeight.w500}) =>
      _texto(20, peso, cor, 1.35);
  TextStyle apoio({Color cor = Cores.textoSecundario, FontWeight peso = FontWeight.w500}) =>
      _texto(16, peso, cor, 1.35);
  TextStyle legenda({Color cor = Cores.textoApagado}) =>
      _texto(14, FontWeight.w500, cor, 1.3);
}

/// Esqueleto comum de todas as telas: título com ícone à esquerda,
/// informação de atualização à direita e o conteúdo abaixo.
class EstruturaTela extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? subtitulo;
  final Color destaque;
  final String? rodapeDireita; // ex.: "Atualizado há 5 min"
  final Widget? acaoDireita;
  final Widget child;
  final EdgeInsets? margem;

  const EstruturaTela({
    super.key,
    required this.icone,
    required this.titulo,
    required this.destaque,
    required this.child,
    this.subtitulo,
    this.rodapeDireita,
    this.acaoDireita,
    this.margem,
  });

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final t = Tipo(r);
    return Padding(
      padding: margem ??
          EdgeInsets.fromLTRB(r.sp(32), r.sp(20), r.sp(32), r.sp(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: r.sp(48),
                height: r.sp(48),
                decoration: BoxDecoration(
                  color: destaque.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(r.sp(14)),
                ),
                child: Icon(icone, color: destaque, size: r.icon(26)),
              ),
              SizedBox(width: r.sp(16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo,
                        style: t.titulo(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitulo != null && subtitulo!.isNotEmpty)
                      Text(subtitulo!,
                          style: t.apoio(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (acaoDireita != null) ...[
                SizedBox(width: r.sp(12)),
                acaoDireita!,
              ],
              if (rodapeDireita != null) ...[
                SizedBox(width: r.sp(16)),
                Text(rodapeDireita!, style: t.legenda()),
              ],
            ],
          ),
          SizedBox(height: r.sp(20)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Área agrupada (lista, tabela, bloco de informação).
class Superficie extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final bool elevada;
  final Color? tinta; // leve tom da cor de destaque
  final double? raio;

  const Superficie({
    super.key,
    required this.child,
    this.padding,
    this.elevada = false,
    this.tinta,
    this.raio,
  });

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Container(
      padding: padding ?? EdgeInsets.all(r.sp(20)),
      decoration: BoxDecoration(
        color: tinta != null
            ? tinta!.withValues(alpha: 0.14)
            : (elevada ? Cores.superficieElevada : Cores.superficie),
        borderRadius: BorderRadius.circular(raio ?? r.sp(24)),
        border: Border.all(color: Cores.contorno),
      ),
      child: child,
    );
  }
}

/// Selo pequeno (categoria, cidade, competição).
class Selo extends StatelessWidget {
  final String texto;
  final Color cor;
  final IconData? icone;
  const Selo(this.texto, {super.key, required this.cor, this.icone});

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(12), vertical: r.sp(5)),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(r.sp(30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: r.icon(16), color: cor),
            SizedBox(width: r.sp(6)),
          ],
          Text(texto, style: Tipo(r).legenda(cor: cor).copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Estado vazio/erro: diz o que aconteceu e o que fazer.
class AvisoTela extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? texto;
  final Color cor;
  const AvisoTela({
    super.key,
    required this.icone,
    required this.titulo,
    this.texto,
    this.cor = Cores.textoSecundario,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tipo.de(context);
    final r = t.r;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: r.sp(620)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: cor, size: r.icon(56)),
            SizedBox(height: r.sp(16)),
            Text(titulo, textAlign: TextAlign.center, style: t.subtitulo()),
            if (texto != null) ...[
              SizedBox(height: r.sp(8)),
              Text(texto!, textAlign: TextAlign.center, style: t.apoio()),
            ],
          ],
        ),
      ),
    );
  }
}

/// Indicador de carregamento padrão.
class Carregando extends StatelessWidget {
  final Color cor;
  const Carregando({super.key, this.cor = Cores.textoSecundario});

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3, color: cor),
        ),
      );
}
