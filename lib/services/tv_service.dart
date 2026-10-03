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

  Future<List<JogoNaTv>> _jogosDaPagina(String caminho, String chave) async {
    final entrada = await buscarComCache<List<dynamic>>(
      chave: chave,
      validade: const Duration(hours: 1),
      buscar: () async {
        final res = await http.get(Uri.parse('$_site$caminho'),
            headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        return parsePagina(res.body).map((j) => j.toJson()).toList();
      },
    );
    return (entrada?.dados ?? [])
        .map((e) => JogoNaTv.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Procura o jogo de [nomesTime] contra [nomesAdversario] em [data].
  /// Só consulta hoje e amanhã (é o que o site publica com canais).
  Future<JogoNaTv?> buscarJogo({
    required DateTime data,
    required List<String> nomesTime,
    required List<String> nomesAdversario,
  }) async {
    final dias = soData(data).difference(soData(DateTime.now())).inDays;
    final String caminho;
    if (dias == 0) {
      caminho = '/jogos-hoje';
    } else if (dias == 1) {
      caminho = '/jogos-amanha';
    } else {
      return null;
    }
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
