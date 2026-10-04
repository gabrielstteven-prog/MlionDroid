import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design/icones.dart';
import 'info_hub.dart';
import 'responsive.dart';
import 'services/weather_service.dart';
import 'util.dart';

/// Modo Noite: relógio de cabeceira. Fundo preto com um brilho de lua bem
/// fraco, números finos e cores âmbar quentes (sem luz azul de madrugada).
///
/// O conjunto muda de posição devagar a cada minuto, para não "marcar"
/// telas com a mesma imagem parada a noite toda.
/// Tocar na tela (ou dizer "Hey Jarvis") acorda o painel.
class TelaNoite extends StatelessWidget {
  final VoidCallback aoTocar;

  /// Descanso da tela: tudo preto (a luz de fundo também é desligada).
  final bool apagada;
  const TelaNoite({super.key, required this.aoTocar, this.apagada = false});

  // Âmbar quente: legível no escuro sem ofuscar nem tirar o sono.
  static const _ambar = Color(0xFFD9B98C);

  @override
  Widget build(BuildContext context) {
    if (apagada) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: aoTocar,
        child: const ColoredBox(color: Colors.black, child: SizedBox.expand()),
      );
    }
    final r = R(context);
    // Material transparente: sem ele os textos ganham o sublinhado amarelo
    // de "texto sem estilo" do Flutter (esta tela fica fora da moldura).
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: aoTocar,
        child: ValueListenableBuilder<DateTime>(
          valueListenable: InfoHub.instance.relogio,
          builder: (context, agora, _) {
            // Posição "andando" num ciclo de 20 minutos.
            final fase = (agora.minute % 20) / 20.0;
            final alinhamento = Alignment(
              -0.35 + fase * 0.7,
              (agora.minute % 10) < 5 ? -0.15 : 0.15,
            );
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                gradient: RadialGradient(
                  center: Alignment(0.8 - fase * 0.4, -0.9),
                  radius: 1.3,
                  colors: const [Color(0xFF1A1610), Color(0xFF070605), Colors.black],
                  stops: const [0, 0.45, 1],
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(seconds: 20),
                curve: Curves.easeInOut,
                alignment: alinhamento,
                child: _conteudo(r, agora),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _conteudo(R r, DateTime agora) {
    final clima = WeatherService.instance.atual;
    final amanha = clima != null && clima.proximosDias.isNotEmpty
        ? clima.proximosDias.first
        : null;
    final h = doisDigitos(agora.hour);
    final m = doisDigitos(agora.minute);
    final numero = GoogleFonts.bricolageGrotesque(
      color: _ambar.withValues(alpha: 0.85),
      fontSize: r.fs(190),
      fontWeight: FontWeight.w200,
      height: 1,
      letterSpacing: -2,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(h, style: numero),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: r.sp(10)),
              child: Text(':', style: numero.copyWith(color: _ambar.withValues(alpha: 0.35))),
            ),
            Text(m, style: numero),
          ],
        ),
        SizedBox(height: r.sp(14)),
        Text(
          '${diaSemanaLongo(agora)}, ${agora.day} de ${mesesLongos[agora.month - 1]}'
              .toUpperCase(),
          style: GoogleFonts.figtree(
            color: _ambar.withValues(alpha: 0.45),
            fontSize: r.fs(20),
            fontWeight: FontWeight.w600,
            letterSpacing: 5,
          ),
        ),
        if (clima != null) ...[
          SizedBox(height: r.sp(40)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: 0.7,
                child: IconeClima(
                    codigo: clima.codigo, ehDia: clima.ehDia, tamanho: r.icon(44), animar: false),
              ),
              SizedBox(width: r.sp(12)),
              Text('${clima.temp}°',
                  style: GoogleFonts.figtree(
                      color: _ambar.withValues(alpha: 0.7),
                      fontSize: r.fs(30),
                      fontWeight: FontWeight.w300)),
              if (amanha != null) ...[
                Container(
                  width: 1,
                  height: r.sp(28),
                  margin: EdgeInsets.symmetric(horizontal: r.sp(20)),
                  color: _ambar.withValues(alpha: 0.2),
                ),
                Text(
                  'Amanhã ${amanha.min}° a ${amanha.max}°'
                  '${amanha.chanceChuva >= 40 ? ', chuva ${amanha.chanceChuva}%' : ''}',
                  style: GoogleFonts.figtree(
                      color: _ambar.withValues(alpha: 0.55), fontSize: r.fs(22)),
                ),
              ],
            ],
          ),
        ],
        SizedBox(height: r.sp(56)),
        Text(
          'Toque ou diga "Hey Jarvis"',
          style: GoogleFonts.figtree(
              color: _ambar.withValues(alpha: 0.18), fontSize: r.fs(15), letterSpacing: 1),
        ),
      ],
    );
  }
}
