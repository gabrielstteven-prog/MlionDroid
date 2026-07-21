// ═══════════════════════════════════════════════════════════════════════════════
//  PATCH — config_manager.dart
//
//  Adicione a entrada 'spotify' no Map defaults, dentro da classe ConfigManager.
//  Localização: após a entrada 'barra_info' no Map defaults.
//
// ═══════════════════════════════════════════════════════════════════════════════

// Trecho a ADICIONAR no Map defaults (após 'barra_info'):
/*
    'spotify': {
      'client_id':           '',        // Preenchido pelo usuário na TelaConfig
      'redirect_uri':        '',
      'duracao_tela_seg':    30,         // Tempo que a TelaSpotify fica visível
      'aparecer_na_rotacao': true,       // Entra na sequência automática
      'cor_acento':          '0xFF1DB954',
      'genius_token':         '',
      'genius_token':        '',
    },
*/

// ─────────────────────────────────────────────────────────────────────────────
//  ARQUIVO COMPLETO com patch aplicado (substitua o original)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ConfigManager {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

  Map<String, dynamic> _config = {};

  static const Map<String, dynamic> defaults = {
    'geral': {
      'nome_usuario': 'Bem-vindo',
      'transicao_tipo': 'fade',
      'transicao_ms': 800,
      'pausa_preta_ms': 300,
      'tempo_modo_manual': 45,
      'sequencia': [
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
      ],
      'telas_ativas': [
        'bom_dia', 'clima', 'palmeiras', 'proxima_partida', 'classificacao',
        'calendario', 'compras', 'brasil', 'regiao', 'fotos',
        // 'spotify' inativo por padrão — só aparece via evento de troca de música
      ],
    },
    'clima': {
      'duracao_seg': 20,
      'cidade': 'Hortolândia',
      'estado': 'SP',
      'lat': '-22.889',
      'lon': '-47.222',
      'unidade': 'C',
      'fonte': 'Poppins',
      'tamanho_temp': 90.0,
      'cor_primaria': '0xFF1e3c72',
      'cor_secundaria': '0xFF2a5298',
      'intervalo_atualizacao_min': 30, // a cada quanto tempo busca dado novo
    },
    'palmeiras': {
      'duracao_scroll_px_seg': 35,
      'pausa_final_seg': 10,
      'cor_gradiente_top': '0xFF00441B',
      'cor_gradiente_bottom': '0xFF000000',
      'cor_destaque': '0xFFC1A163',
      'tamanho_titulo': 42.0,
      'tamanho_noticia': 19.0,
      'fonte': 'Rajdhani',
      'qtd_noticias': 8,
      'nome_rss': 'palmeiras',
      'nome_time': 'Palmeiras',
      'escudo_asset': 'assets/escudos/palmeiras.png',
      'escudo_url': '',
      'intervalo_atualizacao_min': 60,
    },
    'proxima_partida': {
      'duracao_seg': 15,
      'cor_gradiente_top': '0xFF00441B',
      'cor_gradiente_bottom': '0xFF000000',
      'cor_borda': '0xFFC1A163',
      'tamanho_confronto': 28.0,
      'fonte': 'Rajdhani',
      'intervalo_atualizacao_min': 240,
    },
    'classificacao': {
      'scroll_velocidade': 0.8,
      'pausa_troca_seg': 2,
      'cor_fundo_tabela': '0xFF1a1a1a',
      'cor_destaque_palmeiras': '0xFF004d20',
      'cor_g4': '0xFF00c853',
      'cor_z4': '0xFFff5252',
      'tamanho_fonte_dados': 14.0,
      'fonte': 'Rajdhani',
      'intervalo_atualizacao_min': 120,
    },
    'calendario': {
      'duracao_seg': 35,
      'pausa_scroll_seg': 3,
      'fonte': 'Rajdhani',
      'intervalo_atualizacao_min': 30,
    },
    'compras': {
      'duracao_seg': 30,
      'fonte': 'Rajdhani',
      'intervalo_atualizacao_min': 30,
    },
    'brasil': {
      'duracao_scroll_px_seg': 35,
      'pausa_final_seg': 10,
      'cor_gradiente_top': '0xFF0a1628',
      'cor_gradiente_bottom': '0xFF000000',
      'cor_destaque': '0xFFFFD700',
      'qtd_noticias': 3, // agora é "por categoria", não mais total
      'categorias_selecionadas': [
        'politica',
        'economia',
        'tecnologia',
        'saude',
        'geral'
      ],
      'tamanho_noticia': 17.0,
      'fonte': 'Rajdhani',
      'intervalo_atualizacao_min': 60,
    },
    'regiao': {
      'duracao_scroll_px_seg': 35,
      'pausa_final_seg': 10,
      'cor_gradiente_top': '0xFF1a237e',
      'cor_gradiente_bottom': '0xFF000000',
      'cor_destaque': '0xFF00BCD4',
      'tamanho_titulo': 40.0,
      'tamanho_noticia': 18.0,
      'qtd_noticias': 4,
      'fonte': 'Rajdhani',
      'cidades_selecionadas': ['hortolandia'],
      'intervalo_atualizacao_min': 60,
    },
    'bom_dia': {
      'duracao_longa_seg': 90,
      'duracao_curta_seg': 20,
    },
    'fotos': {
      'duracao_por_foto_seg': 8,
      'transicao_foto_ms': 1000,
    },
    'time': {
      'time_key': 'palmeiras',
    },
    'barra_info': {
      'mostrar_clima': true,
      'mostrar_ticker': true,
      'tipo_ticker': 'misturado',
      'intervalo_clima_min': 10,
      'rotacao_ticker_seg': 12,
    },
    // ── NOVO: Spotify ────────────────────────────────────────────────────────
    'spotify': {
      'client_id': '',
      'redirect_uri': 'https://localhost:8888/callback',
      'duracao_tela_seg': 30,
      'aparecer_na_rotacao': false, // fora da rotação automática por padrão
      'aparecer_por_evento': true, // interrompe ao trocar música por padrão
      'cor_acento': '0xFF1DB954',
    },
    // ── NOVO: Performance ────────────────────────────────────────────────────
    'performance': {
      'modo_economico': false, // false = visual completo (padrão atual)
    },
    // ── NOVO: Atualizações ───────────────────────────────────────────────────
    'atualizacoes': {
      'intervalo_verificacao_horas':
          6, // de quanto em quanto tempo verifica sozinho
    },
  };

  Map<String, dynamic> get config => _config;

  /// Intervalo de atualização configurado pelo usuário para uma categoria
  /// (clima, palmeiras, brasil, regiao, classificacao, calendario, compras,
  /// proxima_partida), já convertido em Duration. Usado pelas telas junto
  /// com o CacheManager: se o cache for mais novo que esse intervalo, a
  /// tela usa o dado salvo em vez de buscar de novo na internet.
  Duration getIntervaloAtualizacao(String categoria) {
    final min = getInt(categoria, 'intervalo_atualizacao_min', 60);
    return Duration(minutes: min.clamp(5, 20160)); // mínimo 5min, máx 2 semanas
  }

  /// Opções padrão exibidas na tela de Configurações para o seletor de
  /// intervalo de atualização. Mantido aqui para ficar consistente em
  /// todas as categorias que usam esse campo.
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
    _config[categoria] ??= {};
    _config[categoria][chave] = valor;
  }

  int getInt(String cat, String chave, [int fallback = 0]) {
    try {
      final v = get(cat, chave);
      if (v == null) return fallback;
      return (v as num).toInt();
    } catch (_) {
      return fallback;
    }
  }

  double getDouble(String cat, String chave, [double fallback = 0.0]) {
    try {
      final v = get(cat, chave);
      if (v == null) return fallback;
      return (v as num).toDouble();
    } catch (_) {
      return fallback;
    }
  }

  String getString(String cat, String chave, [String fallback = '']) {
    try {
      return (get(cat, chave) as String?) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Color getColor(String cat, String chave, [Color fallback = Colors.black]) {
    try {
      final raw = get(cat, chave) as String?;
      if (raw == null) return fallback;
      return Color(int.parse(raw));
    } catch (_) {
      return fallback;
    }
  }

  List<String> getStringList(String cat, String chave) {
    try {
      final raw = get(cat, chave);
      if (raw is List) return raw.map((e) => e.toString()).toList();
    } catch (_) {}
    final def = defaults[cat]?[chave];
    if (def is List) return List<String>.from(def);
    return [];
  }

  bool getBool(String cat, String chave, [bool fallback = false]) {
    try {
      final v = get(cat, chave);
      if (v is bool) return v;
    } catch (_) {}
    return fallback;
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
        _config = _deepCopy(jsonDecode(contents));
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
      await file.writeAsString(jsonEncode(_config));
    } catch (e) {
      debugPrint('ConfigManager.salvar erro: $e');
    }
  }

  Future<void> resetar() async {
    _config = _deepCopy(defaults);
    await salvar();
  }

  void _mergeDefaults() {
    for (final cat in defaults.keys) {
      _config[cat] ??= {};
      final defaultCat = defaults[cat] as Map<String, dynamic>;
      for (final chave in defaultCat.keys) {
        _config[cat][chave] ??= defaultCat[chave];
      }
    }
    final seqDefault =
        List<String>.from((defaults['geral'] as Map)['sequencia'] as List);
    final seqAtual =
        List<String>.from(_config['geral']['sequencia'] as List? ?? []);
    bool alterou = false;
    for (final tela in seqDefault) {
      if (!seqAtual.contains(tela)) {
        seqAtual.add(tela);
        alterou = true;
      }
    }
    if (alterou) _config['geral']['sequencia'] = seqAtual;
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
    return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  }
}
