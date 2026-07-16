// ═══════════════════════════════════════════════════════════════════════════════
//  PATCH — barra_info.dart
//
//  Mudanças necessárias:
//
//  1. Adicionar import do SpotifyManager no topo:
//       import 'tela_spotify.dart';
//
//  2. Adicionar tema para 'spotify' no Map _temas:
//       'spotify': _TelaTheme(
//           acento: Color(0xFF1DB954),
//           fundo: Color(0xFF0a1a0a),
//           icone: Icons.music_note_rounded,
//           label: 'Spotify'),
//
//  3. Substituir o método _ticker() pelo novo abaixo que mostra
//     o ícone redondo do álbum + título rolando quando Spotify estiver tocando.
//
// ═══════════════════════════════════════════════════════════════════════════════
//
//  MÉTODO _ticker ATUALIZADO — substitua o existente por este:
//
/*
  Widget _ticker(InfoHub hub, R r, Color acento) {
    final spotify = SpotifyManager.instance;
    final spotifyAtivo = hub.spotifyTocando;

    // ── Quando Spotify estiver ativo: mini-disco + texto rolando ─────────────
    if (spotifyAtivo) {
      final bytes = spotify.albumArtBytes;
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1DB954).withValues(alpha: 0.08),
          border: Border(
            top: BorderSide(
                color: const Color(0xFF1DB954).withValues(alpha: 0.30),
                width: 1),
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: r.sp(10)),
            // ── Ícone redondo do álbum ─────────────────────────────────────
            Container(
              width: r.sp(32),
              height: r.sp(32),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFF1DB954).withValues(alpha: 0.6),
                    width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1DB954).withValues(alpha: 0.25),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: ClipOval(
                child: bytes != null
                    ? Image.memory(bytes!,
                        fit: BoxFit.cover, gaplessPlayback: true)
                    : Container(
                        color: const Color(0xFF1a1a2e),
                        child: Icon(Icons.music_note_rounded,
                            color: const Color(0xFF1DB954),
                            size: r.icon(16)),
                      ),
              ),
            ),
            SizedBox(width: r.sp(10)),
            // Separador
            Container(
                width: 1,
                height: r.sp(18),
                color: const Color(0xFF1DB954).withValues(alpha: 0.30)),
            SizedBox(width: r.sp(10)),
            // ── Texto rolando ─────────────────────────────────────────────
            Expanded(
              child: _MarqueeText(
                key: ValueKey(hub.tickerSpotify),
                text: hub.tickerSpotify,
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: r.fs(r.isCompact ? 12 : 14),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            // Logo Spotify pequeno
            Padding(
              padding: EdgeInsets.symmetric(horizontal: r.sp(10)),
              child: Image.asset(
                'assets/icons/spotify_logo.png',
                width: r.icon(18),
                height: r.icon(18),
              ),
            ),
          ],
        ),
      );
    }

    // ── Comportamento normal (frases / notícias) ───────────────────────────
    final isFrase = hub.tickerAtual.startsWith('💡');
    final icone =
        isFrase ? Icons.format_quote_rounded : Icons.newspaper_rounded;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: acento.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(color: acento.withValues(alpha: 0.20), width: 1),
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.sp(14)),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Icon(icone,
                  key: ValueKey(icone),
                  color: acento.withValues(alpha: 0.85),
                  size: r.icon(19)),
            ),
          ),
          Container(
              width: 1,
              height: r.sp(18),
              color: acento.withValues(alpha: 0.25)),
          SizedBox(width: r.sp(10)),
          Expanded(
            child: _MarqueeText(
              key: ValueKey(hub.tickerAtual),
              text: hub.tickerAtual,
              style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: r.fs(r.isCompact ? 12 : 14),
                fontWeight: FontWeight.w400,
                letterSpacing: 0.2,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          SizedBox(width: r.sp(14)),
        ],
      ),
    );
  }
*/
// ═══════════════════════════════════════════════════════════════════════════════
// Nota: o arquivo barra_info.dart completo NÃO é reproduzido aqui para evitar
// duplicação. Aplique apenas as 3 mudanças listadas acima no arquivo original.
// ═══════════════════════════════════════════════════════════════════════════════
