import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config_manager.dart';
import 'services/news_service.dart';
import 'widgets/tela_noticias.dart';

/// Categorias de notícias do Brasil (G1). Usado também pelas Configurações.
const Map<String, ({String nome, String url, Color cor})> categoriasBrasil = {
  'politica': (
    nome: 'Política',
    url: 'https://g1.globo.com/rss/g1/politica/',
    cor: Color(0xFFEF5350)
  ),
  'economia': (
    nome: 'Economia',
    url: 'https://g1.globo.com/rss/g1/economia/',
    cor: Color(0xFF66BB6A)
  ),
  'tecnologia': (
    nome: 'Tecnologia',
    url: 'https://g1.globo.com/rss/g1/tecnologia/',
    cor: Color(0xFF00D4FF)
  ),
  'saude': (
    nome: 'Saúde',
    url: 'https://g1.globo.com/rss/g1/saude/',
    cor: Color(0xFFEC407A)
  ),
  'geral': (
    nome: 'Geral',
    url: 'https://g1.globo.com/rss/g1/',
    cor: Color(0xFFFFB300)
  ),
};

class TelaBrasil extends StatelessWidget {
  final VoidCallback aoTerminar;
  const TelaBrasil({super.key, required this.aoTerminar});

  List<String> _selecionadas(ConfigManager cfg) {
    final sel = cfg
        .getStringList('brasil', 'categorias_selecionadas')
        .where(categoriasBrasil.containsKey)
        .toList();
    return sel.isEmpty ? categoriasBrasil.keys.toList() : sel;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ConfigManager();
    final selecionadas = _selecionadas(cfg);
    final porRotulo = {
      for (final c in categoriasBrasil.values) c.nome: c.cor,
    };

    return TelaNoticias(
      aoTerminar: aoTerminar,
      corDestaque: const Color(0xFFFFB300),
      tituloLeitor: 'G1 — BRASIL',
      velocidadePxSeg: cfg.getInt('brasil', 'duracao_scroll_px_seg', 35),
      pausaFinalSeg: cfg.getInt('brasil', 'pausa_final_seg', 10),
      corDoRotulo: (n) => porRotulo[n.rotulo] ?? const Color(0xFFFFB300),
      fundo: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0a1628), Color(0xFF060910)],
      ),
      carregar: () async {
        final fontes = [
          for (final k in selecionadas)
            FonteRss(categoriasBrasil[k]!.url, categoriasBrasil[k]!.nome),
        ];
        final r = await NewsService.instance.buscar(
          fontes,
          validade: cfg.getIntervaloAtualizacao('brasil'),
          porFonte: cfg.getInt('brasil', 'qtd_noticias', 3).clamp(1, 15),
        );
        // Intercala as categorias (em vez de embaralhar a cada visita),
        // para a ordem ser previsível e variada.
        return (noticias: _intercalar(r.noticias), atualizadoEm: r.atualizadoEm);
      },
      cabecalho: (context, r, manual) => Padding(
        padding: EdgeInsets.fromLTRB(r.sp(32), r.sp(24), r.sp(32), r.sp(10)),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🇧🇷', style: TextStyle(fontSize: r.fs(38))),
                const SizedBox(width: 16),
                Text('BRASIL',
                    style: GoogleFonts.rajdhani(
                        color: Colors.white,
                        fontSize: r.fs(40),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final k in selecionadas)
                  _chip(categoriasBrasil[k]!.nome, categoriasBrasil[k]!.cor, r.fs(13)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 1.5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
                  Color(0xFF009C3B),
                  Color(0xFFFFDF00),
                  Color(0xFF002776),
                ]),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  static Widget _chip(String texto, Color cor, double fs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cor.withValues(alpha: 0.3)),
        ),
        child: Text(texto,
            style: GoogleFonts.rajdhani(
                color: cor, fontSize: fs, fontWeight: FontWeight.w700)),
      );

  /// [A1, A2, B1, B2, C1] → [A1, B1, C1, A2, B2]
  static List<Noticia> _intercalar(List<Noticia> lista) {
    final grupos = <String, List<Noticia>>{};
    for (final n in lista) {
      grupos.putIfAbsent(n.rotulo, () => []).add(n);
    }
    final resultado = <Noticia>[];
    var i = 0;
    while (resultado.length < lista.length) {
      for (final g in grupos.values) {
        if (i < g.length) resultado.add(g[i]);
      }
      i++;
    }
    return resultado;
  }
}
