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
  Future<String?> responder(
      {required String sistema, required String pergunta, List<int>? imagem}) async {
    if (_chaveGemini.isNotEmpty) {
      try {
        final r = await _gemini(sistema, pergunta, imagem);
        if (r != null && r.isNotEmpty) {
          ultimoProvedor = 'Gemini';
          return r;
        }
      } catch (e) {
        debugPrint('IA Gemini: $e');
      }
    }
    if (imagem != null) return null; // o Groq não enxerga imagens
    if (_chaveGroq.isNotEmpty) {
      try {
        final r = await _groq(sistema, pergunta);
        if (r != null && r.isNotEmpty) {
          ultimoProvedor = 'Groq';
          return r;
        }
      } catch (e) {
        debugPrint('IA Groq: $e');
      }
    }
    return null;
  }

  /// Pede "raciocínio leve" (respostas curtas de assistente não precisam
  /// pensar muito, e pensar demora). Se o modelo não aceitar o campo, tenta
  /// de novo sem ele.
  bool _aceitaNivelDeRaciocinio = true;

  Future<String?> _gemini(String sistema, String pergunta, List<int>? imagem) async {
    if (_aceitaNivelDeRaciocinio) {
      try {
        return await _chamarGemini(sistema, pergunta, imagem, raciocinioLeve: true);
      } on _Recusado {
        _aceitaNivelDeRaciocinio = false;
      }
    }
    return _chamarGemini(sistema, pergunta, imagem, raciocinioLeve: false);
  }

  Future<String?> _chamarGemini(String sistema, String pergunta, List<int>? imagem,
      {required bool raciocinioLeve}) async {
    final res = await http
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/'
              '$_modeloGemini:generateContent'),
          headers: {'x-goog-api-key': _chaveGemini, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': sistema}
              ]
            },
            'contents': [
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
