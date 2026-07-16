import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'config_manager.dart';
import 'cache_manager.dart';
import 'responsive.dart';

class TelaClassificacao extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaClassificacao({super.key, required this.aoTerminar});

  @override
  State<TelaClassificacao> createState() => _TelaClassificacaoState();
}

class _TelaClassificacaoState extends State<TelaClassificacao> {
  final _cfg = ConfigManager();

  List<Map<String, dynamic>> brasileirao = [];
  List<Map<String, dynamic>> libertadoresGrupos = [];
  List<Map<String, dynamic>> libertadoresPartidas = [];
  bool carregando = true;
  bool mostrandoLibertadores = false;
  bool libertadoresMataMata = false;

  final ScrollController _scrollController = ScrollController();
  Timer? _scrollTimer;
  Timer? _switchTimer;

  static const String apiKey = '2fe5b44d83914bd5b4b44df54b718fd0';

  // ── Lê configurações do ConfigManager ─────────────────────────────────────
  double get _scrollVelocidade =>
      (_cfg.get('classificacao', 'scroll_velocidade') as num?)?.toDouble() ??
      0.8;

  int get _pausaTrocaSeg =>
      (_cfg.get('classificacao', 'pausa_troca_seg') as num?)?.toInt() ?? 2;

  Color get _corFundoTabela =>
      _parseColor(_cfg.get('classificacao', 'cor_fundo_tabela'), 0xFF1a1a1a);

  Color get _corDestaquePalmeiras => _parseColor(
      _cfg.get('classificacao', 'cor_destaque_palmeiras'), 0xFF004d20);

  Color get _corG4 =>
      _parseColor(_cfg.get('classificacao', 'cor_g4'), 0xFF00c853);

  Color get _corZ4 =>
      _parseColor(_cfg.get('classificacao', 'cor_z4'), 0xFFff5252);

  double get _tamanhoFonteBase =>
      (_cfg.get('classificacao', 'tamanho_fonte_dados') as num?)?.toDouble() ??
      14.0;

  double _fontSize(R r) => r.fs(_tamanhoFonteBase);

  // Nome do time selecionado para destacar na tabela
  String get _nomeTimeSelecionado =>
      (_cfg.get('palmeiras', 'nome_time') as String?)?.toLowerCase() ??
      'palmeiras';

  Color _parseColor(dynamic raw, int fallback) {
    try {
      if (raw is String) return Color(int.parse(raw));
    } catch (_) {}
    return Color(fallback);
  }

  @override
  void initState() {
    super.initState();
    _carregarClassificacao();
    // Anti-travamento: sai em até 3 minutos mesmo se API falhar
    Timer(const Duration(minutes: 3), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollTimer?.cancel();
    _switchTimer?.cancel();
    super.dispose();
  }

  static const _chaveCache = 'classificacao_dados';

  Future<void> _carregarClassificacao() async {
    final cache = await CacheManager.instance.obter<Map<String, dynamic>>(
      _chaveCache,
      validade: _cfg.getIntervaloAtualizacao('classificacao'),
    );
    if (cache != null && mounted) {
      setState(() {
        brasileirao = List<Map<String, dynamic>>.from(
            (cache['brasileirao'] as List)
                .map((e) => Map<String, dynamic>.from(e)));
        libertadoresGrupos = List<Map<String, dynamic>>.from(
            (cache['libertadoresGrupos'] as List)
                .map((e) => Map<String, dynamic>.from(e)));
        libertadoresPartidas = List<Map<String, dynamic>>.from(
            (cache['libertadoresPartidas'] as List)
                .map((e) => Map<String, dynamic>.from(e)));
        libertadoresMataMata = cache['libertadoresMataMata'] as bool? ?? false;
        carregando = false;
      });
      _iniciarAutoScroll();
      return;
    }
    await buscarClassificacao();
  }

  Future<void> buscarClassificacao() async {
    try {
      final resBr = await http.get(
        Uri.parse(
            'https://api.football-data.org/v4/competitions/BSA/standings'),
        headers: {'X-Auth-Token': apiKey},
      );

      if (resBr.statusCode == 200) {
        final data = jsonDecode(resBr.body);
        final standings = data['standings'] as List;
        final table = standings[0]['table'] as List;
        brasileirao = table
            .map<Map<String, dynamic>>((t) => {
                  'posicao': t['position'],
                  'nome': t['team']['shortName'],
                  'escudo': t['team']['crest'] ?? '',
                  'pontos': t['points'],
                  'jogos': t['playedGames'],
                  'vitorias': t['won'],
                  'empates': t['draw'],
                  'derrotas': t['lost'],
                  'saldo': t['goalDifference'],
                })
            .toList();
      }

      final resLib = await http.get(
        Uri.parse(
            'https://api.football-data.org/v4/competitions/CLI/standings'),
        headers: {'X-Auth-Token': apiKey},
      );

      if (resLib.statusCode == 200) {
        final data = jsonDecode(resLib.body);
        final standings = data['standings'] as List;
        if (standings.isNotEmpty) {
          libertadoresGrupos = standings
              .map<Map<String, dynamic>>((g) => {
                    'grupo': g['group'] ?? 'Grupo',
                    'times': (g['table'] as List)
                        .map<Map<String, dynamic>>((t) => {
                              'posicao': t['position'],
                              'nome': t['team']['shortName'],
                              'escudo': t['team']['crest'] ?? '',
                              'pontos': t['points'],
                              'jogos': t['playedGames'],
                              'vitorias': t['won'],
                              'empates': t['draw'],
                              'derrotas': t['lost'],
                              'saldo': t['goalDifference'],
                            })
                        .toList(),
                  })
              .toList();
        }
      }

      if (libertadoresGrupos.isEmpty) {
        libertadoresMataMata = true;
        final resMatches = await http.get(
          Uri.parse(
              'https://api.football-data.org/v4/teams/1769/matches?competitions=CLI&status=SCHEDULED&limit=5'),
          headers: {'X-Auth-Token': apiKey},
        );
        if (resMatches.statusCode == 200) {
          final data = jsonDecode(resMatches.body);
          final matches = data['matches'] as List? ?? [];
          libertadoresPartidas = matches.map<Map<String, dynamic>>((m) {
            final dataHora = DateTime.parse(m['utcDate']).toLocal();
            return {
              'mandante': m['homeTeam']['shortName'],
              'visitante': m['awayTeam']['shortName'],
              'escudoMandante': m['homeTeam']['crest'] ?? '',
              'escudoVisitante': m['awayTeam']['crest'] ?? '',
              'fase': m['stage'] ?? '',
              'data':
                  '${dataHora.day.toString().padLeft(2, '0')}/${dataHora.month.toString().padLeft(2, '0')}',
              'horario':
                  '${dataHora.hour.toString().padLeft(2, '0')}h${dataHora.minute.toString().padLeft(2, '0')}',
            };
          }).toList();
        }
      }

      setState(() => carregando = false);
      _iniciarAutoScroll();
      await CacheManager.instance.salvar(_chaveCache, {
        'brasileirao': brasileirao,
        'libertadoresGrupos': libertadoresGrupos,
        'libertadoresPartidas': libertadoresPartidas,
        'libertadoresMataMata': libertadoresMataMata,
      });
    } catch (e) {
      setState(() => carregando = false);
    }
  }

  bool _isTimeSelecionado(String nome) {
    return nome.toLowerCase().contains(_nomeTimeSelecionado);
  }

  void _iniciarAutoScroll() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted || !_scrollController.hasClients) {
          timer.cancel();
          return;
        }
        final maxScroll = _scrollController.position.maxScrollExtent;
        final current = _scrollController.offset;

        if (current >= maxScroll) {
          timer.cancel();
          _switchTimer = Timer(Duration(seconds: _pausaTrocaSeg), () {
            if (!mounted) return;
            if (!mostrandoLibertadores) {
              setState(() => mostrandoLibertadores = true);
              Future.delayed(const Duration(milliseconds: 300),
                  () => _iniciarAutoScroll());
            } else {
              widget.aoTerminar();
            }
          });
        } else {
          _scrollController.jumpTo(current + _scrollVelocidade);
        }
      });
    });
  }

  // ── Cores dinâmicas baseadas no time selecionado ─────────────────────────
  Color get _corTimeTop =>
      _parseColor(_cfg.get('palmeiras', 'cor_gradiente_top'), 0xFF00441B);

  Color get _corTimeDestaque =>
      _parseColor(_cfg.get('palmeiras', 'cor_destaque'), 0xFFC1A163);

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _corTimeTop,
              _corTimeTop.withValues(alpha: 0.4),
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Logo da competição em vez de texto ─────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: _buildLogoCompeticao(),
              ),
              // Indicadores (bolinhas)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _indicador(!mostrandoLibertadores),
                  const SizedBox(width: 8),
                  _indicador(mostrandoLibertadores),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: carregando
                    ? Center(
                        child:
                            CircularProgressIndicator(color: _corTimeDestaque))
                    : mostrandoLibertadores
                        ? (libertadoresMataMata
                            ? _buildMataMata(r)
                            : _buildLibertadores(r))
                        : _buildBrasileirao(r),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Logo animado da competição atual
  Widget _buildLogoCompeticao() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: mostrandoLibertadores ? _logoLibertadores() : _logoBrasileirao(),
    );
  }

  Widget _logoBrasileirao() {
    final r = R(context);
    return SizedBox(
      key: const ValueKey('brasileirao'),
      height: r.icon(72),
      child: Image.asset(
        'assets/brasileirao.png',
        height: r.icon(72),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _tituloFallback('BRASILEIRÃO'),
      ),
    );
  }

  Widget _logoLibertadores() {
    final r = R(context);
    return SizedBox(
      key: const ValueKey('libertadores'),
      height: r.icon(72),
      child: Image.asset(
        'assets/libertadores.png',
        height: r.icon(72),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _tituloFallback(
            libertadoresMataMata ? 'LIBERTADORES\nMATA-MATA' : 'LIBERTADORES'),
      ),
    );
  }

  Widget _tituloFallback(String texto) {
    final r = R(context);
    return Text(
      texto,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: r.fs(32),
        fontWeight: FontWeight.w900,
        color: Colors.white,
        letterSpacing: 2,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 15, offset: Offset(3, 3))
        ],
      ),
    );
  }

  Widget _indicador(bool ativo) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ativo
              ? const Color(0xFFC1A163)
              : Colors.white.withValues(alpha: 0.3),
        ),
      );

  Widget _buildBrasileirao(R r) {
    if (brasileirao.isEmpty) {
      return const Center(
          child: Text('Dados indisponíveis',
              style: TextStyle(color: Colors.white70, fontSize: 18)));
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _corFundoTabela,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC1A163), width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF006B2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const SizedBox(
                    width: 32,
                    child: Text('#',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14))),
                const SizedBox(width: 34),
                const Expanded(
                    child: Text('Time',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14))),
                _headerCell('P', r),
                _headerCell('J', r),
                _headerCell('V', r),
                _headerCell('E', r),
                _headerCell('D', r),
                _headerCell('SG', r, width: 34),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: brasileirao.length,
              itemBuilder: (context, index) {
                final time = brasileirao[index];
                final isDestaque = _isTimeSelecionado(time['nome']);
                final isG4 = index < 4;
                final isZ4 = index >= 16;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDestaque
                        ? _corDestaquePalmeiras
                        : (index % 2 == 0
                            ? _corFundoTabela
                            : _corFundoTabela.withValues(alpha: 0.85)),
                    border: Border(
                      left: BorderSide(
                        width: 4,
                        color: isG4
                            ? _corG4
                            : isZ4
                                ? _corZ4
                                : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 32,
                          child: Text('${time['posicao']}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: _fontSize(r),
                                  color: isDestaque
                                      ? const Color(0xFF69f0ae)
                                      : Colors.white))),
                      SizedBox(
                        width: 34,
                        child: time['escudo'].toString().isNotEmpty
                            ? Image.network(time['escudo'],
                                height: 26,
                                width: 26,
                                errorBuilder: (c, e, s) => const Icon(
                                    Icons.shield,
                                    size: 26,
                                    color: Colors.white38))
                            : const Icon(Icons.shield,
                                size: 26, color: Colors.white38),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(time['nome'],
                              style: TextStyle(
                                  fontSize: _fontSize(r),
                                  fontWeight: isDestaque
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isDestaque
                                      ? const Color(0xFF69f0ae)
                                      : Colors.white))),
                      _dataCell('${time['pontos']}', r, bold: true),
                      _dataCell('${time['jogos']}', r),
                      _dataCell('${time['vitorias']}', r),
                      _dataCell('${time['empates']}', r),
                      _dataCell('${time['derrotas']}', r),
                      SizedBox(
                          width: 34,
                          child: Text('${time['saldo']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: _fontSize(r),
                                  fontWeight: FontWeight.bold,
                                  color: time['saldo'] > 0
                                      ? _corG4
                                      : time['saldo'] < 0
                                          ? _corZ4
                                          : Colors.white54))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibertadores(R r) {
    if (libertadoresGrupos.isEmpty) {
      return const Center(
          child: Text('Dados indisponíveis',
              style: TextStyle(color: Colors.white70, fontSize: 18)));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: libertadoresGrupos.length,
      itemBuilder: (context, index) {
        final grupo = libertadoresGrupos[index];
        final times = grupo['times'] as List<Map<String, dynamic>>;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: _corFundoTabela,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFC1A163).withValues(alpha: 0.5),
                width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF006B2E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: Text(
                  grupo['grupo'].toString().replaceAll('GROUP_', 'GRUPO '),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 1.2),
                ),
              ),
              ...times.map((time) {
                final isDestaque = _isTimeSelecionado(time['nome']);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color:
                          isDestaque ? _corDestaquePalmeiras : _corFundoTabela),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 22,
                          child: Text('${time['posicao']}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: _fontSize(r),
                                  color: isDestaque
                                      ? const Color(0xFF69f0ae)
                                      : Colors.white))),
                      SizedBox(
                        width: 28,
                        child: time['escudo'].toString().isNotEmpty
                            ? Image.network(time['escudo'],
                                height: 24,
                                width: 24,
                                errorBuilder: (c, e, s) => const Icon(
                                    Icons.shield,
                                    size: 24,
                                    color: Colors.white38))
                            : const Icon(Icons.shield,
                                size: 24, color: Colors.white38),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(time['nome'],
                              style: TextStyle(
                                  fontSize: _fontSize(r),
                                  fontWeight: isDestaque
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isDestaque
                                      ? const Color(0xFF69f0ae)
                                      : Colors.white))),
                      SizedBox(
                          width: 30,
                          child: Text('${time['pontos']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: _fontSize(r),
                                  color: Colors.white))),
                      SizedBox(
                          width: 26,
                          child: Text('${time['jogos']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: _fontSize(r) - 1,
                                  color: Colors.white70))),
                      SizedBox(
                          width: 26,
                          child: Text('${time['vitorias']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: _fontSize(r) - 1,
                                  color: Colors.white70))),
                      SizedBox(
                          width: 26,
                          child: Text('${time['empates']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: _fontSize(r) - 1,
                                  color: Colors.white70))),
                      SizedBox(
                          width: 26,
                          child: Text('${time['derrotas']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: _fontSize(r) - 1,
                                  color: Colors.white70))),
                      SizedBox(
                          width: 30,
                          child: Text('${time['saldo']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: _fontSize(r),
                                  fontWeight: FontWeight.bold,
                                  color: time['saldo'] > 0
                                      ? _corG4
                                      : time['saldo'] < 0
                                          ? _corZ4
                                          : Colors.white54))),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMataMata(R r) {
    if (libertadoresPartidas.isEmpty) {
      return const Center(
          child: Text('Nenhum jogo agendado na Libertadores',
              style: TextStyle(color: Colors.white70, fontSize: 16)));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: libertadoresPartidas.length,
      itemBuilder: (context, index) {
        final partida = libertadoresPartidas[index];
        bool isPalm(String nome) =>
            nome.toLowerCase().contains(_nomeTimeSelecionado);
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _corFundoTabela,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFFC1A163).withValues(alpha: 0.5),
                width: 1.5),
          ),
          child: Column(
            children: [
              Text(
                partida['fase'].toString().replaceAll('_', ' '),
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFC1A163),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _escudoMataMata(partida['escudoMandante'],
                      partida['mandante'], isPalm(partida['mandante'])),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text('X',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                  ),
                  _escudoMataMata(partida['escudoVisitante'],
                      partida['visitante'], isPalm(partida['visitante'])),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today,
                      size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(partida['data'],
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(width: 16),
                  const Icon(Icons.access_time,
                      size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(partida['horario'],
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _escudoMataMata(String url, String nome, bool destaque) {
    return Column(
      children: [
        url.isNotEmpty
            ? Image.network(url,
                height: 45,
                width: 45,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.shield, size: 45, color: Colors.white38))
            : const Icon(Icons.shield, size: 45, color: Colors.white38),
        const SizedBox(height: 6),
        Text(nome,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: destaque ? const Color(0xFF69f0ae) : Colors.white)),
      ],
    );
  }

  Widget _headerCell(String text, R r, {double width = 30}) {
    return SizedBox(
        width: width,
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: _fontSize(r))));
  }

  Widget _dataCell(String text, R r, {bool bold = false}) {
    return SizedBox(
        width: 30,
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: _fontSize(r),
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: Colors.white)));
  }
}
