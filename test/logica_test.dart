import 'package:flutter_test/flutter_test.dart';
import 'package:mlion_droid/cache_manager.dart';
import 'package:mlion_droid/rodizio.dart';
import 'package:mlion_droid/update_manager.dart';
import 'package:mlion_droid/util.dart';

void main() {
  group('Descanso da tela', () {
    test('ausência agendada: seg–sex 8h–18h', () {
      const uteis = [1, 2, 3, 4, 5];
      expect(emAusenciaAgendada(DateTime(2026, 10, 5, 9), uteis, 8, 18), isTrue); // segunda
      expect(emAusenciaAgendada(DateTime(2026, 10, 5, 19), uteis, 8, 18), isFalse);
      expect(emAusenciaAgendada(DateTime(2026, 10, 3, 9), uteis, 8, 18), isFalse); // sábado
    });
    test('janela que vira a noite conta pelo dia em que começou', () {
      // Sexta 22h até sábado 6h: sábado 2h ainda vale (começou na sexta).
      expect(emAusenciaAgendada(DateTime(2026, 10, 3, 2), [5], 22, 6), isTrue);
      expect(emAusenciaAgendada(DateTime(2026, 10, 4, 2), [5], 22, 6), isFalse);
    });
    test('acorda no fim do horário: hoje se ainda não passou, senão amanhã', () {
      expect(proximaHoraCheia(DateTime(2026, 10, 3, 23, 10), 6), DateTime(2026, 10, 4, 6));
      expect(proximaHoraCheia(DateTime(2026, 10, 4, 0, 5), 6), DateTime(2026, 10, 4, 6));
      expect(proximaHoraCheia(DateTime(2026, 10, 31, 6, 0), 6), DateTime(2026, 11, 1, 6));
    });
  });

  group('Rodízio de telas', () {
    const ordem = ['bom_dia', 'clima', 'palmeiras', 'fotos', 'spotify'];

    test('avança para a próxima tela elegível', () {
      expect(proximaTela(ordem, {'clima', 'palmeiras', 'fotos'}, 'clima'), 'palmeiras');
    });

    test('pula telas fora do horário (Bom Dia) e volta ao início', () {
      expect(proximaTela(ordem, {'clima', 'palmeiras', 'fotos'}, 'fotos'), 'clima');
    });

    test('funciona quando a tela atual acabou de ficar inelegível', () {
      // Spotify parou de tocar enquanto estava na tela: segue para a próxima
      // da ORDEM, em vez de pular uma tela como acontecia com o índice.
      expect(proximaTela(ordem, {'clima', 'palmeiras'}, 'spotify'), 'clima');
      expect(proximaTela(ordem, {'clima', 'fotos'}, 'palmeiras'), 'fotos');
    });

    test('volta (passo -1)', () {
      expect(proximaTela(ordem, {'clima', 'palmeiras', 'fotos'}, 'clima', passo: -1),
          'fotos');
    });

    test('sem telas elegíveis devolve null', () {
      expect(proximaTela(ordem, {}, 'clima'), isNull);
    });

    test('janela de horário que cruza a meia-noite (Modo Noite 23h→6h)', () {
      expect(horaNaJanela(23, 23, 6), isTrue);
      expect(horaNaJanela(2, 23, 6), isTrue);
      expect(horaNaJanela(6, 23, 6), isFalse);
      expect(horaNaJanela(12, 23, 6), isFalse);
      expect(horaNaJanela(5, 4, 10), isTrue);
      expect(horaNaJanela(10, 4, 10), isFalse);
    });
  });

  group('Texto', () {
    test('normalizar remove acentos e pontuação', () {
      expect(normalizar('São Paulo'), 'sao paulo');
      expect(normalizar('Athletico-PR'), 'athletico pr');
      expect(normalizar("Santa Bárbara d'Oeste"), 'santa barbara d oeste');
    });

    test('mencionaTermo exige palavra inteira', () {
      expect(mencionaTermo('Acidente em Sumaré deixa feridos', 'Sumaré'), isTrue);
      expect(mencionaTermo('Paulínia recebe feira', 'Paulo'), isFalse);
      expect(mencionaTermo('Obra em HORTOLANDIA', 'Hortolândia'), isTrue);
    });

    test('etiquetaDias usa a data civil', () {
      final agora = DateTime(2026, 10, 8, 9, 0);
      expect(etiquetaDias(DateTime(2026, 10, 8, 21, 30), agora), 'HOJE');
      expect(etiquetaDias(DateTime(2026, 10, 9, 0, 30), agora), 'AMANHÃ');
      expect(etiquetaDias(DateTime(2026, 10, 12, 16, 0), agora), 'EM 4 DIAS');
    });

    test('dia da semana por extenso (antes saía "Sáb-feira")', () {
      expect(diaSemanaLongo(DateTime(2026, 10, 10)), 'Sábado');
      expect(diaSemanaLongo(DateTime(2026, 10, 11)), 'Domingo');
      expect(diaSemanaLongo(DateTime(2026, 10, 12)), 'Segunda-feira');
    });

    test('descreverIdade', () {
      final agora = DateTime(2026, 10, 3, 12, 0);
      expect(descreverIdade(agora, agora), 'agora mesmo');
      expect(descreverIdade(DateTime(2026, 10, 3, 11, 45), agora), 'há 15 min');
      expect(descreverIdade(DateTime(2026, 10, 3, 9, 0), agora), 'há 3 h');
      expect(descreverIdade(DateTime(2026, 10, 1, 12, 0), agora), 'há 2 dias');
    });
  });

  group('Atualização', () {
    test('compara versões', () {
      expect(UpdateManager.versaoMaisNova('1.0.26', '1.0.25'), isTrue);
      expect(UpdateManager.versaoMaisNova('1.1.0', '1.0.99'), isTrue);
      expect(UpdateManager.versaoMaisNova('1.0.25', '1.0.25'), isFalse);
      expect(UpdateManager.versaoMaisNova('1.0.9', '1.0.10'), isFalse);
      expect(UpdateManager.versaoMaisNova('2.0', '1.9.9'), isTrue);
    });
  });
}
