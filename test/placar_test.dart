import 'package:flutter_test/flutter_test.dart';
import 'package:mlion_droid/services/football_service.dart';

void main() {
  setUp(PlacarConfiavel.limpar);

  test('placar vazio da ESPN mantém o último (não volta a 0 x 0)', () {
    expect(PlacarConfiavel.corrigir('j', 1, 0), (1, 0));
    expect(PlacarConfiavel.corrigir('j', null, null), (1, 0));
    expect(PlacarConfiavel.corrigir('j', 1, 0), (1, 0));
  });

  test('placar menor só vale se repetir (gol anulado)', () {
    PlacarConfiavel.corrigir('j', 1, 0);
    expect(PlacarConfiavel.corrigir('j', 0, 0), (1, 0)); // cópia atrasada
    expect(PlacarConfiavel.corrigir('j', 1, 0), (1, 0));
    expect(PlacarConfiavel.corrigir('j', 0, 0), (1, 0));
    expect(PlacarConfiavel.corrigir('j', 0, 0), (0, 0)); // confirmado: VAR
  });

  test('gol novo entra na hora', () {
    PlacarConfiavel.corrigir('j', 1, 0);
    expect(PlacarConfiavel.corrigir('j', 1, 1), (1, 1));
  });
}
