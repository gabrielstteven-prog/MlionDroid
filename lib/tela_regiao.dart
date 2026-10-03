import 'package:flutter/material.dart';
import 'config_manager.dart';
import 'design/tema.dart';
import 'services/news_service.dart';
import 'widgets/tela_noticias.dart';

/// Cidades da região (feed G1 Campinas e Região). Usado também pelas
/// Configurações. `termos`: como a cidade aparece escrita nas notícias.
const Map<String, ({String nome, List<String> termos, Color cor})> cidadesRegiao = {
  'hortolandia': (nome: 'Hortolândia', termos: ['Hortolândia'], cor: Color(0xFF00BCD4)),
  'campinas': (nome: 'Campinas', termos: ['Campinas'], cor: Color(0xFFFFD54F)),
  'sumare': (nome: 'Sumaré', termos: ['Sumaré'], cor: Color(0xFF80DEEA)),
  'americana': (nome: 'Americana', termos: ['Americana'], cor: Color(0xFFA5D6A7)),
  'santa-barbara': (
    nome: "Sta. Bárbara d'Oeste",
    termos: ["Santa Bárbara d'Oeste", 'Santa Bárbara', "Santa Bárbara D'Oeste"],
    cor: Color(0xFFCE93D8)
  ),
  'indaiatuba': (nome: 'Indaiatuba', termos: ['Indaiatuba'], cor: Color(0xFFFFAB91)),
  'paulinia': (nome: 'Paulínia', termos: ['Paulínia'], cor: Color(0xFFF48FB1)),
  'valinhos': (nome: 'Valinhos', termos: ['Valinhos'], cor: Color(0xFFB39DDB)),
  'vinhedo': (nome: 'Vinhedo', termos: ['Vinhedo'], cor: Color(0xFFC5E1A5)),
  'monte-mor': (nome: 'Monte Mor', termos: ['Monte Mor'], cor: Color(0xFF90CAF9)),
  'nova-odessa': (nome: 'Nova Odessa', termos: ['Nova Odessa'], cor: Color(0xFFFFCC80)),
  'jaguariuna': (nome: 'Jaguariúna', termos: ['Jaguariúna'], cor: Color(0xFFEF9A9A)),
  'itatiba': (nome: 'Itatiba', termos: ['Itatiba'], cor: Color(0xFF80CBC4)),
};

const _rotuloRegiao = 'Região de Campinas';
const _feedRegiao = 'https://g1.globo.com/rss/g1/sp/campinas-regiao/';

class TelaRegiao extends StatelessWidget {
  final VoidCallback aoTerminar;
  const TelaRegiao({super.key, required this.aoTerminar});

  @override
  Widget build(BuildContext context) {
    final cfg = ConfigManager();
    var chaves = cfg
        .getStringList('regiao', 'cidades_selecionadas')
        .where(cidadesRegiao.containsKey)
        .toList();
    if (chaves.isEmpty) chaves = ['hortolandia'];
    final selecionadas = [for (final k in chaves) cidadesRegiao[k]!];

    final cores = {for (final c in cidadesRegiao.values) c.nome: c.cor};

    return TelaNoticias(
      aoTerminar: aoTerminar,
      icone: Icons.location_city_rounded,
      titulo: 'Notícias da região',
      subtitulo: selecionadas.map((c) => c.nome).join(', '),
      destaque: Destaques.regiao,
      velocidadePxSeg: cfg.getInt('regiao', 'duracao_scroll_px_seg', 35),
      pausaFinalSeg: cfg.getInt('regiao', 'pausa_final_seg', 10),
      corDoRotulo: (n) => cores[n.rotulo] ?? Cores.textoSecundario,
      carregar: () async {
        final r = await NewsService.instance.buscar(
          const [FonteRss(_feedRegiao, _rotuloRegiao)],
          validade: cfg.getIntervaloAtualizacao('regiao'),
        );
        final porCidade = cfg.getInt('regiao', 'qtd_noticias', 3).clamp(1, 20);
        final filtradas = NewsService.filtrarPorCidades(
          r.noticias,
          {for (final c in selecionadas) c.nome: c.termos},
          porCidade: porCidade,
          rotuloRegiao: _rotuloRegiao,
          minimoTotal: (porCidade * selecionadas.length).clamp(4, 12),
        );
        return (noticias: filtradas, atualizadoEm: r.atualizadoEm);
      },
    );
  }
}
