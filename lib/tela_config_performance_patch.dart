// ═══════════════════════════════════════════════════════════════════════════════
//  PATCH — tela_config.dart
//  Adicionar categoria '⚡ Performance' no menu de configurações
// ═══════════════════════════════════════════════════════════════════════════════
//
//  1. Adicionar import no topo:
//       import 'performance_manager.dart';
//
//  2. No Map _categoriaLabels, adicione (ordem sugerida: perto do fim,
//     antes ou depois de 'barra_info'):
//       'performance': '⚡ Performance',
//
//  3. No switch/if que constrói o conteúdo de cada categoria, adicione:
//       case 'performance':
//         return _buildPerformance();
//
//  4. Adicione o método _buildPerformance() abaixo na classe _TelaConfigState.
// ═══════════════════════════════════════════════════════════════════════════════
//
//  MÉTODO _buildPerformance — cole dentro da classe _TelaConfigState:

/*
  Widget _buildPerformance() {
    final perf = PerformanceManager.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Desempenho do aparelho'),
        const SizedBox(height: 16),

        // ── Explicação ──────────────────────────────────────────────────────
        _glassCard(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  color: Colors.amberAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Se o app estiver travando, com engasgos ou lento neste '
                  'tablet, ative o Modo Econômico. Ele reduz efeitos visuais '
                  'pesados (desfoque, animações contínuas) mantendo o '
                  'app funcional e bonito, só mais leve.\n\n'
                  'Em tablets modernos e potentes, deixe desligado para '
                  'aproveitar o visual completo.',
                  style: GoogleFonts.rajdhani(
                      color: Colors.white70, fontSize: 14, height: 1.5),
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),

        // ── Switch principal ────────────────────────────────────────────────
        _glassCard(children: [
          AnimatedBuilder(
            animation: perf,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          perf.modoEconomico
                              ? Icons.battery_saver_rounded
                              : Icons.auto_awesome_rounded,
                          color: perf.modoEconomico
                              ? Colors.amberAccent
                              : Colors.cyanAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            perf.modoEconomico
                                ? 'Modo Econômico (tablet fraco)'
                                : 'Visual completo (tablet top)',
                            style: GoogleFonts.rajdhani(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: perf.modoEconomico,
                    activeColor: Colors.amberAccent,
                    onChanged: (v) => perf.definirModoEconomico(v),
                  ),
                ],
              );
            },
          ),
        ]),
      ],
    );
  }
*/
// ═══════════════════════════════════════════════════════════════════════════════
