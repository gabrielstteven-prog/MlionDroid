import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:mlion_droid/barra_info.dart' show textoContagem;
import 'package:mlion_droid/services/football_service.dart';
import 'package:mlion_droid/widgets/campo_tatico.dart';

List<String> nomes(List<Jogador> l) => l.map((j) => j.nome).toList();

void main() {
  group('Campinho com o esquema tático', () {
    test('Palmeiras 3-4-2-1 (escalação real da ESPN)', () {
      const t = [
        Jogador('1', 'Carlos Miguel', 'G'),
        Jogador('15', 'G. Gómez', 'CD'),
        Jogador('2', 'A. Barboza', 'CD-L'),
        Jogador('26', 'Murilo', 'CD-R'),
        Jogador('17', 'M. Freitas', 'CM-L'),
        Jogador('8', 'A. Pereira', 'CM-R'),
        Jogador('56', 'Arthur Gabriel', 'LM'),
        Jogador('12', 'Khellven', 'RM'),
        Jogador('9', 'V. Roque', 'F'),
        Jogador('42', 'J. López', 'CF-L'),
        Jogador('30', 'L. Evangelista', 'CF-R'),
      ];
      final l = linhasDoEsquema('3-4-2-1', t);
      expect(l.map((x) => x.length).toList(), [1, 3, 4, 2, 1]);
      expect(nomes(l[0]), ['Carlos Miguel']);
      expect(nomes(l[1]), ['A. Barboza', 'G. Gómez', 'Murilo']);
      expect(nomes(l[2]), ['Arthur Gabriel', 'M. Freitas', 'A. Pereira', 'Khellven']);
      expect(nomes(l[3]), ['J. López', 'L. Evangelista']);
      expect(nomes(l[4]), ['V. Roque']);
    });

    test('Bahia 4-3-3', () {
      const t = [
        Jogador('1', 'Ronaldo', 'G'),
        Jogador('4', 'Kanu', 'CD-L'),
        Jogador('33', 'D. Duarte', 'CD-R'),
        Jogador('46', 'Luciano Juba', 'LB'),
        Jogador('31', 'R. Gómez', 'RB'),
        Jogador('5', 'N. Acevedo', 'CM'),
        Jogador('6', 'Jean Lucas', 'LM'),
        Jogador('11', 'R. Nestor', 'RM'),
        Jogador('9', 'A. Veliz', 'F'),
        Jogador('16', 'Erick Pulga', 'LF'),
        Jogador('99', 'C. Olivera', 'RF'),
      ];
      final l = linhasDoEsquema('4-3-3', t);
      expect(l.map((x) => x.length).toList(), [1, 4, 3, 3]);
      expect(nomes(l[1]), ['Luciano Juba', 'Kanu', 'D. Duarte', 'R. Gómez']);
      expect(nomes(l[3]), ['Erick Pulga', 'A. Veliz', 'C. Olivera']);
    });

    test('formação que não bate agrupa por posição', () {
      const t = [Jogador('1', 'A', 'G'), Jogador('2', 'B', 'CD'), Jogador('3', 'C', 'F')];
      expect(linhasDoEsquema('', t).map((x) => x.length).toList(), [1, 1, 1]);
    });

    test('cor do time em hexadecimal', () {
      expect(corHex('417505', const Color(0)).toARGB32(), 0xFF417505);
      expect(corHex('', const Color(0xFF123456)).toARGB32(), 0xFF123456);
    });
  });

  test('contagem do cartão do jogo', () {
    final agora = DateTime(2026, 10, 8, 20, 50);
    expect(textoContagem(DateTime(2026, 10, 8, 21, 30), agora), 'começa em 40 min');
    expect(textoContagem(DateTime(2026, 10, 8, 22, 5), agora), 'começa em 1h15');
    expect(textoContagem(DateTime(2026, 10, 8, 20, 50, 30), agora), 'começa em instantes');
  });
}
