// ═══════════════════════════════════════════════════════════════════════════
//  Itens da lista de compras com quantidade.
//
//  No Google Tasks o item fica como "Sabonete (3)" — legível também no app do
//  Google no celular. Sem quantidade (ou 1), fica só "Sabonete".
//  Tudo aqui é função pura — coberto por testes.
// ═══════════════════════════════════════════════════════════════════════════

class ItemLista {
  final String nome; // "Sabonete"
  final int? quantidade; // null = não disse
  const ItemLista(this.nome, [this.quantidade]);

  /// Título salvo no Google Tasks.
  String get titulo => (quantidade ?? 1) > 1 ? '$nome ($quantidade)' : nome;

  /// Como o Jarvis fala: "3 de sabonete" soa estranho; "sabonete, 3 unidades" não.
  String get falado {
    final n = nome.toLowerCase();
    return (quantidade ?? 1) > 1 ? '$n, $quantidade unidades' : n;
  }

  ItemLista comQuantidade(int q) => ItemLista(nome, q);

  @override
  bool operator ==(Object other) =>
      other is ItemLista && other.nome == nome && other.quantidade == quantidade;
  @override
  int get hashCode => Object.hash(nome, quantidade);
  @override
  String toString() => titulo;
}

const _numerosItem = {
  'um': 1, 'uma': 1, 'dois': 2, 'duas': 2, 'tres': 3, 'três': 3, 'quatro': 4,
  'cinco': 5, 'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9, 'dez': 10,
  'onze': 11, 'doze': 12, 'treze': 13, 'quatorze': 14, 'catorze': 14,
  'quinze': 15, 'dezesseis': 16, 'dezessete': 17, 'dezoito': 18,
  'dezenove': 19, 'vinte': 20, 'trinta': 30,
};

int? _numero(String palavra) =>
    int.tryParse(palavra.replaceAll(RegExp(r'x$'), '')) ?? _numerosItem[palavra];

/// "3 sabonetes" → Sabonete (3); "duas caixas de leite" → Caixa de leite (2);
/// "meia dúzia de ovos" → Ovos (6); "sabonete" → Sabonete (sem quantidade).
ItemLista lerItemFalado(String texto) {
  var palavras = texto.trim().toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  if (palavras.isEmpty) return const ItemLista('');
  int? qtd;
  // Dúzias: "uma dúzia de ovos", "meia dúzia de ovos", "duas dúzias de ovos"
  final duzia = palavras.indexWhere((p) => p == 'dúzia' || p == 'duzia' || p.startsWith('dúzias') || p == 'duzias');
  if (duzia >= 0 && duzia <= 1) {
    final antes = duzia == 1 ? palavras[0] : 'uma';
    final mult = antes == 'meia' ? 0.5 : (_numero(antes) ?? 1).toDouble();
    qtd = (12 * mult).round();
    palavras = palavras.sublist(duzia + 1);
    if (palavras.isNotEmpty && palavras.first == 'de') palavras = palavras.sublist(1);
  } else {
    final n = _numero(palavras.first);
    if (n != null && palavras.length > 1) {
      qtd = n;
      palavras = palavras.sublist(1);
    }
  }
  if (qtd != null && qtd > 1 && duzia < 0) palavras = _singular(palavras);
  if (palavras.isEmpty) return const ItemLista('');
  final nome = palavras.join(' ');
  return ItemLista(nome[0].toUpperCase() + nome.substring(1), qtd == 1 ? null : qtd);
}

/// Singular até a primeira preposição: "caixas de leite" → "caixa de leite",
/// "sabonetes líquidos" → "sabonete líquido". O que vem depois do "de" fica.
List<String> _singular(List<String> palavras) {
  final out = <String>[];
  var parar = false;
  for (final p in palavras) {
    if (!parar && const {'de', 'da', 'do', 'das', 'dos', 'com', 'sem', 'para', 'pra'}.contains(p)) {
      parar = true;
    }
    out.add(parar ? p : singularPalavra(p));
  }
  return out;
}

/// Singular de uma palavra em português (regras comuns de mercado).
String singularPalavra(String p) {
  if (p.length <= 3) return p;
  for (final (fim, troca) in const [
    ('ões', 'ão'), ('ães', 'ão'), ('ãos', 'ão'), ('ais', 'al'), ('éis', 'el'),
    ('óis', 'ol'), ('uis', 'ul'), ('ns', 'm'), ('res', 'r'), ('zes', 'z'),
  ]) {
    if (p.endsWith(fim)) return p.substring(0, p.length - fim.length) + troca;
  }
  return p.endsWith('s') ? p.substring(0, p.length - 1) : p;
}

/// Lê um título do Google Tasks de volta: "Sabonete (3)", "3x Sabonete",
/// "Sabonete x3" → Sabonete com 3. Sem número → sem quantidade.
ItemLista itemDoTitulo(String titulo) {
  final t = titulo.trim();
  final fim = RegExp(r'^(.+?)\s*(?:\((\d+)\)|[x×]\s*(\d+))$', caseSensitive: false).firstMatch(t);
  if (fim != null) {
    final q = int.parse(fim.group(2) ?? fim.group(3)!);
    return ItemLista(fim.group(1)!.trim(), q > 1 ? q : null);
  }
  final inicio = RegExp(r'^(\d+)\s*[x×]?\s+(.+)$', caseSensitive: false).firstMatch(t);
  if (inicio != null) {
    final q = int.parse(inicio.group(1)!);
    return ItemLista(inicio.group(2)!.trim(), q > 1 ? q : null);
  }
  return ItemLista(t);
}

/// Resposta a "Quer colocar uma quantidade?": "três", "sim, 3", "coloca duas",
/// "meia dúzia" → número. null = não falou número.
int? quantidadeDaResposta(String falado) {
  final palavras = falado
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  for (var i = 0; i < palavras.length; i++) {
    final p = palavras[i];
    if (p == 'dúzia' || p == 'duzia') {
      final antes = i > 0 ? palavras[i - 1] : 'uma';
      return antes == 'meia' ? 6 : 12 * (_numero(antes) ?? 1);
    }
  }
  for (final p in palavras) {
    final n = _numero(p);
    if (n != null && n > 0) return n;
  }
  return null;
}

/// "não", "não precisa", "deixa assim", "só isso" → não quer quantidade.
bool respostaNegativa(String falado) => RegExp(
        r'(?<![\p{L}])(não|nao|nada|deixa|deixe|precisa não|tanto faz|só isso|so isso|esquece)(?![\p{L}])',
        unicode: true)
    .hasMatch(falado.toLowerCase());

/// "sim", "quero", "pode ser" sem número: pergunta "quantos?" de novo.
bool respostaPositiva(String falado) => RegExp(
        r'(?<![\p{L}])(sim|quero|pode|claro|isso|uhum|aham)(?![\p{L}])',
        unicode: true)
    .hasMatch(falado.toLowerCase());
