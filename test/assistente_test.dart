import 'package:flutter_test/flutter_test.dart';
import 'package:mlion_droid/design/tema.dart';
import 'package:mlion_droid/services/assistente_service.dart';
import 'package:mlion_droid/services/football_service.dart';
import 'package:mlion_droid/services/musica_service.dart';
import 'package:mlion_droid/times.dart';

void main() {
  group('Teste real no tablet (03/10)', () {
    test('despedida encerra a conversa (mas "estou saindo" é modo ausente)', () {
      expect(interpretar('tchau, Jarvis').tipo, TipoComando.encerrar);
      expect(interpretar('valeu, pode ir').tipo, TipoComando.encerrar);
      expect(interpretar('obrigado, era só isso').tipo, TipoComando.encerrar);
      expect(interpretar('estou saindo').tipo, TipoComando.sair);
    });
    test('IA: cartão de receita e tela com fala', () {
      final c = acaoDaIa(
          '{"acao":"card","titulo":"Bolo","secoes":[{"titulo":"Ingredientes","itens":["3 ovos","farinha"]},{"titulo":"Modo de preparo","itens":["Misture","Asse"]}],"fala":"Aqui está!","emocao":"feliz"}',
          'x')!;
      expect(c.tipo, TipoComando.card);
      expect(c.card!.titulo, 'Bolo');
      expect(c.card!.secoes.length, 2);
      expect(c.card!.secoes.first.$2, ['3 ovos', 'farinha']);
      expect(c.fala, 'Aqui está!');
      final t = acaoDaIa('{"acao":"tela","tela":"clima","fala":"Vai chover às 17h."}', 'x')!;
      expect(t.tela, 'clima');
      expect(t.fala, 'Vai chover às 17h.');
    });
    test('visão: o que tenho na mão', () {
      expect(interpretar('Jarvis, olha o que eu tenho na mão').tipo, TipoComando.olhar);
      expect(interpretar('o que é isso?').tipo, TipoComando.olhar);
      expect(interpretar('veja isso aqui').tipo, TipoComando.olhar);
      expect(interpretar('quero ver o jogo').tipo, isNot(TipoComando.olhar));
    });
    test('saindo / chegando em casa', () {
      expect(interpretar('Jarvis, estou saindo').tipo, TipoComando.sair);
      expect(interpretar('tô saindo').tipo, TipoComando.sair);
      expect(interpretar('vou trabalhar').tipo, TipoComando.sair);
      expect(interpretar('cheguei').tipo, TipoComando.chegar);
      expect(interpretar('voltei, Jarvis').tipo, TipoComando.chegar);
    });
    test('troca de personalidade por voz', () {
      expect(interpretar('modo agressivo').personalidade, 'agressivo');
      expect(interpretar('Jarvis, fica sincerão').personalidade, 'sincerao');
      expect(interpretar('volta pro modo normal').personalidade, 'mordomo');
      expect(interpretar('modo comediante').tipo, TipoComando.personalidade);
    });
    test('"time de um minuto" (erro do reconhecimento) é temporizador', () {
      final c = interpretar('time de um minuto');
      expect(c.tipo, TipoComando.temporizador);
      expect(c.duracao, const Duration(minutes: 1));
    });
    test('cronometra / me lembra daqui a', () {
      expect(interpretar('cronometra 5 minutos').duracao, const Duration(minutes: 5));
      expect(interpretar('me lembra daqui a 10 minutos').duracao, const Duration(minutes: 10));
    });
    test('"mostra o time" continua abrindo a tela do time', () {
      final c = interpretar('mostra o time');
      expect(c.tipo, TipoComando.abrirTela);
      expect(c.tela, 'palmeiras');
    });
    test('pergunta livre continua indo para a IA', () {
      expect(interpretar('me conta uma curiosidade do Palmeiras').tipo, TipoComando.desconhecido);
    });
    test('IA devolve ação em JSON: o app executa', () {
      final c = acaoDaIa('{"acao":"temporizador","segundos":90}', 'x')!;
      expect(c.tipo, TipoComando.temporizador);
      expect(c.duracao, const Duration(seconds: 90));
      expect(acaoDaIa('Claro! {"acao":"compras","itens":["leite","pão"]}', 'x')!.itens,
          ['leite', 'pão']);
      expect(acaoDaIa('{"acao":"tela","tela":"clima"}', 'x')!.tela, 'clima');
      expect(acaoDaIa('O Palmeiras foi fundado em 1914.', 'x'), isNull);
      expect(acaoDaIa('{"acao":"tela","tela":"hackear"}', 'x'), isNull);
      expect(acaoDaIa('{"acao":"personalidade","modo":"agressivo"}', 'x')!.personalidade,
          'agressivo');
    });
  });

  group('Assistente — interpretar comandos falados', () {
    test('temporizador em vários jeitos de falar', () {
      expect(interpretar('timer de 10 minutos').duracao, const Duration(minutes: 10));
      expect(interpretar('Temporizador de cinco minutos').duracao, const Duration(minutes: 5));
      expect(interpretar('cronômetro de meia hora').duracao, const Duration(minutes: 30));
      expect(interpretar('timer de 30 segundos').duracao, const Duration(seconds: 30));
      expect(interpretar('alarme de uma hora').duracao, const Duration(hours: 1));
      expect(interpretar('timer de 10 minutos').tipo, TipoComando.temporizador);
    });

    test('cancelar temporizador', () {
      expect(interpretar('cancela o timer').tipo, TipoComando.cancelarTemporizador);
      expect(interpretar('parar o alarme').tipo, TipoComando.cancelarTemporizador);
    });

    test('lista de compras mantém acentos e separa itens', () {
      final c = interpretar('Adiciona leite, pão e café na lista de compras');
      expect(c.tipo, TipoComando.adicionarCompra);
      expect(c.itens, ['leite', 'pão', 'café']);
      expect(interpretar('comprar papel higiênico').itens, ['papel higiênico']);
    });

    test('lista de compras: jeitos naturais de pedir', () {
      expect(itensDeCompra('Jarvis, adiciona leite'), ['leite']);
      expect(itensDeCompra('Pode adicionar arroz e feijão na lista'), ['arroz', 'feijão']);
      expect(itensDeCompra('adiciona na lista de compras leite'), ['leite']);
      expect(itensDeCompra('Adicionar à lista de compras: ovos'), ['ovos']);
      expect(itensDeCompra('na lista de compras adiciona sabão em pó'), ['sabão em pó']);
      expect(itensDeCompra('coloca pra mim manteiga na lista do mercado'), ['manteiga']);
      expect(itensDeCompra('eu quero adicionar leite também'), ['leite']);
      expect(itensDeCompra('põe banana mais maçã na lista'), ['banana', 'maçã']);
      expect(itensDeCompra('anota café, açúcar e pão de queijo'),
          ['café', 'açúcar', 'pão de queijo']);
      expect(itensDeCompra('adicionar na minha lista de compras sabonete'), ['sabonete']);
      expect(itensDeCompra('adicionar adicionar sabonete na minha lista de compras'), ['sabonete']);
      expect(itensDeCompra('adicionar 3 sabonetes na minha lista de compras'), ['3 sabonetes']);
      // Não são compras:
      expect(itensDeCompra('coloca a tela do clima'), isNull);
      expect(itensDeCompra('bota uma música'), isNull);
      expect(itensDeCompra('o que tem na lista de compras?'), isNull);
      expect(itensDeCompra('qual a previsão para amanhã'), isNull);
    });

    test('perguntas de clima, jogo, hora e resumo', () {
      expect(interpretar('vai chover hoje?').tipo, TipoComando.clima);
      expect(interpretar('qual a temperatura amanhã').tipo, TipoComando.clima);
      expect(interpretar('quando é o próximo jogo do Palmeiras').tipo, TipoComando.jogo);
      expect(interpretar('que horas são').tipo, TipoComando.hora);
      expect(interpretar('como está o meu dia').tipo, TipoComando.resumo);
    });

    test('abrir telas', () {
      expect(interpretar('mostra o clima').tela, 'clima');
      expect(interpretar('abre a agenda').tela, 'calendario');
      expect(interpretar('mostrar a tabela').tela, 'classificacao');
    });

    test('o que não entende fica para o Jarvis no futuro', () {
      expect(interpretar('qual a capital da Mongólia').tipo, TipoComando.desconhecido);
      expect(interpretar('').tipo, TipoComando.desconhecido);
    });

    test('descreve durações em português', () {
      expect(descreverDuracao(const Duration(minutes: 1)), '1 minuto');
      expect(descreverDuracao(const Duration(minutes: 25)), '25 minutos');
      expect(descreverDuracao(const Duration(hours: 2)), '2 horas');
      expect(descreverDuracao(const Duration(seconds: 45)), '45 segundos');
    });
  });

  group('Letras sincronizadas (LRCLIB)', () {
    const lrc = '[00:20.32] Todos os dias quando acordo\n'
        '[00:26.91] Não tenho mais o tempo que passou\n'
        '[00:30.74] Mas tenho muito tempo\n';

    test('lê o formato LRC', () {
      final linhas = MusicaService.parseLrc(lrc);
      expect(linhas, hasLength(3));
      expect(linhas.first.tempo, const Duration(seconds: 20, milliseconds: 320));
      expect(linhas[1].texto, 'Não tenho mais o tempo que passou');
    });

    test('acha a linha cantada no momento', () {
      final letra = Letra(MusicaService.parseLrc(lrc), '');
      expect(letra.indiceEm(const Duration(seconds: 10)), -1);
      expect(letra.indiceEm(const Duration(seconds: 21)), 0);
      expect(letra.indiceEm(const Duration(seconds: 29)), 1);
      expect(letra.indiceEm(const Duration(minutes: 3)), 2);
    });
  });

  group('Escalação', () {
    test('lê só os titulares e a formação', () {
      final json = {
        'rosters': [
          {
            'team': {'id': '2029', 'shortDisplayName': 'Palmeiras'},
            'formation': '4-2-3-1',
            'roster': [
              {'starter': true, 'jersey': '21', 'athlete': {'shortName': 'Weverton'}, 'position': {'abbreviation': 'G'}},
              {'starter': false, 'jersey': '1', 'athlete': {'shortName': 'Reserva'}},
            ],
          },
          {
            'team': {'id': '9967', 'shortDisplayName': 'Bahia'},
            'roster': [],
          },
        ],
      };
      final esc = FootballService.parseEscalacao(json);
      expect(esc, hasLength(1), reason: 'time sem escalação publicada é ignorado');
      expect(esc.first.formacao, '4-2-3-1');
      expect(esc.first.titulares.single.nome, 'Weverton');
    });
  });

  group('Padrão visual', () {
    test('o céu acompanha o período do dia', () {
      expect(periodoDaHora(3), Periodo.madrugada);
      expect(periodoDaHora(8), Periodo.manha);
      expect(periodoDaHora(14), Periodo.tarde);
      expect(periodoDaHora(18), Periodo.fimDeTarde);
      expect(periodoDaHora(22), Periodo.noite);
    });

    test('times com cor branca/preta usam o destaque padrão', () {
      expect(corDoTime(timesDisponiveis['corinthians']!), Destaques.time);
      expect(corDoTime(timesDisponiveis['flamengo']!), isNot(Destaques.time));
    });
  });
}
