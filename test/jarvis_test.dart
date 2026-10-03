import 'package:flutter_test/flutter_test.dart';
import 'package:mlion_droid/services/ia_service.dart';
import 'package:mlion_droid/services/voz_service.dart';

void main() {
  group('IA — leitura das respostas', () {
    test('Gemini: junta as partes e ignora o raciocínio', () {
      final r = IaService.textoGemini({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'pensando...', 'thought': true},
                {'text': 'Bom dia! '},
                {'text': 'Hoje faz **23 graus**.'},
              ]
            }
          }
        ]
      });
      expect(r, 'Bom dia! Hoje faz 23 graus.');
    });

    test('Gemini sem candidatos devolve null', () {
      expect(IaService.textoGemini({'candidates': []}), isNull);
      expect(IaService.textoGemini({}), isNull);
    });

    test('Groq (formato OpenAI)', () {
      final r = IaService.textoGroq({
        'choices': [
          {
            'message': {'content': '- Chuva às 17h\n- Leve casaco'}
          }
        ]
      });
      expect(r, 'Chuva às 17h\nLeve casaco');
    });

    test('limpa markdown para a voz não ler símbolos', () {
      expect(IaService.limparParaFala('## Título\n**forte** e `código`'),
          'Título\nforte e código');
    });
  });

  test('ElevenLabs: lista de vozes', () {
    final v = VozService.parseVozes({
      'voices': [
        {'voice_id': 'abc', 'name': 'Rachel', 'category': 'premade'},
        {'voice_id': '', 'name': 'Quebrada'},
        {'voice_id': 'xyz', 'name': 'Minha voz', 'category': 'cloned'},
      ]
    });
    expect(v.map((e) => e.nome), ['Rachel', 'Minha voz']);
    expect(v.first.id, 'abc');
  });
}
