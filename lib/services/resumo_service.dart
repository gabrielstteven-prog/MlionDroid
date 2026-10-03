import 'package:flutter/material.dart';

import '../cache_manager.dart';
import '../util.dart';
import 'football_service.dart';
import 'tv_service.dart';
import 'weather_service.dart';

/// Uma linha do resumo do dia.
class ItemResumo {
  final IconData icone;
  final String texto;
  final Color cor;
  const ItemResumo(this.icone, this.texto, this.cor);
}

/// "Resumo do dia": junta clima, agenda, aniversários, jogo e compras em
/// frases curtas — o que um assistente diria de manhã. Usa os dados que o
/// app já guardou (cache), então é instantâneo e funciona sem internet.
class ResumoService {
  ResumoService._();
  static final ResumoService instance = ResumoService._();

  static const _azul = Color(0xFF7CC6FF);
  static const _verde = Color(0xFF6FD6A0);
  static const _amarelo = Color(0xFFFFD36B);
  static const _rosa = Color(0xFFE7A3F0);

  Future<List<ItemResumo>> montar([DateTime? quando]) async {
    final agora = quando ?? DateTime.now();
    final itens = <ItemResumo>[];

    // ── Clima ──────────────────────────────────────────────────────────────
    final clima = WeatherService.instance.atual ?? await WeatherService.instance.obter();
    if (clima != null && clima.hoje != null) {
      final h = clima.hoje!;
      itens.add(ItemResumo(Icons.thermostat_rounded,
          'Hoje entre ${h.min}° e ${h.max}°, ${descricaoClima(h.codigo).toLowerCase()}.', _azul));
      final chuva = clima.chuvaRestanteHoje(agora);
      if (chuva.horarios.isNotEmpty) {
        itens.add(ItemResumo(Icons.umbrella_rounded,
            'Leve guarda-chuva: chuva possível a partir das ${chuva.horarios.first.hour}h (${chuva.maxima}%).',
            _azul));
      }
    }

    // ── Agenda e aniversários (cache do Calendário) ────────────────────────
    final agenda = await CacheManager.instance
        .obterEntrada<Map<String, dynamic>>('calendario_itens_v2');
    if (agenda != null) {
      final hoje = (agenda.dados[soData(agora).toIso8601String()] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final aniversarios = hoje.where((e) => e['aniversario'] == true).toList();
      final eventos = hoje
          .where((e) => e['tipo'] == 'evento' && e['aniversario'] != true)
          .toList();
      final tarefas =
          hoje.where((e) => e['tipo'] == 'tarefa' && e['concluido'] != true).length;

      for (final a in aniversarios.take(3)) {
        itens.add(ItemResumo(Icons.cake_rounded, '${a['titulo']}.', _rosa));
      }
      if (eventos.isNotEmpty) {
        final primeiro = eventos.first;
        final hora = primeiro['horario'] as String?;
        final mais = eventos.length > 1 ? ' e mais ${eventos.length - 1}' : '';
        itens.add(ItemResumo(
            Icons.event_rounded,
            hora != null
                ? '${primeiro['titulo']} às $hora$mais.'
                : '${primeiro['titulo']}$mais.',
            _verde));
      }
      if (tarefas > 0) {
        itens.add(ItemResumo(Icons.task_alt_rounded,
            tarefas == 1 ? '1 tarefa para hoje.' : '$tarefas tarefas para hoje.', _verde));
      }
    }

    // ── Futebol ────────────────────────────────────────────────────────────
    final jogos = await FootballService.instance.proximosJogos();
    final jogo = jogos?.valor.firstOrNull;
    if (jogo != null) {
      final svc = FootballService.instance;
      final dias = soData(jogo.data).difference(soData(agora)).inDays;
      if (dias <= 1) {
        final adv = jogo.adversarioDe(svc.timeAtual.espnId).nome;
        final quando = dias == 0 ? 'hoje' : 'amanhã';
        final tv = await TvService.instance.buscarJogo(
          data: jogo.data,
          nomesTime: svc.timeAtual.todosOsNomes,
          nomesAdversario: [adv],
        );
        final canais = tv != null && tv.canais.isNotEmpty ? ', na ${tv.canais.first}' : '';
        itens.add(ItemResumo(Icons.sports_soccer_rounded,
            '${svc.timeAtual.nome} joga $quando às ${horaMinuto(jogo.data)} contra o $adv$canais.',
            _amarelo));
      }
    }

    // ── Compras ────────────────────────────────────────────────────────────
    final compras =
        await CacheManager.instance.obterEntrada<Map<String, dynamic>>('compras_itens_v2');
    final qtd = (compras?.dados['itens'] as List?)?.length ?? 0;
    if (qtd > 0) {
      itens.add(ItemResumo(Icons.shopping_cart_rounded,
          qtd == 1 ? '1 item na lista de compras.' : '$qtd itens na lista de compras.',
          _verde));
    }
    return itens;
  }

  /// Texto corrido para ler em voz alta.
  String paraFalar(String saudacao, List<ItemResumo> itens) {
    final b = StringBuffer('$saudacao. ');
    for (final i in itens) {
      b.write('${i.texto} ');
    }
    return b.toString().replaceAll('°', ' graus').trim();
  }
}
