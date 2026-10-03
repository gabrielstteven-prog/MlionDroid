import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Fotos do app ("Memórias"), guardadas na pasta PRIVADA do app.
///
/// Antes as fotos ficavam em /storage/emulated/0/Pictures/MlionDroid, o que
/// exigia a permissão de acesso total ao armazenamento (que o app nunca
/// pedia de fato — no Android 11+ isso falhava em silêncio). Agora o
/// seletor de arquivos copia as imagens para dentro do app, sem permissão.
class FotosService {
  FotosService._();
  static final FotosService instance = FotosService._();

  static const _pastaAntiga = '/storage/emulated/0/Pictures/MlionDroid';
  static const _extensoes = ['.jpg', '.jpeg', '.png', '.webp'];

  Directory? _dir;
  bool _migrou = false;

  Future<Directory> pasta() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/fotos');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  bool _ehImagem(String path) =>
      _extensoes.any((e) => path.toLowerCase().endsWith(e));

  /// Copia (uma vez) as fotos da pasta antiga, se o Android permitir ler.
  Future<void> _migrarPastaAntiga() async {
    if (_migrou) return;
    _migrou = true;
    try {
      final antiga = Directory(_pastaAntiga);
      if (!await antiga.exists()) return;
      final destino = await pasta();
      await for (final f in antiga.list()) {
        if (f is! File || !_ehImagem(f.path)) continue;
        final nome = f.uri.pathSegments.last;
        final novo = File('${destino.path}/$nome');
        if (!await novo.exists()) await f.copy(novo.path);
      }
    } catch (e) {
      debugPrint('FotosService migração: $e');
    }
  }

  Future<List<String>> listar() async {
    await _migrarPastaAntiga();
    final d = await pasta();
    final arquivos = <String>[];
    await for (final f in d.list()) {
      if (f is File && _ehImagem(f.path)) arquivos.add(f.path);
    }
    arquivos.sort();
    return arquivos;
  }

  /// Abre o seletor e copia as imagens escolhidas. Retorna quantas entraram.
  Future<int> adicionarDoSeletor() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: true);
    if (result == null) return 0;
    final d = await pasta();
    var copiadas = 0;
    for (final file in result.files) {
      final origem = file.path;
      if (origem == null) continue;
      final nome = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      await File(origem).copy('${d.path}/$nome');
      copiadas++;
    }
    return copiadas;
  }

  Future<void> remover(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// Sorteia [n] fotos diferentes (sem repetir dentro da visita).
  Future<List<String>> sortear(int n) async {
    final todas = await listar();
    todas.shuffle(Random());
    return todas.take(n).toList();
  }

  /// Foto do dia — muda à meia-noite, percorre a pasta inteira ao longo
  /// dos dias.
  Future<String?> fotoDoDia([DateTime? data]) async {
    final todas = await listar();
    if (todas.isEmpty) return null;
    final d = data ?? DateTime.now();
    final idx = d.difference(DateTime(d.year)).inDays % todas.length;
    return todas[idx];
  }
}
