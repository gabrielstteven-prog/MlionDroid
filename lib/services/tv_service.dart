import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../cache_manager.dart';
import '../util.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  TvService — "onde assistir" o jogo, sem API paga.
//
//  Nenhuma API gratuita traz os canais brasileiros (ESPN vem vazio,
//  TheSportsDB só tem canais estrangeiros, Sofascore bloqueia). A fonte
//  que funciona é a programação pública do futebolnatv.com.br, que lista os
//  jogos de hoje e de amanhã com os canais (SporTV, Premiere, Globo...).
//
//  Como é leitura de página (não API oficial), pode parar de funcionar se o
//  site mudar o layout. Nesse caso este serviço só devolve lista vazia e a
//  tela de próxima partida simplesmente não mostra os canais.
// ═══════════════════════════════════════════════════════════════════════════

class JogoNaTv {
  final String horario;
  final String timeA;
  final String timeB;
  final String liga;
  final List<String> canais;
  const JogoNaTv(this.horario, this.timeA, this.timeB, this.liga, this.canais);

  Map<String, dynamic> toJson() =>
      {'h': horario, 'a': timeA, 'b': timeB, 'l': liga, 'c': canais};
  static JogoNaTv fromJson(Map<String, dynamic> j) => JogoNaTv(
        j['h'] as String? ?? '',
        j['a'] as String? ?? '',
        j['b'] as String? ?? '',
        j['l'] as String? ?? '',
        (j['c'] as List? ?? []).map((e) => '$e').toList(),
      );
}

class TvService {
  TvService._();
  static final TvService instance = TvService._();

  static const _site = 'https://www.futebolnatv.com.br';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0 Mobile Safari/537.36';

  /// Extrai os jogos da página. Função pura — testada em test/.
  static List<JogoNaTv> parsePagina(String htmlPagina) {
    final doc = html_parser.parse(htmlPagina);
    final jogos = <JogoNaTv>[];
    for (final art in doc.querySelectorAll('article')) {
      String nomeTime(String lado) {
        final caixa = art.querySelector('[id^="jogo-card-team-$lado-"]');
        if (caixa == null) return '';
        final img = caixa.querySelector('img');
        final alt = img?.attributes['alt']?.trim() ?? '';
        if (alt.isNotEmpty) return alt;
        return caixa.parent?.text.trim() ?? '';
      }

      final a = nomeTime('a');
      final b = nomeTime('b');
      if (a.isEmpty || b.isEmpty) continue;

      final canais = <String>[];
      for (final icone in art.querySelectorAll('[class*="hero-tv"]')) {
        final txt = icone.parent?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
        if (txt.isNotEmpty && !canais.contains(txt)) canais.add(txt);
      }
      final liga = art.querySelector('[id^="liga-header-logo-"] img')
              ?.attributes['alt']
              ?.trim() ??
          '';
      final horario = art.querySelector('time')?.text.trim() ?? '';
      jogos.add(JogoNaTv(horario, a, b, liga, canais));
    }
    return jogos;
  }

  Future<String> _baixar(String caminho) async {
    final res = await http.get(Uri.parse('$_site$caminho'),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return res.body;
  }

  Future<List<JogoNaTv>> _jogosDaPagina(String caminho, String chave) async {
    final entrada = await buscarComCache<List<dynamic>>(
      chave: chave,
      validade: const Duration(hours: 1),
      buscar: () async =>
          parsePagina(await _baixar(caminho)).map((j) => j.toJson()).toList(),
    );
    return (entrada?.dados ?? [])
        .map((e) => JogoNaTv.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Acha o link da página do time na lista de times do site
  /// (ex.: "/time/palmeiras-va41lxp2r4"). Função pura — testada.
  static String? caminhoDoTime(String htmlTimes, List<String> nomes) {
    final alvos = nomes.map(normalizar).where((n) => n.isNotEmpty).toSet();
    for (final m
        in RegExp(r'href="(/time/([a-z0-9-]+)-[a-z0-9]+)"').allMatches(htmlTimes)) {
      if (alvos.contains(m.group(2)!.replaceAll('-', ' '))) return m.group(1);
    }
    return null;
  }

  /// Página do time: traz o próximo jogo JÁ com os canais, dias antes
  /// (a emissora sai junto com a tabela detalhada da rodada).
  Future<JogoNaTv?> _pelaPaginaDoTime(
      List<String> nomesTime, List<String> nomesAdversario) async {
    final entrada = await buscarComCache<String>(
      chave: 'tv_caminho_${normalizar(nomesTime.first)}',
      validade: const Duration(days: 30),
      buscar: () async => caminhoDoTime(await _baixar('/times'), nomesTime) ?? '',
    );
    final caminho = entrada?.dados ?? '';
    if (caminho.isEmpty) return null;
    final jogos = await _jogosDaPagina(caminho, 'tv_pagina_$caminho');
    // A página mostra o "Último jogo" antes do "Próximo jogo": procura de trás
    // para frente para não pegar o jogo de ida num confronto de ida e volta.
    return encontrarJogo(jogos.reversed.toList(), nomesTime, nomesAdversario);
  }

  /// Página da competição no site a partir do código da ESPN ("bra.1" →
  /// "/liga/brasileirao-serie-a-..."). Ignora sub-17/sub-20/feminino.
  /// Função pura — testada.
  static String? caminhoDaLiga(String htmlLigas, String ligaSlug) {
    final prefixo = switch (ligaSlug) {
      'bra.1' => 'brasileirao-serie-a',
      'bra.2' => 'brasileirao-serie-b',
      'bra.3' => 'brasileirao-serie-c',
      'bra.copa_do_brazil' => 'copa-do-brasil',
      'conmebol.libertadores' => 'copa-libertadores',
      'conmebol.sudamericana' => 'sul-americana',
      'bra.camp.paulista' => 'paulista',
      _ => null,
    };
    if (prefixo == null) return null;
    for (final m in RegExp(r'href="(/liga/([a-z0-9-]+))"').allMatches(htmlLigas)) {
      final slug = m.group(2)!;
      if (RegExp(r'sub-?\d|feminino').hasMatch(slug)) continue;
      if (slug.contains(prefixo)) return m.group(1);
    }
    return null;
  }

  /// Página da competição: lista a rodada inteira com as emissoras — serve
  /// quando a página do time ainda mostra o jogo anterior (ela só "vira"
  /// para o próximo jogo algumas horas depois).
  Future<JogoNaTv?> _pelaPaginaDaLiga(
      String ligaSlug, List<String> nomesTime, List<String> nomesAdversario) async {
    final entrada = await buscarComCache<String>(
      chave: 'tv_liga_$ligaSlug',
      validade: const Duration(days: 30),
      buscar: () async => caminhoDaLiga(await _baixar('/ligas'), ligaSlug) ?? '',
    );
    final caminho = entrada?.dados ?? '';
    if (caminho.isEmpty) return null;
    final jogos = await _jogosDaPagina(caminho, 'tv_pagina_$caminho');
    return encontrarJogo(jogos, nomesTime, nomesAdversario);
  }

  /// Procura o jogo de [nomesTime] contra [nomesAdversario] em [data]:
  /// primeiro na página do time (vale com dias de antecedência), depois na
  /// página da competição ([ligaSlug] da ESPN) e, por fim, na programação
  /// de hoje/amanhã do site.
  Future<JogoNaTv?> buscarJogo({
    required DateTime data,
    required List<String> nomesTime,
    required List<String> nomesAdversario,
    String ligaSlug = '',
  }) async {
    try {
      final j = await _pelaPaginaDoTime(nomesTime, nomesAdversario);
      if (j != null && j.canais.isNotEmpty) return j;
    } catch (_) {}
    if (ligaSlug.isNotEmpty) {
      try {
        final j = await _pelaPaginaDaLiga(ligaSlug, nomesTime, nomesAdversario);
        if (j != null && j.canais.isNotEmpty) return j;
      } catch (_) {}
    }
    final dias = soData(data).difference(soData(DateTime.now())).inDays;
    if (dias != 0 && dias != 1) return null;
    final caminho = dias == 0 ? '/jogos-hoje' : '/jogos-amanha';
    final chave = 'tv_${caminho.substring(1)}_${soData(data).toIso8601String()}';
    try {
      final jogos = await _jogosDaPagina(caminho, chave);
      return encontrarJogo(jogos, nomesTime, nomesAdversario);
    } catch (_) {
      return null;
    }
  }

  /// Casa os nomes do site com os do app (acentos, "Vasco da Gama" x
  /// "Vasco" etc.). Exige os DOIS times — senão um jogo do sub-20 ou do
  /// feminino no mesmo dia poderia ser confundido com o jogo principal.
  static JogoNaTv? encontrarJogo(List<JogoNaTv> jogos, List<String> nomesTime,
      List<String> nomesAdversario) {
    const categoriasBase = ['sub', 'feminino', 'fem', 'u20', 'u17', 'sub20'];
    bool ehBase(String nomeSite) {
      final palavras = normalizar(nomeSite).split(' ');
      return palavras.any(categoriasBase.contains);
    }

    bool casa(String nomeSite, List<String> nomes) {
      if (ehBase(nomeSite)) return false;
      final s = normalizar(nomeSite);
      return nomes.any((n) {
        final x = normalizar(n);
        return x.isNotEmpty && (s == x || s.startsWith('$x ') || x.startsWith('$s '));
      });
    }

    for (final j in jogos) {
      final direto = casa(j.timeA, nomesTime) && casa(j.timeB, nomesAdversario);
      final invertido =
          casa(j.timeB, nomesTime) && casa(j.timeA, nomesAdversario);
      if (direto || invertido) return j;
    }
    return null;
  }
}
