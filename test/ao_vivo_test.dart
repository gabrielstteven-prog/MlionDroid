import 'package:flutter_test/flutter_test.dart';
import 'package:mlion_droid/services/football_service.dart';

void main() {
  test('lances e estatísticas do jogo ao vivo (formato da ESPN)', () {
    final json = {
      'keyEvents': [
        {'type': {'text': 'Kickoff'}},
        {
          'type': {'text': 'Yellow Card'},
          'clock': {'displayValue': "39'"},
          'team': {'id': '2029'},
          'participants': [
            {'athlete': {'displayName': 'Murilo'}}
          ],
        },
        {
          'type': {'text': 'Substitution'},
          'clock': {'displayValue': "45'"},
          'team': {'id': '2029'},
        },
        {
          'type': {'text': 'Red Card'},
          'clock': {'displayValue': "50'"},
          'team': {'id': '4773'},
          'participants': [
            {'athlete': {'displayName': 'Igor Torres'}}
          ],
        },
        {
          'type': {'text': 'Goal'},
          'scoringPlay': true,
          'clock': {'displayValue': "53'"},
          'team': {'id': '2029'},
          'participants': [
            {'athlete': {'displayName': 'Luighi Hanri'}},
            {'athlete': {'displayName': 'Maurício'}},
          ],
        },
      ],
      'boxscore': {
        'teams': [
          {
            'team': {'id': '4773'},
            'statistics': [
              {'name': 'possessionPct', 'displayValue': '41.2'},
              {'name': 'totalShots', 'displayValue': '9'},
            ],
          },
          {
            'team': {'id': '2029'},
            'statistics': [
              {'name': 'possessionPct', 'displayValue': '58.8'},
              {'name': 'totalShots', 'displayValue': '18'},
            ],
          },
        ],
      },
    };
    final v = parseAoVivo(json, 4773); // Portuguesa em casa
    expect(v.lances.map((l) => '${l.tipo} ${l.minuto} ${l.jogador}').toList(), [
      "amarelo 39' Murilo",
      "vermelho 50' Igor Torres",
      "gol 53' Luighi Hanri",
    ]);
    expect(v.lances.last.detalhe, 'assist. Maurício');
    expect(v.lances.last.timeId, 2029);
    expect(v.estatisticas.first.nome, 'Posse de bola');
    expect(v.estatisticas.first.casa, '41%');
    expect(v.estatisticas.first.fora, '59%');
    expect(v.estatisticas[1].fora, '18');
  });
}
