import 'package:flutter/foundation.dart';
import 'config_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  PerformanceManager — chave manual "Modo Econômico" para tablets fracos.
//
//  IDEIA:
//  O app, por padrão, mantém 100% do visual atual (blur, Ken Burns,
//  partículas, sombras). Isso NÃO muda sozinho por benchmark automático.
//
//  Quando o usuário liga "Modo Econômico" em Configurações, cada tela
//  consulta este manager e escolhe uma versão mais leve do MESMO efeito —
//  em vez de simplesmente cortar o efeito. Ex: em vez de BackdropFilter caro,
//  um overlay sólido semitransparente que dá impressão parecida de profundidade
//  sem custar processamento de GPU por pixel.
//
//  Nenhuma tela deve decidir isso sozinha lendo o ConfigManager direto —
//  todas passam por aqui, para manter a lógica de "o que cada modo desliga"
//  centralizada e fácil de ajustar no futuro (ex.: criar um 3º nível depois).
// ═══════════════════════════════════════════════════════════════════════════
class PerformanceManager extends ChangeNotifier {
  PerformanceManager._();
  static final PerformanceManager instance = PerformanceManager._();

  final _cfg = ConfigManager();
  bool _modoEconomico = false;

  bool get modoEconomico => _modoEconomico;

  /// Chamar uma vez, logo depois de ConfigManager().carregar() no main.dart.
  void carregar() {
    _modoEconomico = _cfg.getBool('performance', 'modo_economico', false);
  }

  /// Chamado pelo Switch na tela de Configurações.
  Future<void> definirModoEconomico(bool valor) async {
    if (_modoEconomico == valor) return;
    _modoEconomico = valor;
    _cfg.set('performance', 'modo_economico', valor);
    await _cfg.salvar();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  HELPERS — cada tela consulta estes getters/métodos para decidir como
  //  se desenhar. Adicione novos aqui conforme identificar mais pontos
  //  pesados nas telas (todos seguem o mesmo princípio: "efeito visual
  //  parecido, custo bem menor").
  // ─────────────────────────────────────────────────────────────────────────

  /// true = a tela deve trocar BackdropFilter+blur por um Container sólido
  /// semitransparente (bem mais barato — sem reamostragem de pixels da GPU).
  bool get preferirOverlaySolido => _modoEconomico;

  /// Sigma de blur a usar quando a tela realmente precisa manter um
  /// BackdropFilter (ex: onde o blur é o efeito principal, não decorativo).
  /// Reduz bastante em vez de cortar 100%, mantendo alguma sensação de vidro.
  double sigmaBlur(double sigmaOriginal) {
    if (!_modoEconomico) return sigmaOriginal;
    return (sigmaOriginal * 0.25).clamp(2.0, 10.0);
  }

  /// true = animações puramente decorativas (Ken Burns, flutuação de
  /// partículas, pulso contínuo) devem ficar PARADAS (controller.stop()
  /// ou nem iniciadas). Animações de entrada/transição (curtas, ~1x) continuam
  /// normais em qualquer modo — elas não rodam em loop, custam pouco.
  bool get animacoesDecorativasAtivas => !_modoEconomico;

  /// Duração de fade/transição entre telas. No modo econômico, mais curta
  /// e mais simples também ajuda a "sentir" o app mais responsivo.
  Duration duracaoTransicao(Duration original) {
    if (!_modoEconomico) return original;
    final ms = (original.inMilliseconds * 0.6).round().clamp(150, 100000);
    return Duration(milliseconds: ms);
  }

  /// Lado máximo (em px) para decodificação de imagens grandes via
  /// ResizeImage. Evita decodificar uma foto de 12MP quando ela só vai
  /// ocupar uma fração da tela.
  int get resolucaoMaximaDecodificacao => _modoEconomico ? 900 : 1920;

  /// true = reduzir/zerar BoxShadow (blurRadius alto também custa GPU,
  /// embora bem menos que BackdropFilter).
  bool get sombrasReduzidas => _modoEconomico;
}
