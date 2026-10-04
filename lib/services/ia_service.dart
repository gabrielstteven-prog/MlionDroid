import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  IaService — o "cérebro inteligente" do Jarvis.
//
//  Ordem: Gemini (plano gratuito do Google AI Studio) → Groq (gratuito,
//  reserva) → null (o assistente responde com o cérebro local).
//
//  Privacidade: no plano gratuito o Google pode usar o conteúdo para
//  melhorar os produtos dele. Por isso só vão textos curtos e já resumidos
//  pelo app (clima, agenda, manchetes; de e-mail, só remetente e assunto).
//  Nada de fotos, áudio ou corpo de e-mail.
// ═══════════════════════════════════════════════════════════════════════════

class IaService {
  IaService._();
  static final IaService instance = IaService._();

  final _cfg = ConfigManager();

  String get _chaveGemini => _cfg.getString('assistente', 'gemini_chave', '').trim();
  String get _chaveGroq => _cfg.getString('assistente', 'groq_chave', '').trim();
  String get _modeloGemini =>
      _cfg.getString('assistente', 'gemini_modelo', 'gemini-3.8-flash').trim();
  String get _modeloGroq =>
      _cfg.getString('assistente', 'groq_modelo', 'openai/gpt-oss-120b').trim();

  bool get configurado => _chaveGemini.isNotEmpty || _chaveGroq.isNotEmpty;

  /// Qual cérebro respondeu por último ("Gemini", "Groq") — aparece no teste
  /// das Configurações.
  String ultimoProvedor = '';

  /// Responde [pergunta] seguindo as instruções de [sistema]. Devolve null
  /// se nenhum provedor estiver configurado ou todos falharem.
  /// Com [imagem] (JPEG), só o Gemini responde: ele enxerga a foto.
  /// [historico]: as falas anteriores desta conversa (conversa contínua).
  Future<String?> responder(
      {required String sistema,
      required String pergunta,
      List<int>? imagem,
      List<TurnoConversa> historico = const []}) async {
    _historico = historico;
    motivoFalha = '';
    if (_chaveGemini.isEmpty && (imagem != null || _chaveGroq.isEmpty)) {
      motivoFalha = imagem != null
          ? 'Para enxergar eu preciso da chave do Gemini nas Configurações.'
          : 'A inteligência artificial não está configurada.';
      return null;
    }
    if (_chaveGemini.isNotEmpty) {
      try {
        final r = await _gemini(sistema, pergunta, imagem);
        if (r != null && r.isNotEmpty) {
          ultimoProvedor = 'Gemini';
          return r;
        }
        motivoFalha = 'O Gemini não devolveu resposta. Tente de novo.';
      } catch (e) {
        debugPrint('IA Gemini: $e');
        motivoFalha = explicarFalha(e);
      }
    }
    if (imagem != null) return null; // o Groq não enxerga imagens
    if (_chaveGroq.isNotEmpty) {
      try {
        final r = await _groq(sistema, pergunta);
        if (r != null && r.isNotEmpty) {
          ultimoProvedor = 'Groq';
          motivoFalha = '';
          return r;
        }
      } catch (e) {
        debugPrint('IA Groq: $e');
        if (motivoFalha.isEmpty) motivoFalha = explicarFalha(e);
      }
    }
    return null;
  }

  List<TurnoConversa> _historico = const [];

  /// Por que a última resposta falhou, em português, para o Jarvis falar.
  String motivoFalha = '';

  /// Traduz o erro da IA para algo que dá para entender. Função pura — testada.
  static String explicarFalha(Object e) {
    final s = '$e';
    if (s.contains('HTTP 503') || s.contains('HTTP 500') || s.contains('UNAVAILABLE')) {
      return 'O Gemini está sobrecarregado agora. Tente de novo daqui a pouco.';
    }
    if (s.contains('HTTP 429')) {
      return 'Passei do limite gratuito da inteligência artificial por agora. Tente mais tarde.';
    }
    if (s.contains('HTTP 400') && s.contains('API key') || s.contains('HTTP 401') || s.contains('HTTP 403')) {
      return 'A chave da inteligência artificial foi recusada. Confira nas Configurações.';
    }
    if (s.contains('SocketException') || s.contains('TimeoutException') || s.contains('Failed host')) {
      return 'Estou sem internet ou a resposta demorou demais. Tente de novo.';
    }
    return 'A inteligência artificial falhou agora. Tente de novo.';
  }

  /// Pede "raciocínio leve" (respostas curtas de assistente não precisam
  /// pensar muito, e pensar demora). Se o modelo não aceitar o campo, tenta
  /// de novo sem ele.
  bool _aceitaNivelDeRaciocinio = true;

  /// Modelos de reserva (também gratuitos): quando o principal está
  /// sobrecarregado (erro 503, comum no plano gratuito), tenta estes.
  static const _reservasGemini = ['gemini-3.5-flash', 'gemini-3.5-flash-lite'];

  Future<String?> _gemini(String sistema, String pergunta, List<int>? imagem) async {
    final modelos = {_modeloGemini, ..._reservasGemini}.toList();
    Object? ultimoErro;
    for (var i = 0; i < modelos.length; i++) {
      try {
        return await _geminiModelo(modelos[i], sistema, pergunta, imagem);
      } catch (e) {
        ultimoErro = e;
        final s = '$e';
        final sobrecarga = s.contains('HTTP 503') || s.contains('HTTP 500') || s.contains('HTTP 429');
        // Só vale tentar outro modelo se o problema for sobrecarga/limite;
        // chave errada ou sem internet falham igual em qualquer modelo.
        if (!sobrecarga) rethrow;
        debugPrint('IA Gemini: ${modelos[i]} sobrecarregado, tentando o próximo');
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    throw ultimoErro!;
  }

  Future<String?> _geminiModelo(
      String modelo, String sistema, String pergunta, List<int>? imagem) async {
    if (_aceitaNivelDeRaciocinio) {
      try {
        return await _chamarGemini(modelo, sistema, pergunta, imagem, raciocinioLeve: true);
      } on _Recusado {
        _aceitaNivelDeRaciocinio = false;
      }
    }
    return _chamarGemini(modelo, sistema, pergunta, imagem, raciocinioLeve: false);
  }

  Future<String?> _chamarGemini(
      String modelo, String sistema, String pergunta, List<int>? imagem,
      {required bool raciocinioLeve}) async {
    final res = await http
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/'
              '$modelo:generateContent'),
          headers: {'x-goog-api-key': _chaveGemini, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': sistema}
              ]
            },
            'contents': [
              for (final h in _historico)
                {
                  'role': h.doUsuario ? 'user' : 'model',
                  'parts': [
                    {'text': h.texto}
                  ]
                },
              {
                'role': 'user',
                'parts': [
                  {'text': pergunta},
                  // Foto da câmera ("olha o que eu tenho na mão").
                  if (imagem != null)
                    {
                      'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(imagem)}
                    },
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.7,
              'maxOutputTokens': 1500,
              if (raciocinioLeve) 'thinkingConfig': {'thinkingLevel': 'low'},
            },
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (raciocinioLeve && res.statusCode == 400 && res.body.contains('thinking')) {
      throw _Recusado();
    }
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${_resumoErro(res.body)}');
    }
    return textoGemini(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<String?> _groq(String sistema, String pergunta) async {
    final res = await http
        .post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_chaveGroq',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': _modeloGroq,
            'temperature': 0.7,
            'messages': [
              {'role': 'system', 'content': sistema},
              for (final h in _historico)
                {'role': h.doUsuario ? 'user' : 'assistant', 'content': h.texto},
              {'role': 'user', 'content': pergunta},
            ],
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${_resumoErro(res.body)}');
    }
    return textoGroq(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  static String _resumoErro(String corpo) =>
      corpo.length > 200 ? corpo.substring(0, 200) : corpo;

  /// Junta as partes de texto da resposta do Gemini. Função pura — testada.
  static String? textoGemini(Map<String, dynamic> json) {
    final candidatos = json['candidates'] as List? ?? const [];
    if (candidatos.isEmpty) return null;
    final partes = ((candidatos.first as Map)['content'] as Map?)?['parts'] as List? ?? const [];
    final texto = partes
        .whereType<Map>()
        .where((p) => p['thought'] != true) // ignora o "raciocínio" do modelo
        .map((p) => '${p['text'] ?? ''}')
        .join()
        .trim();
    return texto.isEmpty ? null : limparParaFala(texto);
  }

  /// Texto da resposta no formato OpenAI (Groq). Função pura — testada.
  static String? textoGroq(Map<String, dynamic> json) {
    final escolhas = json['choices'] as List? ?? const [];
    if (escolhas.isEmpty) return null;
    final texto = '${((escolhas.first as Map)['message'] as Map?)?['content'] ?? ''}'.trim();
    return texto.isEmpty ? null : limparParaFala(texto);
  }

  /// A resposta vai ser FALADA: tira markdown (negrito, títulos, listas) que
  /// a voz leria como "asterisco".
  static String limparParaFala(String s) => s
      .replaceAll(RegExp(r'\*\*|__|`|#+\s'), '')
      .replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}

class _Recusado implements Exception {}

/// Uma fala da conversa: do usuário ou do assistente.
class TurnoConversa {
  final bool doUsuario;
  final String texto;
  const TurnoConversa(this.doUsuario, this.texto);
}
