import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'design/tema.dart';
import 'info_hub.dart';
import 'responsive.dart';
import 'services/fotos_service.dart';
import 'services/assistente_service.dart';
import 'services/jarvis_service.dart';
import 'services/news_service.dart';
import 'services/resumo_service.dart';
import 'services/voz_service.dart';
import 'services/weather_service.dart';
import 'util.dart';
import 'widgets/camada_assistente.dart' show OrbeJarvis;
import 'design/aurora.dart';
import 'design/icones.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  TelaBomDia — saudação, clima do dia, foto do dia, notícia e frase.
//  Aparece só na janela de horário configurada (o rodízio filtra).
// ═══════════════════════════════════════════════════════════════════════════
class TelaBomDia extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaBomDia({super.key, required this.aoTerminar});

  /// Pedido de briefing falado ao abrir: o painel viu alguém pela primeira
  /// vez na manhã (câmera, toque ou "Hey Jarvis") e abriu esta tela.
  static bool falarAoAbrir = false;

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
  late AnimationController _entradaCtrl; // fade-in de entrada
  late Animation<double> _entradaAnim;


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
    final base = _cfg.getString('bom_dia', 'fonte', 'bricolage');
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
      case 'poppins':
        return GoogleFonts.poppins(textStyle: estilo);
      default:
        return GoogleFonts.bricolageGrotesque(textStyle: estilo);
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

    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _entradaAnim =
        CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOutCubic);

    _entradaCtrl.forward();
    _carregarDados();
    _antiTravamento = Timer(const Duration(minutes: 5), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _entradaCtrl.dispose();
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
    // O texto do Jarvis chega depois (a IA leva alguns segundos); a fala
    // espera por ele.
    await _carregarBriefing();
    if (!mounted) return;
    setState(() {});
    _falarResumoSeConfigurado();
  }

  List<ItemResumo> _resumo = [];

  /// Briefing escrito pelo Jarvis (IA), guardado por 3 h para não gastar a
  /// cota a cada passagem da tela. null = sem IA: mostra a lista do resumo.
  String? _briefing;
  bool _falando = false;

  Future<void> _carregarBriefing() async {
    final hoje = DateTime.now();
    final chave = 'briefing_${hoje.year}_${hoje.month}_${hoje.day}_${hoje.hour ~/ 3}';
    final salvo = await CacheManager.instance.obterEntrada<String>(chave);
    if (salvo != null) {
      _briefing = salvo.dados;
      return;
    }
    final texto = await JarvisService.instance
        .briefing(_saudacao)
        .timeout(const Duration(seconds: 30), onTimeout: () => null);
    if (texto != null && texto.isNotEmpty) {
      _briefing = texto;
      await CacheManager.instance.salvar(chave, texto);
    }
  }

  /// Fala o briefing uma vez por manhã: quando o painel viu alguém (câmera,
  /// toque, "Hey Jarvis") ou, com a opção ligada, ao abrir a tela.
  Future<void> _falarResumoSeConfigurado() async {
    final pedido = TelaBomDia.falarAoAbrir;
    TelaBomDia.falarAoAbrir = false;
    if (!pedido && !_cfg.getBool('bom_dia', 'falar_resumo', false)) return;
    final hoje = DateTime.now();
    final chave = 'bom_dia_falado_${hoje.year}_${hoje.month}_${hoje.day}';
    if (await CacheManager.instance.obterEntrada<bool>(chave) != null) return;
    await CacheManager.instance.salvar(chave, true);
    final nome = _nomeUsuario;
    final texto = _briefing ??
        ResumoService.instance
            .paraFalar(nome.isEmpty ? _saudacao : '$_saudacao, $nome', _resumo);
    if (!mounted) return;
    _saidaTimer?.cancel(); // não sai da tela no meio da fala
    setState(() => _falando = true);
    await VozService.instance.falar(texto.replaceAll('°', ' graus'));
    if (!mounted) return;
    setState(() => _falando = false);
    _iniciarSaida();
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

    // O fundo é o céu do app (com a aurora) — sem bolinhas, partículas nem
    // riscos desenhados: só uma base escura leve para a leitura.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.38),
                  ],
                  stops: const [0.0, 0.6, 1.0],
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
  //  ┌───────────────────────────────────┬────────────────────┐
  //  │ Bom dia, Gabriel                   │                    │
  //  │ domingo, 4 de outubro · 08:41      │    foto do dia     │
  //  │ (ícone) 20°  hoje 18° a 27°        │                    │
  //  │                                    ├────────────────────┤
  //  │ ◉ JARVIS                           │ notícia (compacta) │
  //  │ "Bom dia, Gabriel. Hoje..."        │                    │
  //  └───────────────────────────────────┴────────────────────┘
  //  frase do dia
  Widget _buildConteudo(R r, _ClimaTheme theme, BoxConstraints constraints) {
    final t = Tipo(r);
    final temFoto = _mostrarFoto && _fotoDoDia != null;
    final temLateral = temFoto || _mostrarNoticia;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.sp(48), r.sp(36), r.sp(40), r.sp(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAbertura(r, theme),
                      SizedBox(height: r.sp(36)),
                      Expanded(child: _buildBriefing(r, theme)),
                    ],
                  ),
                ),
                if (temLateral) ...[
                  SizedBox(width: r.sp(40)),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (temFoto) Expanded(flex: 3, child: _buildFotoDoDiaCard(r, theme)),
                        if (temFoto && _mostrarNoticia) SizedBox(height: r.sp(20)),
                        if (_mostrarNoticia)
                          SizedBox(height: r.sp(150), child: _buildNoticiaCard(r, theme)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_mostrarFrase) ...[
            SizedBox(height: r.sp(18)),
            Text(_frase,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.apoio(cor: Cores.textoApagado).copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  /// Saudação, data/hora e o clima de agora — o que se lê de longe.
  Widget _buildAbertura(R r, _ClimaTheme theme) {
    final t = Tipo(r);
    final nome = _nomeUsuario;
    final tamanho = r.fs(_tamanhoNome.clamp(28, 72) * 1.7);
    // Nome em degradê nas cores da aurora do horário (ou na cor escolhida
    // nas Configurações).
    final coresNome = _corDestaqueHex.isEmpty
        ? Aurora.paleta(periodoDaHora(DateTime.now().hour))
        : [_resolverCorDestaque(theme), _resolverCorDestaque(theme)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(nome.isEmpty ? _saudacao : '$_saudacao, ',
                  style: _fonteEstilo(
                      fontSize: tamanho, fontWeight: FontWeight.w300, height: 1.05)),
              if (nome.isNotEmpty)
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (b) => LinearGradient(
                    colors: [
                      Color.lerp(coresNome[0], Colors.white, 0.35)!,
                      Color.lerp(coresNome[1 % coresNome.length], Colors.white, 0.25)!,
                    ],
                  ).createShader(b),
                  child: Text(nome,
                      style: _fonteEstilo(
                          fontSize: tamanho, fontWeight: FontWeight.w700, height: 1.05)),
                ),
            ],
          ),
        ),
        SizedBox(height: r.sp(4)),
        ValueListenableBuilder<DateTime>(
          valueListenable: InfoHub.instance.relogio,
          builder: (context, agora, _) => Text(
            '${diaSemanaLongo(agora)}, ${agora.day} de ${mesesLongos[agora.month - 1]}  ·  ${horaMinuto(agora)}',
            style: t.corpo(cor: Cores.textoSecundario),
          ),
        ),
        SizedBox(height: r.sp(26)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconeClima(codigo: _weatherCode, ehDia: _ehDia, tamanho: r.icon(96)),
            SizedBox(width: r.sp(14)),
            Text('$_tempAtual°',
                style: t.heroi().copyWith(
                    fontSize: r.fs((_tamanhoTemp / 72 * 104).clamp(72, 140)),
                    fontWeight: FontWeight.w300)),
            SizedBox(width: r.sp(28)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Hoje entre $_tempMin° e $_tempMax°', style: t.subtitulo()),
                if (_mostrarSensacao)
                  Text('Sensação de $_sensacao°', style: t.corpo(cor: Cores.textoSecundario)),
                if (_mostrarChuva && _probChuva >= 30)
                  Text('$_probChuva% de chance de chuva', style: t.corpo(cor: Cores.chuva)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// O briefing do Jarvis: o texto escrito pela IA (ou, sem IA, a lista do
  /// resumo). O orbe pequeno anima enquanto ele fala.
  Widget _buildBriefing(R r, _ClimaTheme theme) {
    final t = Tipo(r);
    final nomeAssistente = JarvisService.instance.nomeAssistente.toUpperCase();
    return Container(
      padding: EdgeInsets.fromLTRB(r.sp(26), r.sp(22), r.sp(26), r.sp(22)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r.sp(28)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            OrbeJarvis(
              estado: _falando ? EstadoAssistente.respondendo : EstadoAssistente.parado,
              tamanho: r.sp(46),
            ),
            SizedBox(width: r.sp(14)),
            Text(nomeAssistente,
                style: t
                    .legenda(cor: const Color(0xFF7FE3FF))
                    .copyWith(letterSpacing: 5, fontWeight: FontWeight.w800)),
            SizedBox(width: r.sp(12)),
            Text(_falando ? 'falando' : 'seu dia', style: t.legenda()),
          ]),
          SizedBox(height: r.sp(16)),
          Expanded(
            child: _briefing != null
                ? Text(
                    _briefing!,
                    style: t.corpo().copyWith(height: 1.45),
                    overflow: TextOverflow.fade,
                  )
                : _resumo.isEmpty
                    ? Text('Dia livre: nenhum compromisso, jogo ou lembrete.',
                        style: t.corpo(cor: Cores.textoSecundario))
                    : ListView(
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (final i in _resumo)
                            Padding(
                              padding: EdgeInsets.only(bottom: r.sp(14)),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(i.icone, color: i.cor, size: r.icon(28)),
                                  SizedBox(width: r.sp(16)),
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
              padding: EdgeInsets.fromLTRB(r.sp(20), r.sp(40), r.sp(20), r.sp(16)),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB3000000)],
                ),
              ),
              child: Row(children: [
                Icon(Icons.auto_awesome_rounded, color: theme.corDestaque, size: r.icon(22)),
                SizedBox(width: r.sp(10)),
                Text('Recordação do dia', style: t.corpo(peso: FontWeight.w600)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Notícia do dia, compacta: miniatura + manchete (toque para ler).
  Widget _buildNoticiaCard(R r, _ClimaTheme theme) {
    final t = Tipo(r);
    final n = _noticia;
    return GestureDetector(
      onTap: _abrirNoticia,
      child: Container(
        padding: EdgeInsets.all(r.sp(14)),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(r.sp(24)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (n != null && n.imagem.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(r.sp(16)),
                child: AspectRatio(
                  aspectRatio: 1.2,
                  child: CachedNetworkImage(
                    imageUrl: n.imagem,
                    fit: BoxFit.cover,
                    memCacheWidth: 400,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
              SizedBox(width: r.sp(16)),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('NOTÍCIA DO DIA',
                      style: t.legenda().copyWith(letterSpacing: 2, fontWeight: FontWeight.w700)),
                  SizedBox(height: r.sp(6)),
                  Text(
                    n?.titulo ?? 'Sem conexão com as notícias agora.',
                    style: t.corpo(peso: FontWeight.w700),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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

