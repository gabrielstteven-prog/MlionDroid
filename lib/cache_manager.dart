import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CacheManager — armazenamento local persistente com expiração por chave.
//
//  Cada tela/serviço consulta o cache antes de ir à internet. Se o dado
//  ainda está dentro da validade, é usado direto. Se venceu, o serviço tenta
//  buscar de novo — e, se a internet falhar, ainda pode mostrar o último
//  dado conhecido (via [obterEntrada]), em vez de deixar a tela vazia.
//
//  Os dados ficam em arquivos JSON na pasta de documentos do app, então
//  sobrevivem a trocas de tela e ao fechamento do app.
// ═══════════════════════════════════════════════════════════════════════════

/// Um dado salvo no cache, com a data em que foi salvo.
class EntradaCache<T> {
  final T dados;
  final DateTime salvoEm;
  const EntradaCache(this.dados, this.salvoEm);

  Duration get idade => DateTime.now().difference(salvoEm);
  bool venceu(Duration validade) => idade > validade;
}

class CacheManager {
  CacheManager._();
  static final CacheManager instance = CacheManager._();

  Directory? _dir;
  final Map<String, dynamic> _memoria = {}; // cache em RAM, mais rápido ainda

  Future<Directory> _diretorio() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final pasta = Directory('${docs.path}/mliondroid_cache');
    if (!await pasta.exists()) await pasta.create(recursive: true);
    _dir = pasta;
    return pasta;
  }

  /// Chaves podem conter coordenadas, nomes de cidade etc. — normaliza para
  /// um nome de arquivo seguro.
  File _arquivo(Directory dir, String chave) {
    final seguro = chave.replaceAll(RegExp(r'[^A-Za-z0-9_\-.]'), '_');
    return File('${dir.path}/$seguro.json');
  }

  /// Salva um valor no cache, junto com o timestamp de quando foi salvo.
  /// O valor deve ser serializável em JSON (Map, List, String, num, bool).
  Future<void> salvar(String chave, dynamic valor) async {
    final pacote = {
      'salvo_em': DateTime.now().toIso8601String(),
      'dados': valor,
    };
    _memoria[chave] = pacote;
    try {
      final dir = await _diretorio();
      await _arquivo(dir, chave).writeAsString(jsonEncode(pacote));
    } catch (e) {
      debugPrint('CacheManager.salvar($chave): $e');
    }
  }

  Future<Map<String, dynamic>?> _pacote(String chave) async {
    final emRam = _memoria[chave];
    if (emRam != null) return emRam as Map<String, dynamic>;
    try {
      final dir = await _diretorio();
      final file = _arquivo(dir, chave);
      if (!await file.exists()) return null;
      final pacote = jsonDecode(await file.readAsString());
      if (pacote is! Map<String, dynamic>) return null;
      _memoria[chave] = pacote; // promove para RAM
      return pacote;
    } catch (e) {
      debugPrint('CacheManager._pacote($chave): $e');
      return null;
    }
  }

  /// Retorna o dado salvo para [chave] COM a data em que foi salvo, mesmo
  /// que já esteja vencido. Quem chama decide se usa (ex.: sem internet,
  /// mostrar o último dado conhecido é melhor que mostrar nada).
  Future<EntradaCache<T>?> obterEntrada<T>(String chave) async {
    final pacote = await _pacote(chave);
    if (pacote == null) return null;
    final salvoEm = DateTime.tryParse(pacote['salvo_em'] as String? ?? '');
    final dados = pacote['dados'];
    if (salvoEm == null || dados is! T) return null;
    return EntradaCache<T>(dados, salvoEm);
  }

  /// Retorna os dados salvos para [chave] se existirem e ainda estiverem
  /// dentro da [validade]. Retorna null se não existir ou estiver expirado.
  Future<T?> obter<T>(String chave, {required Duration validade}) async {
    final entrada = await obterEntrada<T>(chave);
    if (entrada == null || entrada.venceu(validade)) return null;
    return entrada.dados;
  }

  /// Remove uma entrada específica do cache (memória + disco).
  Future<void> invalidar(String chave) async {
    _memoria.remove(chave);
    try {
      final dir = await _diretorio();
      final file = _arquivo(dir, chave);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('CacheManager.invalidar($chave): $e');
    }
  }

  /// Limpa todo o cache — usado pelo botão "Forçar atualização".
  Future<void> limparTudo() async {
    _memoria.clear();
    try {
      final dir = await _diretorio();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('CacheManager.limparTudo: $e');
    }
  }
}

/// Busca com cache "stale-while-revalidate":
///  1. dado dentro da validade → usa direto, sem internet;
///  2. vencido/ausente → busca na internet e salva;
///  3. internet falhou → devolve o último dado salvo, mesmo vencido.
///
/// [buscar] deve lançar exceção (ou retornar null) quando falhar.
Future<EntradaCache<T>?> buscarComCache<T>({
  required String chave,
  required Duration validade,
  required Future<T?> Function() buscar,
  bool forcar = false,
}) async {
  final cache = await CacheManager.instance.obterEntrada<T>(chave);
  if (!forcar && cache != null && !cache.venceu(validade)) return cache;
  try {
    final novo = await buscar();
    if (novo != null) {
      await CacheManager.instance.salvar(chave, novo);
      return EntradaCache<T>(novo, DateTime.now());
    }
  } catch (e) {
    debugPrint('buscarComCache($chave): $e');
  }
  return cache; // pode ser null se nunca houve dado
}

/// Texto curto para "atualizado há X" mostrado nas telas.
String descreverIdade(DateTime salvoEm, [DateTime? agora]) {
  final d = (agora ?? DateTime.now()).difference(salvoEm);
  if (d.inMinutes < 1) return 'agora mesmo';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  final dias = d.inDays;
  return dias == 1 ? 'há 1 dia' : 'há $dias dias';
}
