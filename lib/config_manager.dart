import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Configurações do app, salvas em JSON na pasta de documentos.
///
/// Observação: a categoria do time continua se chamando 'palmeiras' por
/// compatibilidade com as configurações já salvas nos tablets — ela vale
/// para qualquer time escolhido.
class ConfigManager {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

  Map<String, dynamic> _config = {};

  /// Incrementa a cada salvar() — quem depende de configuração (timers da
  /// barra, rodízio...) escuta isto para se reajustar sem reiniciar o app.
  final ValueNotifier<int> revisao = ValueNotifier<int>(0);

  static const List<String> sequenciaPadrao = [
    'bom_dia',
    'clima',
    'palmeiras',
    'proxima_partida',
    'classificacao',
    'calendario',
    'compras',
    'brasil',
    'regiao',
    'fotos',
    'spotify',
  ];

  static const Map<String, dynamic> defaults = {
    'geral': {
      'nome_usuario': '',
      'transicao_tipo': 'fade',
      'transicao_ms': 800,
      'pausa_preta_ms': 300,
      'tempo_modo_manual': 45,
      'manter_tela_ligada': true,
      'sequencia': sequenciaPadrao,
      'telas_ativas': [
        'bom_dia', 'clima', 'palmeiras', 'proxima_partida', 'classificacao',
        'calendario', 'compras', 'brasil', 'regiao', 'fotos',
        // 'spotify' fica fora da rotação — aparece sozinho ao trocar música
      ],
    },
    'clima': {
      'duracao_seg': 20,
      'cidade': 'Hortolândia',
      'estado': 'SP',
      'lat': '-22.889',
      'lon': '-47.222',
      'intervalo_atualizacao_min': 30,
    },
    'palmeiras': {
      'duracao_scroll_px_seg': 35,
      'pausa_final_seg': 10,
      'cor_gradiente_top': '0xFF00441B',
      'cor_gradiente_bottom': '0xFF000000',
      'cor_destaque': '0xFFC1A163',
      'qtd_noticias': 8,
      'nome_rss': 'palmeiras',
      'nome_time': 'Palmeiras',
      'escudo_asset': 'assets/escudos/palmeiras.png',
      'intervalo_atualizacao_min': 60,
    },
    'proxima_partida': {
      'duracao_seg': 20,
      'mostrar_canais': true,
      'intervalo_atualizacao_min': 240,
    },
    'classificacao': {
      'scroll_velocidade': 30, // pixels por segundo
      'pausa_troca_seg': 3,
      'mostrar_libertadores': true,
      'intervalo_atualizacao_min': 120,
    },
    'calendario': {
      'duracao_seg': 35,
      'intervalo_atualizacao_min': 30,
    },
    'compras': {
      'duracao_seg': 30,
      'intervalo_atualizacao_min': 30,
    },
    'brasil': {
      'duracao_scroll_px_seg': 35,
      'pausa_final_seg': 10,
      'qtd_noticias': 3, // por categoria
      'categorias_selecionadas': [
        'politica',
        'economia',
        'tecnologia',
        'saude',
        'geral'
      ],
      'intervalo_atualizacao_min': 60,
    },
    'regiao': {
      'duracao_scroll_px_seg': 35,
      'pausa_final_seg': 10,
      'cor_gradiente_top': '0xFF1a237e',
      'cor_gradiente_bottom': '0xFF000000',
      'qtd_noticias': 3, // por cidade
      'cidades_selecionadas': ['hortolandia'],
      'intervalo_atualizacao_min': 60,
    },
    'bom_dia': {
      'hora_inicio': 4,
      'hora_fim': 10,
      'duracao_longa_seg': 90,
      'duracao_curta_seg': 20,
    },
    'fotos': {
      'duracao_por_foto_seg': 8,
      'fotos_por_visita': 4,
    },
    'time': {
      'time_key': 'palmeiras',
    },
    'barra_info': {
      'mostrar_clima': true,
      'mostrar_ticker': true,
      'aurora_ativa': true,
      'tipo_ticker': 'misturado',
      'intervalo_clima_min': 10,
      'rotacao_ticker_seg': 12,
    },
    'spotify': {
      'client_id': '',
      'redirect_uri': 'https://localhost:8888/callback',
      'duracao_tela_seg': 30,
      'aparecer_na_rotacao': false, // fora da rotação automática por padrão
      'aparecer_por_evento': true, // interrompe ao trocar música
    },
    'noite': {
      'ativo': true,
      'hora_inicio': 23,
      'hora_fim': 6,
    },
    'performance': {
      'modo_economico': false, // false = visual completo
    },
    'atualizacoes': {
      'intervalo_verificacao_horas': 6,
    },
  };

  Map<String, dynamic> get config => _config;

  /// Intervalo de atualização configurado para uma categoria.
  Duration getIntervaloAtualizacao(String categoria) {
    final min = getInt(categoria, 'intervalo_atualizacao_min', 60);
    return Duration(minutes: min.clamp(5, 20160)); // 5 min a 2 semanas
  }

  static const List<Map<String, dynamic>> opcoesIntervaloAtualizacao = [
    {'label': '30 em 30 min', 'min': 30},
    {'label': 'De hora em hora', 'min': 60},
    {'label': 'De 4 em 4 horas', 'min': 240},
    {'label': '1x por dia', 'min': 1440},
    {'label': '1x por semana', 'min': 10080},
  ];

  dynamic get(String categoria, String chave) {
    return _config[categoria]?[chave] ?? defaults[categoria]?[chave];
  }

  void set(String categoria, String chave, dynamic valor) {
    _config[categoria] ??= <String, dynamic>{};
    _config[categoria][chave] = valor;
  }

  int getInt(String cat, String chave, [int fallback = 0]) {
    final v = get(cat, chave);
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? fallback;
    return fallback;
  }

  double getDouble(String cat, String chave, [double fallback = 0.0]) {
    final v = get(cat, chave);
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  String getString(String cat, String chave, [String fallback = '']) {
    final v = get(cat, chave);
    if (v == null) return fallback;
    return v is String ? v : '$v';
  }

  Color getColor(String cat, String chave, [Color fallback = Colors.black]) {
    try {
      final raw = get(cat, chave);
      if (raw is String) return Color(int.parse(raw));
    } catch (_) {}
    return fallback;
  }

  List<String> getStringList(String cat, String chave) {
    final raw = get(cat, chave);
    if (raw is List) return raw.map((e) => e.toString()).toList();
    final def = defaults[cat]?[chave];
    if (def is List) return List<String>.from(def);
    return [];
  }

  bool getBool(String cat, String chave, [bool fallback = false]) {
    final v = get(cat, chave);
    return v is bool ? v : fallback;
  }

  Future<File> get _localFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/mliondroid_config.json');
  }

  Future<void> carregar() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final contents = await file.readAsString();
        _config = _deepCopy(jsonDecode(contents) as Map<String, dynamic>);
        _mergeDefaults();
      } else {
        _config = _deepCopy(defaults);
      }
    } catch (e) {
      debugPrint('ConfigManager.carregar erro: $e');
      _config = _deepCopy(defaults);
    }
  }

  Future<void> salvar() async {
    try {
      final file = await _localFile;
      // Grava num arquivo temporário e renomeia: se o tablet desligar no
      // meio da gravação, o arquivo de configuração antigo continua inteiro.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_config));
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('ConfigManager.salvar erro: $e');
    }
    revisao.value++;
  }

  Future<void> resetar() async {
    _config = _deepCopy(defaults);
    await salvar();
  }

  void _mergeDefaults() {
    for (final cat in defaults.keys) {
      final atual = _config[cat];
      if (atual is! Map) _config[cat] = <String, dynamic>{};
      final defaultCat = defaults[cat] as Map<String, dynamic>;
      for (final chave in defaultCat.keys) {
        _config[cat][chave] ??= _deepCopyValor(defaultCat[chave]);
      }
    }
    // Telas novas adicionadas em versões futuras entram no fim da sequência.
    final seqAtual = getStringList('geral', 'sequencia');
    var alterou = false;
    for (final tela in sequenciaPadrao) {
      if (!seqAtual.contains(tela)) {
        seqAtual.add(tela);
        alterou = true;
      }
    }
    if (alterou) _config['geral']['sequencia'] = seqAtual;
  }

  static dynamic _deepCopyValor(dynamic v) => jsonDecode(jsonEncode(v));

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
    return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  }
}
