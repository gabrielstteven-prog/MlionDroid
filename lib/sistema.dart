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

  /// Fala o texto em voz alta (TTS nativo do Android, em português) e só
  /// retorna quando a fala termina (com limite de segurança).
  static Future<void> falar(String texto) async {
    try {
      await _canal
          .invokeMethod('falar', {'texto': texto})
          .timeout(Duration(seconds: 8 + texto.length ~/ 10), onTimeout: () => null);
    } catch (e) {
      debugPrint('Sistema.falar: $e');
    }
  }

  /// Toca um arquivo de áudio (MP3 da voz premium) e só retorna quando ele
  /// termina. false = não conseguiu tocar (o chamador cai para o TTS).
  static Future<bool> tocarAudio(String caminho) async {
    try {
      return await _canal.invokeMethod<bool>('tocarAudio', {'caminho': caminho}) ?? false;
    } catch (e) {
      debugPrint('Sistema.tocarAudio: $e');
      return false;
    }
  }

  // ── Descanso da tela (Modo Noite) ─────────────────────────────────────

  /// Descanso: desliga a luz de fundo da tela (sem bloquear o tablet) e
  /// agenda o despertar para [acordarEm].
  /// Com [luz]/[proximidade], um serviço vigia esses sensores e acende a
  /// tela quando a luz do cômodo acende ou alguém chega perto.
  static Future<bool> desligarTela(
      {required DateTime acordarEm,
      bool luz = false,
      bool proximidade = false,
      bool camera = false}) async {
    _prepararEventos();
    try {
      return await _canal.invokeMethod<bool>('desligarTela', {
            'acordarEm': acordarEm.millisecondsSinceEpoch,
            'luz': luz,
            'proximidade': proximidade,
            'camera': camera,
          }) ??
          false;
    } catch (e) {
      debugPrint('Sistema.desligarTela: $e');
      return false;
    }
  }

  /// O app pode usar a câmera (descanso inteligente)?
  static Future<bool> cameraPermitida() async {
    try {
      return await _canal.invokeMethod<bool>('cameraPermitida') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> pedirCamera() async {
    try {
      await _canal.invokeMethod('pedirCamera');
    } catch (_) {}
  }

  /// Tira uma foto com a câmera da frente ("olha o que eu tenho na mão").
  /// Devolve o caminho do JPEG, "sem_permissao" ou null se falhar.
  static Future<String?> tirarFoto() async {
    try {
      return await _canal.invokeMethod<String>('tirarFoto');
    } catch (e) {
      debugPrint('Sistema.tirarFoto: $e');
      return null;
    }
  }

  /// Liga a câmera só para conferir se há alguém (tela acesa). false = sem
  /// permissão da câmera.
  static Future<bool> observarPresenca() async {
    try {
      return await _canal.invokeMethod<bool>('observarPresenca') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Para de vigiar os sensores do descanso.
  static Future<void> pararDescanso() async {
    try {
      await _canal.invokeMethod('pararDescanso');
    } catch (_) {}
  }

  /// Um sensor (luz / proximidade) acendeu a tela. O valor é o motivo.
  static final ValueNotifier<String?> acordouPorSensor = ValueNotifier(null);

  static bool _eventosProntos = false;
  /// A câmera ainda vê alguém na frente depois de acender (conta a cada aviso).
  static final ValueNotifier<int> presenca = ValueNotifier(0);

  /// Onde está a pessoa na frente da tela (-1 esquerda .. 1 direita), vista
  /// pela câmera; o rosto do Jarvis olha para lá. Vale por ~1,5 s.
  static double? posicaoPessoa;
  static DateTime? posicaoEm;

  static double? get posicaoRecente => posicaoEm != null &&
          DateTime.now().difference(posicaoEm!) < const Duration(milliseconds: 1500)
      ? posicaoPessoa
      : null;

  /// Inverte a direção do olhar (se o Jarvis olhar para o lado errado).
  static Future<void> inverterOlhar(bool inverter) async {
    try {
      await _canal.invokeMethod('inverterOlhar', {'inverter': inverter});
    } catch (_) {}
  }

  /// Liga a escuta dos avisos do Android (sensores, presença). Chamado no
  /// início do app.
  static void iniciarEventos() => _prepararEventos();

  static void _prepararEventos() {
    if (_eventosProntos) return;
    _eventosProntos = true;
    _canal.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'acordouPorSensor':
          // Valor novo a cada vez (com a hora) para o ouvinte sempre disparar.
          acordouPorSensor.value = '${call.arguments}@${DateTime.now().millisecondsSinceEpoch}';
        case 'presenca':
          presenca.value++;
        case 'posicao':
          posicaoPessoa = (call.arguments as num?)?.toDouble();
          posicaoEm = DateTime.now();
      }
    });
  }

  /// Acende a tela e mostra o painel (por cima da tela de bloqueio).
  static Future<void> acordarTela() async {
    try {
      await _canal.invokeMethod('acordarTela');
    } catch (e) {
      debugPrint('Sistema.acordarTela: $e');
    }
  }

  static Future<void> pararFala() async {
    try {
      await _canal.invokeMethod('pararFala');
    } catch (_) {}
  }

  /// Toca o som de alarme do aparelho (temporizador).
  static Future<void> tocarAlarme() async {
    try {
      await _canal.invokeMethod('tocarAlarme');
    } catch (e) {
      debugPrint('Sistema.tocarAlarme: $e');
    }
  }

  static Future<void> pararAlarme() async {
    try {
      await _canal.invokeMethod('pararAlarme');
    } catch (_) {}
  }

  /// Abre o reconhecimento de voz do Android e devolve o texto falado
  /// ('' se o usuário cancelar ou não houver reconhecimento disponível).
  /// O que já foi entendido enquanto a pessoa fala (aparece no orbe).
  static final ValueNotifier<String> falaParcial = ValueNotifier('');

  /// Volume da voz agora, de 0 a 1 (faz o orbe reagir à fala).
  static final ValueNotifier<double> volumeVoz = ValueNotifier(0);

  /// Ouviu "Jarvis" (conta a cada vez).
  static final ValueNotifier<int> palavraOuvida = ValueNotifier(0);

  /// Liga a escuta de "Hey Jarvis" (no próprio tablet, sem conta). null =
  /// ligou; senão, o motivo.
  static Future<String?> ligarPalavra(double sensibilidade) async {
    _prepararOuvinte();
    try {
      return await _canalVoz.invokeMethod<String>(
          'ligarPalavra', {'sensibilidade': sensibilidade});
    } catch (e) {
      return '$e';
    }
  }

  static Future<void> desligarPalavra() async {
    try {
      await _canalVoz.invokeMethod('desligarPalavra');
    } catch (_) {}
  }

  static bool _ouvintePronto = false;
  static void _prepararOuvinte() {
    if (_ouvintePronto) return;
    _ouvintePronto = true;
    _canalVoz.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'parcial':
          falaParcial.value = '${call.arguments}';
        case 'volume':
          // O Android manda o nível em dB (~ -2 a 10).
          final db = (call.arguments as num?)?.toDouble() ?? 0;
          volumeVoz.value = ((db + 2) / 12).clamp(0.0, 1.0);
        case 'erro':
          debugPrint('Reconhecimento de voz: erro ${call.arguments}');
        case 'palavraAtivacao':
          palavraOuvida.value++;
      }
    });
  }

  static Future<String> ouvir({String prompt = 'Fale agora...'}) async {
    _prepararOuvinte();
    falaParcial.value = '';
    volumeVoz.value = 0;
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
