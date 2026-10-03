import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'cache_manager.dart';
import 'config_manager.dart';
import 'performance_manager.dart';
import 'responsive.dart';
import 'services/fotos_service.dart';
import 'services/google_auth_service.dart';
import 'services/weather_service.dart';
import 'tela_brasil.dart' show categoriasBrasil;
import 'tela_regiao.dart' show cidadesRegiao;
import 'tela_spotify.dart';
import 'times.dart';
import 'update_banner.dart';
import 'update_manager.dart';
import 'widgets/config_assistente.dart';

// ── Estados brasileiros (sigla → nome completo) ───────────────────────────
const Map<String, String> estadosBrasil = {
  'AC': 'Acre',
  'AL': 'Alagoas',
  'AP': 'Amapá',
  'AM': 'Amazonas',
  'BA': 'Bahia',
  'CE': 'Ceará',
  'DF': 'Distrito Federal',
  'ES': 'Espírito Santo',
  'GO': 'Goiás',
  'MA': 'Maranhão',
  'MT': 'Mato Grosso',
  'MS': 'Mato Grosso do Sul',
  'MG': 'Minas Gerais',
  'PA': 'Pará',
  'PB': 'Paraíba',
  'PR': 'Paraná',
  'PE': 'Pernambuco',
  'PI': 'Piauí',
  'RJ': 'Rio de Janeiro',
  'RN': 'Rio Grande do Norte',
  'RS': 'Rio Grande do Sul',
  'RO': 'Rondônia',
  'RR': 'Roraima',
  'SC': 'Santa Catarina',
  'SP': 'São Paulo',
  'SE': 'Sergipe',
  'TO': 'Tocantins',
};

class TelaConfig extends StatefulWidget {
  final VoidCallback aoSalvar;
  const TelaConfig({super.key, required this.aoSalvar});

  @override
  State<TelaConfig> createState() => _TelaConfigState();
}

class _TelaConfigState extends State<TelaConfig>
    with SingleTickerProviderStateMixin {
  final config = ConfigManager();
  String _categoriaAtual = 'sobre';
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  String _timeSelecionado = 'palmeiras';
  List<String> _cidadesSelecionadas = ['hortolandia'];
  List<String> _categoriasBrasilSelecionadas = [
    'politica',
    'economia',
    'tecnologia',
    'saude',
    'geral'
  ];
  bool _mostrarWebViewLogin = false;

  static const _bg = Color(0xFF080C14);
  static const _border = Color(0xFF1E2D45);
  static const _accent = Color(0xFF00D4FF);

  // ── Informações da tela "Sobre" ──────────────────────────────────────────
  // Edite os valores abaixo com suas informações reais. As imagens precisam
  // ser adicionadas nos assets do projeto (pubspec.yaml) nos caminhos abaixo.
  static const _sobreAppNome = 'MlionDroid Center';
  static const _sobreCriadorNome = 'Gabriel Oliveira';
  static const _sobreCriadorFoto = 'assets/sobre/criador.png';
  static const _sobreLogoCanal = 'assets/sobre/logo_canal.png';
  static const _sobreDescricaoApp =
      'O MlionDroid Center nasceu da mesma paixão por tecnologia e '
      'customização Android que move o canal MlionDroid: transformar um '
      'tablet parado em casa num painel inteligente e sempre ativo, com '
      'clima, notícias, compromissos, fotos e muito mais se revezando '
      'automaticamente na tela — pensado, construído e ajustado no dia a '
      'dia por quem realmente gosta de colocar a mão na massa no Android.';
  static const _sobreDescricaoCriador =
      'Gabriel é o criador do canal MlionDroid no YouTube, onde publica '
      'toda semana conteúdo sobre o universo Android: tutoriais de ROMs '
      'customizadas, root, TWRP, reviews, unboxings e as novidades do '
      'mundo Android e MIUI. Apaixonado por tecnologia, gosta de '
      'compartilhar conhecimento e ajudar quem também curte customizar '
      'os próprios aparelhos.';
  static const _sobreUrlCanal =
      'https://www.youtube.com/channel/UCccNy3asccoyN_rYo2rjkJg';
  static const _sobreLabelCanal = 'Visitar canal MlionDroid';

  // ── Seletor Estado/Cidade do Clima ────────────────────────────────────────
  final Map<String, List<String>> _municipiosCache = {};
  bool _geocodificando = false;
  String? _erroLocalizacao;

  final Map<String, String> _categoriaLabels = {
    'sobre': 'ℹ️ Sobre',
    'atualizacoes': '🔄 Atualizações',
    'geral': '⚙️ Geral',
    'assistente': '🤖 Assistente (Jarvis)',
    'time': '⚽ Time & Futebol',
    'clima': '🌤️ Clima',
    'proxima_partida': '🏟️ Próxima Partida',
    'classificacao': '🏆 Classificação',
    'calendario': '📅 Calendário',
    'compras': '🛒 Lista de Compras',
    'brasil': '🇧🇷 Notícias Brasil',
    'regiao': '📍 Notícias Região',
    'fotos': '📷 Fotos',
    'bom_dia': '🌅 Bom Dia',
    'noite': '🌙 Modo Noite',
    'barra_info': '📊 Barra de Informações',
    'spotify': '🎵 Spotify',
    'performance': '⚡ Performance',
  };

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _carregarEstadoLocal();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  late final String _latLonInicial = _latLonAtual;
  String get _latLonAtual =>
      '${config.getString('clima', 'lat')},${config.getString('clima', 'lon')}';

  void _carregarEstadoLocal() {
    _latLonInicial; // fixa a localização de quando a tela abriu
    final tk = config.getString('time', 'time_key', 'palmeiras');
    if (timesDisponiveis.containsKey(tk)) _timeSelecionado = tk;
    _cidadesSelecionadas =
        config.getStringList('regiao', 'cidades_selecionadas');
    if (_cidadesSelecionadas.isEmpty) _cidadesSelecionadas = ['hortolandia'];
    _categoriasBrasilSelecionadas =
        config.getStringList('brasil', 'categorias_selecionadas');
    if (_categoriasBrasilSelecionadas.isEmpty) {
      _categoriasBrasilSelecionadas = [
        'politica',
        'economia',
        'tecnologia',
        'saude',
        'geral'
      ];
    }
  }

  void _mudarCategoria(String cat) {
    _animCtrl.reset();
    setState(() => _categoriaAtual = cat);
    _animCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _BgPainter())),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                if (r.isCompact) _buildCategoriaTabs(),
                Expanded(
                  child: r.isCompact
                      ? FadeTransition(
                          opacity: _fadeAnim, child: _buildPainel())
                      : Row(
                          children: [
                            _buildSidebar(),
                            Expanded(
                                child: FadeTransition(
                                    opacity: _fadeAnim, child: _buildPainel())),
                          ],
                        ),
                ),
              ],
            ),
          ),
          if (_mostrarWebViewLogin)
            _WebViewLoginOverlay(
              redirectUri: config.getString('spotify', 'redirect_uri', ''),
              onFechar: () => setState(() => _mostrarWebViewLogin = false),
              onSucesso: () {
                setState(() => _mostrarWebViewLogin = false);
                _showSnack(context, '🎵 Conectado ao Spotify!',
                    corBorda: const Color(0xFF1DB954));
              },
              onErro: (msg) {
                setState(() => _mostrarWebViewLogin = false);
                _showSnack(context, '❌ $msg', corBorda: Colors.redAccent);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCategoriaTabs() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: _categoriaLabels.entries
            .map((e) => _buildCategoriaChip(e.key, e.value))
            .toList(),
      ),
    );
  }

  Widget _buildCategoriaChip(String key, String label) {
    final sel = _categoriaAtual == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _mudarCategoria(key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _accent.withValues(alpha: 0.12) : Colors.white10,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: sel ? _accent.withValues(alpha: 0.4) : _border),
          ),
          child: Text(label,
              style: GoogleFonts.figtree(
                  color: sel ? _accent : Colors.white60,
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final r = R(context);
    // Sem BackdropFilter aqui de propósito: era a causa real do efeito de
    // "foco" ao rolar a lista por trás — um painel sólido (que é também
    // como o app de referência faz) resolve isso de vez, sem meio-termo.
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.sp(28), vertical: r.sp(16)),
      decoration: const BoxDecoration(
          color: Color(0xFF0d1420),
          border: Border(bottom: BorderSide(color: _border))),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withValues(alpha: 0.12),
              border: Border.all(color: _accent.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                    color: _accent.withValues(alpha: 0.25),
                    blurRadius: 14,
                    spreadRadius: 2)
              ],
            ),
            child: const Icon(Icons.tune_rounded, color: _accent, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CONFIGURAÇÕES',
                    style: GoogleFonts.figtree(
                        color: Colors.white,
                        fontSize: r.fs(22),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
                Text('MlionDroid Center • Painel de Controle',
                    style: GoogleFonts.figtree(
                        color: Colors.white54,
                        fontSize: r.fs(13),
                        letterSpacing: 0.4),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (!r.isCompact) ...[
            _buildHeaderBtn(
                icon: Icons.restart_alt_rounded,
                label: 'Resetar',
                color: Colors.orangeAccent,
                onTap: () async {
                  await config.resetar();
                  _carregarEstadoLocal();
                  if (!mounted) return;
                  setState(() {});
                  _showSnack(this.context, '🔄 Configurações resetadas!');
                }),
            const SizedBox(width: 10),
          ],
          _buildSaveBtn(context),
          if (r.isCompact) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded,
                  color: Colors.orangeAccent),
              onPressed: () async {
                await config.resetar();
                _carregarEstadoLocal();
                if (!mounted) return;
                setState(() {});
                _showSnack(this.context, '🔄 Configurações resetadas!');
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderBtn(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.figtree(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveBtn(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        config.set('time', 'time_key', _timeSelecionado);
        final time = timesDisponiveis[_timeSelecionado]!;
        config.set('palmeiras', 'cor_gradiente_top', time.corTop);
        config.set('palmeiras', 'cor_gradiente_bottom', time.corBottom);
        config.set('palmeiras', 'cor_destaque', time.corDestaque);
        config.set('palmeiras', 'nome_rss', time.nomeRss);
        config.set('palmeiras', 'nome_time', time.nome);
        config.set('palmeiras', 'escudo_asset', time.escudoAsset);
        config.set('regiao', 'cidades_selecionadas', _cidadesSelecionadas);
        config.set(
            'brasil', 'categorias_selecionadas', _categoriasBrasilSelecionadas);
        await config.salvar();
        if (_latLonInicial != _latLonAtual) {
          WeatherService.instance.localizacaoMudou();
        }
        widget.aoSalvar();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_accent, Color(0xFF0099BB)]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: _accent.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.save_rounded, color: Colors.black, size: 18),
            const SizedBox(width: 8),
            Text('SALVAR',
                style: GoogleFonts.figtree(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    // Sem BackdropFilter aqui também, pelo mesmo motivo do cabeçalho.
    return Container(
      width: 210,
      decoration: const BoxDecoration(
          color: Color(0xFF0d1420),
          border: Border(right: BorderSide(color: _border))),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          ..._categoriaLabels.entries
              .map((e) => _buildSidebarItem(e.key, e.value)),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AnimatedBuilder(
              animation: UpdateManager.instance,
              builder: (context, _) {
                final v = UpdateManager.instance.versaoInstalada;
                return Text(
                  v.isNotEmpty ? 'v$v • MlionDroid' : 'MlionDroid',
                  style:
                      GoogleFonts.figtree(color: Colors.white12, fontSize: 12),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(String key, String label) {
    final sel = _categoriaAtual == key;
    // O label vem como "🌤️ Clima" — separamos o emoji (vira o "ícone" do
    // topo) do texto (vira o rótulo pequeno embaixo), no mesmo padrão de
    // barra lateral com ícone grande + nome curto abaixo.
    final espaco = label.indexOf(' ');
    final emoji = espaco > 0 ? label.substring(0, espaco) : label;
    final texto = espaco > 0 ? label.substring(espaco + 1) : '';

    return GestureDetector(
      onTap: () => _mudarCategoria(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        decoration: BoxDecoration(
          color: sel ? _accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: sel ? _accent.withValues(alpha: 0.55) : Colors.transparent,
              width: 1.3),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: _accent.withValues(alpha: 0.25), blurRadius: 14)
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 19)),
            const SizedBox(height: 6),
            Text(
              texto,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.figtree(
                color: sel ? Colors.white : Colors.white70,
                fontSize: 11.5,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPainel() {
    try {
      switch (_categoriaAtual) {
        case 'sobre':
          return _buildSobreConfig();
        case 'geral':
          return _buildGeralConfig();
        case 'assistente':
          return const ConfigAssistente();
        case 'time':
          return _buildTimeConfig();
        case 'clima':
          return _buildClimaConfig();
        case 'regiao':
          return _buildRegiaoConfig();
        case 'calendario':
          return _buildCalendarioConfig();
        case 'compras':
          return _buildComprasConfig();
        case 'proxima_partida':
          return _buildProximaPartidaConfig();
        case 'classificacao':
          return _buildClassificacaoConfig();
        case 'brasil':
          return _buildBrasilConfig();
        case 'fotos':
          return _buildFotosConfig();
        case 'bom_dia':
          return _buildBomDiaConfig();
        case 'noite':
          return _buildNoiteConfig();
        case 'barra_info':
          return _buildBarraInfoConfig();
        case 'spotify':
          return _buildSpotifyConfig();
        case 'performance':
          return _buildPerformanceConfig();
        case 'atualizacoes':
          return _buildAtualizacoesConfig();
        default:
          return _buildGeralConfig();
      }
    } catch (e) {
      return Center(child: Text('Erro: $e'));
    }
  }

  Widget _buildSobreConfig() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        // ── Cabeçalho do app ────────────────────────────────────────────────
        Center(
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_accent, Color(0xFF0099BB)],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: _accent.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 2),
                  ],
                ),
                // Mostra o logo do canal quando o asset for adicionado; até
                // lá, cai graciosamente no ícone genérico (não quebra o app).
                child: ClipOval(
                  child: Image.asset(
                    _sobreLogoCanal,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 40),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(_sobreAppNome,
                  style: GoogleFonts.figtree(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              AnimatedBuilder(
                animation: UpdateManager.instance,
                builder: (context, _) {
                  final v = UpdateManager.instance.versaoInstalada;
                  return Text(
                    v.isNotEmpty ? 'Versão $v' : 'Versão...',
                    style: GoogleFonts.figtree(
                        color: Colors.white54, fontSize: 14),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // ── Sobre o app ─────────────────────────────────────────────────────
        _sectionTitle('✨ Sobre o app'),
        const SizedBox(height: 14),
        _glassCard(children: [
          Text(_sobreDescricaoApp,
              style: GoogleFonts.figtree(
                  color: Colors.white70, fontSize: 15, height: 1.6)),
        ]),
        const SizedBox(height: 24),

        // ── Sobre o criador ─────────────────────────────────────────────────
        _sectionTitle('👤 Sobre o criador'),
        const SizedBox(height: 14),
        _glassCard(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(
                child: Image.asset(
                  _sobreCriadorFoto,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  // Enquanto a foto real não for adicionada aos assets do
                  // projeto, mostra um ícone no lugar em vez de quebrar.
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(color: _border),
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: Colors.white54, size: 30),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_sobreCriadorNome,
                        style: GoogleFonts.figtree(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(_sobreDescricaoCriador,
                        style: GoogleFonts.figtree(
                            color: Colors.white70, fontSize: 14, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () async {
              final url = Uri.tryParse(_sobreUrlCanal);
              if (url != null) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _accent.withValues(alpha: 0.5)),
                color: _accent.withValues(alpha: 0.08),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_circle_outline_rounded,
                      color: _accent, size: 20),
                  const SizedBox(width: 10),
                  Text(_sobreLabelCanal,
                      style: GoogleFonts.figtree(
                          color: _accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Feito com 💙 para deixar seu tablet mais inteligente.',
            style: GoogleFonts.figtree(color: Colors.white24, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  bool _selecionandoFotos = false;
  int? _fotosAdicionadas;
  int? _totalFotos;

  Future<void> _selecionarFotosConfig() async {
    setState(() {
      _selecionandoFotos = true;
      _fotosAdicionadas = null;
    });
    try {
      final n = await FotosService.instance.adicionarDoSeletor();
      _fotosAdicionadas = n;
      _totalFotos = (await FotosService.instance.listar()).length;
    } catch (e) {
      debugPrint('Erro ao selecionar fotos (config): $e');
    } finally {
      if (mounted) setState(() => _selecionandoFotos = false);
    }
  }

  Widget _buildFotosConfig() {
    if (_totalFotos == null) {
      FotosService.instance.listar().then((l) {
        if (mounted) setState(() => _totalFotos = l.length);
      });
    }
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('📷 Memórias (fotos)'),
        const SizedBox(height: 20),
        _glassCard(children: [
          Text(
            _totalFotos == null
                ? 'Contando fotos...'
                : '$_totalFotos foto(s) nas Memórias',
            style: GoogleFonts.figtree(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _selecionandoFotos ? null : _selecionarFotosConfig,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _accent.withValues(alpha: 0.5)),
                color: _accent.withValues(alpha: 0.08),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_selecionandoFotos)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.add_photo_alternate_rounded,
                        color: _accent, size: 20),
                  const SizedBox(width: 10),
                  Text('Adicionar fotos',
                      style: GoogleFonts.figtree(
                          color: _accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          if (_fotosAdicionadas != null) ...[
            const SizedBox(height: 8),
            Text('$_fotosAdicionadas foto(s) adicionada(s).',
                style: GoogleFonts.figtree(
                    color: Colors.greenAccent, fontSize: 13)),
          ],
          const SizedBox(height: 6),
          Text(
            'As fotos são copiadas para dentro do app (não precisa de '
            'permissão de armazenamento) e entram no slideshow das Memórias '
            'e na "Recordação do dia" da tela Bom Dia.',
            style: GoogleFonts.figtree(color: Colors.white54, fontSize: 12),
          ),
        ]),
        const SizedBox(height: 20),
        _glassCard(children: [
          _sliderInt('fotos', 'duracao_por_foto_seg', 'Segundos por foto',
              config.getInt('fotos', 'duracao_por_foto_seg', 8), 3, 60,
              unidade: 's'),
          _sliderInt('fotos', 'fotos_por_visita', 'Fotos por passagem na tela',
              config.getInt('fotos', 'fotos_por_visita', 4), 1, 20),
        ]),
      ],
    );
  }

  Widget _buildGeralConfig() {
    final sequencia = config.getStringList('geral', 'sequencia');
    final tipoTrans = config.getString('geral', 'transicao_tipo', 'fade');
    final nomeTelas = {
      'clima': '🌤️ Clima',
      'palmeiras': '⚽ Time & Futebol',
      'proxima_partida': '🏟️ Próxima Partida',
      'calendario': '📅 Calendário Google',
      'classificacao': '🏆 Classificação',
      'compras': '🛒 Lista de Compras',
      'brasil': '🇧🇷 Notícias Brasil',
      'regiao': '📍 Notícias Região',
      'fotos': '📷 Fotos',
      'bom_dia': '🌅 Bom Dia',
      'spotify': '🎵 Spotify',
    };
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('👤 Identificação'),
        const SizedBox(height: 14),
        _glassCard(children: [
          _textFieldConfig(
            'geral',
            'nome_usuario',
            'Seu nome',
            'Como o app vai te cumprimentar na tela Bom Dia',
            Icons.person_outline_rounded,
          ),
        ]),
        const SizedBox(height: 24),
        _sectionTitle('⚙️ Configurações Gerais'),
        const SizedBox(height: 20),
        _glassCard(children: [
          _sliderInt('geral', 'transicao_ms', 'Duração da transição',
              config.getInt('geral', 'transicao_ms', 800), 200, 3000,
              unidade: 'ms'),
          _sliderInt('geral', 'pausa_preta_ms', 'Pausa entre telas',
              config.getInt('geral', 'pausa_preta_ms', 300), 0, 1000,
              unidade: 'ms'),
          _sliderInt(
              'geral',
              'tempo_modo_manual',
              'Depois de tocar na tela, voltar ao automático em',
              config.getInt('geral', 'tempo_modo_manual', 45),
              10,
              300,
              unidade: 's'),
          _toggleConfig(
            titulo: 'Manter a tela sempre ligada',
            subtitulo:
                'Impede que o tablet apague a tela sozinho enquanto o app está aberto',
            categoria: 'geral',
            chave: 'manter_tela_ligada',
            valorPadrao: true,
          ),
        ]),
        const SizedBox(height: 16),
        _glassCard(children: [
          Text('Dados guardados',
              style: GoogleFonts.figtree(
                  color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'O app guarda clima, notícias e jogos para mostrar algo mesmo sem '
            'internet. Use o botão abaixo se algum dado parecer travado.',
            style: GoogleFonts.figtree(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await CacheManager.instance.limparTudo();
              if (!mounted) return;
              _showSnack(context, 'Dados apagados — tudo será buscado de novo.');
            },
            icon: const Icon(Icons.refresh_rounded, color: _accent),
            label: Text('Forçar atualização de todos os dados',
                style: GoogleFonts.figtree(color: _accent)),
          ),
        ]),
        const SizedBox(height: 24),
        _sectionTitle('🎬 Tipo de Transição'),
        const SizedBox(height: 12),
        _glassCard(children: [_buildTransicaoPicker(tipoTrans)]),
        const SizedBox(height: 28),
        _sectionTitle('🔀 Sequência das Telas'),
        const SizedBox(height: 14),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: (oldIdx, newIdx) {
            setState(() {
              if (newIdx > oldIdx) newIdx--;
              final item = sequencia.removeAt(oldIdx);
              sequencia.insert(newIdx, item);
              config.set('geral', 'sequencia', List<String>.from(sequencia));
            });
          },
          children: sequencia.asMap().entries.map((e) {
            final telaId = e.value;
            final ativas = config.getStringList('geral', 'telas_ativas');
            final bool estaAtiva = ativas.contains(telaId);
            return Container(
              key: ValueKey('seq_$telaId'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: estaAtiva ? 0.04 : 0.01),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color:
                        estaAtiva ? _border : _border.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: estaAtiva,
                    activeColor: _accent,
                    onChanged: (val) {
                      setState(() {
                        List<String> novaAtivas = List.from(ativas);
                        val == true
                            ? novaAtivas.add(telaId)
                            : novaAtivas.remove(telaId);
                        config.set('geral', 'telas_ativas', novaAtivas);
                      });
                    },
                  ),
                  const Icon(Icons.drag_handle_rounded,
                      color: Colors.white24, size: 20),
                  const SizedBox(width: 14),
                  Text(nomeTelas[telaId] ?? telaId,
                      style: GoogleFonts.figtree(
                          color: estaAtiva ? Colors.white70 : Colors.white24,
                          fontSize: 16,
                          decoration: estaAtiva
                              ? TextDecoration.none
                              : TextDecoration.lineThrough)),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTransicaoPicker(String valorAtual) {
    final opcoes = [
      {'key': 'fade', 'label': 'Fade', 'icon': Icons.blur_on_rounded},
      {
        'key': 'slide_horizontal',
        'label': 'Slide Horizontal',
        'icon': Icons.swap_horiz_rounded
      },
      {
        'key': 'slide_vertical',
        'label': 'Slide Vertical',
        'icon': Icons.swap_vert_rounded
      },
      {'key': 'zoom', 'label': 'Zoom', 'icon': Icons.zoom_in_rounded}
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: opcoes.map((op) {
        final sel = valorAtual == op['key'];
        return GestureDetector(
          onTap: () =>
              setState(() => config.set('geral', 'transicao_tipo', op['key'])),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: sel
                    ? _accent.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? _accent : _border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(op['icon'] as IconData,
                  color: sel ? _accent : Colors.white54),
              const SizedBox(width: 8),
              Text(op['label'] as String,
                  style: GoogleFonts.figtree(
                      color: sel ? _accent : Colors.white60))
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTimeConfig() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('⚽ Selecionar Time'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: timesDisponiveis.entries.map((e) {
            final sel = _timeSelecionado == e.key;
            return GestureDetector(
              onTap: () => setState(() => _timeSelecionado = e.key),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    color: sel
                        ? _accent.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? _accent : _border)),
                child: Text(e.value.nome,
                    style: GoogleFonts.figtree(
                        color: sel ? _accent : Colors.white60)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        _glassCard(children: [
          _sliderInt('palmeiras', 'qtd_noticias', 'Quantidade de notícias',
              config.getInt('palmeiras', 'qtd_noticias', 8), 2, 30),
          _sliderInt(
              'palmeiras',
              'duracao_scroll_px_seg',
              'Velocidade do scroll',
              config.getInt('palmeiras', 'duracao_scroll_px_seg', 35),
              10,
              100),
          _sliderInt(
              'palmeiras',
              'pausa_final_seg',
              'Pausa ao chegar na última notícia',
              config.getInt('palmeiras', 'pausa_final_seg', 10),
              0,
              30,
              unidade: 'seg'),
          _intervaloPicker('palmeiras'),
        ]),
      ],
    );
  }

  Widget _buildClimaConfig() {
    final cidadeAtual = config.getString('clima', 'cidade', 'Hortolândia');
    final ufAtual = config.getString('clima', 'estado', 'SP');
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('🌤️ Tela Clima'),
        const SizedBox(height: 20),
        _glassCard(children: [
          Row(children: [
            const Icon(Icons.location_on_rounded, color: _accent, size: 16),
            const SizedBox(width: 8),
            Text('Localização',
                style: GoogleFonts.figtree(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _geocodificando ? null : _abrirSeletorLocalizacaoClima,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$cidadeAtual • $ufAtual',
                      style: GoogleFonts.figtree(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_geocodificando)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.edit_rounded, color: _accent, size: 18),
                ],
              ),
            ),
          ),
          if (_erroLocalizacao != null) ...[
            const SizedBox(height: 8),
            Text(_erroLocalizacao!,
                style:
                    GoogleFonts.figtree(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 6),
          Text(
            'Toque para escolher Estado e Cidade — a previsão e o mapa '
            'são atualizados automaticamente.',
            style: GoogleFonts.figtree(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 20),
          _sliderInt('clima', 'duracao_seg', 'Tempo na tela',
              config.getInt('clima', 'duracao_seg', 20), 5, 120),
          _intervaloPicker('clima'),
        ]),
      ],
    );
  }

  Widget _buildBrasilConfig() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('🇧🇷 Categorias de Notícias'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: categoriasBrasil.entries.map((e) {
            final sel = _categoriasBrasilSelecionadas.contains(e.key);
            return GestureDetector(
              onTap: () {
                setState(() {
                  sel
                      ? _categoriasBrasilSelecionadas.remove(e.key)
                      : _categoriasBrasilSelecionadas.add(e.key);
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                    color: sel ? Colors.white12 : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? _accent : _border)),
                child: Text(e.value.nome,
                    style: GoogleFonts.figtree(
                        color: sel ? _accent : Colors.white70)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        _glassCard(children: [
          _sliderInt(
              'brasil',
              'qtd_noticias',
              'Notícias por categoria selecionada',
              config.getInt('brasil', 'qtd_noticias', 3),
              1,
              15),
          _sliderInt('brasil', 'duracao_scroll_px_seg', 'Velocidade do scroll',
              config.getInt('brasil', 'duracao_scroll_px_seg', 35), 10, 100),
          _sliderInt(
              'brasil',
              'pausa_final_seg',
              'Pausa ao chegar na última notícia',
              config.getInt('brasil', 'pausa_final_seg', 10),
              0,
              30,
              unidade: 'seg'),
          _intervaloPicker('brasil'),
        ]),
      ],
    );
  }

  Widget _buildRegiaoConfig() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('📍 Cidades da Região'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cidadesRegiao.entries.map((e) {
            final sel = _cidadesSelecionadas.contains(e.key);
            return GestureDetector(
              onTap: () {
                setState(() {
                  sel
                      ? _cidadesSelecionadas.remove(e.key)
                      : _cidadesSelecionadas.add(e.key);
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                    color: sel ? Colors.white12 : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? _accent : _border)),
                child: Text(e.value.nome,
                    style: GoogleFonts.figtree(
                        color: sel ? _accent : Colors.white60)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        _glassCard(children: [
          _sliderInt(
              'regiao',
              'qtd_noticias',
              'Notícias por cidade selecionada',
              config.getInt('regiao', 'qtd_noticias', 2),
              2,
              20),
          _sliderInt('regiao', 'duracao_scroll_px_seg', 'Velocidade do scroll',
              config.getInt('regiao', 'duracao_scroll_px_seg', 35), 10, 100),
          _sliderInt(
              'regiao',
              'pausa_final_seg',
              'Pausa ao chegar na última notícia',
              config.getInt('regiao', 'pausa_final_seg', 10),
              0,
              30,
              unidade: 'seg'),
          _intervaloPicker('regiao'),
        ]),
      ],
    );
  }

  /// Conta Google usada por Calendário e Compras. A janela de login só abre
  /// por aqui — durante o rodízio o app nunca pede login.
  Widget _cartaoContaGoogle() {
    return ListenableBuilder(
      listenable: GoogleAuthService.instance,
      builder: (context, _) {
        final auth = GoogleAuthService.instance;
        final conta = auth.conta;
        return _glassCard(children: [
          Row(children: [
            Icon(conta != null ? Icons.verified_user_rounded : Icons.account_circle_outlined,
                color: conta != null ? Colors.greenAccent : Colors.orangeAccent, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conta != null ? 'Conta Google conectada' : 'Conta Google não conectada',
                      style: GoogleFonts.figtree(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(
                      conta?.email ??
                          'Necessária para Calendário (Google Agenda) e Lista de Compras (Google Tasks).',
                      style: GoogleFonts.figtree(color: Colors.white60, fontSize: 13)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                if (conta != null) {
                  await auth.desconectar();
                } else {
                  final ok = await auth.conectar();
                  if (!mounted) return;
                  _showSnack(this.context, ok ? 'Conta conectada!' : 'Login cancelado.');
                }
              },
              icon: Icon(conta != null ? Icons.logout_rounded : Icons.login_rounded,
                  color: _accent),
              label: Text(conta != null ? 'Desconectar' : 'Conectar conta Google',
                  style: GoogleFonts.figtree(color: _accent, fontWeight: FontWeight.w700)),
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildCalendarioConfig() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('📅 Calendário'),
        const SizedBox(height: 20),
        _cartaoContaGoogle(),
        const SizedBox(height: 16),
        _glassCard(children: [
          _sliderInt('calendario', 'duracao_seg', 'Tempo na tela',
              config.getInt('calendario', 'duracao_seg', 35), 10, 120,
              unidade: 's'),
          _intervaloPicker('calendario'),
        ]),
      ],
    );
  }

  Widget _buildComprasConfig() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('🛒 Compras'),
        const SizedBox(height: 20),
        _cartaoContaGoogle(),
        const SizedBox(height: 16),
        _glassCard(children: [
          Text(
            'A tela usa a lista do Google Tasks chamada "Compras" (ou '
            '"Mercado", "Supermercado", "Feira"). Tocar num item marca como '
            'comprado — com 5 segundos para desfazer.',
            style: GoogleFonts.figtree(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _sliderInt('compras', 'duracao_seg', 'Tempo na tela',
              config.getInt('compras', 'duracao_seg', 30), 10, 120,
              unidade: 's'),
          _intervaloPicker('compras'),
        ]),
      ],
    );
  }

  Widget _buildProximaPartidaConfig() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('🏟️ Próxima Partida'),
        const SizedBox(height: 20),
        _glassCard(children: [
          _sliderInt('proxima_partida', 'duracao_seg', 'Tempo na tela',
              config.getInt('proxima_partida', 'duracao_seg', 20), 5, 120,
              unidade: 's'),
          _toggleConfig(
            titulo: 'Mostrar onde assistir',
            subtitulo:
                'Canais de TV/streaming do jogo (aparecem no dia e na véspera, '
                'lidos da programação pública do futebolnatv.com.br)',
            categoria: 'proxima_partida',
            chave: 'mostrar_canais',
            valorPadrao: true,
          ),
          _toggleConfig(
            titulo: 'Avisar gols em voz alta',
            subtitulo:
                'No dia do jogo o painel acompanha o placar; a cada gol, mostra a partida e fala o placar',
            categoria: 'proxima_partida',
            chave: 'falar_gols',
            valorPadrao: true,
          ),
          const SizedBox(height: 16),
          _intervaloPicker('proxima_partida'),
        ]),
      ],
    );
  }

  Widget _buildClassificacaoConfig() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('🏆 Classificação'),
        const SizedBox(height: 20),
        _glassCard(children: [
          _sliderInt('classificacao', 'scroll_velocidade', 'Velocidade da rolagem',
              config.getInt('classificacao', 'scroll_velocidade', 30), 10, 120,
              unidade: 'px/s'),
          _sliderInt('classificacao', 'pausa_troca_seg', 'Pausa ao final de cada tabela',
              config.getInt('classificacao', 'pausa_troca_seg', 3), 1, 30,
              unidade: 's'),
          _toggleConfig(
            titulo: 'Mostrar Libertadores',
            subtitulo: 'Depois do Brasileirão, mostra os grupos da Libertadores',
            categoria: 'classificacao',
            chave: 'mostrar_libertadores',
            valorPadrao: true,
          ),
          const SizedBox(height: 16),
          _intervaloPicker('classificacao'),
        ]),
      ],
    );
  }

  Widget _buildNoiteConfig() {
    final inicio = config.getInt('noite', 'hora_inicio', 23);
    final fim = config.getInt('noite', 'hora_fim', 6);
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('🌙 Modo Noite'),
        const SizedBox(height: 8),
        Text(
          'De madrugada o painel troca o rodízio por um relógio grande e '
          'escuro, e reduz o brilho da tela. Tocar na tela acorda o painel '
          'por 10 minutos.',
          style: GoogleFonts.figtree(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _glassCard(children: [
          _toggleConfig(
            titulo: 'Ativar Modo Noite',
            subtitulo: 'Relógio escuro + brilho reduzido no horário abaixo',
            categoria: 'noite',
            chave: 'ativo',
            valorPadrao: true,
          ),
          const Divider(color: Colors.white10, height: 28),
          Row(children: [
            Expanded(
                child: Text('Começa às',
                    style: GoogleFonts.figtree(color: Colors.white70, fontSize: 15))),
            _horaPicker(
                valor: inicio,
                min: 0,
                max: 23,
                onChanged: (v) => setState(() => config.set('noite', 'hora_inicio', v))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: Text('Termina às',
                    style: GoogleFonts.figtree(color: Colors.white70, fontSize: 15))),
            _horaPicker(
                valor: fim,
                min: 0,
                max: 23,
                onChanged: (v) => setState(() => config.set('noite', 'hora_fim', v))),
          ]),
        ]),
      ],
    );
  }

  Widget _buildBarraInfoConfig() {
    final tipo = config.getString('barra_info', 'tipo_ticker', 'misturado');
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('📊 Barra Superior (sempre visível)'),
        const SizedBox(height: 14),
        const Text(
          'Relógio, clima e faixa de notícias/frases aparecem em todas as telas.',
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        const SizedBox(height: 20),
        _glassCard(children: [
          _sliderInt(
              'barra_info',
              'intervalo_clima_min',
              'Atualizar clima a cada',
              config.getInt('barra_info', 'intervalo_clima_min', 10),
              5,
              60,
              unidade: 'min'),
          _sliderInt(
              'barra_info',
              'rotacao_ticker_seg',
              'Trocar frase/notícia a cada',
              config.getInt('barra_info', 'rotacao_ticker_seg', 12),
              6,
              60,
              unidade: 's'),
        ]),
        const SizedBox(height: 20),
        _sectionTitle('Tipo de conteúdo na faixa'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _chipTicker('misturado', 'Frases + Notícias', tipo),
            _chipTicker('frase', 'Só frases', tipo),
            _chipTicker('noticias', 'Só notícias G1', tipo),
          ],
        ),
      ],
    );
  }

  Widget _chipTicker(String key, String label, String atual) {
    final sel = atual == key;
    return GestureDetector(
      onTap: () => setState(() => config.set('barra_info', 'tipo_ticker', key)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? _accent.withValues(alpha: 0.12) : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? _accent : _border),
        ),
        child: Text(label,
            style: GoogleFonts.figtree(
                color: sel ? _accent : Colors.white60,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  // ── Spotify ────────────────────────────────────────────────────────────────
  Widget _buildSpotifyConfig() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('🎵 Conectar ao Spotify'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF1DB954).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF1DB954).withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFF1DB954), size: 18),
                const SizedBox(width: 10),
                Text('Como configurar',
                    style: GoogleFonts.figtree(
                        color: const Color(0xFF1DB954),
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              _instrucaoStep('1',
                  'No celular, abra o Chrome e acesse: developer.spotify.com/dashboard'),
              _instrucaoStep('2',
                  'IMPORTANTE: ative o "Modo para computador" no menu do navegador (⋮) — sem isso o botão de criar app não aparece'),
              _instrucaoStep('3',
                  'Faça login com sua conta Spotify e clique em "Create app"'),
              _instrucaoStep('4',
                  'Preencha o nome e a descrição. No campo Redirect URIs, cole o endereço fixo que está logo abaixo (toque para copiar) — depois clique em Add'),
              _instrucaoStep(
                  '5', 'Marque "Web API", aceite os termos e clique em Save'),
              _instrucaoStep(
                  '6', 'Copie o Client ID que aparecer e cole no campo abaixo'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _sectionTitle('🔑 Credenciais'),
        const SizedBox(height: 14),
        _glassCard(children: [
          _textFieldConfig(
            'spotify',
            'client_id',
            'Client ID',
            'Cole aqui o Client ID do seu app Spotify',
            Icons.vpn_key_rounded,
          ),
          const SizedBox(height: 8),
          _textFieldConfig(
            'spotify',
            'redirect_uri',
            'Redirect URI',
            'https://localhost:8888/callback',
            Icons.link_rounded,
          ),
          const SizedBox(height: 4),
          Text(
            '⚠️  Digite exatamente: https://localhost:8888/callback\nCom "https://" (com o s) — e cadastre igual no Spotify Dashboard',
            style: GoogleFonts.figtree(
                color: Colors.white54, fontSize: 13, height: 1.5),
          ),
        ]),
        const SizedBox(height: 28),
        _sectionTitle('⚙️ Comportamento'),
        const SizedBox(height: 14),
        _glassCard(children: [
          _sliderInt(
            'spotify',
            'duracao_tela_seg',
            'Tempo na tela ao trocar música',
            config.getInt('spotify', 'duracao_tela_seg', 30),
            10,
            90,
            unidade: 's',
          ),
          const SizedBox(height: 8),
          _toggleConfig(
            titulo: 'Aparecer ao trocar música',
            subtitulo:
                'Interrompe qualquer tela automaticamente quando você inicia ou troca uma música em qualquer dispositivo',
            categoria: 'spotify',
            chave: 'aparecer_por_evento',
            valorPadrao: true,
            cor: const Color(0xFF1DB954),
          ),
          const Divider(color: Colors.white12, height: 24),
          _toggleConfig(
            titulo: 'Aparecer na rotação automática',
            subtitulo:
                'Inclui a tela do Spotify na sequência normal de telas — mesmo sem música tocando',
            categoria: 'spotify',
            chave: 'aparecer_na_rotacao',
            valorPadrao: false,
            cor: const Color(0xFF1DB954),
            aoMudar: (v) {
              final ativas = config.getStringList('geral', 'telas_ativas');
              if (v && !ativas.contains('spotify')) {
                ativas.add('spotify');
              } else if (!v) {
                ativas.remove('spotify');
              }
              config.set('geral', 'telas_ativas', ativas);
            },
          ),
        ]),
        const SizedBox(height: 24),
        _sectionTitle('🔌 Status da Conexão'),
        const SizedBox(height: 14),
        _buildSpotifyStatus(),
      ],
    );
  }

  Widget _buildSpotifyStatus() {
    final spotify = SpotifyManager.instance;
    final clientId = config.getString('spotify', 'client_id', '');
    final redirectUri = config.getString('spotify', 'redirect_uri', '');
    final semClientId = clientId.isEmpty;
    final semRedirect = redirectUri.isEmpty;

    Color corStatus;
    IconData iconeStatus;
    String tituloStatus;
    String subtituloStatus;

    if (semClientId || semRedirect) {
      corStatus = Colors.orange;
      iconeStatus = Icons.warning_amber_rounded;
      tituloStatus = 'Dados incompletos';
      subtituloStatus = semClientId
          ? 'Preencha o Client ID acima'
          : 'Preencha o Redirect URI acima';
    } else if (spotify.autenticado) {
      corStatus = const Color(0xFF1DB954);
      iconeStatus = Icons.check_circle_rounded;
      tituloStatus = 'Conectado ✓';
      subtituloStatus = spotify.faixaAtual != null
          ? '🎵 ${spotify.faixaAtual!.titulo} • ${spotify.faixaAtual!.artista}'
          : 'Aguardando música...';
    } else {
      corStatus = Colors.white54;
      iconeStatus = Icons.radio_button_unchecked_rounded;
      tituloStatus = 'Não conectado';
      subtituloStatus = 'Toque em "Conectar" para fazer login';
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: corStatus.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: corStatus.withValues(alpha: 0.30)),
          ),
          child: Row(children: [
            Icon(iconeStatus, color: corStatus, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tituloStatus,
                      style: GoogleFonts.figtree(
                          color: corStatus,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtituloStatus,
                      style: GoogleFonts.figtree(
                          color: Colors.white60, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (spotify.autenticado)
              GestureDetector(
                onTap: () async {
                  await SpotifyManager.instance.iniciar();
                  if (mounted) setState(() {});
                },
                child: const Icon(Icons.refresh_rounded,
                    color: Color(0xFF1DB954), size: 22),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_mostrarWebViewLogin && !semClientId && !semRedirect)
          _WebViewLoginOverlay(
            redirectUri: redirectUri,
            onFechar: () => setState(() => _mostrarWebViewLogin = false),
            onSucesso: () {
              setState(() => _mostrarWebViewLogin = false);
              _showSnack(context, '🎵 Conectado ao Spotify!');
            },
            onErro: (msg) {
              setState(() => _mostrarWebViewLogin = false);
              _showSnack(context, '❌ $msg');
            },
          ),
        if (!semClientId && !semRedirect && !spotify.autenticado)
          GestureDetector(
            onTap: () {
              config.salvar();
              setState(() => _mostrarWebViewLogin = true);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1DB954), Color(0xFF17a349)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1DB954).withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.login_rounded,
                      color: Colors.black, size: 20),
                  const SizedBox(width: 10),
                  Text('CONECTAR AO SPOTIFY',
                      style: GoogleFonts.figtree(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6)),
                ],
              ),
            ),
          ),
        if (spotify.autenticado)
          GestureDetector(
            onTap: () {
              SpotifyManager.instance.deslogar();
              setState(() {});
              _showSnack(context, '🎵 Deslogado do Spotify.');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded,
                      color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Text('DESLOGAR DO SPOTIFY',
                      style: GoogleFonts.figtree(
                          color: Colors.redAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _toggleConfig({
    required String titulo,
    required String subtitulo,
    required String categoria,
    required String chave,
    required bool valorPadrao,
    Color cor = _accent,
    void Function(bool)? aoMudar,
  }) {
    final valor = config.getBool(categoria, chave, valorPadrao);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: GoogleFonts.figtree(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(subtitulo,
                  style: GoogleFonts.figtree(
                      color: Colors.white54, fontSize: 12, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: valor,
          activeThumbColor: cor,
          onChanged: (v) {
            setState(() {
              config.set(categoria, chave, v);
              aoMudar?.call(v);
            });
          },
        ),
      ],
    );
  }

  Widget _instrucaoStep(String num, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(right: 10, top: 1),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF1DB954),
          ),
          child: Center(
            child: Text(num,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
        ),
        Expanded(
          child: Text(texto,
              style: GoogleFonts.figtree(
                  color: Colors.white70, fontSize: 14, height: 1.4)),
        ),
      ]),
    );
  }

  Widget _textFieldConfig(
    String categoria,
    String chave,
    String label,
    String hint,
    IconData icone,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icone, color: _accent, size: 16),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.figtree(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            // initialValue + key estável: o campo mantém o próprio estado.
            // Antes um TextEditingController novo era criado a cada
            // redesenho (vazava memória e o cursor pulava).
            key: ValueKey('campo_${categoria}_$chave'),
            initialValue: config.getString(categoria, chave, ''),
            style: GoogleFonts.figtree(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  GoogleFonts.figtree(color: Colors.white24, fontSize: 14),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _accent),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (val) {
              config.set(categoria, chave, val);
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(children: [
      Container(width: 3, height: 20, color: _accent),
      const SizedBox(width: 12),
      Text(title,
          style: GoogleFonts.figtree(
              color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _glassCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildPerformanceConfig() {
    final perf = PerformanceManager.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('⚡ Desempenho do aparelho'),
        const SizedBox(height: 16),

        // ── Explicação ──────────────────────────────────────────────────────
        _glassCard(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  color: Colors.amberAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Se o app estiver travando, com engasgos ou lento neste '
                  'tablet, ative o Modo Econômico. Ele reduz efeitos visuais '
                  'pesados (desfoque, animações contínuas) mantendo o '
                  'app funcional e bonito, só mais leve.\n\n'
                  'Em tablets modernos e potentes, deixe desligado para '
                  'aproveitar o visual completo.',
                  style: GoogleFonts.figtree(
                      color: Colors.white70, fontSize: 14, height: 1.5),
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),

        // ── Switch principal ────────────────────────────────────────────────
        _glassCard(children: [
          AnimatedBuilder(
            animation: perf,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          perf.modoEconomico
                              ? Icons.battery_saver_rounded
                              : Icons.auto_awesome_rounded,
                          color: perf.modoEconomico
                              ? Colors.amberAccent
                              : Colors.cyanAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            perf.modoEconomico
                                ? 'Modo Econômico (tablet fraco)'
                                : 'Visual completo (tablet top)',
                            style: GoogleFonts.figtree(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: perf.modoEconomico,
                    activeThumbColor: Colors.amberAccent,
                    onChanged: (v) => perf.definirModoEconomico(v),
                  ),
                ],
              );
            },
          ),
        ]),
      ],
    );
  }

  Widget _buildAtualizacoesConfig() {
    return AnimatedBuilder(
      animation: UpdateManager.instance,
      builder: (context, _) {
        final upd = UpdateManager.instance;
        final horaAtual =
            config.getInt('atualizacoes', 'intervalo_verificacao_horas', 6);

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            _sectionTitle('🔄 Atualizações do app'),
            const SizedBox(height: 16),

            // ── Versão instalada + status ──────────────────────────────────────
            _glassCard(children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: upd.disponivel
                          ? const Color(0xFF00D4FF).withValues(alpha: 0.15)
                          : Colors.greenAccent.withValues(alpha: 0.12),
                      border: Border.all(
                        color: upd.disponivel
                            ? const Color(0xFF00D4FF).withValues(alpha: 0.6)
                            : Colors.greenAccent.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      upd.disponivel
                          ? Icons.system_update_rounded
                          : Icons.check_rounded,
                      color: upd.disponivel
                          ? const Color(0xFF00D4FF)
                          : Colors.greenAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          upd.versaoInstalada.isNotEmpty
                              ? 'Versão instalada: ${upd.versaoInstalada}'
                              : 'Verificando versão instalada...',
                          style: GoogleFonts.figtree(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          upd.disponivel
                              ? 'Versão ${upd.info?.versao} disponível'
                              : upd.ultimaVerificacao != null
                                  ? 'Você está com a versão mais recente'
                                  : 'Ainda não verificado nesta sessão',
                          style: GoogleFonts.figtree(
                            color: upd.disponivel
                                ? const Color(0xFF00D4FF)
                                : Colors.white60,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (upd.ultimaVerificacao != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Última verificação: ${_formatarHorario(upd.ultimaVerificacao!)}',
                  style:
                      GoogleFonts.figtree(color: Colors.white54, fontSize: 12),
                ),
              ],
            ]),
            const SizedBox(height: 16),

            // ── Changelog da última release encontrada ──────────────────────────
            if (upd.info != null && upd.info!.changelog.isNotEmpty) ...[
              _glassCard(children: [
                Row(
                  children: [
                    const Icon(Icons.notes_rounded,
                        color: Colors.white60, size: 16),
                    const SizedBox(width: 8),
                    Text('Novidades da versão ${upd.info!.versao}',
                        style: GoogleFonts.figtree(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  upd.info!.changelog,
                  style: GoogleFonts.figtree(
                      color: Colors.white60, fontSize: 14, height: 1.5),
                ),
              ]),
              const SizedBox(height: 16),
            ],

            // ── Botão verificar agora ────────────────────────────────────────────
            GestureDetector(
              onTap: upd.verificando
                  ? null
                  : () async {
                      await upd.verificar();
                      if (!context.mounted) return;
                      if (upd.disponivel) {
                        // Mesma ação do ícone da barra superior — encontrou
                        // atualização, já abre a folha de baixar/instalar.
                        abrirFolhaAtualizacao(context);
                      } else {
                        // Sem atualização — precisa de uma confirmação
                        // visual rápida, senão parece que o toque não fez
                        // nada.
                        _showSnack(
                            context, 'Você está com a última versão instalada.',
                            corBorda: Colors.greenAccent);
                      }
                    },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.5)),
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.08),
                ),
                child: Center(
                  child: upd.verificando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF00D4FF)),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded,
                                color: Color(0xFF00D4FF), size: 20),
                            const SizedBox(width: 10),
                            Text('Verificar agora',
                                style: GoogleFonts.figtree(
                                    color: const Color(0xFF00D4FF),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Intervalo de verificação automática ──────────────────────────────
            _sectionTitle('⏱️ Verificação automática'),
            const SizedBox(height: 12),
            _glassCard(children: [
              Text(
                'De quanto em quanto tempo o app verifica sozinho se tem '
                'versão nova, sem precisar fechar e abrir.',
                style: GoogleFonts.figtree(
                    color: Colors.white60, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              ...IntervaloVerificacao.opcoes.map((opcao) {
                final sel = horaAtual == opcao['horas'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      config.set('atualizacoes', 'intervalo_verificacao_horas',
                          opcao['horas']);
                    });
                    UpdateManager.instance.atualizarIntervalo();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: sel
                          ? const Color(0xFF00D4FF).withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.03),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFF00D4FF).withValues(alpha: 0.5)
                            : _border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sel
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: sel ? const Color(0xFF00D4FF) : Colors.white30,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          opcao['label'] as String,
                          style: GoogleFonts.figtree(
                            color: sel ? Colors.white : Colors.white70,
                            fontSize: 15,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ]),
          ],
        );
      },
    );
  }

  String _formatarHorario(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _sliderInt(
      String cat, String chave, String label, int valor, int min, int max,
      {String unidade = ''}) {
    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
              child: Text(label, style: GoogleFonts.figtree(color: Colors.white70))),
          Text('${valor.clamp(min, max)} $unidade',
              style: GoogleFonts.figtree(color: _accent)),
        ]),
        Slider(
            // clamp: valores antigos salvos fora da faixa travavam o Slider.
            value: valor.clamp(min, max).toDouble(),
            divisions: (max - min) > 0 && (max - min) <= 200 ? max - min : null,
            activeColor: _accent,
            min: min.toDouble(),
            max: max.toDouble(),
            onChanged: (v) =>
                setState(() => config.set(cat, chave, v.toInt()))),
        const SizedBox(height: 20),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SELETOR DE LOCALIZAÇÃO (Clima) — Estado → Cidade em cascata
  // ═══════════════════════════════════════════════════════════════════════

  /// Busca a lista de municípios de um estado na API do IBGE.
  /// Resultado fica em cache na sessão (não busca de novo se já tiver).
  Future<List<String>> _municipiosDoEstado(String uf) async {
    if (_municipiosCache.containsKey(uf)) return _municipiosCache[uf]!;
    final res = await http
        .get(Uri.parse(
            'https://servicodados.ibge.gov.br/api/v1/localidades/estados/$uf/municipios'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('IBGE respondeu ${res.statusCode}');
    }
    final lista = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    final nomes = lista.map((m) => m['nome'] as String).toList()..sort();
    _municipiosCache[uf] = nomes;
    return nomes;
  }

  /// Converte "cidade + estado" em latitude/longitude usando a API de
  /// geocoding do Open-Meteo (mesma API já usada pra buscar o tempo —
  /// gratuita, sem necessidade de chave).
  Future<Map<String, double>?> _geocodificarCidade(
      String cidade, String uf) async {
    final res = await http
        .get(Uri.parse('https://geocoding-api.open-meteo.com/v1/search'
            '?name=${Uri.encodeQueryComponent(cidade)}'
            '&count=20&language=pt&format=json&country=BR'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    final resultados = data['results'] as List? ?? [];
    if (resultados.isEmpty) return null;

    final nomeEstado = estadosBrasil[uf] ?? '';
    // Prioriza o resultado cujo estado (admin1) bate com o selecionado —
    // importante porque várias cidades brasileiras têm nomes repetidos
    // em estados diferentes (ex: existem várias "Bom Jesus").
    final match = resultados.firstWhere(
      (r) => (r['admin1'] as String? ?? '')
          .toLowerCase()
          .contains(nomeEstado.toLowerCase()),
      orElse: () => resultados.first,
    );

    return {
      'lat': (match['latitude'] as num).toDouble(),
      'lon': (match['longitude'] as num).toDouble(),
    };
  }

  /// Fluxo completo: escolhe estado → escolhe cidade → geocodifica → salva.
  Future<void> _abrirSeletorLocalizacaoClima() async {
    final ufAtual = config.getString('clima', 'estado', 'SP');
    final uf = await _dialogSelecionarEstado(ufAtual);
    if (uf == null || !mounted) return;

    final cidade = await _dialogSelecionarCidade(uf);
    if (cidade == null || !mounted) return;

    setState(() {
      _geocodificando = true;
      _erroLocalizacao = null;
    });

    try {
      final coords = await _geocodificarCidade(cidade, uf);
      if (coords == null) {
        setState(() {
          _geocodificando = false;
          _erroLocalizacao = 'Não encontramos coordenadas para essa cidade.';
        });
        return;
      }
      setState(() {
        config.set('clima', 'cidade', cidade);
        config.set('clima', 'ibge', ''); // avisos da Defesa Civil: recalcula
        config.set('clima', 'estado', uf);
        config.set('clima', 'lat', coords['lat'].toString());
        config.set('clima', 'lon', coords['lon'].toString());
        _geocodificando = false;
      });
    } catch (e) {
      setState(() {
        _geocodificando = false;
        _erroLocalizacao = 'Falha ao buscar localização. Tente de novo.';
      });
    }
  }

  Future<String?> _dialogSelecionarEstado(String ufAtual) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF12141a),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('📍 Escolha o Estado'),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 3,
                      childAspectRatio: 2.6,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: estadosBrasil.entries.map((e) {
                        final sel = e.key == ufAtual;
                        return GestureDetector(
                          onTap: () => Navigator.pop(ctx, e.key),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: sel
                                  ? _accent.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: sel ? _accent : _border),
                            ),
                            child: Text(
                              e.key,
                              style: GoogleFonts.figtree(
                                color: sel ? _accent : Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: Text('Cancelar',
                        style: GoogleFonts.figtree(color: Colors.white60)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _dialogSelecionarCidade(String uf) {
    // Estado do diálogo vive AQUI (fora do builder do StatefulBuilder),
    // porque o builder interno roda de novo a cada setLocalState — variáveis
    // declaradas dentro dele seriam reiniciadas a cada rebuild.
    List<String>? municipios;
    String? erro;
    String busca = '';
    bool buscando = false;

    return showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocalState) {
          Future<void> carregar() async {
            buscando = true;
            try {
              final lista = await _municipiosDoEstado(uf);
              setLocalState(() {
                municipios = lista;
                buscando = false;
              });
            } catch (e) {
              setLocalState(() {
                erro = 'Falha ao buscar municípios.';
                buscando = false;
              });
            }
          }

          if (municipios == null && erro == null && !buscando) {
            carregar();
          }

          final filtrados = (municipios ?? [])
              .where((m) => m.toLowerCase().contains(busca.toLowerCase()))
              .toList();

          return Dialog(
            backgroundColor: const Color(0xFF12141a),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('🏙️ Cidades de ${estadosBrasil[uf]}'),
                    const SizedBox(height: 16),
                    if (municipios != null)
                      TextField(
                        style: GoogleFonts.figtree(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Buscar cidade...',
                          hintStyle: GoogleFonts.figtree(color: Colors.white54),
                          prefixIcon:
                              const Icon(Icons.search, color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setLocalState(() => busca = v),
                      ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: erro != null
                          ? Center(
                              child: Text(erro!,
                                  style: GoogleFonts.figtree(
                                      color: Colors.white60)))
                          : municipios == null
                              ? const Center(child: CircularProgressIndicator())
                              : ListView.builder(
                                  itemCount: filtrados.length,
                                  itemBuilder: (_, i) {
                                    final nome = filtrados[i];
                                    return ListTile(
                                      title: Text(nome,
                                          style: GoogleFonts.figtree(
                                              color: Colors.white70)),
                                      onTap: () => Navigator.pop(ctx, nome),
                                    );
                                  },
                                ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      child: Text('Cancelar',
                          style: GoogleFonts.figtree(color: Colors.white60)),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  /// Seletor de intervalo de atualização — usado em todas as categorias que
  /// buscam dado externo (clima, notícias, classificação, calendário, etc).
  /// Controla a cada quanto tempo a tela vai buscar dado novo na internet;
  /// fora desse intervalo, ela usa o que já está salvo em cache, sem gastar
  /// rede nem processamento — bom pra economizar bateria/RAM em tablets
  /// mais fracos.
  Widget _intervaloPicker(String cat) {
    final atual = config.getInt(cat, 'intervalo_atualizacao_min', 60);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.update_rounded, color: _accent, size: 16),
          const SizedBox(width: 8),
          Text('Atualizar dados a cada',
              style: GoogleFonts.figtree(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ConfigManager.opcoesIntervaloAtualizacao.map((o) {
            final min = o['min'] as int;
            final sel = atual == min;
            return GestureDetector(
              onTap: () => setState(
                  () => config.set(cat, 'intervalo_atualizacao_min', min)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel
                      ? _accent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? _accent : _border),
                ),
                child: Text(
                  o['label'] as String,
                  style: GoogleFonts.figtree(
                    color: sel ? _accent : Colors.white70,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildBomDiaConfig() {
    final horaInicio = config.getInt('bom_dia', 'hora_inicio', 4);
    final horaFim = config.getInt('bom_dia', 'hora_fim', 10);
    final tamanhoNome =
        double.tryParse(config.getString('bom_dia', 'tamanho_nome', '44.0')) ??
            44.0;
    final tamanhoTemp =
        double.tryParse(config.getString('bom_dia', 'tamanho_temp', '88.0')) ??
            88.0;
    final fonteAtual = config.getString('bom_dia', 'fonte', 'poppins');
    final corHex = config.getString('bom_dia', 'cor_destaque', '');

    // Mapa de cores predefinidas
    const coresDisponiveis = [
      {'label': 'Auto (clima)', 'hex': '', 'preview': Color(0xFF90CAF9)},
      {
        'label': 'Dourado ☀️',
        'hex': '0xFFFFD54F',
        'preview': Color(0xFFFFD54F)
      },
      {'label': 'Ciano 🌊', 'hex': '0xFF18FFFF', 'preview': Color(0xFF18FFFF)},
      {
        'label': 'Laranja 🔥',
        'hex': '0xFFFF6B35',
        'preview': Color(0xFFFF6B35)
      },
      {'label': 'Rosa 🌸', 'hex': '0xFFFF80AB', 'preview': Color(0xFFFF80AB)},
      {'label': 'Verde 🌿', 'hex': '0xFF69F0AE', 'preview': Color(0xFF69F0AE)},
      {'label': 'Branco ⬜', 'hex': '0xFFFFFFFF', 'preview': Color(0xFFFFFFFF)},
    ];

    const fontesDisponiveis2 = [
      {'key': 'poppins', 'label': 'Poppins', 'sample': 'Bom dia Gabriel'},
      {'key': 'rajdhani', 'label': 'Rajdhani', 'sample': 'Bom dia Gabriel'},
      {'key': 'orbitron', 'label': 'Orbitron', 'sample': 'Bom dia Gabriel'},
      {'key': 'exo2', 'label': 'Exo 2', 'sample': 'Bom dia Gabriel'},
      {'key': 'roboto', 'label': 'Roboto', 'sample': 'Bom dia Gabriel'},
    ];

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        // ── Identificação ────────────────────────────────────────────────
        _sectionTitle('👤 Nome na Saudação'),
        const SizedBox(height: 6),
        Text('Quem vai receber o bom dia?',
            style: GoogleFonts.figtree(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 14),
        _glassCard(children: [
          _textFieldConfig(
            'geral',
            'nome_usuario',
            'Nome',
            'Ex: Gabriel, Família, Meu amor…',
            Icons.person_rounded,
          ),
          const SizedBox(height: 4),
          Text(
              'Aparece como: "Bom dia ${config.getString('geral', 'nome_usuario', 'Gabriel')},"',
              style: GoogleFonts.figtree(
                  color: _accent.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontStyle: FontStyle.italic)),
        ]),

        const SizedBox(height: 28),

        // ── Horário ──────────────────────────────────────────────────────
        _sectionTitle('⏰ Horário de Exibição'),
        const SizedBox(height: 6),
        Text('Fora deste intervalo a tela é ignorada completamente.',
            style: GoogleFonts.figtree(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 14),
        _glassCard(children: [
          // Início
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A237E).withValues(alpha: 0.4),
                border: Border.all(color: _accent.withValues(alpha: 0.40)),
              ),
              child: const Icon(Icons.wb_twilight_rounded,
                  color: _accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Início',
                    style: GoogleFonts.figtree(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Text('A partir de qual hora a tela pode aparecer',
                    style: GoogleFonts.figtree(
                        color: Colors.white54, fontSize: 12)),
              ],
            )),
            _horaPicker(
              valor: horaInicio,
              min: 0,
              max: 11,
              onChanged: (v) =>
                  setState(() => config.set('bom_dia', 'hora_inicio', v)),
            ),
          ]),

          const Divider(color: Colors.white10, height: 28),

          // Fim
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orangeAccent.withValues(alpha: 0.15),
                border: Border.all(
                    color: Colors.orangeAccent.withValues(alpha: 0.45)),
              ),
              child: const Icon(Icons.wb_sunny_rounded,
                  color: Colors.orangeAccent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fim',
                    style: GoogleFonts.figtree(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Text('Até qual hora a tela ainda pode aparecer',
                    style: GoogleFonts.figtree(
                        color: Colors.white54, fontSize: 12)),
              ],
            )),
            _horaPicker(
              valor: horaFim,
              min: 1,
              max: 23,
              onChanged: (v) =>
                  setState(() => config.set('bom_dia', 'hora_fim', v)),
            ),
          ]),

          const SizedBox(height: 16),

          // Preview visual do intervalo
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accent.withValues(alpha: 0.18)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.access_time_rounded, color: _accent, size: 16),
              const SizedBox(width: 8),
              Text(
                'Ativa das ${horaInicio.toString().padLeft(2, '0')}:00'
                ' até ${horaFim.toString().padLeft(2, '0')}:00'
                '  •  ${horaFim - horaInicio}h de exibição',
                style: GoogleFonts.figtree(
                    color: _accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4),
              ),
            ]),
          ),
        ]),

        const SizedBox(height: 28),

        // ── Duração ──────────────────────────────────────────────────────
        _sectionTitle('⏱️ Tempo na Tela'),
        const SizedBox(height: 14),
        _glassCard(children: [
          _sliderInt(
              'bom_dia',
              'duracao_longa_seg',
              'Duração longa (início do dia)',
              config.getInt('bom_dia', 'duracao_longa_seg', 90),
              20,
              300,
              unidade: 's'),
          Text('Usado quando você ainda tem tempo para absorver tudo',
              style: GoogleFonts.figtree(color: Colors.white30, fontSize: 12)),
          const SizedBox(height: 16),
          _sliderInt(
              'bom_dia',
              'duracao_curta_seg',
              'Duração curta (final do horário)',
              config.getInt('bom_dia', 'duracao_curta_seg', 20),
              5,
              120,
              unidade: 's'),
          Text('Passagem rápida antes de sair para o trabalho',
              style: GoogleFonts.figtree(color: Colors.white30, fontSize: 12)),
        ]),

        const SizedBox(height: 28),

        // ── Fonte ────────────────────────────────────────────────────────
        _sectionTitle('🔤 Fonte'),
        const SizedBox(height: 6),
        Text('Afeta o nome, temperatura e todas as informações da tela.',
            style: GoogleFonts.figtree(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 14),
        ...fontesDisponiveis2.map((f) {
          final sel = fonteAtual == f['key'];
          TextStyle sample(String fk) {
            switch (fk) {
              case 'rajdhani':
                return GoogleFonts.rajdhani(
                    color: sel ? _accent : Colors.white60,
                    fontSize: 18,
                    fontWeight: FontWeight.w700);
              case 'orbitron':
                return GoogleFonts.orbitron(
                    color: sel ? _accent : Colors.white60,
                    fontSize: 15,
                    fontWeight: FontWeight.w600);
              case 'exo2':
                return GoogleFonts.exo2(
                    color: sel ? _accent : Colors.white60,
                    fontSize: 18,
                    fontWeight: FontWeight.w700);
              case 'roboto':
                return GoogleFonts.roboto(
                    color: sel ? _accent : Colors.white60,
                    fontSize: 18,
                    fontWeight: FontWeight.w500);
              default:
                return GoogleFonts.poppins(
                    color: sel ? _accent : Colors.white60,
                    fontSize: 18,
                    fontWeight: FontWeight.w600);
            }
          }

          return GestureDetector(
            onTap: () =>
                setState(() => config.set('bom_dia', 'fonte', f['key'])),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: sel
                    ? _accent.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? _accent.withValues(alpha: 0.45) : _border,
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f['label']!,
                            style: GoogleFonts.figtree(
                                color: sel ? _accent : Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6)),
                        const SizedBox(height: 4),
                        Text(f['sample']!,
                            style: sample(f['key']!)),
                      ]),
                ),
                if (sel)
                  const Icon(Icons.check_circle_rounded,
                      color: _accent, size: 22),
              ]),
            ),
          );
        }),

        const SizedBox(height: 28),

        // ── Tamanhos ─────────────────────────────────────────────────────
        _sectionTitle('📐 Tamanho dos Textos'),
        const SizedBox(height: 14),
        _glassCard(children: [
          _sliderDouble('bom_dia', 'tamanho_nome', 'Tamanho do nome',
              tamanhoNome, 28.0, 64.0,
              unidade: 'px'),
          Text('"Bom dia Gabriel" — quanto maior, mais impacto',
              style: GoogleFonts.figtree(color: Colors.white30, fontSize: 12)),
          const SizedBox(height: 16),
          _sliderDouble('bom_dia', 'tamanho_temp', 'Tamanho da temperatura',
              tamanhoTemp, 56.0, 120.0,
              unidade: 'px'),
          Text('O número enorme de graus no centro da tela',
              style: GoogleFonts.figtree(color: Colors.white30, fontSize: 12)),
        ]),

        const SizedBox(height: 28),

        // ── Cor de destaque ──────────────────────────────────────────────
        _sectionTitle('🎨 Cor de Destaque'),
        const SizedBox(height: 6),
        Text('Cor usada no seu nome e nos destaques da tela.',
            style: GoogleFonts.figtree(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: coresDisponiveis.map((cor) {
            final hex = cor['hex'] as String;
            final preview = cor['preview'] as Color;
            final sel = corHex == hex;
            return GestureDetector(
              onTap: () =>
                  setState(() => config.set('bom_dia', 'cor_destaque', hex)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel
                      ? preview.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: sel ? preview.withValues(alpha: 0.70) : _border,
                    width: sel ? 2 : 1,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hex.isEmpty ? Colors.transparent : preview,
                      border: hex.isEmpty
                          ? Border.all(color: Colors.white30, width: 1.5)
                          : null,
                      gradient: hex.isEmpty
                          ? const LinearGradient(
                              colors: [
                                Color(0xFFFFD54F),
                                Color(0xFF90CAF9),
                                Color(0xFF69F0AE)
                              ],
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(cor['label'] as String,
                      style: GoogleFonts.figtree(
                        color: sel ? preview : Colors.white60,
                        fontSize: 13,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      )),
                ]),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 28),

        // ── O que mostrar ────────────────────────────────────────────────
        _sectionTitle('👁️ O Que Mostrar'),
        const SizedBox(height: 14),
        _glassCard(children: [
          _toggleConfig(
            titulo: 'Foto do dia',
            subtitulo: 'Recordação puxada da pasta de Fotos — troca todo dia',
            categoria: 'bom_dia',
            chave: 'mostrar_foto',
            valorPadrao: true,
          ),
          const Divider(color: Colors.white10, height: 24),
          _toggleConfig(
            titulo: 'Notícia principal do dia',
            subtitulo: 'Busca em tempo real no G1 Globo',
            categoria: 'bom_dia',
            chave: 'mostrar_noticia',
            valorPadrao: true,
          ),
          const Divider(color: Colors.white10, height: 24),
          _toggleConfig(
            titulo: 'Frase / inspiração do dia',
            subtitulo: 'Frase motivacional ou filosófica diária',
            categoria: 'bom_dia',
            chave: 'mostrar_frase',
            valorPadrao: true,
          ),
          const Divider(color: Colors.white10, height: 24),
          _toggleConfig(
            titulo: 'Sensação térmica',
            subtitulo: 'Temperatura que o corpo realmente sente',
            categoria: 'bom_dia',
            chave: 'mostrar_sensacao',
            valorPadrao: true,
          ),
          const Divider(color: Colors.white10, height: 24),
          _toggleConfig(
            titulo: 'Alerta de chuva',
            subtitulo: 'Aparece quando há ≥30% de chance de chuva',
            categoria: 'bom_dia',
            chave: 'mostrar_chuva',
            valorPadrao: true,
          ),
          const Divider(color: Colors.white10, height: 24),
          _toggleConfig(
            titulo: 'Ler o resumo do dia em voz alta',
            subtitulo:
                'Uma vez por manhã, na primeira vez que a tela Bom Dia aparece',
            categoria: 'bom_dia',
            chave: 'falar_resumo',
            valorPadrao: false,
          ),
        ]),

        const SizedBox(height: 28),

        // ── Preview resumo ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              const Color(0xFFFFCC00).withValues(alpha: 0.08),
              const Color(0xFF18FFFF).withValues(alpha: 0.05),
            ]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFFFFCC00).withValues(alpha: 0.22)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🌅', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text('Resumo da configuração',
                  style: GoogleFonts.figtree(
                      color: const Color(0xFFFFCC00),
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            _resumoLinha(
                'Nome', config.getString('geral', 'nome_usuario', 'Gabriel')),
            _resumoLinha('Horário',
                '${horaInicio.toString().padLeft(2, '0')}:00 → ${horaFim.toString().padLeft(2, '0')}:00'),
            _resumoLinha(
                'Fonte',
                fontesDisponiveis2.firstWhere((f) => f['key'] == fonteAtual,
                            orElse: () => {'label': fonteAtual})['label'] ??
                    fonteAtual),
            _resumoLinha('Nome', '${tamanhoNome.round()}px'),
            _resumoLinha('Temp.', '${tamanhoTemp.round()}px'),
            _resumoLinha(
                'Cor', corHex.isEmpty ? 'Automática (segue o clima)' : corHex),
            _resumoLinha(
                'Mostra',
                [
                  if (config.getBool('bom_dia', 'mostrar_foto', true))
                    'foto do dia',
                  if (config.getBool('bom_dia', 'mostrar_noticia', true))
                    'notícia',
                  if (config.getBool('bom_dia', 'mostrar_frase', true)) 'frase',
                  if (config.getBool('bom_dia', 'mostrar_sensacao', true))
                    'sensação',
                  if (config.getBool('bom_dia', 'mostrar_chuva', true)) 'chuva',
                ].join(' • ')),
          ]),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  // ── _horaPicker: botões ± ─────────────────────────────────────────────────
  Widget _horaPicker({
    required int valor,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _horaBtn(Icons.remove_rounded, () {
        if (valor > min) onChanged(valor - 1);
      }),
      Container(
        width: 58,
        alignment: Alignment.center,
        child: Text(
          '${valor.toString().padLeft(2, '0')}h',
          style: GoogleFonts.bricolageGrotesque(
              color: _accent, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      _horaBtn(Icons.add_rounded, () {
        if (valor < max) onChanged(valor + 1);
      }),
    ]);
  }

  Widget _horaBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.07),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, color: Colors.white60, size: 18),
      ),
    );
  }

  // ── _sliderDouble ─────────────────────────────────────────────────────────
  Widget _sliderDouble(String cat, String chave, String label, double valor,
      double min, double max,
      {String unidade = ''}) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: GoogleFonts.figtree(color: Colors.white70)),
        Text('${valor.round()} $unidade',
            style: GoogleFonts.figtree(
                color: _accent, fontWeight: FontWeight.w700)),
      ]),
      Slider(
        value: valor,
        min: min,
        max: max,
        activeColor: _accent,
        onChanged: (v) =>
            setState(() => config.set(cat, chave, v.toStringAsFixed(1))),
      ),
      const SizedBox(height: 12),
    ]);
  }

  // ── _resumoLinha ──────────────────────────────────────────────────────────
  Widget _resumoLinha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: GoogleFonts.figtree(color: Colors.white54, fontSize: 13)),
        ),
        Expanded(
          child: Text(
            valor.isEmpty ? '—' : valor,
            style: GoogleFonts.figtree(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  void _showSnack(BuildContext context, String msg, {Color? corBorda}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.figtree(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: const Color(0xFF0d1420),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: corBorda ?? _accent.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  WebView de login em tela cheia — overlay por cima das configurações
// ─────────────────────────────────────────────────────────────────────────────
class _WebViewLoginOverlay extends StatefulWidget {
  final String redirectUri;
  final VoidCallback onFechar;
  final VoidCallback onSucesso;
  final void Function(String) onErro;

  const _WebViewLoginOverlay({
    required this.redirectUri,
    required this.onFechar,
    required this.onSucesso,
    required this.onErro,
  });

  @override
  State<_WebViewLoginOverlay> createState() => _WebViewLoginOverlayState();
}

class _WebViewLoginOverlayState extends State<_WebViewLoginOverlay> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final url = req.url;
          final isRedirect = widget.redirectUri.isNotEmpty &&
              (url.startsWith(widget.redirectUri) ||
                  url.startsWith('mliondroid://'));
          if (isRedirect) {
            final uri = Uri.parse(url);
            final code = uri.queryParameters['code'] ?? '';
            final error = uri.queryParameters['error'] ?? '';
            if (code.isNotEmpty) {
              SpotifyManager.instance.trocarCodePorToken(code).then((ok) {
                if (ok) {
                  widget.onSucesso();
                } else {
                  widget.onErro('Falha no login. Verifique os dados.');
                }
              });
            } else {
              widget.onErro(error.isNotEmpty ? error : 'Falha no login');
            }
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(SpotifyManager.instance.gerarUrlAutorizacao()));
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Container(
          color: const Color(0xFF080C14),
          child: SafeArea(
            child: Column(children: [
              Container(
                color: const Color(0xFF0a1a0a),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(children: [
                  const Icon(Icons.music_note_rounded, color: Color(0xFF1DB954), size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                        'Login Spotify — role para baixo para autorizar',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ),
                  GestureDetector(
                    onTap: widget.onFechar,
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white60, size: 26),
                  ),
                ]),
              ),
              Expanded(
                child: WebViewWidget(
                  controller: _controller,
                  gestureRecognizers: {
                    Factory<VerticalDragGestureRecognizer>(
                      () => VerticalDragGestureRecognizer(),
                    ),
                    Factory<HorizontalDragGestureRecognizer>(
                      () => HorizontalDragGestureRecognizer(),
                    ),
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = const Color(0xFF080C14);
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), p);
    p.shader = RadialGradient(colors: [
      const Color(0xFF00D4FF).withValues(alpha: 0.08),
      Colors.transparent
    ]).createShader(Rect.fromCircle(
        center: Offset(s.width * 0.8, s.height * 0.2), radius: s.width * 0.3));
    canvas.drawCircle(Offset(s.width * 0.8, s.height * 0.2), s.width * 0.3, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
