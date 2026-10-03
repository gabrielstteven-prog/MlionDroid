import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../cache_manager.dart';
import '../util.dart';

class Noticia {
  final String titulo;
  final String descricao;
  final String link;
  final String imagem;
  final String rotulo; // categoria ou cidade
  final DateTime? publicadaEm;

  const Noticia({
    required this.titulo,
    required this.descricao,
    required this.link,
    required this.imagem,
    this.rotulo = '',
    this.publicadaEm,
  });

  Noticia comRotulo(String r) => Noticia(
      titulo: titulo,
      descricao: descricao,
      link: link,
      imagem: imagem,
      rotulo: r,
      publicadaEm: publicadaEm);

  Map<String, dynamic> toJson() => {
        't': titulo,
        'd': descricao,
        'l': link,
        'i': imagem,
        'r': rotulo,
        'p': publicadaEm?.toIso8601String(),
      };

  static Noticia fromJson(Map<String, dynamic> j) => Noticia(
        titulo: j['t'] as String? ?? '',
        descricao: j['d'] as String? ?? '',
        link: j['l'] as String? ?? '',
        imagem: j['i'] as String? ?? '',
        rotulo: j['r'] as String? ?? '',
        publicadaEm: DateTime.tryParse(j['p'] as String? ?? ''),
      );
}

/// Feed RSS com o rótulo que suas notícias recebem.
class FonteRss {
  final String url;
  final String rotulo;
  const FonteRss(this.url, this.rotulo);
}

class NewsService {
  NewsService._();
  static final NewsService instance = NewsService._();

  /// Lê um RSS. Itens malformados são ignorados em vez de derrubar o feed
  /// inteiro (antes, um item sem <description> quebrava tudo).
  static List<Noticia> parseRss(String xml, {String rotulo = ''}) {
    final doc = XmlDocument.parse(xml);
    final itens = <Noticia>[];
    for (final node in doc.findAllElements('item')) {
      String campo(String nome) {
        final els = node.findElements(nome);
        return els.isEmpty ? '' : els.first.innerText.trim();
      }

      final titulo = limparHtml(campo('title'));
      final link = campo('link');
      if (titulo.isEmpty || link.isEmpty) continue;
      final descRaw = campo('description');
      var imagem = RegExp(r'src="([^"]+)"').firstMatch(descRaw)?.group(1) ?? '';
      if (imagem.isEmpty) {
        final media = node.findElements('media:content');
        if (media.isNotEmpty) imagem = media.first.getAttribute('url') ?? '';
      }
      itens.add(Noticia(
        titulo: titulo,
        descricao: limparHtml(descRaw),
        link: link,
        imagem: imagem,
        rotulo: rotulo,
        publicadaEm: _parseData(campo('pubDate')),
      ));
    }
    return itens;
  }

  static DateTime? _parseData(String s) {
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // RFC 822: "Fri, 03 Oct 2026 10:15:00 -0000"
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(s);
    if (m == null) return null;
    const meses = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
    final mes = meses.indexOf(m.group(2)!) + 1;
    if (mes == 0) return null;
    return DateTime.utc(int.parse(m.group(3)!), mes, int.parse(m.group(1)!),
            int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!))
        .toLocal();
  }

  Future<List<Noticia>> _buscarFeed(FonteRss fonte) async {
    final res = await http
        .get(Uri.parse(fonte.url))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return parseRss(utf8.decode(res.bodyBytes), rotulo: fonte.rotulo);
  }

  /// Busca vários feeds (com cache por feed), remove duplicadas e devolve
  /// também a data do dado mais antigo usado (para "atualizado há X").
  Future<({List<Noticia> noticias, DateTime? atualizadoEm})> buscar(
    List<FonteRss> fontes, {
    required Duration validade,
    int? porFonte,
    bool forcar = false,
  }) async {
    final todas = <Noticia>[];
    DateTime? maisAntigo;
    for (final f in fontes) {
      final entrada = await buscarComCache<List<dynamic>>(
        chave: 'rss_${f.url}',
        validade: validade,
        forcar: forcar,
        buscar: () async =>
            (await _buscarFeed(f)).map((n) => n.toJson()).toList(),
      );
      if (entrada == null) continue;
      if (maisAntigo == null || entrada.salvoEm.isBefore(maisAntigo)) {
        maisAntigo = entrada.salvoEm;
      }
      var itens = entrada.dados
          .map((e) => Noticia.fromJson(Map<String, dynamic>.from(e as Map)))
          .map((n) => n.comRotulo(f.rotulo))
          .toList();
      if (porFonte != null) itens = itens.take(porFonte).toList();
      todas.addAll(itens);
    }
    return (noticias: semDuplicadas(todas), atualizadoEm: maisAntigo);
  }

  /// O ge e o G1 reaproveitam a mesma foto em matérias diferentes (ex.: a
  /// foto de agência do jogador em três notícias seguidas) — parecia notícia
  /// repetida. A primeira mantém a foto; as outras ficam sem (a tela desenha
  /// uma capa própria). Compara pelo NOME do arquivo, porque o mesmo
  /// arquivo vem em URLs de tamanhos diferentes. Função pura — testada.
  static List<Noticia> semFotosRepetidas(List<Noticia> lista) {
    final vistas = <String>{};
    return [
      for (final n in lista)
        if (n.imagem.isEmpty || vistas.add(arquivoDaImagem(n.imagem)))
          n
        else
          Noticia(
              titulo: n.titulo,
              descricao: n.descricao,
              link: n.link,
              imagem: '',
              rotulo: n.rotulo,
              publicadaEm: n.publicadaEm),
    ];
  }

  static String arquivoDaImagem(String url) {
    final caminho = Uri.tryParse(url)?.path ?? url;
    return caminho.split('/').last.toLowerCase();
  }

  /// O feed "Geral" do G1 repete manchetes das editorias — mantém a
  /// primeira ocorrência de cada link/título.
  static List<Noticia> semDuplicadas(List<Noticia> lista) {
    final vistos = <String>{};
    return lista.where((n) {
      final chave = n.link.isNotEmpty ? n.link : normalizar(n.titulo);
      return vistos.add(chave);
    }).toList();
  }

  /// Filtra notícias de região pelas cidades escolhidas, verificando se a
  /// notícia REALMENTE cita a cidade (título ou resumo). Antes, o app só
  /// distribuía as manchetes do feed regional entre as cidades na ordem,
  /// rotulando com o nome errado.
  ///
  /// Se faltar notícia das cidades escolhidas, completa com manchetes da
  /// região, rotuladas honestamente como [rotuloRegiao].
  static List<Noticia> filtrarPorCidades(
    List<Noticia> noticias,
    Map<String, List<String>> cidades, // nome exibido → termos de busca
    {required int porCidade,
    required String rotuloRegiao,
    int minimoTotal = 6}) {
    final resultado = <Noticia>[];
    final usados = <String>{};
    for (final entry in cidades.entries) {
      bool cita(Noticia n) => entry.value.any((termo) =>
          mencionaTermo(n.titulo, termo) || mencionaTermo(n.descricao, termo));
      final daCidade = noticias
          .where((n) => !usados.contains(n.link) && cita(n))
          .take(porCidade);
      for (final n in daCidade) {
        usados.add(n.link);
        resultado.add(n.comRotulo(entry.key));
      }
    }
    if (resultado.length < minimoTotal) {
      for (final n in noticias) {
        if (resultado.length >= minimoTotal) break;
        if (usados.add(n.link)) resultado.add(n.comRotulo(rotuloRegiao));
      }
    }
    return resultado;
  }
}
