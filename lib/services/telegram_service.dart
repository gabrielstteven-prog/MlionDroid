import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config_manager.dart';
import '../sistema.dart';
import '../util.dart';
import 'weather_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  TelegramService — a casa pelo celular, via um bot do Telegram.
//
//  • /foto        → o tablet tira uma foto com a câmera da frente e manda
//  • /audio 15    → grava 15 s do microfone (máx. 60) e manda
//  • /status      → clima, tela e modo ausente
//  • alerta       → no Modo Ausente, movimento na câmera manda uma foto
//
//  Segurança: só UM chat controla o tablet — o que mandar "/parear CÓDIGO"
//  com o código que aparece nas Configurações. Mensagens de qualquer outro
//  chat são ignoradas. O token e o chat ficam só neste tablet.
//
//  Funciona puxando as mensagens do Telegram (long polling): não precisa de
//  servidor, nem de porta aberta, nem de conta além do bot.
// ═══════════════════════════════════════════════════════════════════════════

class TelegramService {
  TelegramService._();
  static final TelegramService instance = TelegramService._();

  final _cfg = ConfigManager();

  String get _token => _cfg.getString('telegram', 'token', '').trim();
  String get chatPareado => _cfg.getString('telegram', 'chat_id', '').trim();
  bool get configurado => _token.isNotEmpty;
  bool get pareado => chatPareado.isNotEmpty;

  /// Código de pareamento (6 dígitos), criado uma vez e guardado.
  String get codigo {
    var c = _cfg.getString('telegram', 'codigo', '');
    if (c.isEmpty) {
      c = (100000 + math.Random.secure().nextInt(900000)).toString();
      _cfg.set('telegram', 'codigo', c);
      _cfg.salvar();
    }
    return c;
  }

  /// Avisa o app quando a câmera foi usada (o descanso religa a vigilância).
  final ValueNotifier<int> cameraUsada = ValueNotifier(0);

  /// Estado para as Configurações ("conectado", "token recusado"...).
  final ValueNotifier<String> status = ValueNotifier('');

  bool _rodando = false;
  int _offset = 0;
  DateTime? _ultimoAlerta;

  String get _base => 'https://api.telegram.org/bot$_token';

  /// Liga (ou religa) a escuta das mensagens do bot.
  void iniciar() {
    if (!configurado || _rodando) return;
    _rodando = true;
    _loop();
  }

  void parar() => _rodando = false;

  Future<void> reiniciar() async {
    parar();
    await Future.delayed(const Duration(seconds: 1));
    iniciar();
  }

  Future<void> _loop() async {
    status.value = 'Conectando...';
    while (_rodando && configurado) {
      try {
        final res = await http
            .get(Uri.parse('$_base/getUpdates?timeout=50&offset=$_offset'))
            .timeout(const Duration(seconds: 65));
        if (res.statusCode == 401 || res.statusCode == 404) {
          status.value = 'O Telegram recusou o token. Confira se colou o token certo.';
          _rodando = false;
          return;
        }
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        status.value = pareado ? 'Conectado e pareado.' : 'Conectado. Falta parear.';
        final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        for (final u in (json['result'] as List? ?? const []).whereType<Map>()) {
          _offset = ((u['update_id'] as num?)?.toInt() ?? _offset) + 1;
          final msg = u['message'] as Map?;
          if (msg == null) continue;
          final chat = '${(msg['chat'] as Map?)?['id'] ?? ''}';
          final texto = '${msg['text'] ?? ''}'.trim();
          if (chat.isEmpty || texto.isEmpty) continue;
          await _tratar(chat, texto);
        }
      } catch (e) {
        debugPrint('Telegram: $e');
        status.value = 'Sem conexão com o Telegram, tentando de novo...';
        await Future.delayed(const Duration(seconds: 15));
      }
    }
  }

  Future<void> _tratar(String chat, String texto) async {
    final (comando, argumento) = separarComando(texto);
    if (!pareado) {
      if (comando == 'parear' && argumento == codigo) {
        _cfg.set('telegram', 'chat_id', chat);
        await _cfg.salvar();
        status.value = 'Conectado e pareado.';
        await enviarTexto('Pareado! Agora este chat controla o painel.\n\n$_ajuda', chat: chat);
      } else {
        await enviarTexto(
            'Para usar, mande /parear seguido do código que aparece no tablet '
            '(Configurações > Assistente > Casa pelo celular).',
            chat: chat);
      }
      return;
    }
    if (chat != chatPareado) return; // outro chat: ignora em silêncio

    switch (comando) {
      case 'foto':
        await enviarTexto('📸 Tirando a foto...');
        await enviarFotoAgora('Foto agora, ${horaMinuto(DateTime.now())}');
      case 'audio':
        final seg = (int.tryParse(argumento ?? '') ?? 15).clamp(3, 60);
        await enviarTexto('🎙️ Gravando $seg segundos...');
        final caminho = await Sistema.gravarAudio(seg);
        cameraUsada.value++; // o microfone também volta a ouvir o "Hey Jarvis"
        if (caminho == null) {
          await enviarTexto('Não consegui gravar (microfone sem permissão ou ocupado).');
        } else {
          await _enviarArquivo('sendAudio', 'audio', caminho,
              legenda: 'Áudio da casa, ${horaMinuto(DateTime.now())}');
        }
      case 'status':
        await enviarTexto(_status());
      default:
        await enviarTexto(_ajuda);
    }
  }

  /// "/audio@MeuBot 20" → ("audio", "20"). Função pura — testada.
  static (String, String?) separarComando(String texto) {
    final partes = texto.trim().split(RegExp(r'\s+'));
    final cmd = partes.first.replaceFirst('/', '').split('@').first.toLowerCase();
    return (cmd, partes.length > 1 ? partes[1] : null);
  }

  String get _ajuda => 'Comandos:\n'
      '/foto — foto agora pela câmera do painel\n'
      '/audio 15 — grava 15 segundos de áudio (até 60)\n'
      '/status — clima e situação do painel\n\n'
      'No Modo Ausente, se a câmera vir movimento, eu mando uma foto sozinho.';

  String _status() {
    final c = WeatherService.instance.atual;
    final b = StringBuffer('🏠 Painel ligado, ${horaMinuto(DateTime.now())}.');
    if (c != null) {
      b.write('\n🌡️ ${c.temp}° em ${_cfg.getString('clima', 'cidade', 'casa')} '
          '(${descricaoClima(c.codigo).toLowerCase()}).');
    }
    return b.toString();
  }

  /// Foto pela câmera da frente, mandada para o chat pareado.
  Future<bool> enviarFotoAgora(String legenda) async {
    if (!pareado) return false;
    final caminho = await Sistema.tirarFoto();
    cameraUsada.value++;
    if (caminho == null || caminho == 'sem_permissao') {
      await enviarTexto('Não consegui usar a câmera agora.');
      return false;
    }
    return _enviarArquivo('sendPhoto', 'photo', caminho, legenda: legenda);
  }

  /// Modo Ausente: alguém apareceu na câmera. Manda foto (no máximo uma a
  /// cada 5 minutos, para não lotar o celular).
  Future<void> alertaMovimento() async {
    if (!pareado || !_cfg.getBool('telegram', 'alerta_ausente', true)) return;
    final agora = DateTime.now();
    if (_ultimoAlerta != null && agora.difference(_ultimoAlerta!) < const Duration(minutes: 5)) {
      return;
    }
    _ultimoAlerta = agora;
    await enviarFotoAgora('🚨 Movimento em casa às ${horaMinuto(agora)} (modo ausente)');
  }

  Future<void> enviarTexto(String texto, {String? chat}) async {
    final destino = chat ?? chatPareado;
    if (!configurado || destino.isEmpty) return;
    try {
      await http.post(Uri.parse('$_base/sendMessage'),
          body: {'chat_id': destino, 'text': texto}).timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('Telegram texto: $e');
    }
  }

  Future<bool> _enviarArquivo(String metodo, String campo, String caminho,
      {String? legenda}) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$_base/$metodo'))
        ..fields['chat_id'] = chatPareado
        ..files.add(await http.MultipartFile.fromPath(campo, caminho));
      if (legenda != null) req.fields['caption'] = legenda;
      final res = await req.send().timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) debugPrint('Telegram $metodo: HTTP ${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Telegram $metodo: $e');
      return false;
    } finally {
      try {
        File(caminho).deleteSync(); // não guarda fotos nem áudios no tablet
      } catch (_) {}
    }
  }

  /// Esquece o chat pareado e cria um código novo.
  Future<void> desparear() async {
    _cfg.set('telegram', 'chat_id', '');
    _cfg.set('telegram', 'codigo', '');
    await _cfg.salvar();
    status.value = 'Conectado. Falta parear.';
  }
}
