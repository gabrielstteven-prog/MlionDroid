import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'info_hub.dart';
import 'services/weather_service.dart';
import 'util.dart';

/// Modo Noite: relógio grande e escuro, sem animações, no horário
/// configurado (padrão 23h–6h). O brilho da tela também é reduzido.
///
/// O relógio muda de posição a cada minuto, devagar, para não "marcar"
/// telas OLED/AMOLED com a mesma imagem parada a noite toda.
/// Tocar na tela acorda o painel por 10 minutos.
class TelaNoite extends StatelessWidget {
  final VoidCallback aoTocar;
  const TelaNoite({super.key, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: aoTocar,
      child: ColoredBox(
        color: Colors.black,
        child: ValueListenableBuilder<DateTime>(
          valueListenable: InfoHub.instance.relogio,
          builder: (context, agora, _) {
            // Posição "andando" num ciclo de 20 minutos.
            final fase = (agora.minute % 20) / 20.0;
            final alinhamento = Alignment(
              -0.5 + fase * 1.0,
              (agora.minute % 10) < 5 ? -0.2 : 0.2,
            );
            final clima = WeatherService.instance.atual;
            const cor = Color(0xFF7A8BA8);
            return AnimatedAlign(
              duration: const Duration(seconds: 20),
              curve: Curves.easeInOut,
              alignment: alinhamento,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    horaMinuto(agora),
                    style: GoogleFonts.orbitron(
                      color: cor,
                      fontSize: 120,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${diaSemanaLongo(agora)}, ${agora.day} de '
                    '${mesesLongos[agora.month - 1]}',
                    style: GoogleFonts.poppins(
                        color: cor.withValues(alpha: 0.7), fontSize: 22),
                  ),
                  if (clima != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      '${emojiClima(clima.codigo, ehDia: clima.ehDia)}  '
                      '${clima.temp}°C  •  amanhã '
                      '${clima.proximosDias.isNotEmpty ? '${clima.proximosDias.first.min}° / ${clima.proximosDias.first.max}°' : '--'}',
                      style: GoogleFonts.poppins(
                          color: cor.withValues(alpha: 0.6), fontSize: 20),
                    ),
                  ],
                  const SizedBox(height: 30),
                  Text(
                    'Toque para acordar o painel',
                    style: GoogleFonts.poppins(
                        color: cor.withValues(alpha: 0.25), fontSize: 13),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
