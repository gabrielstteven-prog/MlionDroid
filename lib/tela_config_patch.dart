// ═══════════════════════════════════════════════════════════════════════════════
//  PATCH — tela_config.dart
//  Adicionar categoria '🎵 Spotify' no menu de configurações
// ═══════════════════════════════════════════════════════════════════════════════
//
//  1. No Map _categoriaLabels, adicione ANTES de 'barra_info':
//       'spotify': '🎵 Spotify',
//
//  2. No switch/if que constrói o conteúdo de cada categoria (_buildCategoria
//     ou equivalente), adicione o case 'spotify' chamando _buildSpotify().
//     Se o seu arquivo usar um Map _camposPorCategoria, adicione também:
//
//  3. Adicione o método _buildSpotify() abaixo na classe _TelaConfigState.
//
// ═══════════════════════════════════════════════════════════════════════════════
//
//  MÉTODO _buildSpotify — cole dentro da classe _TelaConfigState:

/*
  Widget _buildSpotify() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Conexão com Spotify'),
        const SizedBox(height: 16),

        // ── Instruções ──────────────────────────────────────────────────────
        _glassCard(children: [
          Row(children: [
            const Icon(Icons.info_outline, color: Color(0xFF1DB954), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Para conectar, crie um app em '
                'developer.spotify.com/dashboard.\n'
                'Cole o Client ID abaixo e adicione '
                '"mliondroid://callback" como Redirect URI.',
                style: GoogleFonts.rajdhani(
                    color: Colors.white70, fontSize: 14, height: 1.5),
              ),
            ),
          ]),
        ]),
        const SizedBox(height: 16),

        // ── Client ID ────────────────────────────────────────────────────────
        _glassCard(children: [
          _textFieldConfig(
            'spotify', 'client_id',
            'Client ID',
            'Cole aqui o Client ID do seu app Spotify',
            Icons.vpn_key_rounded,
          ),
          const SizedBox(height: 8),
          _textFieldConfig(
            'spotify', 'redirect_uri',
            'Redirect URI',
            'mliondroid://callback',
            Icons.link_rounded,
          ),
        ]),
        const SizedBox(height: 16),

        // ── Comportamento ────────────────────────────────────────────────────
        _sectionTitle('Comportamento'),
        const SizedBox(height: 12),
        _glassCard(children: [
          _sliderInt(
            'spotify', 'duracao_tela_seg',
            'Tempo na tela ao trocar música',
            config.getInt('spotify', 'duracao_tela_seg', 30),
            10, 90,
            unidade: 'seg',
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Aparecer na rotação automática',
                  style: GoogleFonts.rajdhani(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              Switch(
                value: config.getBool('spotify', 'aparecer_na_rotacao', true),
                activeColor: const Color(0xFF1DB954),
                onChanged: (v) {
                  setState(() {
                    config.set('spotify', 'aparecer_na_rotacao', v);
                    // Atualiza telas_ativas
                    final ativas = config.getStringList('geral', 'telas_ativas');
                    if (v && !ativas.contains('spotify')) {
                      ativas.add('spotify');
                    } else if (!v) {
                      ativas.remove('spotify');
                    }
                    config.set('geral', 'telas_ativas', ativas);
                  });
                },
              ),
            ],
          ),
        ]),
      ],
    );
  }
*/

// ═══════════════════════════════════════════════════════════════════════════════
//  ONDE CHAMAR _buildSpotify()
//
//  Procure no seu arquivo tela_config.dart o método que renderiza o conteúdo
//  da categoria selecionada. Geralmente é um switch ou if-else em _buildCategoria.
//  Adicione:
//
//    case 'spotify':
//      return _buildSpotify();
//
//  E no Map _categoriaLabels:
//    'spotify': '🎵 Spotify',
// ═══════════════════════════════════════════════════════════════════════════════
