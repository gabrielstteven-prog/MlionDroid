// ─────────────────────────────────────────────────────────────────────────────
//  Lógica pura do rodízio de telas (sem Flutter) — coberta por testes.
//
//  O rodízio navega pela CHAVE da tela, não pela posição na lista. Antes,
//  o app guardava o índice; quando a lista de telas elegíveis mudava (o
//  Bom Dia sai às 10h, o Spotify sai quando a música pausa), o mesmo
//  índice passava a apontar para outra tela e o rodízio pulava/repetia.
// ─────────────────────────────────────────────────────────────────────────────

/// Próxima tela a mostrar depois de [atual].
///
/// [ordem]: sequência configurada (inclui telas que podem estar
/// temporariamente fora, como o Bom Dia fora do horário).
/// [elegiveis]: telas que podem aparecer agora.
/// [passo]: 1 = avançar, -1 = voltar.
String? proximaTela(
  List<String> ordem,
  Set<String> elegiveis,
  String? atual, {
  int passo = 1,
}) {
  final candidatas = ordem.where(elegiveis.contains).toList();
  if (candidatas.isEmpty) return null;
  if (atual == null) return candidatas.first;

  var pos = ordem.indexOf(atual);
  if (pos < 0) return candidatas.first;
  // Anda pela ordem completa até achar uma tela elegível — funciona mesmo
  // que a tela atual tenha acabado de ficar inelegível.
  for (var i = 1; i <= ordem.length; i++) {
    pos = (pos + passo) % ordem.length;
    if (pos < 0) pos += ordem.length;
    if (elegiveis.contains(ordem[pos])) return ordem[pos];
  }
  return candidatas.first;
}

/// true se [hora] está na janela [inicio, fim). Aceita janelas que cruzam a
/// meia-noite (ex.: 23h → 6h).
bool horaNaJanela(int hora, int inicio, int fim) {
  if (inicio == fim) return false;
  if (inicio < fim) return hora >= inicio && hora < fim;
  return hora >= inicio || hora < fim;
}
