import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../cache_manager.dart';
import '../config_manager.dart';
import '../sistema.dart';
import 'jarvis_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  VozJarvis — a voz do Jarvis gerada NO APARELHO (Qwen3-TTS, voz clonada).
//
//  Qualidade de voz paga, mas lenta neste tablet (~6x o tempo da fala). Então
//  ela nunca é gerada na hora em que o Jarvis vai falar:
//    • Bom Dia: o briefing é escrito e gravado às 4h;
//    • resumo da noite: preparado 1 h antes do horário dele;
//    • frases frequentes ("Pronto, anotei", "Temporizador cancelado"...)
//      ficam gravadas; as frases curtas novas entram na fila e, da próxima
//      vez, já saem na voz do Jarvis.
//  Quando o áudio não está pronto, o Jarvis fala na voz rápida (sem esperar).
//
//  O motor roda como servidor só enquanto há fila (libera ~2,5 GB depois).
// ═══════════════════════════════════════════════════════════════════════════

class VozJarvis {
  VozJarvis._();
  static final VozJarvis instance = VozJarvis._();

  final _cfg = ConfigManager();

  /// O aparelho roda (ARM 64) e o modelo foi baixado.
  bool disponivel = false;
  bool suportado = false;
  int _porta = 18093;

  /// Quantas frases faltam gerar (aparece nas Configurações).
  final ValueNotifier<int> naFila = ValueNotifier(0);

  Directory? _dir;
  String? _voz;
  final List<String> _fila = []; // frases (as urgentes vão para o começo)
  bool _trabalhando = false;
  Timer? _desligar;
  Timer? _agenda;

  /// Frases que o app fala sempre: já ficam gravadas.
  static const frasesFixas = [
    'Às ordens. Até mais.',
    'Quer colocar uma quantidade?',
    'Quantos?',
    'Tudo bem, fica assim.',
    'Certo, um só.',
    'Temporizador cancelado.',
    'Não há temporizador ativo.',
    'Abrindo.',
    'Pronto, está na tela.',
    'Deixa eu ver...',
    'De volta ao modo mordomo, às suas ordens.',
    'Até mais! Vou descansar a tela.',
    'Quando você chegar, eu acendo.',
    'Não consegui fazer isso agora.',
    'Verifique a internet e tente de novo.',
  ];

  Future<void> iniciar() async {
    final e = await Sistema.vozQwenEstado();
    suportado = e['suportado'] == true;
    disponivel = suportado && e['instalado'] == true;
    _porta = (e['porta'] as int?) ?? _porta;
    if (!disponivel) return;
    await _limparAntigos();
    _agenda?.cancel();
    _agenda = Timer.periodic(const Duration(minutes: 5), (_) => _prepararDoDia());
    _prepararDoDia();
    final nome = JarvisService.instance.nomeUsuario;
    pedir([
      ...frasesFixas,
      if (nome.isNotEmpty) 'Bem-vindo de volta, $nome!' else 'Bem-vindo de volta!',
    ]);
  }

  // ── Cache dos áudios (uma frase = um .wav) ──────────────────────────────

  Future<Directory> _pasta() async {
    if (_dir != null) return _dir!;
    final d = Directory('${(await getApplicationSupportDirectory()).path}/voz_jarvis');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  static String _limpa(String s) =>
      s.replaceAll('°', ' graus').replaceAll(RegExp(r'\s+'), ' ').trim();

  File _arquivo(Directory d, String frase) =>
      File('${d.path}/${sha1.convert(utf8.encode('v1|${_limpa(frase)}')).toString()}.wav');

  /// Frases na ordem em que são faladas. Função pura — testada.
  static List<String> frases(String texto) => _limpa(texto)
      .split(RegExp(r'(?<=[.!?…])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Vale gravar uma frase dita na hora para a próxima vez? Só as curtas e
  /// sem números (hora, temperatura e placar mudam sempre). Testada.
  static bool valeGuardar(String frase) => frase.length <= 70 && !RegExp(r'\d').hasMatch(frase);

  /// Áudios do texto inteiro, se TODAS as frases já estão gravadas (não
  /// mistura duas vozes numa resposta). null = falar na voz rápida.
  Future<List<File>?> audios(String texto) async {
    if (!disponivel) return null;
    final d = await _pasta();
    final lista = <File>[];
    for (final f in frases(texto)) {
      final a = _arquivo(d, f);
      if (!await a.exists()) return null;
      lista.add(a);
    }
    if (lista.isEmpty) return null;
    final agora = DateTime.now();
    for (final a in lista) {
      a.setLastModified(agora).catchError((_) {}); // usado agora: não apaga
    }
    return lista;
  }

  /// Põe frases na fila para gravar. [urgente] passa na frente (briefing).
  Future<void> pedir(Iterable<String> textos, {bool urgente = false}) async {
    if (!disponivel) return;
    final d = await _pasta();
    final novas = <String>[];
    for (final t in textos) {
      for (final f in frases(t)) {
        if (_fila.contains(f) || novas.contains(f)) continue;
        if (await _arquivo(d, f).exists()) continue;
        novas.add(f);
      }
    }
    if (novas.isEmpty) return;
    if (urgente) {
      _fila.insertAll(0, novas);
    } else {
      _fila.addAll(novas);
    }
    naFila.value = _fila.length;
    _trabalhar();
  }

  /// Uma resposta dita na voz rápida: guarda as frases curtas para a próxima.
  void aprender(String texto) {
    final curtas = frases(texto).where(valeGuardar).toList();
    if (curtas.isNotEmpty) pedir(curtas);
  }

  Future<String> _arquivoVoz() async {
    if (_voz != null) return _voz!;
    final f = File('${(await _pasta()).path}/voz.bin');
    final dados = await rootBundle.load('assets/vozes/jarvis.bin');
    await f.writeAsBytes(dados.buffer.asUint8List(), flush: true);
    return _voz = f.path;
  }

  Future<bool> _servidorPronto() async {
    try {
      final r = await http
          .get(Uri.parse('http://127.0.0.1:$_porta/v1/health'))
          .timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ligar() async {
    if (await _servidorPronto()) return true;
    if (!await Sistema.vozQwenIniciar(await _arquivoVoz())) return false;
    // Carregar o modelo leva ~20 s neste tablet.
    for (var i = 0; i < 90; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (await _servidorPronto()) return true;
    }
    debugPrint('VozJarvis: o servidor de voz não respondeu');
    await Sistema.vozQwenParar();
    return false;
  }

  Future<void> _trabalhar() async {
    if (_trabalhando || _fila.isEmpty) return;
    _trabalhando = true;
    _desligar?.cancel();
    try {
      if (!await _ligar()) return;
      final d = await _pasta();
      var falhas = 0;
      while (_fila.isNotEmpty && falhas < 3) {
        final frase = _fila.first;
        final ok = await _gerar(frase, _arquivo(d, frase));
        // Remove pela frase (não pela posição): um pedido urgente pode ter
        // entrado na frente enquanto esta era gravada.
        if (ok || ++falhas >= 3) _fila.remove(frase);
        if (ok) falhas = 0;
        naFila.value = _fila.length;
      }
    } finally {
      _trabalhando = false;
      // Sem fila por 2 minutos: desliga o motor e devolve a memória.
      _desligar = Timer(const Duration(minutes: 2), () {
        if (_fila.isEmpty && !_trabalhando) Sistema.vozQwenParar();
      });
    }
  }

  Future<bool> _gerar(String frase, File destino) async {
    try {
      final r = await http
          .post(Uri.parse('http://127.0.0.1:$_porta/v1/tts'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'text': frase, 'language': 'Portuguese'}))
          .timeout(const Duration(minutes: 10));
      if (r.statusCode != 200 || r.bodyBytes.length < 1000) {
        debugPrint('VozJarvis: HTTP ${r.statusCode} em "$frase"');
        return false;
      }
      final tmp = File('${destino.path}.tmp');
      await tmp.writeAsBytes(r.bodyBytes, flush: true);
      await tmp.rename(destino.path);
      debugPrint('VozJarvis: gravada "$frase"');
      return true;
    } catch (e) {
      debugPrint('VozJarvis: $e');
      return false;
    }
  }

  /// Apaga áudios sem uso há 15 dias (briefings velhos); as fixas ficam.
  Future<void> _limparAntigos() async {
    try {
      final d = await _pasta();
      final fixas = {for (final f in frasesFixas) _arquivo(d, f).path};
      final limite = DateTime.now().subtract(const Duration(days: 15));
      await for (final f in d.list()) {
        if (f is File && f.path.endsWith('.wav') && !fixas.contains(f.path)) {
          if ((await f.lastModified()).isBefore(limite)) await f.delete();
        }
      }
    } catch (_) {}
  }

  // ── Bom Dia às 4h e resumo da noite 1 h antes ───────────────────────────

  static String _dia(DateTime d) => '${d.year}_${d.month}_${d.day}';
  static String chaveBriefing(DateTime d) => 'briefing_preparado_${_dia(d)}';
  static String chaveNoite(DateTime d) => 'resumo_noite_preparado_${_dia(d)}';

  /// Texto preparado de hoje (briefing ou resumo da noite), se houver.
  Future<String?> preparado(String chave) async =>
      (await CacheManager.instance.obterEntrada<String>(chave))?.dados;

  bool _preparando = false;

  Future<void> _prepararDoDia() async {
    if (_preparando || !disponivel || _cfg.getString('assistente', 'motor_voz', 'auto') != 'jarvis') {
      return;
    }
    _preparando = true;
    try {
      final agora = DateTime.now();
      // Bom Dia: das 4h às 11h.
      if (agora.hour >= 4 && agora.hour < 11) {
        await _preparar(chaveBriefing(agora),
            () => JarvisService.instance.briefing('Bom dia', antecipado: true));
      }
      // Resumo da noite: a partir de 1 h antes do horário configurado.
      final inicio = _cfg.getInt('resumo_noite', 'hora_inicio', 18);
      final fim = _cfg.getInt('resumo_noite', 'hora_fim', 22);
      if (_cfg.getBool('resumo_noite', 'ativo', true) &&
          agora.hour >= inicio - 1 &&
          agora.hour < fim) {
        await _preparar(chaveNoite(agora), JarvisService.instance.resumoDaNoite);
      }
    } catch (e) {
      debugPrint('VozJarvis preparar: $e');
    } finally {
      _preparando = false;
    }
  }

  /// Escreve o texto do dia uma vez (IA) e garante que todas as frases dele
  /// estão gravadas — se o app fechou no meio, completa o que faltou.
  Future<void> _preparar(String chave, Future<String?> Function() escrever) async {
    var texto = await preparado(chave);
    if (texto == null) {
      texto = await escrever();
      if (texto == null || texto.isEmpty) return;
      await CacheManager.instance.salvar(chave, texto);
    }
    await pedir([texto], urgente: true);
  }

  // ── Instalação ───────────────────────────────────────────────────────────

  Future<bool> baixar() async {
    final ok = await Sistema.vozQwenBaixar();
    if (ok) await iniciar();
    return ok;
  }

  Future<void> apagar() async {
    _fila.clear();
    naFila.value = 0;
    await Sistema.vozQwenApagar();
    disponivel = false;
    try {
      final d = await _pasta();
      await d.delete(recursive: true);
      _dir = null;
      _voz = null;
    } catch (_) {}
  }
}
