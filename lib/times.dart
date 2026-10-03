// ─────────────────────────────────────────────────────────────────────────────
//  Times disponíveis — fonte única de verdade.
//
//  espnId: ID do time na API pública da ESPN (gratuita, sem chave), usada
//  para próximos jogos, resultados, estádio e classificação. Para conferir
//  ou adicionar um time, abra no navegador:
//    https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/teams
//  (troque bra.1 por bra.2 para a Série B).
//
//  nomeRss: trecho da URL do time no ge.globo.com (notícias).
//  apelidos: nomes alternativos usados por sites de programação de TV.
// ─────────────────────────────────────────────────────────────────────────────
class TimeInfo {
  final String nome;
  final String nomeRss;
  final String corTop;
  final String corBottom;
  final String corDestaque;
  final String escudoAsset;
  final int espnId;
  final List<String> apelidos;

  const TimeInfo({
    required this.nome,
    required this.nomeRss,
    required this.corTop,
    required this.corBottom,
    required this.corDestaque,
    required this.espnId,
    this.escudoAsset = '',
    this.apelidos = const [],
  });

  /// Escudo em PNG servido pela ESPN — existe para todos os times, mesmo
  /// os que não têm imagem nos assets do app.
  String get escudoUrl =>
      'https://a.espncdn.com/i/teamlogos/soccer/500/$espnId.png';

  /// Todos os nomes pelos quais o time pode aparecer em fontes externas.
  List<String> get todosOsNomes => [nome, ...apelidos];
}

const String timePadrao = 'palmeiras';

const Map<String, TimeInfo> timesDisponiveis = {
  'palmeiras': TimeInfo(
      nome: 'Palmeiras',
      nomeRss: 'palmeiras',
      corTop: '0xFF00441B',
      corBottom: '0xFF000000',
      corDestaque: '0xFFC1A163',
      espnId: 2029,
      escudoAsset: 'assets/escudos/palmeiras.png'),
  'flamengo': TimeInfo(
      nome: 'Flamengo',
      nomeRss: 'flamengo',
      corTop: '0xFF8B0000',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFD700',
      espnId: 819,
      escudoAsset: 'assets/escudos/flamengo.png'),
  'corinthians': TimeInfo(
      nome: 'Corinthians',
      nomeRss: 'corinthians',
      corTop: '0xFF1a1a1a',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFFFFF',
      espnId: 874,
      escudoAsset: 'assets/escudos/corinthians.png'),
  'sao-paulo': TimeInfo(
      nome: 'São Paulo',
      nomeRss: 'sao-paulo',
      corTop: '0xFF8B0000',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFFFFF',
      espnId: 2026,
      escudoAsset: 'assets/escudos/sao-paulo.png'),
  'santos': TimeInfo(
      nome: 'Santos',
      nomeRss: 'santos',
      corTop: '0xFF1a1a1a',
      corBottom: '0xFF000000',
      corDestaque: '0xFFF5F5F5',
      espnId: 2674,
      escudoAsset: 'assets/escudos/santos.png'),
  'atletico-mg': TimeInfo(
      nome: 'Atlético-MG',
      nomeRss: 'atletico-mg',
      corTop: '0xFF1a1a1a',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFD700',
      espnId: 7632,
      apelidos: ['Atlético Mineiro', 'Atletico-MG']),
  'cruzeiro': TimeInfo(
      nome: 'Cruzeiro',
      nomeRss: 'cruzeiro',
      corTop: '0xFF0a1628',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFD700',
      espnId: 2022),
  'internacional': TimeInfo(
      nome: 'Internacional',
      nomeRss: 'internacional',
      corTop: '0xFF8B0000',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFFFFF',
      espnId: 1936),
  'gremio': TimeInfo(
      nome: 'Grêmio',
      nomeRss: 'gremio',
      corTop: '0xFF1a3a6e',
      corBottom: '0xFF000000',
      corDestaque: '0xFF87CEEB',
      espnId: 6273),
  'vasco': TimeInfo(
      nome: 'Vasco',
      nomeRss: 'vasco-da-gama',
      corTop: '0xFF1a1a1a',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFFFFF',
      espnId: 3454,
      apelidos: ['Vasco da Gama']),
  'botafogo': TimeInfo(
      nome: 'Botafogo',
      nomeRss: 'botafogo',
      corTop: '0xFF1a1a1a',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFFFFF',
      espnId: 6086),
  'fluminense': TimeInfo(
      nome: 'Fluminense',
      nomeRss: 'fluminense',
      corTop: '0xFF5C0A14',
      corBottom: '0xFF000000',
      corDestaque: '0xFF8FBC8F',
      espnId: 3445),
  'atletico-pr': TimeInfo(
      nome: 'Athletico-PR',
      nomeRss: 'atletico-pr',
      corTop: '0xFF8B0000',
      corBottom: '0xFF000000',
      corDestaque: '0xFF1a1a1a',
      espnId: 3458,
      apelidos: ['Athletico Paranaense', 'Athletico']),
  'bahia': TimeInfo(
      nome: 'Bahia',
      nomeRss: 'bahia',
      corTop: '0xFF003087',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFD700',
      espnId: 9967),
  'fortaleza': TimeInfo(
      nome: 'Fortaleza',
      nomeRss: 'fortaleza',
      corTop: '0xFF003087',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFF0000',
      espnId: 6272),
  'ceara': TimeInfo(
      nome: 'Ceará',
      nomeRss: 'ceara',
      corTop: '0xFF1a1a1a',
      corBottom: '0xFF000000',
      corDestaque: '0xFF1a90d4',
      espnId: 9969),
  'bragantino': TimeInfo(
      nome: 'Bragantino',
      nomeRss: 'bragantino',
      corTop: '0xFF8B0000',
      corBottom: '0xFF000000',
      corDestaque: '0xFFFFFFFF',
      espnId: 6079,
      apelidos: ['Red Bull Bragantino', 'RB Bragantino']),
};
