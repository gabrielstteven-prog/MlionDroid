import 'package:flutter/material.dart';
import 'config_manager.dart';
import 'design/icones.dart';
import 'design/tema.dart';
import 'responsive.dart';
import 'services/news_service.dart';
import 'widgets/tela_noticias.dart';

/// Categorias de notícias do Brasil (G1). Usado também pelas Configurações.
const Map<String, ({String nome, String url, Color cor})> categoriasBrasil = {
  'politica': (
    nome: 'Política',
    url: 'https://g1.globo.com/rss/g1/politica/',
    cor: Color(0xFFFF8A80)
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
      icone: Icons.public_rounded,
      marca: BandeiraBrasil(tamanho: R(context).sp(54)),
      titulo: 'Notícias do Brasil',
      subtitulo: [for (final k in selecionadas) categoriasBrasil[k]!.nome].join(', '),
      destaque: Destaques.brasil,
      velocidadePxSeg: cfg.getInt('brasil', 'duracao_scroll_px_seg', 35),
      pausaFinalSeg: cfg.getInt('brasil', 'pausa_final_seg', 10),
      corDoRotulo: (n) => porRotulo[n.rotulo] ?? Destaques.brasil,
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
    );
  }

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
