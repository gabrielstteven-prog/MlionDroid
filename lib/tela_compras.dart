import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'config_manager.dart';
import 'cache_manager.dart';
import 'responsive.dart';
import 'performance_manager.dart';

// ─── CLIENTE HTTP ─────────────────────────────────────────────────────────────
class _AuthClient extends http.BaseClient {
  final Map<String, String> _h;
  final http.Client _inner = http.Client();
  _AuthClient(this._h);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) {
    r.headers.addAll(_h);
    return _inner.send(r);
  }
}

// ─── MODELO ───────────────────────────────────────────────────────────────────
class ItemCompra {
  final String id;
  final String listaId;
  final String titulo;
  bool marcando = false; // animação de carregamento

  ItemCompra({
    required this.id,
    required this.listaId,
    required this.titulo,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'listaId': listaId, 'titulo': titulo};

  factory ItemCompra.fromJson(Map<String, dynamic> j) => ItemCompra(
        id: j['id'] as String? ?? '',
        listaId: j['listaId'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
      );
}

// Cores vibrantes para os cards — cada item tem uma cor diferente
const List<Color> _coresItens = [
  Color(0xFF18FFFF), // ciano neon
  Color(0xFF00E676), // verde neon
  Color(0xFFFFD740), // amarelo ouro
  Color(0xFFFF6D00), // laranja vibrante
  Color(0xFFE040FB), // roxo neon
  Color(0xFFFF4081), // rosa neon
  Color(0xFF40C4FF), // azul claro
  Color(0xFFCCFF90), // verde limão
  Color(0xFFFF6E40), // coral
  Color(0xFFEA80FC), // lilás
];

// ─────────────────────────────────────────────────────────────────────────────
class TelaCompras extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaCompras({super.key, required this.aoTerminar});

  @override
  State<TelaCompras> createState() => _TelaComprasState();
}

class _TelaComprasState extends State<TelaCompras>
    with TickerProviderStateMixin {
  final _cfg = ConfigManager();
  // ── DADOS ─────────────────────────────────────────────────────────────────
  List<ItemCompra> _itens = [];
  bool _carregando = true;
  String _statusMsg = 'Buscando lista de compras...';
  String _nomeListaEncontrada = '';

  // ── AUTH ──────────────────────────────────────────────────────────────────
  _AuthClient? _client;
  final _googleSignIn = GoogleSignIn(
    scopes: [tasks.TasksApi.tasksScope],
  );

  // ── SCROLL AUTOMÁTICO ─────────────────────────────────────────────────────
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _scrollTimer;

  // ── TIMERS ────────────────────────────────────────────────────────────────
  Timer? _saidaTimer;
  Timer? _updateTimer;

  // ── ANIMAÇÕES ─────────────────────────────────────────────────────────────
  late AnimationController _bgCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _entradaCtrl;
  late Animation<double> _entradaAnim;

  // Nomes aceitos para a lista de compras
  static const _nomesAceitos = [
    'compras',
    'compra',
    'lista de compras',
    'shopping',
    'shopping list',
    'mercado',
    'supermercado',
  ];

  @override
  void initState() {
    super.initState();

    _bgCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 6));

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    if (!PerformanceManager.instance.modoEconomico) {
      _bgCtrl.repeat(reverse: true);
      _pulseCtrl.repeat(reverse: true);
    }

    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _entradaAnim =
        CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOutCubic);
    _entradaCtrl.forward();

    _autenticarECarregar();

    // Anti-travamento
    Timer(const Duration(minutes: 2), () {
      if (mounted) widget.aoTerminar();
    });
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _pulseCtrl.dispose();
    _entradaCtrl.dispose();
    _scrollCtrl.dispose();
    _scrollTimer?.cancel();
    _saidaTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  // ── AUTH ──────────────────────────────────────────────────────────────────
  static const _chaveCache = 'compras_itens';

  Future<void> _autenticarECarregar() async {
    try {
      setState(() => _statusMsg = 'Autenticando...');
      final conta =
          await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (conta == null) {
        setState(() {
          _carregando = false;
          _statusMsg = 'Login cancelado';
        });
        _iniciarSaida(10);
        return;
      }
      // _client fica pronto mesmo em cache hit — necessário para marcar
      // itens como comprados direto na tela.
      _client = _AuthClient(await conta.authHeaders);

      final cache = await CacheManager.instance.obter<Map<String, dynamic>>(
        _chaveCache,
        validade: _cfg.getIntervaloAtualizacao('compras'),
      );
      if (cache != null && mounted) {
        setState(() {
          _itens = (cache['itens'] as List)
              .map((e) => ItemCompra.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _nomeListaEncontrada = cache['nomeLista'] as String? ?? '';
          _carregando = false;
        });
        _iniciarScrollAutomatico();
        _updateTimer = Timer.periodic(
            _cfg.getIntervaloAtualizacao('compras'), (_) => _carregarItens());
        _iniciarSaida(30);
        return;
      }

      await _carregarItens();
      _updateTimer = Timer.periodic(
          _cfg.getIntervaloAtualizacao('compras'), (_) => _carregarItens());
      _iniciarSaida(30);
    } catch (e) {
      debugPrint('TelaCompras erro: $e');
      setState(() {
        _carregando = false;
        _statusMsg = 'Erro ao conectar';
      });
      _iniciarSaida(8);
    }
  }

  Future<void> _carregarItens() async {
    if (_client == null) return;
    try {
      final api = tasks.TasksApi(_client!);
      final listas = await api.tasklists.list();

      tasks.TaskList? listaAlvo;
      for (final lista in listas.items ?? []) {
        final nomeMin = (lista.title ?? '').toLowerCase().trim();
        if (_nomesAceitos.any((n) => nomeMin.contains(n))) {
          listaAlvo = lista;
          break;
        }
      }

      listaAlvo ??=
          listas.items?.isNotEmpty == true ? listas.items!.first : null;

      if (listaAlvo == null || listaAlvo.id == null) {
        setState(() {
          _carregando = false;
          _nomeListaEncontrada = '';
        });
        return;
      }

      // Busca APENAS pendentes — sem itens comprados
      final tl = await api.tasks.list(
        listaAlvo.id!,
        showCompleted: false,
        showHidden: false,
      );

      final novosItens = (tl.items ?? [])
          .where((t) => t.status != 'completed' && t.title != null)
          .map((t) => ItemCompra(
                id: t.id ?? '',
                listaId: listaAlvo!.id!,
                titulo: t.title!,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _itens = novosItens;
          _nomeListaEncontrada = listaAlvo!.title ?? 'Compras';
          _carregando = false;
        });
        _iniciarScrollAutomatico();
      }
      await _salvarCache();
    } catch (e) {
      debugPrint('TelaCompras _carregarItens: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvarCache() async {
    await CacheManager.instance.salvar(_chaveCache, {
      'itens': _itens.map((i) => i.toJson()).toList(),
      'nomeLista': _nomeListaEncontrada,
    });
  }

  // ── MARCAR COMO COMPRADO ──────────────────────────────────────────────────
  Future<void> _marcarComprado(ItemCompra item) async {
    if (_client == null || item.id.isEmpty) return;
    if (item.marcando) return;

    _saidaTimer?.cancel();

    setState(() => item.marcando = true);

    try {
      final api = tasks.TasksApi(_client!);
      final taskAtual = await api.tasks.get(item.listaId, item.id);
      taskAtual.status = 'completed';
      await api.tasks.update(taskAtual, item.listaId, item.id);

      // Pequeno delay para feedback visual
      await Future.delayed(const Duration(milliseconds: 600));

      if (mounted) {
        setState(() => _itens.removeWhere((i) => i.id == item.id));
        await _salvarCache();
      }
    } catch (e) {
      debugPrint('TelaCompras marcar erro: $e');
      if (mounted) setState(() => item.marcando = false);
    } finally {
      _iniciarSaida(25);
    }
  }

  // ── SCROLL AUTOMÁTICO ─────────────────────────────────────────────────────
  void _iniciarScrollAutomatico() {
    _scrollTimer?.cancel();
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);

    _scrollTimer = Timer(const Duration(seconds: 4), () async {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (max < 100) return;

      // Velocidade lenta para ler confortavelmente
      final dur = (max / 40).clamp(8, 60).toInt();
      await _scrollCtrl.animateTo(max,
          duration: Duration(seconds: dur), curve: Curves.linear);

      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      await _scrollCtrl.animateTo(0,
          duration: const Duration(seconds: 2), curve: Curves.easeOut);
    });
  }

  void _iniciarSaida(int seg) {
    _saidaTimer?.cancel();
    _saidaTimer = Timer(Duration(seconds: seg), () {
      if (mounted) widget.aoTerminar();
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fundo animado
          Positioned.fill(child: _buildFundo()),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          FadeTransition(
            opacity: _entradaAnim,
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(r),
                  Expanded(
                      child:
                          _carregando ? _buildCarregando(r) : _buildCorpo(r)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── FUNDO ANIMADO ─────────────────────────────────────────────────────────
  Widget _buildFundo() {
    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (_, __) => CustomPaint(
        painter: _BgPainter(_bgCtrl.value),
        child: const SizedBox.expand(),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader(R r) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: PerformanceManager.instance.sigmaBlur(20),
          sigmaY: PerformanceManager.instance.sigmaBlur(20),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            border: Border(
                bottom: BorderSide(
                    color: const Color(0xFF00E676).withValues(alpha: 0.4),
                    width: 1.5)),
          ),
          child: Row(
            children: [
              // Ícone carrinho com glow
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF18FFFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF00E676)
                              .withValues(alpha: _pulseAnim.value * 0.7),
                          blurRadius: 20,
                          spreadRadius: 3)
                    ],
                  ),
                  child: Icon(Icons.shopping_cart_rounded,
                      color: Colors.black, size: r.icon(26)),
                ),
              ),
              const SizedBox(width: 16),
              // Título
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nomeListaEncontrada.isEmpty
                          ? 'LISTA DE COMPRAS'
                          : _nomeListaEncontrada.toUpperCase(),
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: r.fs(22),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5),
                    ),
                    Text(
                      _itens.isEmpty
                          ? 'Tudo comprado! 🎉'
                          : '${_itens.length} item${_itens.length != 1 ? 's' : ''} para comprar',
                      style: GoogleFonts.poppins(
                          color: const Color(0xFF00E676).withValues(alpha: 0.8),
                          fontSize: r.fs(13),
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CARREGANDO ────────────────────────────────────────────────────────────
  Widget _buildCarregando(R r) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [Color(0xFF00E676), Color(0xFF18FFFF)]),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF00E676)
                          .withValues(alpha: _pulseAnim.value * 0.7),
                      blurRadius: 28,
                      spreadRadius: 4)
                ],
              ),
              child: Icon(Icons.shopping_basket_rounded,
                  color: Colors.black, size: r.icon(40)),
            ),
          ),
          const SizedBox(height: 20),
          Text(_statusMsg,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }

  // ── CORPO ─────────────────────────────────────────────────────────────────
  Widget _buildCorpo(R r) {
    if (_itens.isEmpty) return _buildListaVazia(r);

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: _itens.length,
      itemBuilder: (_, i) => _buildItemCard(_itens[i], i, r),
    );
  }

  // ── CARD DE ITEM — GRANDE E VIBRANTE ──────────────────────────────────────
  Widget _buildItemCard(ItemCompra item, int index, R r) {
    final cor = _coresItens[index % _coresItens.length];
    final marcando = item.marcando;

    return GestureDetector(
      onTap: () => _marcarComprado(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 14),
        height: r.isCompact ? r.sp(72) : r.sp(95),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              cor.withValues(alpha: marcando ? 0.08 : 0.15),
              cor.withValues(alpha: marcando ? 0.04 : 0.06),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          border: Border.all(
            color: cor.withValues(alpha: marcando ? 0.3 : 0.6),
            width: marcando ? 1.5 : 2,
          ),
          boxShadow: marcando
              ? null
              : [
                  BoxShadow(
                      color: cor.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: PerformanceManager.instance.sigmaBlur(8),
              sigmaY: PerformanceManager.instance.sigmaBlur(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Row(
                children: [
                  // Número do item
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cor.withValues(alpha: 0.15),
                      border: Border.all(
                          color: cor.withValues(alpha: 0.5), width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: GoogleFonts.poppins(
                            color: cor,
                            fontSize: r.fs(17),
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),

                  // Nome do item — FONTE GRANDE
                  Expanded(
                    child: Text(
                      item.titulo,
                      style: GoogleFonts.poppins(
                        color: marcando
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.white,
                        fontSize:
                            r.fs(26), // fonte bem grande para ler de longe
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        shadows: [
                          Shadow(
                              color: cor.withValues(alpha: 0.3), blurRadius: 8),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Botão de marcar / loading
                  marcando
                      ? SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: cor.withValues(alpha: 0.8)),
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cor.withValues(alpha: 0.12),
                            border: Border.all(
                                color: cor.withValues(alpha: 0.5), width: 2),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            color: cor.withValues(alpha: 0.7),
                            size: 24,
                          ),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── LISTA VAZIA ───────────────────────────────────────────────────────────
  Widget _buildListaVazia(R r) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [Color(0xFF00E676), Color(0xFF18FFFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF00E676)
                          .withValues(alpha: _pulseAnim.value * 0.6),
                      blurRadius: 30,
                      spreadRadius: 6)
                ],
              ),
              child: Icon(Icons.check_rounded,
                  color: Colors.black, size: r.icon(52)),
            ),
          ),
          const SizedBox(height: 28),
          Text('Tudo comprado!',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: r.fs(32),
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Sua lista está vazia 🎉',
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: 18)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(
              '"Ok Google, adicionar [item]\nna lista de tarefas Compras"',
              style: GoogleFonts.poppins(
                  color: Colors.white38, fontSize: r.fs(14), height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FUNDO ANIMADO ────────────────────────────────────────────────────────────
class _BgPainter extends CustomPainter {
  final double t;
  _BgPainter(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..style = PaintingStyle.fill;

    // Base escura
    p.color = const Color(0xFF04080F);
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), p);

    void orb(Offset c, double r, Color cor, double op) {
      p.shader = RadialGradient(
              colors: [cor.withValues(alpha: op), Colors.transparent])
          .createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, p);
    }

    final wave = math.sin(t * math.pi);

    // Orb verde pulsante
    orb(Offset(s.width * 0.15, s.height * (0.2 + wave * 0.05)), s.width * 0.35,
        const Color(0xFF00E676), 0.10);

    // Orb ciano
    orb(Offset(s.width * 0.85, s.height * (0.3 - wave * 0.04)), s.width * 0.30,
        const Color(0xFF18FFFF), 0.08);

    // Orb âmbar
    orb(Offset(s.width * 0.50, s.height * (0.75 + wave * 0.03)), s.width * 0.28,
        const Color(0xFFFFD740), 0.07);

    // Orb roxo suave
    orb(Offset(s.width * 0.80, s.height * (0.80 - wave * 0.03)), s.width * 0.22,
        const Color(0xFFE040FB), 0.06);
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.t != t;
}
