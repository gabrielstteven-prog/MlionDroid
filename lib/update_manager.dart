import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'config_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  UpdateManager — verifica, baixa e instala atualizações do app, sem
//  depender da Play Store. Funciona consultando os "Releases" de um
//  repositório no GitHub.
//
//  IMPORTANTE — LIMITAÇÃO REAL DO ANDROID:
//  Nenhum app fora da Play Store consegue instalar uma atualização 100%
//  sozinho, sem nenhum toque do usuário — isso é bloqueado pelo sistema
//  por segurança (só a própria Play Store tem essa permissão especial).
//  O que este manager faz é o máximo permitido: verifica sozinho, baixa
//  sozinho, e abre a tela de instalação do Android pronta — falta só
//  1 toque em "Instalar" pra confirmar.
//
//  COMO PUBLICAR UMA ATUALIZAÇÃO NO FUTURO:
//  1. Gere o apk novo:  flutter build apk --release
//  2. No GitHub, vá em Releases → "Draft a new release"
//  3. Crie uma tag de versão (ex: v1.0.1) — IGUAL à versão em pubspec.yaml
//  4. Anexe o arquivo .apk gerado como asset da release
//  5. Escreva o changelog na descrição da release (aparece no app)
//  6. Publique — o app detecta sozinho na próxima verificação
// ═══════════════════════════════════════════════════════════════════════════
class InfoAtualizacao {
  final String versao;
  final String changelog;
  final String urlApk;
  final int tamanho; // bytes, informado pelo GitHub (0 = desconhecido)
  final String? sha256; // hex, campo "digest" do GitHub quando existe
  InfoAtualizacao({
    required this.versao,
    required this.changelog,
    required this.urlApk,
    this.tamanho = 0,
    this.sha256,
  });
}

/// Opções de intervalo de verificação — usadas tanto pelo manager quanto
/// pela tela de Configurações (mesma fonte, sem duplicar a lista em dois
/// lugares diferentes).
class IntervaloVerificacao {
  static const List<Map<String, dynamic>> opcoes = [
    {'label': 'A cada 4 horas', 'horas': 4},
    {'label': 'A cada 8 horas', 'horas': 8},
    {'label': '1x por dia', 'horas': 24},
    {'label': '1x por semana', 'horas': 168},
  ];
}

class UpdateManager extends ChangeNotifier {
  UpdateManager._();
  static final UpdateManager instance = UpdateManager._();

  // ── CONFIGURE AQUI ─────────────────────────────────────────────────────
  static const String _owner = 'gabrielstteven-prog';
  static const String _repo = 'MlionDroid';
  // ──────────────────────────────────────────────────────────────────────

  final _cfg = ConfigManager();

  bool _verificando = false;
  bool _disponivel = false;
  bool _baixando = false;
  bool _baixado = false;
  double _progresso = 0.0;
  InfoAtualizacao? _info;
  String? _caminhoApkBaixado;
  Timer? _timerPeriodico;
  DateTime? _ultimaVerificacao;
  String _versaoInstalada = '';

  bool get verificando => _verificando;
  bool get disponivel => _disponivel;
  bool get baixando => _baixando;
  bool get baixado => _baixado;
  double get progresso => _progresso;
  InfoAtualizacao? get info => _info;
  DateTime? get ultimaVerificacao => _ultimaVerificacao;
  String get versaoInstalada => _versaoInstalada;

  /// Chamar 1x no main.dart. Verifica assim que o app abre, e continua
  /// verificando de tempos em tempos ENQUANTO o app estiver rodando —
  /// pensado para um tablet que fica ligado o dia inteiro, sem depender
  /// de fechar e abrir o app pra descobrir que tem versão nova. O
  /// intervalo é lido das Configurações (padrão: a cada 6 horas).
  Future<void> iniciarVerificacaoPeriodica() async {
    final pacote = await PackageInfo.fromPlatform();
    _versaoInstalada = pacote.version;
    notifyListeners();

    await verificar();
    _reagendarTimer();
  }

  /// Chamado pela tela de Configurações quando o usuário troca o
  /// intervalo — reagenda o timer sem precisar reiniciar o app.
  void atualizarIntervalo() {
    _reagendarTimer();
  }

  void _reagendarTimer() {
    final horas =
        _cfg.getInt('atualizacoes', 'intervalo_verificacao_horas', 6);
    _timerPeriodico?.cancel();
    _timerPeriodico = Timer.periodic(
        Duration(hours: horas.clamp(1, 336)), (_) => verificar());
  }

  /// Consulta o GitHub em busca da release mais recente e compara com a
  /// versão instalada agora. Sempre guarda a última release encontrada
  /// (mesmo que não seja mais nova), pra tela de Configurações poder
  /// mostrar "você está atualizado" com o changelog da versão atual.
  Future<void> verificar() async {
    if (_verificando) return;
    _verificando = true;
    notifyListeners();
    try {
      final res = await http
          .get(
            Uri.parse(
                'https://api.github.com/repos/$_owner/$_repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));

      _ultimaVerificacao = DateTime.now();

      if (res.statusCode != 200) {
        debugPrint('UpdateManager: releases indisponível (${res.statusCode})');
        return;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
      final assets = (data['assets'] as List?) ?? [];

      final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
            (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
            orElse: () => <String, dynamic>{},
          );

      if (tag.isEmpty || apkAsset.isEmpty) {
        debugPrint('UpdateManager: release sem tag ou sem .apk anexado');
        return;
      }

      if (_versaoInstalada.isEmpty) {
        final pacote = await PackageInfo.fromPlatform();
        _versaoInstalada = pacote.version;
      }

      // Guarda a info da release mais recente sempre — usado na tela de
      // Configurações mesmo quando ela não é "mais nova" que a instalada.
      _info = InfoAtualizacao(
        versao: tag,
        changelog: (data['body'] as String? ?? '').trim(),
        urlApk: apkAsset['browser_download_url'] as String,
        tamanho: (apkAsset['size'] as num?)?.toInt() ?? 0,
        sha256: _extrairSha256(apkAsset['digest'] as String?),
      );
      _disponivel = versaoMaisNova(tag, _versaoInstalada);
    } catch (e) {
      debugPrint('UpdateManager.verificar: $e');
    } finally {
      _verificando = false;
      notifyListeners();
    }
  }

  static String? _extrairSha256(String? digest) {
    if (digest == null || !digest.startsWith('sha256:')) return null;
    return digest.substring(7).toLowerCase();
  }

  /// Compara duas versões no formato "1.2.3". Retorna true se [remota] for
  /// mais nova que [local].
  static bool versaoMaisNova(String remota, String local) {
    List<int> partes(String v) => v
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final r = partes(remota);
    final l = partes(local);
    for (int i = 0; i < r.length || i < l.length; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  /// Mensagem do último erro de download (mostrada na folha de atualização).
  String? erroDownload;

  /// Baixa o .apk da release e abre a tela de instalação do Android (que
  /// exige 1 toque de confirmação — regra do sistema).
  ///
  /// Verificações (antes não existiam): resposta HTTP 200, tamanho igual ao
  /// informado pelo GitHub e, quando disponível, o SHA-256 do arquivo. Um
  /// download corrompido ou uma página de erro nunca chega ao instalador.
  Future<void> baixarEInstalar() async {
    final info = _info;
    if (info == null || _baixando) return;
    _baixando = true;
    _progresso = 0.0;
    erroDownload = null;
    notifyListeners();

    final client = http.Client();
    File? file;
    try {
      final dir = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      await _apagarApksAntigos(dir);
      final caminho = '${dir.path}/mliondroid_update_${info.versao}.apk';
      file = File(caminho);

      final response = await client
          .send(http.Request('GET', Uri.parse(info.urlApk)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('servidor respondeu ${response.statusCode}');
      }
      final total = response.contentLength ?? info.tamanho;
      var recebido = 0;
      var ultimoPercentual = -1;

      final sink = file.openWrite();
      final coletor = _ColetorSha256();
      final hasher = sha256.startChunkedConversion(coletor);
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          hasher.add(chunk);
          recebido += chunk.length;
          if (total > 0) {
            _progresso = recebido / total;
            // Notifica a cada 1% (antes era a cada pedaço recebido).
            final pct = (_progresso * 100).floor();
            if (pct != ultimoPercentual) {
              ultimoPercentual = pct;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
        hasher.close();
      }

      if (info.tamanho > 0 && recebido != info.tamanho) {
        throw Exception('arquivo incompleto ($recebido de ${info.tamanho} bytes)');
      }
      final esperado = info.sha256;
      if (esperado != null && coletor.valor?.toString() != esperado) {
        throw Exception('arquivo corrompido (SHA-256 não confere)');
      }

      _caminhoApkBaixado = caminho;
      _baixado = true;
      _baixando = false;
      notifyListeners();
      await OpenFilex.open(caminho);
    } catch (e) {
      debugPrint('UpdateManager.baixarEInstalar: $e');
      erroDownload = 'Falha no download: $e. Tente de novo.';
      _baixando = false;
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      notifyListeners();
    } finally {
      client.close();
    }
  }

  /// Remove APKs de versões anteriores que ficavam acumulando no tablet.
  Future<void> _apagarApksAntigos(Directory dir) async {
    try {
      await for (final f in dir.list()) {
        if (f is File &&
            f.uri.pathSegments.last.startsWith('mliondroid_update_') &&
            f.path.endsWith('.apk')) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  /// Caso o usuário tenha fechado a tela de instalação sem confirmar,
  /// permite abrir de novo sem precisar baixar tudo outra vez.
  Future<void> abrirInstaladorNovamente() async {
    if (_caminhoApkBaixado != null) {
      await OpenFilex.open(_caminhoApkBaixado!);
    }
  }

  /// Esconde o ícone/banner por agora (volta na próxima verificação).
  void dispensar() {
    _disponivel = false;
    notifyListeners();
  }
}

class _ColetorSha256 implements Sink<Digest> {
  Digest? valor;
  @override
  void add(Digest data) => valor = data;
  @override
  void close() {}
}
