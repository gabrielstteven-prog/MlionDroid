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
    test('página do time traz o próximo jogo com canais', () {
      final caminho = TvService.caminhoDoTime(
          _fixture('futebolnatv_times.html'), ['Palmeiras', 'SE Palmeiras']);
      expect(caminho, '/time/palmeiras-va41lxp2r4');
      final jogos = TvService.parsePagina(_fixture('futebolnatv_time.html'));
      final j = TvService.encontrarJogo(
          jogos.reversed.toList(), ['Palmeiras'], ['Bahia']);
      expect(j, isNotNull);
      expect(j!.canais, containsAll(['GLOBO', 'PREMIERE 2']));
    });

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

  group('Notícias', () {
    test('foto repetida em outra matéria some (mesmo arquivo, outro tamanho)', () {
      Noticia n(String t, String img) =>
          Noticia(titulo: t, descricao: '', link: t, imagem: img);
      final r = NewsService.semFotosRepetidas([
        n('a', 'https://s2.glbimg.com/x=/600x400/i.s3/afp-flaco.jpg'),
        n('b', 'https://s2.glbimg.com/y=/1080x608/i.s3/afp-flaco.jpg'),
        n('c', 'https://s2.glbimg.com/z/outra.jpg'),
        n('d', ''),
      ]);
      expect(r.map((e) => e.imagem.isNotEmpty), [true, false, true, false]);
      expect(r[1].titulo, 'b');
    });
  });

  group('INMET', () {
    test('vários alertas viram um só: o mais grave, do início ao fim', () {
      final a = AvisosService.consolidarInmet([
        {'descricao': 'Acumulado de Chuva', 'severidade': 'Perigo Potencial',
          'inicio': '2026-10-04 00:00:00', 'fim': '2026-10-04 23:59:00'},
        {'descricao': 'Tempestade', 'severidade': 'Perigo',
          'inicio': '2026-10-04 00:01:00', 'fim': '2026-10-06 23:59:00'},
        {'descricao': 'Tempestade', 'severidade': 'Perigo Potencial',
          'inicio': '2026-10-04 00:02:00', 'fim': '2026-10-05 12:00:00'},
        {'descricao': 'Baixa Umidade', 'severidade': 'Perigo',
          'inicio': '2026-10-01 10:00:00', 'fim': '2026-10-02 18:00:00'}, // vencido
      ], DateTime(2026, 10, 3, 20));
      expect(a!.titulo, 'Defesa Civil: Tempestade');
      expect(a.nivel, NivelAviso.perigo);
      expect(a.detalhe, 'Alerta laranja a partir de amanhã, 0h');
    });

    test('sem alerta vigente, nada de Defesa Civil', () {
      expect(
          AvisosService.consolidarInmet([
            {'descricao': 'Tempestade', 'severidade': 'Perigo',
              'inicio': '2026-10-01 00:00:00', 'fim': '2026-10-02 00:00:00'},
          ], DateTime(2026, 10, 3, 20)),
          isNull);
    });

    test('aviso oficial curto, com cor e prazo', () {
      final a = AvisosService.avisoInmet({
        'descricao': 'Tempestade',
        'severidade': 'Perigo',
        'riscos': '[Chuva entre 30 e 60 mm/h, ventos intensos. Queda de árvores.]',
        'inicio': '2026-10-03 10:00:00',
        'fim': '2026-10-06 23:59:00',
      }, DateTime(2026, 10, 3, 15));
      expect(a.titulo, 'Defesa Civil: Tempestade');
      expect(a.nivel, NivelAviso.perigo);
      expect(a.detalhe, 'Alerta laranja até terça, 23h59');
    });
  });
}
