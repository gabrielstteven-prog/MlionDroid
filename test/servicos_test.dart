import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mlion_droid/services/avisos_service.dart';
import 'package:mlion_droid/services/football_service.dart';
import 'package:mlion_droid/services/news_service.dart';
import 'package:mlion_droid/services/tv_service.dart';
import 'package:mlion_droid/services/weather_service.dart';

// As fixtures em test/fixtures são respostas REAIS salvas das fontes
// (ESPN, G1, futebolnatv). Se uma fonte mudar de formato, estes testes
// mostram exatamente onde quebrou.
String _fixture(String nome) => File('test/fixtures/$nome').readAsStringSync();
Map<String, dynamic> _json(String nome) =>
    jsonDecode(_fixture(nome)) as Map<String, dynamic>;

void main() {
  group('ESPN — futebol', () {
    test('lê próximos jogos com data, estádio e times', () {
      final evs = (_json('espn_proximos.json')['events'] as List)
          .cast<Map<String, dynamic>>();
      final partidas = evs.map(Partida.fromEspn).whereType<Partida>().toList();
      expect(partidas, isNotEmpty);
      final p = partidas.first;
      expect(p.mandante.nome, isNotEmpty);
      expect(p.visitante.nome, isNotEmpty);
      expect(p.envolve(2029), isTrue, reason: 'fixture é do Palmeiras (2029)');
      expect(p.mandante.escudo, startsWith('https://'));
      expect(p.competicao, isNotEmpty);
    });

    test('lê resultados com placar e V/E/D', () {
      final evs = (_json('espn_resultados.json')['events'] as List)
          .cast<Map<String, dynamic>>();
      final encerradas = evs
          .map(Partida.fromEspn)
          .whereType<Partida>()
          .where((p) => p.encerrada)
          .toList();
      expect(encerradas, isNotEmpty);
      for (final p in encerradas) {
        expect(p.mandante.gols, isNotNull, reason: 'placar de ${p.id}');
        expect(['V', 'E', 'D'], contains(p.resultadoPara(2029)));
      }
    });

    test('lê a tabela do Brasileirão (20 times, ordenada)', () {
      final grupos = FootballService.parseTabela(_json('espn_tabela.json'));
      expect(grupos, hasLength(1));
      final linhas = grupos.first.linhas;
      expect(linhas, hasLength(20));
      expect(linhas.first.posicao, 1);
      expect(linhas.last.posicao, 20);
      expect(linhas.first.pontos, greaterThanOrEqualTo(linhas.last.pontos));
      expect(linhas.any((l) => l.timeId == 2029), isTrue);
    });

    test('traduz nomes de competição', () {
      expect(traduzirCompeticao('Brazilian Serie A'), 'Brasileirão');
      expect(traduzirCompeticao('CONMEBOL Libertadores'), 'Libertadores');
      expect(traduzirCompeticao('Outra Liga'), 'Outra Liga');
    });
  });

  group('TV — onde assistir', () {
    test('lê a página real de jogos de hoje', () {
      final jogos = TvService.parsePagina(_fixture('futebolnatv_hoje.html'));
      expect(jogos, isNotEmpty);
      expect(jogos.every((j) => j.timeA.isNotEmpty && j.timeB.isNotEmpty), isTrue);
      expect(jogos.any((j) => j.canais.isNotEmpty), isTrue);
    });

    test('encontra o jogo certo e ignora sub-20/feminino', () {
      const jogos = [
        JogoNaTv('16:00', 'Palmeiras Sub-20', 'Bahia Sub-20', 'Brasileiro Sub-20', ['Canal X']),
        JogoNaTv('21:30', 'Palmeiras', 'Bahia', 'Brasileirão', ['PREMIERE', 'SPORTV']),
      ];
      final j = TvService.encontrarJogo(jogos, ['Palmeiras'], ['Bahia']);
      expect(j?.canais, ['PREMIERE', 'SPORTV']);
    });

    test('casa nomes diferentes entre fontes', () {
      const jogos = [
        JogoNaTv('19:00', 'Vasco', 'Athletico-PR', 'Brasileirão', ['GLOBO']),
      ];
      final j = TvService.encontrarJogo(
          jogos, ['Vasco', 'Vasco da Gama'], ['Athletico-PR', 'Athletico Paranaense']);
      expect(j, isNotNull);
      expect(TvService.encontrarJogo(jogos, ['Vasco'], ['Bahia']), isNull);
    });
  });

  group('Notícias', () {
    test('lê o RSS real do G1', () {
      final ns = NewsService.parseRss(_fixture('g1_campinas.xml'), rotulo: 'Região');
      expect(ns.length, greaterThan(10));
      expect(ns.every((n) => n.titulo.isNotEmpty && n.link.startsWith('http')), isTrue);
      expect(ns.where((n) => n.imagem.isNotEmpty), isNotEmpty);
    });

    test('ignora item malformado em vez de derrubar o feed', () {
      const xml = '<rss><channel>'
          '<item><title>Sem link</title></item>'
          '<item><title>Ok</title><link>https://g1.globo.com/a</link></item>'
          '</channel></rss>';
      final ns = NewsService.parseRss(xml);
      expect(ns, hasLength(1));
      expect(ns.first.titulo, 'Ok');
    });

    test('remove duplicadas', () {
      const a = Noticia(titulo: 'A', descricao: '', link: 'x', imagem: '');
      const b = Noticia(titulo: 'A de novo', descricao: '', link: 'x', imagem: '');
      expect(NewsService.semDuplicadas([a, b]), hasLength(1));
    });

    test('filtro por cidade só rotula notícias que citam a cidade', () {
      const ns = [
        Noticia(titulo: 'Chuva alaga ruas em Campinas', descricao: '', link: '1', imagem: ''),
        Noticia(titulo: 'Hortolândia abre vagas', descricao: '', link: '2', imagem: ''),
        Noticia(titulo: 'Rodovia tem trânsito', descricao: '', link: '3', imagem: ''),
      ];
      final r = NewsService.filtrarPorCidades(
        ns,
        {'Hortolândia': ['Hortolândia']},
        porCidade: 3,
        rotuloRegiao: 'Região de Campinas',
        minimoTotal: 3,
      );
      expect(r.first.rotulo, 'Hortolândia');
      expect(r.first.link, '2');
      expect(r.where((n) => n.rotulo == 'Hortolândia'), hasLength(1));
      expect(r.skip(1).every((n) => n.rotulo == 'Região de Campinas'), isTrue);
    });
  });

  group('Clima', () {
    final json = {
      'current': {
        'temperature_2m': 24.6,
        'apparent_temperature': 26.1,
        'weather_code': 0,
        'is_day': 0,
      },
      'hourly': {
        'time': ['2026-10-03T13:00', '2026-10-03T16:00', '2026-10-04T10:00'],
        'precipitation_probability': [10, 60, 90],
      },
      'daily': {
        'time': ['2026-10-03', '2026-10-04'],
        'weather_code': [0, 61],
        'temperature_2m_max': [29.4, 22.0],
        'temperature_2m_min': [15.2, 14.0],
        'precipitation_probability_max': [60, 90],
      },
    };

    test('interpreta o JSON do Open-Meteo', () {
      final d = DadosClima.fromJson(json, DateTime(2026, 10, 3, 12))!;
      expect(d.temp, 25);
      expect(d.sensacao, 26);
      expect(d.ehDia, isFalse);
      expect(d.hoje!.max, 29);
      expect(d.proximosDias.single.codigo, 61);
    });

    test('chuva considera só o resto do dia', () {
      final d = DadosClima.fromJson(json, DateTime(2026, 10, 3, 12))!;
      final c = d.chuvaRestanteHoje(DateTime(2026, 10, 3, 14));
      expect(c.maxima, 60);
      expect(c.horarios, hasLength(1));
    });

    test('emoji respeita dia/noite', () {
      expect(emojiClima(0, ehDia: true), '☀️');
      expect(emojiClima(0, ehDia: false), '🌙');
    });
    });

  group('INMET', () {
    test('aviso oficial sem colchetes e com nível certo', () {
      final a = AvisosService.avisoInmet({
        'descricao': 'Tempestade',
        'severidade': 'Perigo',
        'riscos': '[Chuva entre 30 e 60 mm/h, ventos intensos. Queda de árvores.]',
        'fim': '2026-10-06 23:59:00',
      });
      expect(a.titulo, 'Defesa Civil: Tempestade');
      expect(a.nivel, NivelAviso.perigo);
      expect(a.detalhe, isNot(contains('[')));
      expect(a.detalhe, endsWith('Chuva entre 30 e 60 mm/h, ventos intensos'));
    });
  });
}
