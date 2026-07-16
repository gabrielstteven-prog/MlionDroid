import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:async';
import 'config_manager.dart';
import 'cache_manager.dart';
import 'responsive.dart';
import 'performance_manager.dart';
// Importa timesDisponiveis — fonte única de verdade dos IDs de cada time
import 'tela_config.dart' show timesDisponiveis;

const String _kApiKey = '2fe5b44d83914bd5b4b44df54b718fd0';

// ─────────────────────────────────────────────────────────────────────────────
//  Painter de fundo animado — linhas de campo + partículas
// ─────────────────────────────────────────────────────────────────────────────
class _CampoPainter extends CustomPainter {
  final double t;
  final Color cor1;
  final Color cor2;

  const _CampoPainter(this.t, this.cor1, this.cor2);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..style = PaintingStyle.fill;

    // Gradiente base
    p.shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        cor1.withValues(alpha: 0.95),
        Color.lerp(cor1, Colors.black, 0.65)!,
      ],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), p);

    // Círculos concêntricos pulsantes
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final cx = s.width * 0.5;
    final cy = s.height * 0.42;
    final pulse = 1.0 + math.sin(t * math.pi * 2) * 0.03;
    for (int i = 1; i <= 4; i++) {
      linePaint.color = cor2.withValues(alpha: 0.04 + (4 - i) * 0.02);
      canvas.drawCircle(Offset(cx, cy), s.width * 0.12 * i * pulse, linePaint);
    }

    // Linhas horizontais
    final fieldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = cor2.withValues(alpha: 0.07);
    for (int i = 0; i < 5; i++) {
      final y = s.height * 0.1 + s.height * 0.8 * i / 4;
      canvas.drawLine(
          Offset(s.width * 0.05, y), Offset(s.width * 0.95, y), fieldPaint);
    }

    // Área do gol
    final areaPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = cor2.withValues(alpha: 0.08);
    final areaPath = Path()
      ..moveTo(s.width * 0.3, 0)
      ..lineTo(s.width * 0.3, s.height * 0.18)
      ..lineTo(s.width * 0.7, s.height * 0.18)
      ..lineTo(s.width * 0.7, 0);
    canvas.drawPath(areaPath, areaPaint);

    // Partículas flutuantes
    final rng = math.Random(42);
    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 18; i++) {
      final bx = rng.nextDouble() * s.width;
      final by = rng.nextDouble() * s.height;
      final off = math.sin(t * math.pi * 2 + i * 0.7) * 6;
      final sz = rng.nextDouble() * 2.5 + 0.5;
      particlePaint.color =
          cor2.withValues(alpha: 0.12 + rng.nextDouble() * 0.08);
      canvas.drawCircle(Offset(bx, by + off), sz, particlePaint);
    }
  }

  @override
  bool shouldRepaint(_CampoPainter old) => old.t != t;
}

class TelaTabela extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaTabela({super.key, required this.aoTerminar});

  @override
  State<TelaTabela> createState() => _TelaTabelaState();
}

class _TelaTabelaState extends State<TelaTabela>
    with SingleTickerProviderStateMixin {
  final _cfg = ConfigManager();

  Map<String, dynamic>? _jogo;
  bool _carregando = true;
  Timer? _saidaTimer;

  late AnimationController _bgCtrl;

  // ── Getters de config ──────────────────────────────────────────────────────
  String get _timeKey => _cfg.getString('time', 'time_key', 'palmeiras');
  String get _nomeTime => _cfg.getString('palmeiras', 'nome_time', 'Palmeiras');
  String get _escudoAsset => _cfg.getString(
      'palmeiras', 'escudo_asset', 'assets/escudos/palmeiras.png');

  // Fonte única: lê o teamId direto do TimeInfo em tela_config.dart
  int get _teamId {
    final info = timesDisponiveis[_timeKey];
    return info?.teamId ?? 1769; // fallback Palmeiras
  }

  // Cores lidas do TimeInfo para manter consistência com o resto do app
  Color get _corPrimaria {
    final info = timesDisponiveis[_timeKey];
    if (info == null) return const Color(0xFF006B2E);
    try {
      return Color(int.parse(info.corTop));
    } catch (_) {}
    return const Color(0xFF006B2E);
  }

  Color get _corAcento {
    final info = timesDisponiveis[_timeKey];
    if (info == null) return const Color(0xFFC1A163);
    try {
      return Color(int.parse(info.corDestaque));
    } catch (_) {}
    return const Color(0xFFC1A163);
  }

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    if (!PerformanceManager.instance.modoEconomico) {
      _bgCtrl.repeat(reverse: true);
    }
    _carregarJogo();
  }

  String get _chaveCache => 'proxima_partida_$_teamId';

  /// Checa o cache. Mesmo num cache hit, os campos de data (HOJE/AMANHÃ/
  /// EM X DIAS) são recalculados a partir da data real do jogo — assim a
  /// etiqueta nunca fica errada mesmo que o dado tenha alguns dias.
  Future<void> _carregarJogo() async {
    final cache = await CacheManager.instance.obter<Map<String, dynamic>>(
      _chaveCache,
      validade: _cfg.getIntervaloAtualizacao('proxima_partida'),
    );
    if (cache != null && mounted) {
      final dt = DateTime.tryParse(cache['utcDate'] as String? ?? '');
      // Só usa o cache se o jogo salvo ainda não passou
      if (dt != null && dt.isAfter(DateTime.now())) {
        setState(() {
          _jogo = _construirJogo(cache);
          _carregando = false;
        });
        _saidaTimer = Timer(const Duration(seconds: 18), () {
          if (mounted) widget.aoTerminar();
        });
        return;
      }
    }
    await _buscarJogo();
  }

  /// Monta o Map de exibição a partir do Map crú retornado pela API
  /// (ou recuperado do cache).
  Map<String, dynamic> _construirJogo(Map<String, dynamic> p) {
    final dt = DateTime.parse(p['utcDate']).toLocal();
    final diasSemana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    final meses = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez'
    ];
    final agora = DateTime.now();
    final diff =
        dt.difference(DateTime(agora.year, agora.month, agora.day)).inDays;

    String etiqueta;
    if (diff == 0) {
      etiqueta = 'HOJE';
    } else if (diff == 1) {
      etiqueta = 'AMANHÃ';
    } else {
      etiqueta = 'EM $diff DIAS';
    }

    return {
      'mandante': p['homeTeam']['shortName'] ?? p['homeTeam']['name'] ?? '',
      'visitante': p['awayTeam']['shortName'] ?? p['awayTeam']['name'] ?? '',
      'nomeMandante': p['homeTeam']['name'] ?? '',
      'nomeVisitante': p['awayTeam']['name'] ?? '',
      'escudoMandante': p['homeTeam']['crest'] ?? '',
      'escudoVisitante': p['awayTeam']['crest'] ?? '',
      'competicao': p['competition']['name'] ?? '',
      'diaSemana': diasSemana[dt.weekday % 7],
      'dia': dt.day.toString(),
      'mes': meses[dt.month - 1],
      'ano': dt.year.toString(),
      'horario':
          '${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}',
      'estadio': p['venue'] ?? 'A confirmar',
      'etiqueta': etiqueta,
      'diasRestantes': diff,
    };
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _saidaTimer?.cancel();
    super.dispose();
  }

  Future<void> _buscarJogo() async {
    // Tenta primeiro o endpoint direto do time
    // Se vier vazio, tenta filtrar por competição específica (BSA/CLI/BRC/CSA)
    // O plano free da football-data.org permite acesso a competições selecionadas
    final id = _teamId;
    Map<String, dynamic>? jogoEncontrado;

    // Lista de competições para tentar (ordem de prioridade)
    const comps = ['BSA', 'CLI', 'BRC', 'CSA', 'WC'];

    // Tentativa 1: endpoint direto sem filtro de competição
    jogoEncontrado = await _fetchEndpoint(
      'https://api.football-data.org/v4/teams/$id/matches?status=SCHEDULED&limit=1',
    );

    // Tentativa 2: endpoint com cada competição separada
    if (jogoEncontrado == null) {
      for (final comp in comps) {
        jogoEncontrado = await _fetchEndpoint(
          'https://api.football-data.org/v4/teams/$id/matches?competitions=$comp&status=SCHEDULED&limit=1',
        );
        if (jogoEncontrado != null) break;
      }
    }

    // Tentativa 3: buscar via competição (todos os jogos, filtrar pelo time)
    if (jogoEncontrado == null) {
      for (final comp in ['BSA', 'CLI']) {
        jogoEncontrado = await _fetchCompetition(comp, id);
        if (jogoEncontrado != null) break;
      }
    }

    if (jogoEncontrado != null) {
      final p = jogoEncontrado;
      setState(() {
        _jogo = _construirJogo(p);
        _carregando = false;
      });
      await CacheManager.instance.salvar(_chaveCache, p);
    } else {
      setState(() {
        _jogo = null;
        _carregando = false;
      });
    }

    _saidaTimer = Timer(const Duration(seconds: 18), () {
      if (mounted) widget.aoTerminar();
    });
  }

  // Busca um endpoint direto e retorna o primeiro match ou null
  Future<Map<String, dynamic>?> _fetchEndpoint(String url) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {'X-Auth-Token': _kApiKey},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final matches = data['matches'] as List? ?? [];
        if (matches.isNotEmpty) return matches[0] as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // Busca via competição e filtra pelo time
  Future<Map<String, dynamic>?> _fetchCompetition(
      String comp, int teamId) async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://api.football-data.org/v4/competitions/$comp/matches?status=SCHEDULED',
        ),
        headers: {'X-Auth-Token': _kApiKey},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final matches = data['matches'] as List? ?? [];
        // Filtrar apenas jogos do time selecionado
        for (final m in matches) {
          final homeId = m['homeTeam']['id'] as int? ?? 0;
          final awayId = m['awayTeam']['id'] as int? ?? 0;
          if (homeId == teamId || awayId == teamId) {
            return m as Map<String, dynamic>;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _bgCtrl,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Fundo animado
              CustomPaint(
                painter: _CampoPainter(_bgCtrl.value, _corPrimaria, _corAcento),
                size: Size.infinite,
              ),

              // Conteúdo
              SafeArea(
                child: _carregando
                    ? _buildCarregando(r)
                    : _jogo == null
                        ? _buildVazio(r)
                        : _buildJogo(r),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Loading ────────────────────────────────────────────────────────────────
  Widget _buildCarregando(R r) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _corAcento, strokeWidth: 2),
          SizedBox(height: r.sp(16)),
          Text('Buscando próximo jogo...',
              style: GoogleFonts.rajdhani(
                  color: Colors.white54, fontSize: r.fs(16))),
        ],
      ),
    );
  }

  // ── Sem jogo ───────────────────────────────────────────────────────────────
  Widget _buildVazio(R r) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_soccer,
              color: _corAcento.withValues(alpha: 0.4), size: r.icon(60)),
          SizedBox(height: r.sp(16)),
          Text('Nenhum jogo agendado',
              style: GoogleFonts.rajdhani(
                  color: Colors.white54,
                  fontSize: r.fs(20),
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Tela principal ─────────────────────────────────────────────────────────
  Widget _buildJogo(R r) {
    final j = _jogo!;
    final diasRestantes = j['diasRestantes'] as int;

    return Padding(
      padding: EdgeInsets.fromLTRB(r.sp(24), r.sp(14), r.sp(24), r.sp(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Título + sub ──────────────────────────────────────────────────
          _buildTitulo(r, j),
          SizedBox(height: r.sp(14)),

          // ── Confronto — ocupa a maior parte da tela ───────────────────────
          Expanded(child: _buildConfronto(r, j)),
          SizedBox(height: r.sp(14)),

          // ── Grade de infos: 3 células ─────────────────────────────────────
          _buildInfoGrid(r, j),
          SizedBox(height: r.sp(12)),

          // ── Countdown ─────────────────────────────────────────────────────
          if (diasRestantes >= 0) _buildCountdown(r, j),
        ],
      ),
    );
  }

  // ── Título ─────────────────────────────────────────────────────────────────
  Widget _buildTitulo(R r, Map j) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Escudo do time configurado — sem anel/brilho ao redor, só o
        // escudo em si, num tamanho proporcional ao título ao lado.
        Container(
          width: r.sp(62),
          height: r.sp(62),
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: ClipOval(
            child: Image.asset(_escudoAsset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.sports_soccer,
                    color: _corAcento, size: r.icon(30))),
          ),
        ),
        SizedBox(width: r.sp(14)),

        // Título e subtítulo
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PRÓXIMA PARTIDA',
                style: GoogleFonts.rajdhani(
                  color: Colors.white,
                  fontSize: r.fs(r.isCompact ? 22 : 30),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  shadows: [
                    Shadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 8),
                  ],
                ),
              ),
              Text(
                _nomeTime.toUpperCase(),
                style: GoogleFonts.poppins(
                  color: _corAcento,
                  fontSize: r.fs(r.isCompact ? 11 : 13),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),

        // Badge competição
        Container(
          padding:
              EdgeInsets.symmetric(horizontal: r.sp(14), vertical: r.sp(7)),
          decoration: BoxDecoration(
            color: _corAcento.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: _corAcento.withValues(alpha: 0.55), width: 1.2),
          ),
          child: Text(
            j['competicao'],
            style: GoogleFonts.rajdhani(
              color: _corAcento,
              fontSize: r.fs(r.isCompact ? 13 : 15),
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── Confronto ──────────────────────────────────────────────────────────────
  Widget _buildConfronto(R r, Map j) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(r.radius(22)),
        border:
            Border.all(color: _corAcento.withValues(alpha: 0.20), width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
              child: _buildTimeCard(
                  r, j['escudoMandante'], j['mandante'], 'MANDANTE')),
          _buildVS(r),
          Expanded(
              child: _buildTimeCard(
                  r, j['escudoVisitante'], j['visitante'], 'VISITANTE')),
        ],
      ),
    );
  }

  Widget _buildTimeCard(R r, String url, String nome, String papel) {
    final nomeNorm = nome.toLowerCase();
    final isNosso = nomeNorm.contains(_timeKey.split('-')[0]) ||
        _nomeTime.toLowerCase().contains(nomeNorm);

    // Escudo maior — sem círculo ao redor, apenas sombra no nosso time
    final escudoSize = r.sp(r.isCompact ? 90 : 130);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Escudo — sem BoxDecoration circular, só a imagem com sombra
        Stack(
          alignment: Alignment.center,
          children: [
            // Halo de glow atrás (só no nosso time)
            if (isNosso)
              Container(
                width: escudoSize * 1.12,
                height: escudoSize * 1.12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    _corAcento.withValues(alpha: 0.18),
                    Colors.transparent,
                  ]),
                ),
              ),
            // Escudo sem moldura circular
            SizedBox(
              width: escudoSize,
              height: escudoSize,
              child: url.isNotEmpty
                  ? Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(Icons.shield_rounded,
                          color: _corAcento, size: escudoSize * 0.7),
                    )
                  : Icon(Icons.shield_rounded,
                      color: _corAcento, size: escudoSize * 0.7),
            ),
          ],
        ),

        SizedBox(height: r.sp(14)),

        // Nome do time — bem grande, legível de longe
        Text(
          nome,
          style: GoogleFonts.rajdhani(
            color: isNosso ? _corAcento : Colors.white,
            fontSize: r.fs(r.isCompact ? 26 : 36),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            shadows: isNosso
                ? [
                    Shadow(
                        color: _corAcento.withValues(alpha: 0.4),
                        blurRadius: 12)
                  ]
                : [],
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        SizedBox(height: r.sp(6)),

        // Papel — tamanho maior, cor totalmente visível
        Text(
          papel,
          style: GoogleFonts.poppins(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: r.fs(r.isCompact ? 12 : 14),
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildVS(R r) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.sp(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'VS',
            style: GoogleFonts.orbitron(
              color: _corAcento,
              fontSize: r.fs(r.isCompact ? 32 : 48),
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              shadows: [
                Shadow(
                    color: _corAcento.withValues(alpha: 0.65), blurRadius: 28),
                Shadow(
                    color: _corAcento.withValues(alpha: 0.28), blurRadius: 56),
              ],
            ),
          ),
          SizedBox(height: r.sp(8)),
          Container(
            width: r.sp(56),
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                _corAcento.withValues(alpha: 0.80),
                Colors.transparent,
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Grade de infos ─────────────────────────────────────────────────────────
  Widget _buildInfoGrid(R r, Map j) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
              child: _infoCell(
                  r,
                  Icons.calendar_today_rounded,
                  '${j['diaSemana']}, ${j['dia']} ${j['mes']} ${j['ano']}',
                  'DATA')),
          SizedBox(width: r.sp(10)),
          Expanded(
              child: _infoCell(r, Icons.access_time_rounded,
                  '${j['horario']} (Brasília)', 'HORÁRIO')),
          SizedBox(width: r.sp(10)),
          Expanded(
              child:
                  _infoCell(r, Icons.stadium_rounded, j['estadio'], 'ESTÁDIO')),
        ],
      ),
    );
  }

  Widget _infoCell(R r, IconData icon, String valor, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(14), vertical: r.sp(16)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(r.radius(16)),
        border:
            Border.all(color: _corAcento.withValues(alpha: 0.28), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _corAcento, size: r.icon(r.isCompact ? 26 : 32)),
          SizedBox(height: r.sp(8)),
          Text(
            valor,
            style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontSize: r.fs(r.isCompact ? 17 : 22),
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: r.sp(5)),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: _corAcento,
              fontSize: r.fs(r.isCompact ? 11 : 13),
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Countdown ──────────────────────────────────────────────────────────────
  Widget _buildCountdown(R r, Map j) {
    final int dias = j['diasRestantes'] as int;
    final String etiqueta = j['etiqueta'];
    final bool urgente = dias <= 1;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: r.sp(24), vertical: r.sp(14)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _corAcento.withValues(alpha: urgente ? 0.28 : 0.14),
            _corPrimaria.withValues(alpha: urgente ? 0.20 : 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(r.radius(16)),
        border: Border.all(
          color: _corAcento.withValues(alpha: urgente ? 0.70 : 0.35),
          width: urgente ? 2 : 1.2,
        ),
        boxShadow: urgente
            ? [
                BoxShadow(
                    color: _corAcento.withValues(alpha: 0.20),
                    blurRadius: 20,
                    spreadRadius: 1)
              ]
            : [],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            urgente ? Icons.notifications_active_rounded : Icons.timer_outlined,
            color: _corAcento,
            size: r.icon(r.isCompact ? 20 : 26),
          ),
          SizedBox(width: r.sp(12)),
          Text(
            etiqueta,
            style: GoogleFonts.orbitron(
              color: _corAcento,
              fontSize: r.fs(r.isCompact ? 18 : 26),
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              shadows: [
                Shadow(
                    color: _corAcento.withValues(alpha: 0.55), blurRadius: 16),
              ],
            ),
          ),
          if (dias > 1) ...[
            SizedBox(width: r.sp(16)),
            Container(
              width: 1.5,
              height: r.sp(22),
              color: _corAcento.withValues(alpha: 0.35),
            ),
            SizedBox(width: r.sp(16)),
            Text(
              '${j['diaSemana']}-feira',
              style: GoogleFonts.rajdhani(
                color: Colors.white.withValues(alpha: 0.80),
                fontSize: r.fs(r.isCompact ? 16 : 22),
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
