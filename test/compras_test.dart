import 'package:flutter_test/flutter_test.dart';
import 'package:mlion_droid/services/compras.dart';

void main() {
  group('Lista de compras — quantidade', () {
    test('lê a quantidade falada e passa para o singular', () {
      expect(lerItemFalado('3 sabonetes'), const ItemLista('Sabonete', 3));
      expect(lerItemFalado('três sabonetes'), const ItemLista('Sabonete', 3));
      expect(lerItemFalado('duas caixas de leite'), const ItemLista('Caixa de leite', 2));
      expect(lerItemFalado('10 pães'), const ItemLista('Pão', 10));
      expect(lerItemFalado('4 limões'), const ItemLista('Limão', 4));
      expect(lerItemFalado('2 papéis higiênicos'), const ItemLista('Papel higiênico', 2));
      expect(lerItemFalado('meia dúzia de ovos'), const ItemLista('Ovos', 6));
      expect(lerItemFalado('uma dúzia de bananas'), const ItemLista('Bananas', 12));
    });

    test('sem número ou com "um" fica sem quantidade', () {
      expect(lerItemFalado('sabonete'), const ItemLista('Sabonete'));
      expect(lerItemFalado('um sabonete'), const ItemLista('Sabonete'));
      expect(lerItemFalado('pão de queijo'), const ItemLista('Pão de queijo'));
    });

    test('título no Google Tasks vai e volta', () {
      expect(const ItemLista('Sabonete', 3).titulo, 'Sabonete (3)');
      expect(const ItemLista('Sabonete').titulo, 'Sabonete');
      expect(itemDoTitulo('Sabonete (3)'), const ItemLista('Sabonete', 3));
      expect(itemDoTitulo('3x Sabonete'), const ItemLista('Sabonete', 3));
      expect(itemDoTitulo('Sabonete x3'), const ItemLista('Sabonete', 3));
      expect(itemDoTitulo('Leite'), const ItemLista('Leite'));
      expect(itemDoTitulo('Pilha AA'), const ItemLista('Pilha AA'));
    });

    test('resposta à pergunta da quantidade', () {
      expect(quantidadeDaResposta('três'), 3);
      expect(quantidadeDaResposta('Sim, 3'), 3);
      expect(quantidadeDaResposta('coloca duas'), 2);
      expect(quantidadeDaResposta('meia dúzia'), 6);
      expect(quantidadeDaResposta('sim'), isNull);
      expect(respostaPositiva('sim'), isTrue);
      expect(respostaNegativa('não precisa'), isTrue);
      expect(respostaNegativa('sim, três'), isFalse);
    });
  });
}
