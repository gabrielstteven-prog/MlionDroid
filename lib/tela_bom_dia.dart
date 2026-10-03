import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'design/tema.dart';
import 'info_hub.dart';
import 'performance_manager.dart';
import 'responsive.dart';
import 'services/fotos_service.dart';
import 'services/jarvis_service.dart';
import 'services/news_service.dart';
import 'services/resumo_service.dart';
import 'services/voz_service.dart';
import 'services/weather_service.dart';
import 'util.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  TelaBomDia — saudação, clima do dia, foto do dia, notícia e frase.
//  Aparece só na janela de horário configurada (o rodízio filtra).
// ═══════════════════════════════════════════════════════════════════════════
class TelaBomDia extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaBomDia({super.key, required this.aoTerminar});

  @override
  State<TelaBomDia> createState() => _TelaBomDiaState();
}

class _TelaBomDiaState extends State<TelaBomDia> with TickerProviderStateMixin {
  final _cfg = ConfigManager();

  // ── Dados ─────────────────────────────────────────────────────────────────
  DadosClima? _clima = WeatherService.instance.atual;
  int get _tempAtual => _clima?.temp ?? 0;
  int get _tempMax => _clima?.hoje?.max ?? 0;
  int get _tempMin => _clima?.hoje?.min ?? 0;
  int get _sensacao => _clima?.sensacao ?? 0;
  int get _probChuva => _clima?.hoje?.chanceChuva ?? 0;
  int get _weatherCode => _clima?.codigo ?? 0;
  bool get _ehDia => _clima?.ehDia ?? true;

  final String _frase = fraseDoDia();
  Noticia? _noticia;
  String? _fotoDoDia;
  bool _carregando = true;

  Timer? _saidaTimer;
  Timer? _antiTravamento;

  // ── Controllers ───────────────────────────────────────────────────────────
  late AnimationController _bgCtrl; // fundo animado infinito
  late AnimationController _entradaCtrl; // fade-in de entrada
  late AnimationController _floatCtrl; // partículas flutuantes
  late Animation<double> _entradaAnim;

  final List<_Particula> _particulas = [];

  // ── Config ────────────────────────────────────────────────────────────────
  /// Nome na saudação. Vazio (ou o antigo padrão "Bem-vindo") = sem nome,
  /// evitando o estranho "Bom dia Bem-vindo,".
  String get _nomeUsuario {
    final n = _cfg.getString('geral', 'nome_usuario', '').trim();
    return n.toLowerCase() == 'bem-vindo' ? '' : n;
  }

  int get _horaInicio => _cfg.getInt('bom_dia', 'hora_inicio', 4);
  int get _horaFim => _cfg.getInt('bom_dia', 'hora_fim', 10);
  int get _duracaoLongo => _cfg.getInt('bom_dia', 'duracao_longa_seg', 90);
  int get _duracaoCurto => _cfg.getInt('bom_dia', 'duracao_curta_seg', 20);

  // ── Personalização visual ───────────────────────────────────────────────
  double get _tamanhoNome => _cfg.getDouble('bom_dia', 'tamanho_nome', 40.0);
  double get _tamanhoTemp => _cfg.getDouble('bom_dia', 'tamanho_temp', 72.0);
  String get _corDestaqueHex => _cfg.getString('bom_dia', 'cor_destaque', '');
  bool get _mostrarChuva => _cfg.getBool('bom_dia', 'mostrar_chuva', true);
  bool get _mostrarFrase => _cfg.getBool('bom_dia', 'mostrar_frase', true);
  bool get _mostrarNoticia => _cfg.getBool('bom_dia', 'mostrar_noticia', true);
  bool get _mostrarSensacao =>
      _cfg.getBool('bom_dia', 'mostrar_sensacao', true);
  bool get _mostrarFoto => _cfg.getBool('bom_dia', 'mostrar_foto', true);

  // ── Helper: fonte configurável ──────────────────────────────────────────
  TextStyle _fonteEstilo({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color color = Colors.white,
    double? height,
    FontStyle fontStyle = FontStyle.normal,
    List<Shadow>? shadows,
  }) {
    final base = _cfg.getString('bom_dia', 'fonte', 'poppins');
    final estilo = TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        fontStyle: fontStyle,
        shadows: shadows);
    switch (base) {
      case 'rajdhani':
        return GoogleFonts.rajdhani(textStyle: estilo);
      case 'orbitron':
        return GoogleFonts.orbitron(textStyle: estilo);
      case 'roboto':
        return GoogleFonts.roboto(textStyle: estilo);
      case 'exo2':
        return GoogleFonts.exo2(textStyle: estilo);
      default:
        return GoogleFonts.poppins(textStyle: estilo);
    }
  }

  // ── Cor de destaque: usa config ou fallback do tema ──────────────────────
  Color _resolverCorDestaque(_ClimaTheme theme) {
    final hex = _corDestaqueHex;
    if (hex.isEmpty) return theme.corDestaque;
    return parseCor(hex, theme.corDestaque.toARGB32());
  }

  _ClimaTheme get _climaTheme =>
      _ClimaTheme.fromCode(_weatherCode, _probChuva, ehDia: _ehDia);

  @override
  void initState() {
    super.initState();

    _bgCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 12));
    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _floatCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 18));

    // Fundo, ícone, pulso e partículas são decorativos — só em loop no modo
    // visual completo.
    if (PerformanceManager.instance.animacoesDecorativasAtivas) {
      _bgCtrl.repeat(reverse: true);
      _floatCtrl.repeat();
    }

    _entradaAnim =
        CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOutCubic);

    final rng = math.Random();
    for (int i = 0; i < 30; i++) {
      _particulas.add(_Particula(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: rng.nextDouble() * 4 + 1.5,
        speed: rng.nextDouble() * 0.25 + 0.08,
        phase: rng.nextDouble() * math.pi * 2,
        opacity: rng.nextDouble() * 0.5 + 0.1,
      ));
    }

    _entradaCtrl.forward();
    _carregarDados();
    _antiTravamento = Timer(const Duration(minutes: 5), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _entradaCtrl.dispose();
    _floatCtrl.dispose();
    _saidaTimer?.cancel();
    _antiTravamento?.cancel();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    await Future.wait([
      WeatherService.instance.obter().then((c) => _clima = c ?? _clima),
      _buscarNoticia(),
      FotosService.instance.fotoDoDia().then((f) => _fotoDoDia = f),
    ]);
    _resumo = await ResumoService.instance.montar();
    if (!mounted) return;
    setState(() => _carregando = false);
    _iniciarSaida();
    _falarResumoSeConfigurado();
  }

  List<ItemResumo> _resumo = [];

  /// Lê o resumo em voz alta uma vez por manhã (opcional, nas Configurações).
  Future<void> _falarResumoSeConfigurado() async {
    if (!_cfg.getBool('bom_dia', 'falar_resumo', false) || _resumo.isEmpty) return;
    final hoje = DateTime.now();
    final chave = 'bom_dia_falado_${hoje.year}_${hoje.month}_${hoje.day}';
    if (await CacheManager.instance.obterEntrada<bool>(chave) != null) return;
    await CacheManager.instance.salvar(chave, true);
    // Com IA configurada, o Jarvis escreve um briefing natural; sem IA (ou
    // se ela falhar), lê o resumo pronto.
    final nome = _nomeUsuario;
    final texto = await JarvisService.instance.briefing(_saudacao) ??
        ResumoService.instance
            .paraFalar(nome.isEmpty ? _saudacao : '$_saudacao, $nome', _resumo);
    if (!mounted) return;
    await VozService.instance.falar(texto.replaceAll('°', ' graus'));
  }

  Future<void> _buscarNoticia() async {
    final r = await NewsService.instance.buscar(
      const [FonteRss('https://g1.globo.com/rss/g1/', 'G1')],
      validade: const Duration(hours: 1),
    );
    // O RSS do G1 às vezes traz só uma palavra como descrição — prefere
    // uma notícia com resumo de verdade.
    _noticia = r.noticias.where((n) => n.descricao.length >= 40).firstOrNull ??
        r.noticias.firstOrNull;
  }

  void _abrirNoticia() {
    final n = _noticia;
    if (n == null) return;
    _saidaTimer?.cancel();
    final web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(n.link));
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          children: [
            ListTile(
              title: Text(n.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            Expanded(child: WebViewWidget(controller: web)),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) _iniciarSaida();
    });
  }

  void _iniciarSaida() {
    final h = DateTime.now().hour;
    final seg = h < (_horaInicio + (_horaFim - _horaInicio) ~/ 2)
        ? _duracaoLongo
        : _duracaoCurto;
    _saidaTimer?.cancel();
    _saidaTimer = Timer(Duration(seconds: seg.clamp(5, 600)), () {
      if (mounted) widget.aoTerminar();
    });
  }

  String get _saudacao => saudacaoDaHora();

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final theme = _climaTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fundo e partículas são pintados com `repaint:` dentro de um
          // RepaintBoundary — a animação NÃO reconstrói o conteúdo da tela
          // (antes a tela inteira, com imagens e textos, era refeita 60x/s).
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _FundoClimaticoPainter(anim: _bgCtrl, theme: theme),
                foregroundPainter: _ParticulasPainter(
                  particulas: _particulas,
                  anim: _floatCtrl,
                  theme: theme,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          if (_carregando)
            _buildCarregando(r, theme)
          else
            SafeArea(
              child: FadeTransition(
                opacity: _entradaAnim,
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildConteudo(r, theme, constraints),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCarregando(R r, _ClimaTheme theme) =>
      const Carregando(cor: Destaques.bomDia);

  // ── Layout ────────────────────────────────────────────────────────────────
  //  ┌─────────────────────────────────────┬──────────────────┐
  //  │ Bom dia, Gabriel                     │                  │
  //  │ sábado, 3 de outubro · 06:42         │   foto do dia    │
  //  │ ☀ 22°   hoje 16° a 28°               │                  │
  //  ├─────────────────────────────────────┴──────────────────┤
  //  │ Seu dia (frases)                     │ notícia          │
  //  │ frase do dia                                            │
  //  └─────────────────────────────────────────────────────────┘
  Widget _buildConteudo(R r, _ClimaTheme theme, BoxConstraints constraints) {
    final t = Tipo(r);
    final temFoto = _mostrarFoto && _fotoDoDia != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.sp(40), r.sp(28), r.sp(40), r.sp(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _buildAbertura(r, theme)),
                if (temFoto) ...[
                  SizedBox(width: r.sp(32)),
                  Expanded(flex: 2, child: _buildFotoDoDiaCard(r, theme)),
                ],
              ],
            ),
          ),
          SizedBox(height: r.sp(24)),
          Expanded(
            flex: 9,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _buildSeuDia(r)),
                if (_mostrarNoticia) ...[
                  SizedBox(width: r.sp(32)),
                  Expanded(flex: 2, child: _buildNoticiaCard(r, theme)),
                ],
              ],
            ),
          ),
          if (_mostrarFrase) ...[
            SizedBox(height: r.sp(14)),
            Text(_frase,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.apoio().copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  /// Saudação, data/hora e o clima de agora — o que se lê de longe.
  Widget _buildAbertura(R r, _ClimaTheme theme) {
    final t = Tipo(r);
    final nome = _nomeUsuario;
    final corNome = _corDestaqueHex.isEmpty ? Destaques.bomDia : _resolverCorDestaque(theme);
    final tamanho = r.fs(_tamanhoNome.clamp(28, 72) * 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: nome.isEmpty ? _saudacao : '$_saudacao, ',
                  style: _fonteEstilo(fontSize: tamanho, fontWeight: FontWeight.w400)),
              if (nome.isNotEmpty)
                TextSpan(
                    text: nome,
                    style: _fonteEstilo(
                        fontSize: tamanho, fontWeight: FontWeight.w700, color: corNome)),
            ]),
          ),
        ),
        SizedBox(height: r.sp(6)),
        ValueListenableBuilder<DateTime>(
          valueListenable: InfoHub.instance.relogio,
          builder: (context, agora, _) => Text(
            '${diaSemanaLongo(agora)}, ${agora.day} de ${mesesLongos[agora.month - 1]}, ${horaMinuto(agora)}',
            style: t.subtitulo(cor: Cores.textoSecundario).copyWith(fontWeight: FontWeight.w400),
          ),
        ),
        SizedBox(height: r.sp(20)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(theme.emoji, style: TextStyle(fontSize: r.fs(64))),
            SizedBox(width: r.sp(16)),
            Text('$_tempAtual°',
                style: t.heroi().copyWith(
                    fontSize: r.fs((_tamanhoTemp / 72 * 104).clamp(72, 140)))),
            SizedBox(width: r.sp(20)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Hoje entre $_tempMin° e $_tempMax°', style: t.corpo()),
                if (_mostrarSensacao)
                  Text('Sensação de $_sensacao°', style: t.apoio()),
                if (_mostrarChuva && _probChuva >= 30)
                  Text('$_probChuva% de chance de chuva', style: t.apoio(cor: Cores.chuva)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// "Seu dia": o resumo montado pelo ResumoService.
  Widget _buildSeuDia(R r) {
    final t = Tipo(r);
    return Superficie(
      padding: EdgeInsets.all(r.sp(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Seu dia', style: t.subtitulo()),
          SizedBox(height: r.sp(10)),
          Expanded(
            child: _resumo.isEmpty
                ? Text('Dia livre: nenhum compromisso, jogo ou lembrete encontrado.',
                    style: t.apoio())
                : ListView(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final i in _resumo)
                        Padding(
                          padding: EdgeInsets.only(bottom: r.sp(10)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(i.icone, color: i.cor, size: r.icon(26)),
                              SizedBox(width: r.sp(14)),
                              Expanded(child: Text(i.texto, style: t.corpo())),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoDoDiaCard(R r, _ClimaTheme theme) {
    final t = Tipo(r);
    return ClipRRect(
      borderRadius: BorderRadius.circular(r.sp(28)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: ResizeImage(FileImage(File(_fotoDoDia!)), width: 900),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ColoredBox(color: Cores.superficie),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(r.sp(18), r.sp(28), r.sp(18), r.sp(14)),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xAA000000)],
                ),
              ),
              child: Text('Recordação do dia', style: t.apoio(cor: Cores.texto)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticiaCard(R r, _ClimaTheme theme) {
    final t = Tipo(r);
    final n = _noticia;
    return GestureDetector(
      onTap: _abrirNoticia,
      child: Superficie(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (n != null && n.imagem.isNotEmpty)
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(r.sp(24))),
                  child: CachedNetworkImage(
                    imageUrl: n.imagem,
                    fit: BoxFit.cover,
                    memCacheWidth: 700,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Expanded(
              flex: 6,
              child: Padding(
                padding: EdgeInsets.all(r.sp(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notícia do dia', style: t.legenda()),
                    SizedBox(height: r.sp(6)),
                    Expanded(
                      child: Text(
                        n?.titulo ?? 'Sem conexão com as notícias agora.',
                        style: t.corpo(peso: FontWeight.w700),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (n != null) Text('Toque para ler', style: t.legenda(cor: Destaques.bomDia)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Tema de clima: paleta + emoji por código WMO
// ═══════════════════════════════════════════════════════════════════════════
class _ClimaTheme {
  final List<Color> fundoCores;
  final Color corDestaque;
  final String emoji;
  final _TipoTempo tipo;

  const _ClimaTheme({
    required this.fundoCores,
    required this.corDestaque,
    required this.emoji,
    required this.tipo,
  });

  factory _ClimaTheme.fromCode(int code, int probChuva, {bool ehDia = true}) {
    // Antes do sol nascer (a tela aparece a partir das 4h) não faz sentido
    // mostrar sol: céu limpo ou nublado à noite vira o tema noturno.
    if (!ehDia && code <= 3 && probChuva < 70) {
      return const _ClimaTheme(
        fundoCores: [
          Color(0xFF0B1026),
          Color(0xFF141E3C),
          Color(0xFF1B2A4A),
          Color(0xFF2A3B66)
        ],
        corDestaque: Color(0xFFFFE082),
        emoji: '🌙',
        tipo: _TipoTempo.noite,
      );
    }
    if (code >= 51 || probChuva >= 70) {
      return const _ClimaTheme(
        fundoCores: [
          Color(0xFF1A237E),
          Color(0xFF263238),
          Color(0xFF37474F),
          Color(0xFF455A64)
        ],
        corDestaque: Color(0xFF90CAF9),
        emoji: '🌧️',
        tipo: _TipoTempo.chuva,
      );
    }
    if (code >= 2 && code <= 48) {
      return const _ClimaTheme(
        fundoCores: [
          Color(0xFF455A64),
          Color(0xFF546E7A),
          Color(0xFF607D8B),
          Color(0xFF78909C)
        ],
        corDestaque: Color(0xFFB0BEC5),
        emoji: '☁️',
        tipo: _TipoTempo.nublado,
      );
    }
    if (code == 1) {
      return const _ClimaTheme(
        fundoCores: [
          Color(0xFF0277BD),
          Color(0xFF0288D1),
          Color(0xFF039BE5),
          Color(0xFF81D4FA)
        ],
        corDestaque: Color(0xFFFFE082),
        emoji: '⛅',
        tipo: _TipoTempo.solComNuvens,
      );
    }
    return const _ClimaTheme(
      fundoCores: [
        Color(0xFF0D47A1),
        Color(0xFF1565C0),
        Color(0xFF1976D2),
        Color(0xFF42A5F5)
      ],
      corDestaque: Color(0xFFFFD54F),
      emoji: '☀️',
      tipo: _TipoTempo.sol,
    );
  }
}

enum _TipoTempo { sol, solComNuvens, nublado, chuva, noite }

// ═══════════════════════════════════════════════════════════════════════════
//  Painter: fundo dinâmico
// ═══════════════════════════════════════════════════════════════════════════
class _FundoClimaticoPainter extends CustomPainter {
  final Animation<double> anim;
  final _ClimaTheme theme;

  _FundoClimaticoPainter({required this.anim, required this.theme})
      : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size s) {
    final t = anim.value;
    final lerp = (math.sin(t * math.pi) + 1) / 2;
    final c0 = Color.lerp(theme.fundoCores[0], theme.fundoCores[1], lerp)!;
    final c1 = Color.lerp(theme.fundoCores[2], theme.fundoCores[3], lerp)!;

    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c0, c1],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

    if (theme.tipo == _TipoTempo.sol || theme.tipo == _TipoTempo.solComNuvens) {
      _pintarSol(canvas, s, lerp);
    }
    if (theme.tipo == _TipoTempo.chuva) {
      _pintarFundoChuva(canvas, s);
      _pintarNuvens(canvas, s, intensidade: 0.85);
    }
    if (theme.tipo == _TipoTempo.nublado) {
      _pintarFundoNublado(canvas, s, lerp);
      _pintarNuvens(canvas, s, intensidade: 0.65);
    }
    if (theme.tipo == _TipoTempo.solComNuvens) {
      _pintarNuvens(canvas, s, intensidade: 0.35);
    }
  }

  // ── Nuvens orgânicas, formadas por múltiplos círculos sobrepostos ────────
  void _pintarNuvens(Canvas canvas, Size s, {required double intensidade}) {
    void desenharNuvem(
        double cx, double cy, double escala, double opacidadeMult) {
      final p = Paint()
        ..color =
            Colors.white.withValues(alpha: 0.09 * intensidade * opacidadeMult)
        ..style = PaintingStyle.fill;
      final blobs = [
        Offset(cx, cy),
        Offset(cx + 38 * escala, cy + 6 * escala),
        Offset(cx - 36 * escala, cy + 8 * escala),
        Offset(cx + 14 * escala, cy - 14 * escala),
        Offset(cx - 16 * escala, cy - 10 * escala),
      ];
      final radii = [34.0, 26.0, 24.0, 22.0, 20.0];
      for (int i = 0; i < blobs.length; i++) {
        canvas.drawCircle(blobs[i], radii[i] * escala, p);
      }
    }

    // Três nuvens em profundidades e velocidades diferentes — leve parallax
    final x1 = ((anim.value * 0.06) % 1.2 - 0.1) * s.width;
    final x2 = ((anim.value * 0.04 + 0.4) % 1.2 - 0.1) * s.width;
    final x3 = ((anim.value * 0.05 + 0.75) % 1.2 - 0.1) * s.width;

    desenharNuvem(x1, s.height * 0.14, 1.6, 1.0);
    desenharNuvem(x2, s.height * 0.24, 1.1, 0.7);
    desenharNuvem(x3, s.height * 0.09, 1.3, 0.85);
  }

  void _pintarSol(Canvas canvas, Size s, double lerp) {
    final cx = s.width * 0.75;
    final cy = s.height * 0.18;
    for (int i = 5; i >= 1; i--) {
      final r = s.width * 0.08 * i;
      final op = (0.04 - i * 0.005).clamp(0.0, 0.10);
      canvas.drawCircle(
          Offset(cx, cy),
          r,
          Paint()
            ..color =
                const Color(0xFFFFD54F).withValues(alpha: op + lerp * 0.02));
    }
    final rayPaint = Paint()
      ..color = const Color(0xFFFFD54F).withValues(alpha: 0.06 + lerp * 0.03)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 12; i++) {
      final angle = i * math.pi / 6 + lerp * 0.2;
      final r1 = s.width * 0.08;
      final r2 = s.width * 0.32;
      canvas.drawLine(
        Offset(cx + math.cos(angle) * r1, cy + math.sin(angle) * r1),
        Offset(cx + math.cos(angle) * r2, cy + math.sin(angle) * r2),
        rayPaint,
      );
    }
  }

  void _pintarFundoChuva(Canvas canvas, Size s) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.5),
          radius: 1.2,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.30)],
        ).createShader(Rect.fromLTWH(0, 0, s.width, s.height)),
    );
  }

  void _pintarFundoNublado(Canvas canvas, Size s, double lerp) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()..color = Colors.white.withValues(alpha: 0.04 + lerp * 0.03),
    );
  }

  @override
  bool shouldRepaint(_FundoClimaticoPainter old) =>
      old.anim != anim || old.theme.tipo != theme.tipo;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Painter: partículas ambiente
// ═══════════════════════════════════════════════════════════════════════════
class _ParticulasPainter extends CustomPainter {
  final List<_Particula> particulas;
  final Animation<double> anim;
  final _ClimaTheme theme;

  _ParticulasPainter({
    required this.particulas,
    required this.anim,
    required this.theme,
  }) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size s) {
    final t = anim.value;
    final p = Paint()..style = PaintingStyle.fill;

    for (final pt in particulas) {
      double x, y;

      if (theme.tipo == _TipoTempo.chuva) {
        x = pt.x * s.width +
            math.sin(t * math.pi * 2 * pt.speed + pt.phase) * 6;
        y = ((pt.y + t * pt.speed * 0.8) % 1.0) * s.height;
        p.color = const Color(0xFF90CAF9).withValues(alpha: pt.opacity * 0.6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, y), width: 1.5, height: pt.size * 2.5),
            const Radius.circular(2),
          ),
          p,
        );
      } else if (theme.tipo == _TipoTempo.nublado) {
        x = ((pt.x + t * pt.speed * 0.15) % 1.0) * s.width;
        y = pt.y * s.height * 0.6;
        p.color = Colors.white.withValues(alpha: pt.opacity * 0.25);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, y), width: pt.size * 12, height: pt.size * 2),
            Radius.circular(pt.size),
          ),
          p,
        );
      } else {
        x = pt.x * s.width +
            math.sin(t * math.pi * 2 * pt.speed * 0.3 + pt.phase) *
                s.width *
                0.015;
        y = pt.y * s.height * 0.7;
        final pulso = (math.sin(t * math.pi * 4 * pt.speed + pt.phase) + 1) / 2;
        p.color =
            const Color(0xFFFFECB3).withValues(alpha: pt.opacity * 0.5 * pulso);
        canvas.drawCircle(Offset(x, y), pt.size * 0.8, p);
      }
    }
  }

  @override
  bool shouldRepaint(_ParticulasPainter old) =>
      old.anim != anim || old.theme.tipo != theme.tipo;
}

class _Particula {
  final double x, y, size, speed, phase, opacity;
  const _Particula({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.opacity,
  });
}
