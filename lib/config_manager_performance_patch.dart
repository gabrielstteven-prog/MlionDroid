// ═══════════════════════════════════════════════════════════════════════════════
//  PATCH — config_manager.dart
//
//  Adicione a entrada 'performance' no Map defaults, dentro da classe
//  ConfigManager. Localização: pode ir logo após a entrada 'barra_info'
//  (ou antes de 'spotify', a ordem não importa).
// ═══════════════════════════════════════════════════════════════════════════════

// Trecho a ADICIONAR no Map defaults:
/*
    'performance': {
      'modo_economico': false, // false = visual completo (padrão atual do app)
    },
*/

// Nenhuma outra mudança é necessária neste arquivo — o PerformanceManager
// usa apenas config.getBool('performance', 'modo_economico', false) e
// config.set('performance', 'modo_economico', valor), que já funcionam
// com os métodos genéricos get/set/getBool que a classe já possui.
