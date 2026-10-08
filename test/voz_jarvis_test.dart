import 'package:flutter_test/flutter_test.dart';
import 'package:mlion_droid/services/voz_jarvis_service.dart';

void main() {
  group('Voz do Jarvis (gravada antes)', () {
    test('divide em frases e troca ° por graus', () {
      expect(VozJarvis.frases('Bom dia!  Faz 22° lá fora. Quer café?'),
          ['Bom dia!', 'Faz 22 graus lá fora.', 'Quer café?']);
      expect(VozJarvis.frases('   '), isEmpty);
    });

    test('só guarda frases curtas e sem números', () {
      expect(VozJarvis.valeGuardar('Pronto, anotei na lista.'), isTrue);
      expect(VozJarvis.valeGuardar('Agora são 7 horas.'), isFalse);
      expect(VozJarvis.valeGuardar('x' * 71), isFalse);
    });
  });
}
