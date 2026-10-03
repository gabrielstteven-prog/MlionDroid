import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ponte com o lado Android (MainActivity.kt) para recursos de "painel de
/// parede": manter a tela ligada, ajustar o brilho (Modo Noite) e
/// reconhecimento de voz.
class Sistema {
  static const _canal = MethodChannel('com.mlion_droid/sistema');
  static const _canalVoz = MethodChannel('com.mlion_droid/speech');

  /// Impede que a tela apague sozinha enquanto o app está aberto.
  static Future<void> manterTelaLigada(bool ligada) async {
    try {
      await _canal.invokeMethod('manterTelaLigada', {'ligada': ligada});
    } catch (e) {
      debugPrint('Sistema.manterTelaLigada: $e');
    }
  }

  /// Brilho da janela do app, de 0.0 a 1.0. null = brilho do sistema.
  static Future<void> brilho(double? valor) async {
    try {
      await _canal.invokeMethod('brilho', {'valor': valor ?? -1.0});
    } catch (e) {
      debugPrint('Sistema.brilho: $e');
    }
  }

  /// Abre o reconhecimento de voz do Android e devolve o texto falado
  /// ('' se o usuário cancelar ou não houver reconhecimento disponível).
  static Future<String> ouvir({String prompt = 'Fale agora...'}) async {
    try {
      final r = await _canalVoz.invokeMethod<String>(
          'startListening', {'language': 'pt-BR', 'prompt': prompt});
      return r ?? '';
    } catch (e) {
      debugPrint('Sistema.ouvir: $e');
      return '';
    }
  }
}
