import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../cache_manager.dart';
import '../config_manager.dart';
import '../times.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  FootballService — dados de futebol pela API pública da ESPN.
//
//  Gratuita e sem chave (substitui a football-data.org, que exigia uma
//  chave que acabava exposta dentro do APK). Traz todas as competições do
//  time juntas (Brasileirão, Libertadores, Copa do Brasil, estaduais...),
//  com data, horário, estádio, placar e escudos em PNG.
//
//  Não é uma API oficialmente documentada: se a ESPN mudar algo, as telas
//  continuam mostrando o último dado salvo em cache.
// ═══════════════════════════════════════════════════════════════════════════

class TimePartida {
  final int id;
  final String nome;
  final String abreviacao;
  final String escudo;
  final int? gols;
  const TimePartida(this.id, this.nome, this.abreviacao, this.escudo, this.gols);
}

class Partida {
  final String id;
  final DateTime data; // horário local
  final String competicao;
  final String ligaSlug; // ex.: bra.1 — escolhe o logo da competição
  final String ligaLogoId; // id do logo na ESPN (alternateId da liga)
  final TimePartida mandante;
  final TimePartida visitante;
  final String estadio;
  final String cidade;

  /// 'pre' (agendado), 'in' (em andamento) ou 'post' (encerrado).
  final String estado;
  final String relogio; // ex.: "67'" quando em andamento
  final String detalhe; // ex.: "Intervalo", "Fim"

  const Partida({
    required this.id,
    required this.data,
    required this.competicao,
    this.ligaSlug = '',
    this.ligaLogoId = '',
    required this.mandante,
    required this.visitante,
    required this.estadio,
    required this.cidade,
    required this.estado,
    required this.relogio,
    required this.detalhe,
  });

  bool get agendada => estado == 'pre';
  bool get aoVivo => estado == 'in';
  bool get encerrada => estado == 'post';

  bool envolve(int espnId) => mandante.id == espnId || visitante.id == espnId;
  TimePartida adversarioDe(int espnId) =>
      mandante.id == espnId ? visitante : mandante;
  bool mandanteEh(int espnId) => mandante.id == espnId;

  /// 'V', 'E' ou 'D' do ponto de vista do time [espnId].
  String? resultadoPara(int espnId) {
    final a = mandante.gols, b = visitante.gols;
    if (!encerrada || a == null || b == null) return null;
    final nossos = mandanteEh(espnId) ? a : b;
    final deles = mandanteEh(espnId) ? b : a;
    if (nossos > deles) return 'V';
    if (nossos < deles) return 'D';
    return 'E';
  }

  static int? _gols(dynamic score) {
    if (score == null) return null;
    if (score is num) return score.toInt();
    if (score is String) return int.tryParse(score);
    if (score is Map) {
      final v = score['value'] ?? score['displayValue'];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
    }
    return null;
  }

  static TimePartida _time(Map<String, dynamic> c) {
    final t = c['team'] as Map<String, dynamic>? ?? {};
    final logos = t['logos'] as List?;
    var logo = '';
    if (logos != null && logos.isNotEmpty && logos.first is Map) {
      logo = (logos.first as Map)['href'] as String? ?? '';
    }
    logo = logo.isNotEmpty ? logo : (t['logo'] as String? ?? '');
    final id = int.tryParse('${t['id'] ?? c['id'] ?? ''}') ?? -1;
    if (logo.isEmpty && id > 0) {
      logo = 'https://a.espncdn.com/i/teamlogos/soccer/500/$id.png';
    }
    return TimePartida(
      id,
      t['shortDisplayName'] as String? ?? t['displayName'] as String? ?? '',
      t['abbreviation'] as String? ?? '',
      logo,
      _gols(c['score']),
    );
  }

  static Partida? fromEspn(Map<String, dynamic> ev) {
    final comps = ev['competitions'] as List?;
    if (comps == null || comps.isEmpty) return null;
    final comp = comps.first as Map<String, dynamic>;
    final competidores =
        (comp['competitors'] as List? ?? []).cast<Map<String, dynamic>>();
    if (competidores.length < 2) return null;
    final casa = competidores.firstWhere((c) => c['homeAway'] == 'home',
        orElse: () => competidores[0]);
    final fora = competidores.firstWhere((c) => c['homeAway'] == 'away',
        orElse: () => competidores[1]);
    final data = DateTime.tryParse(ev['date'] as String? ?? '');
    if (data == null) return null;
    final status = comp['status'] as Map<String, dynamic>? ??
        ev['status'] as Map<String, dynamic>? ??
        {};
    final tipo = status['type'] as Map<String, dynamic>? ?? {};
    final venue = comp['venue'] as Map<String, dynamic>? ?? {};
    final liga = ev['league'] as Map<String, dynamic>?;
    var mandante = _time(casa);
    var visitante = _time(fora);
    final estado = tipo['state'] as String? ?? 'pre';
    if (estado != 'pre') {
      // A ESPN às vezes manda o jogo sem placar (ou de uma cópia atrasada):
      // sem isso o painel voltava a 0 x 0 e anunciava "gol" de novo.
      final (gc, gf) = PlacarConfiavel.corrigir('${ev['id']}', mandante.gols, visitante.gols);
      mandante = TimePartida(
          mandante.id, mandante.nome, mandante.abreviacao, mandante.escudo, gc);
      visitante = TimePartida(
          visitante.id, visitante.nome, visitante.abreviacao, visitante.escudo, gf);
    }
    return Partida(
      id: '${ev['id']}',
      data: data.toLocal(),
      competicao: traduzirCompeticao(
          liga?['name'] as String? ?? liga?['abbreviation'] as String? ?? ''),
      ligaSlug: liga?['slug'] as String? ?? '',
      ligaLogoId: '${liga?['alternateId'] ?? ''}',
      mandante: mandante,
      visitante: visitante,
      estadio: venue['fullName'] as String? ?? '',
      cidade: (venue['address'] as Map?)?['city'] as String? ?? '',
      estado: tipo['state'] as String? ?? 'pre',
      relogio: status['displayClock'] as String? ?? '',
      detalhe: tipo['shortDetail'] as String? ?? '',
    );
  }
}

/// Último placar válido de cada jogo. Placar não volta para trás à toa:
///  • veio vazio → mantém o último;
///  • veio MENOR → só aceita se repetir na consulta seguinte (gol anulado
///    pelo VAR acaba corrigido; uma cópia atrasada da ESPN, não).
/// Testada.
class PlacarConfiavel {
  static final Map<String, (int, int)> _ultimo = {};
  static final Map<String, (int, int)> _menorPendente = {};

  static (int?, int?) corrigir(String jogo, int? casa, int? fora) {
    final antes = _ultimo[jogo];
    if (casa == null || fora == null) return antes ?? (casa, fora);
    if (antes != null && (casa < antes.$1 || fora < antes.$2)) {
      if (_menorPendente[jogo] != (casa, fora)) {
        _menorPendente[jogo] = (casa, fora);
        return antes; // espera confirmar
      }
    }
    _menorPendente.remove(jogo);
    _ultimo[jogo] = (casa, fora);
    return (casa, fora);
  }

  @visibleForTesting
  static void limpar() {
    _ultimo.clear();
    _menorPendente.clear();
  }
}

/// Os nomes das competições vêm em inglês na ESPN.
String traduzirCompeticao(String nome) {
  const mapa = {
    'Brazilian Serie A': 'Brasileirão',
    'Brazilian Serie B': 'Brasileirão Série B',
    'CONMEBOL Libertadores': 'Libertadores',
    'CONMEBOL Sudamericana': 'Sul-Americana',
    'Brazilian Copa do Brasil': 'Copa do Brasil',
    'Copa do Brasil': 'Copa do Brasil',
    'Brazilian Campeonato Paulista': 'Paulistão',
    'Brazilian Campeonato Carioca': 'Carioca',
    'Brazilian Campeonato Mineiro': 'Mineiro',
    'Brazilian Campeonato Gaucho': 'Gauchão',
    'FIFA Club World Cup': 'Mundial de Clubes',
    'CONMEBOL Recopa': 'Recopa',
    'Supercopa do Brasil': 'Supercopa',
  };
  return mapa[nome] ?? nome;
}

class LinhaTabela {
  final int posicao;
  final int timeId;
  final String time;
  final String escudo;
  final int pontos, jogos, vitorias, empates, derrotas, saldo;
  const LinhaTabela({
    required this.posicao,
    required this.timeId,
    required this.time,
    required this.escudo,
    required this.pontos,
    required this.jogos,
    required this.vitorias,
    required this.empates,
    required this.derrotas,
    required this.saldo,
  });
}

class GrupoTabela {
  final String nome;
  final List<LinhaTabela> linhas;
  const GrupoTabela(this.nome, this.linhas);
}

/// Resultado com a data de quando o dado foi obtido (para "atualizado há").
class ComIdade<T> {
  final T valor;
  final DateTime atualizadoEm;
  const ComIdade(this.valor, this.atualizadoEm);
}

class FootballService {
  FootballService._();
  static final FootballService instance = FootballService._();

  static const _base = 'https://site.api.espn.com/apis';
  final _cfg = ConfigManager();

  TimeInfo get timeAtual {
    final key = _cfg.getString('time', 'time_key', timePadrao);
    return timesDisponiveis[key] ?? timesDisponiveis[timePadrao]!;
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('ESPN respondeu ${res.statusCode} para $url');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  List<Partida> _partidas(Map<String, dynamic> json) {
    final evs = (json['events'] as List? ?? []).cast<Map<String, dynamic>>();
    return evs.map(Partida.fromEspn).whereType<Partida>().toList();
  }

  /// Próximos jogos (inclui um jogo em andamento), do mais próximo ao mais
  /// distante. Quando há jogo perto de começar ou rolando, o cache dura só
  /// 1 minuto, para o placar ao vivo acompanhar.
  Future<ComIdade<List<Partida>>?> proximosJogos({bool forcar = false}) async {
    final id = timeAtual.espnId;
    final chave = 'futebol_proximos_$id';
    final antigo = await CacheManager.instance.obterEntrada<Map<String, dynamic>>(chave);
    var validade = _cfg.getIntervaloAtualizacao('proxima_partida');
    if (antigo != null && _temJogoPerto(_partidas(antigo.dados))) {
      validade = const Duration(minutes: 1);
    }
    final entrada = await buscarComCache<Map<String, dynamic>>(
      chave: chave,
      validade: validade,
      forcar: forcar,
      buscar: () =>
          _getJson('$_base/site/v2/sports/soccer/all/teams/$id/schedule?fixture=true'),
    );
    if (entrada == null) return null;
    final agora = DateTime.now();
    final lista = _partidas(entrada.dados)
        .where((p) =>
            !p.encerrada &&
            p.data.isAfter(agora.subtract(const Duration(hours: 3))))
        .toList()
      ..sort((a, b) => a.data.compareTo(b.data));
    return ComIdade(lista, entrada.salvoEm);
  }

  bool _temJogoPerto(List<Partida> ps) {
    final agora = DateTime.now();
    return ps.any((p) =>
        p.aoVivo ||
        (p.agendada &&
            p.data.difference(agora).inMinutes.abs() < 150));
  }

  /// Últimos resultados, do mais recente ao mais antigo.
  Future<ComIdade<List<Partida>>?> ultimosResultados({int limite = 5}) async {
    final id = timeAtual.espnId;
    // Dia de jogo (antes, durante ou logo depois): 5 min — senão o jogo que
    // acabou de terminar só aparecia nos "Últimos jogos" horas depois.
    final perto = jogoDoMomento.value != null ||
        _temJogoPerto(_partidas(
            (await CacheManager.instance
                        .obterEntrada<Map<String, dynamic>>('futebol_proximos_$id'))
                    ?.dados ??
                const {}));
    final entrada = await buscarComCache<Map<String, dynamic>>(
      chave: 'futebol_resultados_$id',
      validade: perto ? const Duration(minutes: 5) : const Duration(minutes: 30),
      buscar: () =>
          _getJson('$_base/site/v2/sports/soccer/all/teams/$id/schedule'),
    );
    if (entrada == null) return null;
    final lista = _partidas(entrada.dados).where((p) => p.encerrada).toList()
      ..sort((a, b) => b.data.compareTo(a.data));
    return ComIdade(lista.take(limite).toList(), entrada.salvoEm);
  }

  /// Classificação. [liga]: 'bra.1' (Brasileirão), 'conmebol.libertadores'...
  Future<ComIdade<List<GrupoTabela>>?> tabela(String liga) async {
    final entrada = await buscarComCache<Map<String, dynamic>>(
      chave: 'futebol_tabela_$liga',
      validade: _cfg.getIntervaloAtualizacao('classificacao'),
      buscar: () => _getJson('$_base/v2/sports/soccer/$liga/standings'),
    );
    if (entrada == null) return null;
    return ComIdade(parseTabela(entrada.dados), entrada.salvoEm);
  }

  static List<GrupoTabela> parseTabela(Map<String, dynamic> json) {
    final grupos = <GrupoTabela>[];
    final filhos = (json['children'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final g in filhos) {
      final entries = ((g['standings'] as Map?)?['entries'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final linhas = <LinhaTabela>[];
      for (final e in entries) {
        final stats = <String, num>{};
        for (final s in (e['stats'] as List? ?? []).cast<Map<String, dynamic>>()) {
          final v = s['value'];
          if (v is num) stats[s['name'] as String? ?? ''] = v;
        }
        final team = e['team'] as Map<String, dynamic>? ?? {};
        final logos = team['logos'] as List?;
        int st(String k) => (stats[k] ?? 0).round();
        linhas.add(LinhaTabela(
          posicao: st('rank'),
          timeId: int.tryParse('${team['id']}') ?? -1,
          time: team['shortDisplayName'] as String? ??
              team['displayName'] as String? ??
              '',
          escudo: (logos != null && logos.isNotEmpty)
              ? (logos.first as Map)['href'] as String? ?? ''
              : '',
          pontos: st('points'),
          jogos: st('gamesPlayed'),
          vitorias: st('wins'),
          empates: st('ties'),
          derrotas: st('losses'),
          saldo: st('pointDifferential'),
        ));
      }
      linhas.sort((a, b) => a.posicao.compareTo(b.posicao));
      final nome = (g['name'] as String? ?? '')
          .replaceFirst(RegExp(r'^Group\s+'), 'Grupo ');
      grupos.add(GrupoTabela(nome, linhas));
    }
    return grupos;
  }

  // ── Escalação ────────────────────────────────────────────────────────────
  /// Escalação do jogo (a ESPN publica perto do horário da partida; antes
  /// disso a lista vem vazia).
  Future<List<Escalacao>> escalacao(String eventId) async {
    final entrada = await buscarComCache<Map<String, dynamic>>(
      chave: 'futebol_escalacao_$eventId',
      validade: const Duration(minutes: 10),
      buscar: () => _getJson('$_base/site/v2/sports/soccer/all/summary?event=$eventId'),
    );
    if (entrada == null) return [];
    return parseEscalacao(entrada.dados);
  }

  /// Lances e estatísticas do jogo (atualiza a cada ~30 s durante o jogo).
  Future<JogoAoVivo?> aoVivo(Partida jogo) async {
    final entrada = await buscarComCache<Map<String, dynamic>>(
      chave: 'futebol_aovivo_${jogo.id}',
      validade: const Duration(seconds: 25),
      buscar: () => _getJson('$_base/site/v2/sports/soccer/all/summary?event=${jogo.id}'),
    );
    if (entrada == null) return null;
    return parseAoVivo(entrada.dados, jogo.mandante.id);
  }

  static List<Escalacao> parseEscalacao(Map<String, dynamic> json) {
    final lista = <Escalacao>[];
    for (final r in (json['rosters'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final team = r['team'] as Map<String, dynamic>? ?? {};
      final jogadores = <Jogador>[];
      for (final j in (r['roster'] as List? ?? []).cast<Map<String, dynamic>>()) {
        if (j['starter'] != true) continue;
        final atleta = j['athlete'] as Map<String, dynamic>? ?? {};
        jogadores.add(Jogador(
          '${j['jersey'] ?? ''}',
          atleta['shortName'] as String? ?? atleta['displayName'] as String? ?? '',
          (j['position'] as Map?)?['abbreviation'] as String? ?? '',
        ));
      }
      if (jogadores.isEmpty) continue;
      lista.add(Escalacao(
        int.tryParse('${team['id']}') ?? -1,
        team['shortDisplayName'] as String? ?? team['displayName'] as String? ?? '',
        r['formation'] as String? ?? '',
        jogadores,
        team['color'] as String? ?? '',
      ));
    }
    return lista;
  }

  // ── Monitor de dia de jogo ───────────────────────────────────────────────
  /// Jogo do time que está perto (até 90 min antes), rolando, ou que
  /// terminou há menos de 30 min. null = nenhum jogo agora.
  final ValueNotifier<Partida?> jogoDoMomento = ValueNotifier(null);

  /// Último acontecimento ao vivo ("Gol do Palmeiras!") — a barra superior
  /// mostra isso no ticker e o app pode falar em voz alta.
  final ValueNotifier<String?> ultimoLance = ValueNotifier(null);

  Timer? _monitor;
  String? _placarAnterior;

  void iniciarMonitor() {
    _monitor?.cancel();
    _verificarJogo();
  }

  Future<void> _verificarJogo() async {
    Partida? momento;
    try {
      final r = await proximosJogos();
      final agora = DateTime.now();
      for (final p in r?.valor ?? const <Partida>[]) {
        final ate = p.data.difference(agora).inMinutes;
        if (p.aoVivo || (p.agendada && ate <= 90 && ate > -150)) {
          momento = p;
          break;
        }
      }
      // Jogo recém-encerrado: continua em destaque por 30 min.
      final atual = jogoDoMomento.value;
      if (momento == null &&
          atual != null &&
          agora.difference(atual.data).inMinutes < 150 + 30) {
        final res = await ultimosResultados(limite: 1);
        final fim = res?.valor.firstOrNull;
        if (fim != null && fim.id == atual.id) momento = fim;
      }
    } catch (_) {}

    _detectarGol(momento);
    // Jogo acabou: os "Últimos jogos" guardados ficaram velhos (sem ele).
    if (momento != null && momento.encerrada && jogoDoMomento.value?.encerrada != true) {
      await CacheManager.instance.invalidar('futebol_resultados_${timeAtual.espnId}');
    }
    jogoDoMomento.value = momento;

    // Perto do jogo: confere a cada minuto. Longe: a cada 15 min.
    _monitor = Timer(
        momento != null ? const Duration(minutes: 1) : const Duration(minutes: 15),
        _verificarJogo);
  }

  void _detectarGol(Partida? p) {
    if (p == null || (!p.aoVivo && !p.encerrada)) {
      _placarAnterior = null;
      return;
    }
    final placar = '${p.id}:${p.mandante.gols ?? 0}-${p.visitante.gols ?? 0}';
    final antes = _placarAnterior;
    _placarAnterior = placar;
    if (antes == null || antes == placar || !antes.startsWith('${p.id}:')) {
      if (p.encerrada && antes != null && antes.startsWith('${p.id}:') &&
          ultimoLance.value?.startsWith('Fim de jogo') != true) {
        ultimoLance.value =
            'Fim de jogo: ${p.mandante.nome} ${p.mandante.gols} x ${p.visitante.gols} ${p.visitante.nome}';
      }
      return;
    }
    final golsAntes = antes.split(':').last.split('-').map(int.parse).toList();
    final casaMarcou = (p.mandante.gols ?? 0) > golsAntes[0];
    final quem = casaMarcou ? p.mandante : p.visitante;
    final nosso = quem.id == timeAtual.espnId;
    ultimoLance.value = '${nosso ? 'Gol do ${quem.nome}!' : 'Gol do ${quem.nome}.'} '
        '${p.mandante.nome} ${p.mandante.gols} x ${p.visitante.gols} ${p.visitante.nome}';
  }
}

/// Lance do jogo ao vivo: gol, cartão amarelo ou vermelho.
class Lance {
  final String tipo; // 'gol', 'amarelo', 'vermelho'
  final String minuto; // "53'", "90'+2'"
  final int timeId;
  final String jogador;
  final String detalhe; // "assist. Maurício", "contra", "pênalti"
  const Lance(this.tipo, this.minuto, this.timeId, this.jogador, [this.detalhe = '']);
}

/// Uma estatística lado a lado: "Posse de bola 58% x 42%".
class Estatistica {
  final String nome;
  final String casa;
  final String fora;
  final double vCasa;
  final double vFora;
  const Estatistica(this.nome, this.casa, this.fora, this.vCasa, this.vFora);
}

class JogoAoVivo {
  final List<Lance> lances;
  final List<Estatistica> estatisticas;
  const JogoAoVivo(this.lances, this.estatisticas);
}

/// Lances e estatísticas do resumo da ESPN. [casaId] = mandante (as
/// estatísticas ficam na ordem casa x fora). Função pura — testada.
JogoAoVivo parseAoVivo(Map<String, dynamic> json, int casaId) {
  final lances = <Lance>[];
  for (final k in (json['keyEvents'] as List? ?? []).whereType<Map>()) {
    final texto = '${(k['type'] as Map?)?['text'] ?? ''}'.toLowerCase();
    final String tipo;
    if (k['scoringPlay'] == true || texto.contains('goal')) {
      tipo = 'gol';
    } else if (texto.contains('red card')) {
      tipo = 'vermelho';
    } else if (texto.contains('yellow card')) {
      tipo = 'amarelo';
    } else {
      continue; // substituições, início, intervalo...
    }
    final nomes = [
      for (final p in (k['participants'] as List? ?? []).whereType<Map>())
        '${(p['athlete'] as Map?)?['displayName'] ?? ''}',
    ].where((s) => s.isNotEmpty).toList();
    var detalhe = '';
    if (tipo == 'gol') {
      if (texto.contains('own goal')) {
        detalhe = 'contra';
      } else if (texto.contains('penalty')) {
        detalhe = 'pênalti';
      } else if (nomes.length > 1) {
        detalhe = 'assist. ${nomes[1]}';
      }
    }
    lances.add(Lance(
      tipo,
      '${(k['clock'] as Map?)?['displayValue'] ?? ''}',
      int.tryParse('${(k['team'] as Map?)?['id']}') ?? -1,
      nomes.isEmpty ? '' : nomes.first,
      detalhe,
    ));
  }

  final times = (json['boxscore'] as Map?)?['teams'] as List? ?? [];
  Map<String, String> stats(Map t) => {
        for (final s in (t['statistics'] as List? ?? []).whereType<Map>())
          '${s['name']}': '${s['displayValue'] ?? ''}',
      };
  Map<String, String>? casa, fora;
  for (final t in times.whereType<Map>()) {
    final id = int.tryParse('${(t['team'] as Map?)?['id']}');
    if (id == casaId) {
      casa = stats(t);
    } else {
      fora = stats(t);
    }
  }
  final estat = <Estatistica>[];
  if (casa != null && fora != null) {
    for (final (chave, nome, pct) in const [
      ('possessionPct', 'Posse de bola', true),
      ('totalShots', 'Finalizações', false),
      ('shotsOnTarget', 'No gol', false),
      ('wonCorners', 'Escanteios', false),
      ('foulsCommitted', 'Faltas', false),
      ('offsides', 'Impedimentos', false),
    ]) {
      final a = double.tryParse(casa[chave] ?? '');
      final b = double.tryParse(fora[chave] ?? '');
      if (a == null || b == null) continue;
      String txt(double v) => pct ? '${v.round()}%' : '${v.round()}';
      estat.add(Estatistica(nome, txt(a), txt(b), a, b));
    }
  }
  return JogoAoVivo(lances, estat);
}

class Jogador {
  final String camisa;
  final String nome;
  final String posicao;
  const Jogador(this.camisa, this.nome, this.posicao);
}

class Escalacao {
  final int timeId;
  final String time;
  final String formacao;
  final List<Jogador> titulares;
  final String cor; // "417505" (hex, sem #), vazio se a ESPN não mandar
  const Escalacao(this.timeId, this.time, this.formacao, this.titulares, [this.cor = '']);
}
