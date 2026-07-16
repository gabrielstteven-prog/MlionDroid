import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CacheManager — armazenamento local persistente com expiração por chave.
//
//  PROBLEMA QUE RESOLVE:
//  Toda vez que uma tela é reconstruída (troca de tela, volta na sequência),
//  ela buscava dados (clima, notícias, imagens) do zero pela internet.
//  Isso deixava o app lento e gerava tráfego de rede desnecessário, já que
//  esses dados não mudam a cada poucos segundos.
//
//  SOLUÇÃO:
//  Cada tela, antes de buscar dados online, consulta o cache local. Se os
//  dados existem e ainda não "venceram" (têm um tempo de validade próprio
//  por tipo de informação), eles são usados imediatamente — sem requisição
//  de rede. Só quando o cache está vazio ou expirado é que a tela busca de
//  novo, salva o resultado, e o ciclo se repete.
//
//  Os dados ficam salvos em arquivos JSON na pasta de documentos do app,
//  então sobrevivem a trocas de tela e fechamento do app.
// ═══════════════════════════════════════════════════════════════════════════
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

  File _arquivo(Directory dir, String chave) => File('${dir.path}/$chave.json');

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

  /// Retorna os dados salvos para [chave] se existirem e ainda estiverem
  /// dentro da [validade]. Retorna null se não existir ou estiver expirado.
  Future<T?> obter<T>(String chave, {required Duration validade}) async {
    // 1. Tenta primeiro a RAM (instantâneo, sem I/O de disco)
    var pacote = _memoria[chave];

    // 2. Se não está na RAM, tenta carregar do disco
    if (pacote == null) {
      try {
        final dir = await _diretorio();
        final file = _arquivo(dir, chave);
        if (await file.exists()) {
          pacote = jsonDecode(await file.readAsString());
          _memoria[chave] = pacote; // promove para RAM
        }
      } catch (e) {
        debugPrint('CacheManager.obter($chave): $e');
        return null;
      }
    }

    if (pacote == null) return null;

    final salvoEm = DateTime.tryParse(pacote['salvo_em'] ?? '');
    if (salvoEm == null) return null;

    final expirado = DateTime.now().difference(salvoEm) > validade;
    if (expirado) return null;

    return pacote['dados'] as T?;
  }

  /// Verifica se existe cache válido para [chave], sem precisar ler os dados.
  Future<bool> temCacheValido(String chave,
      {required Duration validade}) async {
    final dados = await obter(chave, validade: validade);
    return dados != null;
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

  /// Limpa todo o cache — útil para um botão "Forçar atualização" nas
  /// configurações, ou debug.
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

  /// Retorna quando os dados de [chave] foram salvos por último, ou null.
  Future<DateTime?> salvoEm(String chave) async {
    var pacote = _memoria[chave];
    if (pacote == null) {
      try {
        final dir = await _diretorio();
        final file = _arquivo(dir, chave);
        if (await file.exists()) {
          pacote = jsonDecode(await file.readAsString());
        }
      } catch (_) {
        return null;
      }
    }
    if (pacote == null) return null;
    return DateTime.tryParse(pacote['salvo_em'] ?? '');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Validades padrão recomendadas por tipo de dado — centralizado aqui para
//  fácil ajuste e consistência entre todas as telas do app.
// ═══════════════════════════════════════════════════════════════════════════
class CacheValidade {
  // Clima: temperatura atual muda rápido, mas não precisa ser em tempo real
  static const climaAtual = Duration(minutes: 20);
  // Previsão dos próximos dias muda bem pouco ao longo do dia
  static const climaPrevisao = Duration(hours: 3);

  // Notícias: o "principal do dia" não muda de minuto a minuto
  static const noticias = Duration(hours: 1);

  // Imagens de notícias: o conteúdo da imagem em si nunca muda depois de
  // publicada — pode ficar em cache bem mais tempo que o texto
  static const imagemNoticia = Duration(hours: 6);

  // Classificação do campeonato: atualiza só após jogos terminarem
  static const classificacao = Duration(hours: 2);

  // Próxima partida do time: muda raramente, só após o jogo acontecer
  static const proximaPartida = Duration(hours: 6);

  // Frase/inspiração do dia: por definição, é "do dia" — vale o dia todo
  static const fraseDoDia = Duration(hours: 12);
}
