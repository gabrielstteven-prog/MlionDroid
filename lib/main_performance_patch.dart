// ═══════════════════════════════════════════════════════════════════════════════
//  PATCH — main.dart
//
//  1. Adicionar import no topo (junto com os outros managers):
//       import 'performance_manager.dart';
//
//  2. Na função main(), logo depois de:
//       await ConfigManager().carregar();
//     adicionar:
//       PerformanceManager.instance.carregar();
//
//     Precisa ser DEPOIS do ConfigManager().carregar() porque o
//     PerformanceManager lê o valor salvo a partir dele.
//
//  Trecho final da main() deve ficar assim:
//
//    await ConfigManager().carregar();
//    PerformanceManager.instance.carregar();     // ← NOVO
//    InfoHub.instance.iniciar();
//    SpotifyManager.instance.iniciar();
// ═══════════════════════════════════════════════════════════════════════════════
