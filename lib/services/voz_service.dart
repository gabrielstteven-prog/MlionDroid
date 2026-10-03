import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../cache_manager.dart';
import '../config_manager.dart';
import '../sistema.dart';

class VozPremium {
  final String id;
  final String nome;
  final String tipo; // premade, cloned, generated...
  const VozPremium(this.id, this.nome, this.tipo);
}

// ═══════════════════════════════════════════════════════════════════════════
//  VozService — a voz do Jarvis.
//
//  Voz premium: ElevenLabs. O plano gratuito dá 10 mil créditos por mês; o
//  modelo Flash gasta 0,5 crédito por letra, ou seja ~20 mil letras (~20
//  minutos de fala). Por isso:
//    • a voz premium fica para o que vale a pena (briefing e respostas da
//      IA); avisos curtos (temporizador, gol) usam a voz do Android;
//    • o app conta as letras do mês e, perto do limite, volta sozinho para
//      a voz do Android — nunca fica mudo;
//    • frases repetidas saem de um cache local (não gastam de novo).
// ═══════════════════════════════════════════════════════════════════════════

class VozService {
  VozService._();
  static final VozService instance = VozService._();

  final _cfg = ConfigManager();

  String get _chave => _cfg.getString('assistente', 'elevenlabs_chave', '').trim();
  String get _vozId => _cfg.getString('assistente', 'elevenlabs_voz', '').trim();
  String get _modelo =>
      _cfg.getString('assistente', 'elevenlabs_modelo', 'eleven_flash_v2_5').trim();

  /// Letras por mês antes de voltar para a voz do Android. 18 mil no modelo
  /// Flash = 9 mil créditos, uma folga sobre os 10 mil do plano gratuito.
  int get limiteMensal => _cfg.getInt('assistente', 'elevenlabs_limite_mes', 18000);

  bool get premiumConfigurado => _chave.isNotEmpty && _vozId.isNotEmpty;

  static String _mes(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  // Contagem guardada no cache (não nas configurações: salvar a config
  // avisa o app inteiro e reajusta o rodízio a cada fala).
  String get _chaveUso => 'voz_uso_${_mes(DateTime.now())}';
  String? _usoChave; // mês do valor em memória (zera na virada do mês)
  int _uso = 0;

  Future<int> usoNoMes() async {
    final chave = _chaveUso;
    if (_usoChave != chave) {
      _uso = (await CacheManager.instance.obterEntrada<int>(chave))?.dados ?? 0;
      _usoChave = chave;
    }
    return _uso;
  }

  Future<void> _registrarUso(int letras) async {
    final total = await usoNoMes() + letras;
    _uso = total;
    await CacheManager.instance.salvar(_chaveUso, total);
  }

  /// Fala [texto]. Com [premium], tenta a ElevenLabs e cai para o TTS do
  /// Android se não houver chave, cota ou internet. Só retorna quando a fala
  /// premium termina (o TTS do Android retorna na hora).
  Future<void> falar(String texto, {bool premium = true}) async {
    final t = texto.trim();
    if (t.isEmpty) return;
    if (premium && premiumConfigurado) {
      try {
        final arquivo = await _audioPremium(t);
        if (arquivo != null && await Sistema.tocarAudio(arquivo.path)) {
          ultimoErro = '';
          return;
        }
        ultimoErro = arquivo == null
            ? 'Limite de voz do mês atingido. Usando a voz do Android.'
            : 'Não consegui tocar o áudio da voz premium.';
      } catch (e) {
        debugPrint('Voz premium: $e');
        ultimoErro = explicarErro('$e');
      }
    }
    await Sistema.falar(t);
  }

  Future<void> parar() => Sistema.pararFala();

  /// Motivo da última falha da voz premium, em português (aparece no teste
  /// das Configurações). Vazio quando a última fala premium deu certo.
  String ultimoErro = '';

  Future<File?> _audioPremium(String texto) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/voz');
    if (!await dir.exists()) await dir.create(recursive: true);
    final nome = sha1.convert(utf8.encode('$_vozId|$_modelo|$texto')).toString();
    final arquivo = File('${dir.path}/$nome.mp3');
    if (await arquivo.exists()) return arquivo; // frase repetida: grátis

    if (await usoNoMes() + texto.length > limiteMensal) {
      debugPrint('Voz premium: limite do mês atingido, usando a voz do Android');
      return null;
    }
    final res = await http
        .post(
          Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$_vozId'
              '?output_format=mp3_44100_64'),
          headers: {'xi-api-key': _chave, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': texto,
            'model_id': _modelo,
            if (_modelo.contains('flash') || _modelo.contains('turbo')) 'language_code': 'pt',
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('ElevenLabs ${res.statusCode}: '
          '${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
    }
    await arquivo.writeAsBytes(res.bodyBytes, flush: true);
    await _registrarUso(texto.length);
    _limparCacheAntigo(dir);
    return arquivo;
  }

  /// Mantém só os ~60 áudios mais recentes.
  void _limparCacheAntigo(Directory dir) {
    try {
      final arquivos = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final f in arquivos.skip(60)) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  /// Traduz o erro da ElevenLabs para algo que dá para resolver. Testada.
  static String explicarErro(String e) {
    if (e.contains('402') || e.contains('paid_plan_required') || e.contains('library voices')) {
      return 'Essa voz é da biblioteca da comunidade: no plano gratuito ela não funciona '
          'pelo app. Escolha uma voz padrão da ElevenLabs (ex.: Daniel, George) ou '
          'assine um plano pago.';
    }
    if (e.contains('401')) return 'A chave da ElevenLabs foi recusada. Confira se colou a chave certa.';
    if (e.contains('quota') || e.contains('429')) {
      return 'A cota da ElevenLabs acabou ou está no limite. Usando a voz do Android.';
    }
    if (e.contains('404')) return 'Voz não encontrada. Toque em Carregar vozes e escolha de novo.';
    return 'Sem resposta da ElevenLabs (internet?). Usando a voz do Android.';
  }

  /// Vozes da conta (para escolher nas Configurações).
  Future<List<VozPremium>> listarVozes(String chave) async {
    final res = await http.get(Uri.parse('https://api.elevenlabs.io/v1/voices'),
        headers: {'xi-api-key': chave.trim()}).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('ElevenLabs ${res.statusCode}');
    }
    return parseVozes(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Função pura — testada.
  static List<VozPremium> parseVozes(Map<String, dynamic> json) => [
        for (final v in (json['voices'] as List? ?? const []).whereType<Map>())
          if ('${v['voice_id'] ?? ''}'.isNotEmpty)
            VozPremium('${v['voice_id']}', '${v['name'] ?? 'Sem nome'}',
                '${v['category'] ?? ''}'),
      ];
}
