import 'package:flutter/material.dart';

import '../design/tema.dart';
import '../services/assistente_service.dart';

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
    final (icone, status) = switch (a.estado) {
      EstadoAssistente.ouvindo => (Icons.mic_rounded, 'Ouvindo...'),
      EstadoAssistente.pensando => (Icons.more_horiz_rounded, 'Um instante...'),
      _ => (Icons.graphic_eq_rounded, ''),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: a.fechar,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // toque no balão não fecha
            child: Container(
              margin: EdgeInsets.all(r.sp(32)),
              padding: EdgeInsets.all(r.sp(28)),
              constraints: BoxConstraints(maxWidth: r.sp(900)),
              decoration: BoxDecoration(
                color: const Color(0xFF16213A),
                borderRadius: BorderRadius.circular(r.sp(32)),
                border: Border.all(color: Cores.contorno),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: r.sp(56),
                    height: r.sp(56),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Cores.chuva,
                    ),
                    child: Icon(icone, color: Colors.black, size: r.icon(30)),
                  ),
                  SizedBox(width: r.sp(20)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (a.ultimaFala.isNotEmpty)
                          Text('“${a.ultimaFala}”', style: t.apoio()),
                        if (status.isNotEmpty) ...[
                          SizedBox(height: r.sp(6)),
                          Text(status, style: t.subtitulo()),
                        ],
                        if (a.ultimaResposta.isNotEmpty) ...[
                          SizedBox(height: r.sp(8)),
                          Text(a.ultimaResposta, style: t.subtitulo()),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
              Icon(Icons.alarm_on_rounded, color: Cores.aviso, size: r.icon(96)),
              SizedBox(height: r.sp(16)),
              Text('Temporizador de ${t.rotulo} terminou',
                  textAlign: TextAlign.center, style: tipo.titulo()),
              SizedBox(height: r.sp(12)),
              Text('Toque em qualquer lugar para parar o alarme', style: tipo.corpo(cor: Cores.textoSecundario)),
            ],
          ),
        ),
      ),
    );
  }
}
