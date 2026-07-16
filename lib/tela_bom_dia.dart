import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io';
import 'config_manager.dart';
import 'cache_manager.dart';
import 'responsive.dart';
import 'performance_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  TelaBomDia v4 — Visual, dinâmico, inspirador, com Foto do Dia
// ═══════════════════════════════════════════════════════════════════════════
class TelaBomDia extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaBomDia({super.key, required this.aoTerminar});

  @override
  State<TelaBomDia> createState() => _TelaBomDiaState();
}

class _TelaBomDiaState extends State<TelaBomDia> with TickerProviderStateMixin {
  final _cfg = ConfigManager();

  // ── Dados clima ───────────────────────────────────────────────────────────
  int _tempAtual = 22;
  int _tempMax = 26;
  int _tempMin = 16;
  int _sensacao = 21;
  int _probChuva = 0;
  int _weatherCode = 0;
  String _frase = '';
  String _noticiaTitle = '';
  String _noticiaDesc = '';
  String _noticiaImg = '';
  String? _fotoDoDia;
  bool _carregando = true;
  bool _foraDoHorario = false;

  Timer? _saidaTimer;

  // ── Controllers ───────────────────────────────────────────────────────────
  late AnimationController _bgCtrl; // fundo animado infinito
  late AnimationController _entradaCtrl; // fade-in de entrada
  late AnimationController _iconCtrl; // oscilação do ícone de clima
  late AnimationController _pulseCtrl; // pulse no nome
  late AnimationController _floatCtrl; // partículas flutuantes
  late Animation<double> _entradaAnim;
  late Animation<double> _iconFloat;
  late Animation<double> _pulseAnim;

  final List<_Particula> _particulas = [];

  // ── Config ────────────────────────────────────────────────────────────────
  String get _nomeUsuario => _cfg.getString('geral', 'nome_usuario', 'Gabriel');
  String get _lat => _cfg.getString('clima', 'lat', '-22.889');
  String get _lon => _cfg.getString('clima', 'lon', '-47.222');
  int get _horaInicio => _cfg.getInt('bom_dia', 'hora_inicio', 4);
  int get _horaFim => _cfg.getInt('bom_dia', 'hora_fim', 10);
  int get _duracaoLongo => _cfg.getInt('bom_dia', 'duracao_longa_seg', 90);
  int get _duracaoCurto => _cfg.getInt('bom_dia', 'duracao_curta_seg', 20);

  // ── Personalização visual ───────────────────────────────────────────────
  double get _tamanhoNome =>
      double.tryParse(_cfg.getString('bom_dia', 'tamanho_nome', '40.0')) ??
      40.0;
  double get _tamanhoTemp =>
      double.tryParse(_cfg.getString('bom_dia', 'tamanho_temp', '72.0')) ??
      72.0;
  String get _fonteEscolha => _cfg.getString('bom_dia', 'fonte', 'poppins');
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
    switch (base) {
      case 'rajdhani':
        return GoogleFonts.rajdhani(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            fontStyle: fontStyle,
            shadows: shadows);
      case 'orbitron':
        return GoogleFonts.orbitron(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            fontStyle: fontStyle,
            shadows: shadows);
      case 'roboto':
        return GoogleFonts.roboto(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            fontStyle: fontStyle,
            shadows: shadows);
      case 'exo2':
        return GoogleFonts.exo2(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            fontStyle: fontStyle,
            shadows: shadows);
      default:
        return GoogleFonts.poppins(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            fontStyle: fontStyle,
            shadows: shadows);
    }
  }

  // ── Cor de destaque: usa config ou fallback do tema ──────────────────────
  Color _resolverCorDestaque(_ClimaTheme theme) {
    final hex = _corDestaqueHex;
    if (hex.isEmpty) return theme.corDestaque;
    try {
      return Color(int.parse(hex));
    } catch (_) {
      return theme.corDestaque;
    }
  }

  // ── Clima: paleta e ícone baseados no código ──────────────────────────────
  _ClimaTheme get _climaTheme => _ClimaTheme.fromCode(_weatherCode, _probChuva);

  // ── Data e hora — calculadas sob demanda, sem Timer próprio ─────────────
  // A tela já é reconstruída a cada frame por causa das animações de fundo
  // (_bgCtrl/_floatCtrl), então ler DateTime.now() aqui já é suficiente para
  // o relógio "andar" sozinho, sem custo extra de performance.
  static const _diasSemana = [
    'segunda-feira',
    'terça-feira',
    'quarta-feira',
    'quinta-feira',
    'sexta-feira',
    'sábado',
    'domingo',
  ];

  static const _mesesAbrev = [
    'JAN',
    'FEV',
    'MAR',
    'ABR',
    'MAI',
    'JUN',
    'JUL',
    'AGO',
    'SET',
    'OUT',
    'NOV',
    'DEZ',
  ];

  String get _horaFormatada {
    final agora = DateTime.now();
    final h = agora.hour.toString().padLeft(2, '0');
    final m = agora.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _dataNumerica {
    final agora = DateTime.now();
    final d = agora.day.toString().padLeft(2, '0');
    final mes = _mesesAbrev[agora.month - 1];
    return '$d $mes';
  }

  String get _anoFormatado => '${DateTime.now().year}';

  String get _diaSemanaFormatado {
    final agora = DateTime.now();
    final nome = _diasSemana[agora.weekday - 1];
    return nome[0].toUpperCase() + nome.substring(1);
  }

  @override
  void initState() {
    super.initState();

    // Inicializa controllers ANTES de qualquer verificação
    _bgCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 12));
    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _iconCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _floatCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 18));

    // Fundo, ícone, pulso e partículas são puramente decorativos — só
    // rodam em loop contínuo no modo visual completo. _entradaCtrl (fade-in
    // de entrada) não entra aqui: ele dispara uma vez só, custa muito pouco.
    if (!PerformanceManager.instance.modoEconomico) {
      _bgCtrl.repeat(reverse: true);
      _iconCtrl.repeat(reverse: true);
      _pulseCtrl.repeat(reverse: true);
      _floatCtrl.repeat();
    }

    _entradaAnim =
        CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOutCubic);
    _iconFloat = Tween<double>(begin: -8.0, end: 8.0)
        .animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.easeInOut));
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.03)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Partículas: sol=estrelas, chuva=gotas, nublado=cirros
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

    // Verifica horário
    final hora = DateTime.now().hour;
    if (hora < _horaInicio || hora >= _horaFim) {
      _foraDoHorario = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.aoTerminar();
      });
      return;
    }

    _entradaCtrl.forward();
    _carregarDados();
    Timer(const Duration(minutes: 3), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _entradaCtrl.dispose();
    _iconCtrl.dispose();
    _pulseCtrl.dispose();
    _floatCtrl.dispose();
    _saidaTimer?.cancel();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    await Future.wait([
      _buscarClima(),
      _buscarFrase(),
      _buscarNoticia(),
      _carregarFotoDoDia(),
    ]);
    if (mounted) {
      setState(() => _carregando = false);
      _iniciarSaida();
    }
  }

  // ── Clima: tenta cache antes de ir à internet (válido por 20min) ─────────
  Future<void> _buscarClima() async {
    const chave = 'bom_dia_clima';

    // 1. Tenta usar dados em cache, se ainda válidos
    final cache = await CacheManager.instance
        .obter<Map<String, dynamic>>(chave, validade: CacheValidade.climaAtual);
    if (cache != null) {
      _aplicarDadosClima(cache);
      return; // não bate na internet — já está pronto
    }

    // 2. Cache vazio ou expirado: busca de fato
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_lat&longitude=$_lon'
        '&current=temperature_2m,apparent_temperature,weather_code'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max'
        '&timezone=America%2FSao_Paulo',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        _aplicarDadosClima(d);
        await CacheManager.instance.salvar(chave, d); // salva pra próxima vez
      }
    } catch (_) {}
  }

  void _aplicarDadosClima(Map<String, dynamic> d) {
    if (!mounted) return;
    setState(() {
      _tempAtual = (d['current']['temperature_2m'] as num?)?.round() ?? 22;
      _sensacao = (d['current']['apparent_temperature'] as num?)?.round() ?? 21;
      _weatherCode = (d['current']['weather_code'] as int?) ?? 0;
      _tempMax = (d['daily']['temperature_2m_max'][0] as num?)?.round() ?? 26;
      _tempMin = (d['daily']['temperature_2m_min'][0] as num?)?.round() ?? 16;
      _probChuva =
          (d['daily']['precipitation_probability_max'][0] as num?)?.toInt() ??
              0;
    });
  }

  // ── Frase do dia: banco curado em português, sem depender de API externa
  // que só retorna em inglês (ZenQuotes não tem opção de idioma). Chave
  // inclui a data para trocar sozinha à meia-noite (mesmo fix da foto).
  Future<void> _buscarFrase() async {
    final hoje = DateTime.now();
    final chave = 'bom_dia_frase_${hoje.year}_${hoje.month}_${hoje.day}';

    final cache = await CacheManager.instance
        .obter<String>(chave, validade: const Duration(hours: 25));
    if (cache != null && cache.isNotEmpty) {
      if (mounted) setState(() => _frase = cache);
      return;
    }

    const frasesPtBr = [
      '"Comece cada dia com um sorriso e termine com alegria." — Anônimo',
      '"O segredo é começar. Isso é tudo." — Mark Twain',
      '"Cada amanhecer é uma nova oportunidade de mudar sua vida." — Anônimo',
      '"Acredite que você pode — e você já está na metade do caminho." — Theodore Roosevelt',
      '"Só se pode alcançar um grande êxito quando nos mantemos fiéis a nós mesmos." — Friedrich Nietzsche',
      '"A persistência é o caminho do êxito." — Charles Chaplin',
      '"Não é o quanto fazemos, mas quanto amor colocamos no que fazemos." — Madre Teresa de Calcutá',
      '"O otimista vê a oportunidade em toda dificuldade." — Winston Churchill',
      '"Tudo o que um sonho precisa para ser realizado é alguém que acredite que ele possa ser realizado." — Roberto Shinyashiki',
      '"Que os vossos esforços desafiem as impossibilidades, lembrai-vos de que as grandes coisas do homem foram conquistadas do que parecia impossível." — Charles Chaplin',
      '"A vida é a arte do encontro, embora haja tanto desencontro pela vida." — Vinícius de Moraes',
      '"Feliz aquele que transfere o que sabe e aprende o que ensina." — Cora Coralina',
      '"Não sei se a vida é curta ou longa para nós, mas sei que nada do que vivemos tem sentido, se não tocarmos o coração das pessoas." — Cora Coralina',
      '"Que darei eu, ó Senhor, em troca de tantos bens que me haveis dado?" — Santa Teresa de Ávila',
      '"O que vale na vida não é o ponto de partida e sim a caminhada." — Cora Coralina',
      '"Bom mesmo é ir à luta com determinação, abraçar a vida com paixão, perder com classe e vencer com ousadia." — Charles Chaplin',
      '"Não temos mais tempo de sermos os mesmos." — Paulo Freire',
      '"Toda a nossa ciência, comparada com a realidade, é primitiva e infantil — e, no entanto, é a coisa mais preciosa que temos." — Albert Einstein',
      '"Que os dias difíceis te ensinem, e os bons te façam grato." — Anônimo',
      '"Comece fazendo o que é necessário, depois o que é possível, e de repente você estará fazendo o impossível." — São Francisco de Assis',
    ];
    final idx = hoje.difference(DateTime(hoje.year)).inDays % frasesPtBr.length;
    final frase = frasesPtBr[idx];
    if (mounted) setState(() => _frase = frase);
    await CacheManager.instance.salvar(chave, frase);
  }

  // ── Notícia: cache válido por 1h — texto e imagem juntos no mesmo pacote ──
  Future<void> _buscarNoticia() async {
    const chave = 'bom_dia_noticia';

    final cache = await CacheManager.instance
        .obter<Map<String, dynamic>>(chave, validade: CacheValidade.noticias);
    if (cache != null) {
      if (mounted) {
        setState(() {
          _noticiaTitle = cache['title'] ?? '';
          _noticiaDesc = cache['desc'] ?? '';
          _noticiaImg = cache['img'] ?? '';
        });
      }
      return; // já tem notícia fresca — não bate no RSS de novo
    }

    const feeds = [
      'https://g1.globo.com/rss/g1/',
      'https://g1.globo.com/rss/g1/politica/',
      'https://g1.globo.com/rss/g1/economia/',
    ];
    for (final feedUrl in feeds) {
      try {
        final res = await http
            .get(Uri.parse(feedUrl))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final doc = XmlDocument.parse(utf8.decode(res.bodyBytes));
          final itens = doc.findAllElements('item');
          if (itens.isNotEmpty) {
            final node = itens.first;
            final descRaw = node.findElements('description').first.innerText;
            final img =
                RegExp(r'src="([^"]+)"').firstMatch(descRaw)?.group(1) ?? '';
            final desc =
                descRaw.replaceAll(RegExp(r'<[^>]*>|&nbsp;'), '').trim();
            final title = node.findElements('title').first.innerText.trim();
            // O RSS do G1 às vezes traz só a categoria (ex: "Idosos") como
            // descrição — texto curto demais para ser um resumo de verdade.
            // Nesse caso, ignoramos e deixamos o card mostrar o fallback.
            final descUtil = desc.length >= 40 ? desc : '';
            final descCortada = descUtil.length > 160
                ? '${descUtil.substring(0, 157)}...'
                : descUtil;

            if (mounted) {
              setState(() {
                _noticiaTitle = title;
                _noticiaImg = img;
                _noticiaDesc = descCortada;
              });
            }
            // Salva o pacote completo — próxima troca de tela usa isso direto
            await CacheManager.instance.salvar(chave, {
              'title': title,
              'desc': descCortada,
              'img': img,
            });
            return; // sucesso — interrompe o loop de feeds
          }
        }
      } catch (e) {
        debugPrint('TelaBomDia notícia ($feedUrl): $e');
      }
    }
    // Todos os feeds falharam
    if (mounted) {
      setState(() {
        _noticiaTitle = 'Sem conexão com as notícias';
        _noticiaDesc =
            'Verifique sua internet para ver a notícia principal do dia.';
      });
    }
  }

  // ── Foto do Dia: chave inclui a data, então vira sozinha à meia-noite ────
  // (Bug corrigido: antes a validade era "24h após salvar", então se você
  // visse a foto ontem às 8h, ela só trocava hoje às 8h — não na virada do
  // dia. Agora a chave do cache muda automaticamente todo dia civil.)
  Future<void> _carregarFotoDoDia() async {
    final hoje = DateTime.now();
    final chave = 'bom_dia_foto_${hoje.year}_${hoje.month}_${hoje.day}';

    final cache = await CacheManager.instance
        .obter<String>(chave, validade: const Duration(hours: 25));
    if (cache != null && cache.isNotEmpty && await File(cache).exists()) {
      if (mounted) setState(() => _fotoDoDia = cache);
      return; // já sabemos qual é a foto de hoje — não relista a pasta
    }

    try {
      final diretorio = Directory('/storage/emulated/0/Pictures/MlionDroid');
      if (!await diretorio.exists()) return;

      final arquivos = diretorio.listSync();
      final caminhos = arquivos
          .where((item) =>
              item.path.toLowerCase().endsWith('.jpg') ||
              item.path.toLowerCase().endsWith('.png') ||
              item.path.toLowerCase().endsWith('.jpeg'))
          .map((item) => item.path)
          .toList();

      if (caminhos.isEmpty) return;

      // Dia do ano garante uma foto diferente por dia, ciclando pela pasta
      final diaDoAno = hoje.difference(DateTime(hoje.year)).inDays;
      final idx = diaDoAno % caminhos.length;
      final escolhida = caminhos[idx];

      if (mounted) setState(() => _fotoDoDia = escolhida);
      await CacheManager.instance.salvar(chave, escolhida);
    } catch (e) {
      debugPrint('TelaBomDia foto do dia: $e');
    }
  }

  void _iniciarSaida() {
    final h = DateTime.now().hour;
    final seg = h < (_horaInicio + (_horaFim - _horaInicio) ~/ 2)
        ? _duracaoLongo
        : _duracaoCurto;
    _saidaTimer?.cancel();
    _saidaTimer = Timer(Duration(seconds: seg), () {
      if (mounted) widget.aoTerminar();
    });
  }

  String get _saudacao {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_foraDoHorario) return const SizedBox.shrink();
    final r = R(context);
    final theme = _climaTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: Listenable.merge([_bgCtrl, _floatCtrl]),
        builder: (context, _) {
          return Stack(
            children: [
              // ── Fundo dinâmico ─────────────────────────────────────────
              Positioned.fill(
                child: CustomPaint(
                  painter:
                      _FundoClimaticoPainter(t: _bgCtrl.value, theme: theme),
                ),
              ),

              // ── Partículas (estrelas, gotas, nuvens) ───────────────────
              Positioned.fill(
                child: CustomPaint(
                  painter: _ParticulasPainter(
                    particulas: _particulas,
                    t: _floatCtrl.value,
                    theme: theme,
                    weatherCode: _weatherCode,
                  ),
                ),
              ),

              // ── Gradiente de legibilidade (base) ───────────────────────
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

              // ── Conteúdo ───────────────────────────────────────────────
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
          );
        },
      ),
    );
  }

  Widget _buildCarregando(R r, _ClimaTheme theme) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Opacity(
          opacity: 0.5 + _pulseCtrl.value * 0.5,
          child: Text(theme.emoji, style: TextStyle(fontSize: r.fs(72))),
        ),
      ),
    );
  }

  // ── Layout principal — proporcional à altura real disponível ─────────────
  Widget _buildConteudo(R r, _ClimaTheme theme, BoxConstraints constraints) {
    final sw = constraints.maxWidth;
    final sh = constraints.maxHeight;
    final temFoto = _mostrarFoto && _fotoDoDia != null;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sw * 0.04,
        vertical: sh * 0.02,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── 1. Topo: Data (esq) | Saudação (centro) | Relógio (dir) ────
          _buildTopoInfo(r, theme, sh, sw),

          SizedBox(height: sh * 0.015),

          // ── 2. Linha principal: Clima | Foto do Dia ─────────────────────
          Expanded(
            flex: 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: temFoto ? 56 : 100,
                  child: _buildClimaDestaque(r, theme, sh),
                ),
                if (temFoto) ...[
                  SizedBox(width: sw * 0.025),
                  Expanded(flex: 44, child: _buildFotoDoDiaCard(r, theme)),
                ],
              ],
            ),
          ),

          SizedBox(height: sh * 0.018),

          // ── 3. Notícia do dia (largura total, com imagem) ──────────────
          if (_mostrarNoticia)
            Expanded(
              flex: 34,
              child: _buildNoticiaCard(r, theme),
            ),

          // ── 4. Frase do dia — rodapé discreto, sempre visível ──────────
          if (_mostrarFrase) ...[
            SizedBox(height: sh * 0.012),
            _buildFraseRodape(r, theme, sw),
          ],
        ],
      ),
    );
  }

  // ── Topo: Data | Saudação | Relógio ───────────────────────────────────────
  // Saudação fica no centro como protagonista (maior, com pulse e glow).
  // Data e relógio são elementos de apoio, menores e discretos, um em cada
  // canto — dão a informação sem competir visualmente com o "Bom dia, nome".
  Widget _buildTopoInfo(R r, _ClimaTheme theme, double sh, double sw) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 27,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildDataCard(r, theme, sh),
            ),
          ),
          Expanded(
            flex: 46,
            child: Center(child: _buildSaudacao(r, theme, sh)),
          ),
          Expanded(
            flex: 27,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildRelogioCard(r, theme, sh),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card de data — canto esquerdo: dia/mês/ano + dia da semana por extenso
  Widget _buildDataCard(R r, _ClimaTheme theme, double sh) {
    final fsData = math.min(r.fs(20), sh * 0.040);
    final fsAno = fsData * 0.55;
    final fsSemana = math.min(r.fs(12), sh * 0.024);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(14), vertical: r.sp(8)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Icon(Icons.calendar_today_rounded,
                  color: Colors.white.withValues(alpha: 0.55),
                  size: fsData * 0.6),
              SizedBox(width: r.sp(7)),
              Text(
                _dataNumerica,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: fsData,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
              SizedBox(width: r.sp(4)),
              Text(
                _anoFormatado,
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: fsAno,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: r.sp(2)),
          Text(
            _diaSemanaFormatado,
            style: GoogleFonts.poppins(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: fsSemana,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Card de relógio — canto direito: relógio digital grande e moderno ────
  Widget _buildRelogioCard(R r, _ClimaTheme theme, double sh) {
    final fsHora = math.min(r.fs(30), sh * 0.065);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(16), vertical: r.sp(8)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.corDestaque.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: r.sp(7),
            height: r.sp(7),
            margin: EdgeInsets.only(right: r.sp(9)),
            decoration: BoxDecoration(
              color: theme.corDestaque,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: theme.corDestaque.withValues(alpha: 0.65),
                    blurRadius: 8),
              ],
            ),
          ),
          Text(
            _horaFormatada,
            style: GoogleFonts.orbitron(
              color: Colors.white,
              fontSize: fsHora,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              shadows: [
                Shadow(
                    color: theme.corDestaque.withValues(alpha: 0.45),
                    blurRadius: 20),
                const Shadow(color: Colors.black54, blurRadius: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Saudação ──────────────────────────────────────────────────────────────
  Widget _buildSaudacao(R r, _ClimaTheme theme, double sh) {
    // Cor de destaque do nome: se a config não define uma cor fixa, NÃO usa
    // a cor do tema diretamente (ela pode ser clara/cinza no clima nublado,
    // se misturando com o fundo). Em vez disso, usa um dourado vibrante fixo
    // que sempre contrasta bem com qualquer fundo, e só a sombra usa a cor
    // do tema para manter a identidade visual.
    final corHexConfig = _corDestaqueHex;
    const corContrasteFixa = Color(0xFFFFD54F); // dourado — sempre se destaca
    final corNome = corHexConfig.isNotEmpty
        ? _resolverCorDestaque(theme)
        : corContrasteFixa;

    final fsNome = math.min(r.fs(_tamanhoNome), sh * 0.075);
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Transform.scale(
        scale: _pulseAnim.value,
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: r.sp(24), vertical: r.sp(10)),
          decoration: BoxDecoration(
            // Glow bem sutil — só o suficiente pra ajudar a leitura,
            // sem virar um "balão" escuro que chama atenção sozinho
            color: Colors.black.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(30),
          ),
          child: RichText(
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$_saudacao ',
                  style: _fonteEstilo(
                    fontSize: fsNome,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                          color: Colors.black.withValues(alpha: 0.75),
                          blurRadius: 16),
                      const Shadow(color: Colors.black, blurRadius: 4),
                    ],
                  ),
                ),
                TextSpan(
                  text: '$_nomeUsuario,',
                  style: _fonteEstilo(
                    fontSize: fsNome,
                    fontWeight: FontWeight.w800,
                    color: corNome,
                    shadows: [
                      Shadow(
                          color: corNome.withValues(alpha: 0.6),
                          blurRadius: 28),
                      Shadow(
                          color: Colors.black.withValues(alpha: 0.75),
                          blurRadius: 16),
                      const Shadow(color: Colors.black, blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Clima destaque — ícone+temp centralizados, máx/mín ao lado (vertical) ──
  Widget _buildClimaDestaque(R r, _ClimaTheme theme, double sh) {
    return LayoutBuilder(
      builder: (context, box) {
        final boxH = box.maxHeight;
        final boxW = box.maxWidth;

        final temRodape =
            _mostrarSensacao || (_mostrarChuva && _probChuva >= 30);
        // Rodapé fixo (sensação | chuva) — altura reservada ANTES de calcular
        // o tamanho do bloco principal, garantindo que nunca disputem espaço
        final alturaRodape = temRodape ? boxH * 0.20 : 0.0;
        final espacoVertical = boxH * 0.06;
        final alturaBlocoPrincipal = boxH - alturaRodape - espacoVertical;

        // Base de escala mais conservadora — evita que o ícone/temp fiquem
        // grandes demais e ultrapassem a altura disponível na vertical
        final base = math.min(alturaBlocoPrincipal * 0.92, boxW * 0.42);

        final fsIcone = base * 0.95;
        final fsTemp = base * 0.90;
        final fsGrau = fsTemp * 0.36;
        final fsMinMax = base * 0.28;
        final fsRodape = (alturaRodape * 0.26).clamp(10.0, 15.0);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.10), width: 1.5),
          ),
          padding: EdgeInsets.all(boxW * 0.04),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              // ── Bloco principal: ícone | temperatura | máx/mín ao lado ──
              // FittedBox como salvaguarda final: mesmo se as contas acima
              // calcularem algo um pouco grande para o espaço real, o
              // conteúdo encolhe proporcionalmente em vez de dar overflow.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _iconFloat,
                        builder: (_, __) => Transform.translate(
                          offset: Offset(0, _iconFloat.value * 1.3),
                          child: Text(
                            theme.emoji,
                            style: TextStyle(
                              fontSize: fsIcone,
                              shadows: [
                                Shadow(
                                    color: theme.corDestaque
                                        .withValues(alpha: 0.6),
                                    blurRadius: 50),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SizedBox(width: boxW * 0.02),

                      Text(
                        '$_tempAtual',
                        style: _fonteEstilo(
                          fontSize: fsTemp,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.0,
                          shadows: [
                            Shadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 24),
                            Shadow(
                                color: _resolverCorDestaque(theme)
                                    .withValues(alpha: 0.35),
                                blurRadius: 50),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: boxH * 0.008),
                        child: Text(
                          '°C',
                          style: GoogleFonts.poppins(
                            color: Colors.white.withValues(alpha: 0.70),
                            fontSize: fsGrau,
                            fontWeight: FontWeight.w300,
                            shadows: [
                              Shadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 14)
                            ],
                          ),
                        ),
                      ),

                      SizedBox(width: boxW * 0.03),

                      // Máx (cima) / Mín (baixo) — empilhados ao lado da temperatura
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _tempChipEscalado('↑', '$_tempMax°',
                              const Color(0xFFFF6B6B), fsMinMax),
                          SizedBox(height: boxH * 0.012),
                          _tempChipEscalado('↓', '$_tempMin°',
                              const Color(0xFF64B5F6), fsMinMax),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Rodapé fixo: sensação (esquerda) | chuva (direita) ──────
              if (temRodape)
                SizedBox(
                  height: alturaRodape,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Sensação térmica — canto esquerdo
                      if (_mostrarSensacao)
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            padding: EdgeInsets.symmetric(
                                horizontal: boxW * 0.03,
                                vertical: alturaRodape * 0.18),
                            margin: EdgeInsets.only(
                                right: (_mostrarChuva && _probChuva >= 30)
                                    ? boxW * 0.02
                                    : 0),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  width: 1),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.thermostat_rounded,
                                      color:
                                          Colors.white.withValues(alpha: 0.65),
                                      size: fsRodape * 1.1),
                                  SizedBox(width: boxW * 0.012),
                                  Text(
                                    'Sensação $_sensacao°C',
                                    style: GoogleFonts.poppins(
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                      fontSize: fsRodape,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Chuva — canto direito
                      if (_mostrarChuva && _probChuva >= 30)
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            padding: EdgeInsets.symmetric(
                                horizontal: boxW * 0.03,
                                vertical: alturaRodape * 0.18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0)
                                  .withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                  color: const Color(0xFF64B5F6)
                                      .withValues(alpha: 0.50)),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('🌧',
                                      style:
                                          TextStyle(fontSize: fsRodape * 1.05)),
                                  SizedBox(width: boxW * 0.012),
                                  Text(
                                    '$_probChuva% de chuva',
                                    style: GoogleFonts.poppins(
                                      color: const Color(0xFF90CAF9),
                                      fontSize: fsRodape,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tempChipEscalado(String seta, String val, Color cor, double fs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(seta,
            style: TextStyle(
                color: cor,
                fontSize: fs,
                fontWeight: FontWeight.w900,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 8)])),
        SizedBox(width: fs * 0.18),
        Text(val,
            style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: fs,
                fontWeight: FontWeight.w700,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 8)])),
      ],
    );
  }

  // ── Foto do Dia — card novo, estilo "recordação" ──────────────────────────
  Widget _buildFotoDoDiaCard(R r, _ClimaTheme theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Foto
          Image.file(
            File(_fotoDoDia!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.white.withValues(alpha: 0.05),
              child: Icon(Icons.image_rounded,
                  color: Colors.white24, size: r.icon(40)),
            ),
          ),
          // Gradiente de legibilidade do label
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
          ),
          // Borda sutil
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18), width: 1.5),
              ),
            ),
          ),
          // Label
          Positioned(
            left: r.sp(14),
            bottom: r.sp(12),
            right: r.sp(14),
            child: Row(
              children: [
                Icon(Icons.auto_awesome,
                    color: theme.corDestaque, size: r.icon(15)),
                SizedBox(width: r.sp(6)),
                Text(
                  'Recordação do dia',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: r.fs(12),
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 6)
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

  // ── Notícia — com imagem ao lado, igual a TelaBrasil ──────────────────────
  Widget _buildNoticiaCard(R r, _ClimaTheme theme) {
    final temImagem = _noticiaImg.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: PerformanceManager.instance.sigmaBlur(4),
          sigmaY: PerformanceManager.instance.sigmaBlur(4),
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.15), width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Imagem da notícia (se disponível)
              if (temImagem)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(22)),
                  child: SizedBox(
                    width: r.w(0.20),
                    child: CachedNetworkImage(
                      imageUrl: _noticiaImg,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          color: Colors.white.withValues(alpha: 0.05)),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.white.withValues(alpha: 0.05),
                        child: Icon(Icons.article_rounded,
                            color: Colors.white24, size: r.icon(30)),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: r.sp(56),
                  margin: EdgeInsets.all(r.sp(16)),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.newspaper_rounded,
                      color: Colors.white, size: r.icon(22)),
                ),

              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: r.sp(18), vertical: r.sp(14)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: r.sp(9), vertical: r.sp(3)),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0)
                                  .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFF64B5F6)
                                      .withValues(alpha: 0.45)),
                            ),
                            child: Text('PRINCIPAL NOTÍCIA',
                                style: GoogleFonts.poppins(
                                    color: const Color(0xFF90CAF9),
                                    fontSize: r.fs(10),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1)),
                          ),
                          const Spacer(),
                          Icon(Icons.rss_feed_rounded,
                              color: Colors.white.withValues(alpha: 0.30),
                              size: r.icon(11)),
                          SizedBox(width: r.sp(4)),
                          Text('Fonte: G1',
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.40),
                                  fontSize: r.fs(11),
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                      SizedBox(height: r.sp(8)),
                      Text(
                        _noticiaTitle.isEmpty
                            ? 'Carregando notícias...'
                            : _noticiaTitle,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: r.fs(17),
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 8)
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: r.sp(6)),
                      Text(
                        _noticiaDesc.isNotEmpty
                            ? _noticiaDesc
                            : (_noticiaTitle.isEmpty
                                ? 'Buscando as principais notícias do dia...'
                                : 'Toque para saber mais sobre essa notícia no G1.'),
                        style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: r.fs(13),
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Frase do dia — rodapé discreto, marquee se necessário ─────────────────
  Widget _buildFraseRodape(R r, _ClimaTheme theme, double sw) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: r.sp(18), vertical: r.sp(10)),
      decoration: BoxDecoration(
        color: theme.corDestaque.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.corDestaque.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        children: [
          Text('✨', style: TextStyle(fontSize: r.fs(14))),
          SizedBox(width: r.sp(10)),
          Expanded(
            child: Text(
              _frase.isEmpty
                  ? '"Cada amanhecer é uma nova chance de ser melhor." — Anônimo'
                  : _frase,
              style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: r.fs(13),
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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

  factory _ClimaTheme.fromCode(int code, int probChuva) {
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

enum _TipoTempo { sol, solComNuvens, nublado, chuva }

// ═══════════════════════════════════════════════════════════════════════════
//  Painter: fundo dinâmico
// ═══════════════════════════════════════════════════════════════════════════
class _FundoClimaticoPainter extends CustomPainter {
  final double t;
  final _ClimaTheme theme;

  const _FundoClimaticoPainter({required this.t, required this.theme});

  @override
  void paint(Canvas canvas, Size s) {
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
    final cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10 * intensidade)
      ..style = PaintingStyle.fill;

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
    final x1 = ((t * 0.06) % 1.2 - 0.1) * s.width;
    final x2 = ((t * 0.04 + 0.4) % 1.2 - 0.1) * s.width;
    final x3 = ((t * 0.05 + 0.75) % 1.2 - 0.1) * s.width;

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
      old.t != t || old.theme.tipo != theme.tipo;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Painter: partículas ambiente
// ═══════════════════════════════════════════════════════════════════════════
class _ParticulasPainter extends CustomPainter {
  final List<_Particula> particulas;
  final double t;
  final _ClimaTheme theme;
  final int weatherCode;

  const _ParticulasPainter({
    required this.particulas,
    required this.t,
    required this.theme,
    required this.weatherCode,
  });

  @override
  void paint(Canvas canvas, Size s) {
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
  bool shouldRepaint(_ParticulasPainter old) => old.t != t;
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
