import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'responsive.dart';
import 'performance_manager.dart'; // ← NOVO
import 'package:file_picker/file_picker.dart';

class TelaFotos extends StatefulWidget {
  final VoidCallback aoTerminar;

  const TelaFotos({
    super.key,
    required this.aoTerminar,
  });

  @override
  State<TelaFotos> createState() => _TelaFotosState();
}

class _TelaFotosState extends State<TelaFotos>
    with SingleTickerProviderStateMixin {
  String? _fotoExibida;
  bool _carregando = true;
  late AnimationController _animationController;
  Timer? _trocaTelaTimer;

  // Lido uma vez ao entrar na tela — se o usuário mudar a chave em
  // Configurações, o efeito novo passa a valer na próxima vez que esta
  // tela for reconstruída (próxima rodada da sequência).
  bool get _economico => PerformanceManager.instance.modoEconomico;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    // ── Ken Burns só roda em loop no modo visual completo. No modo
    // econômico o controller existe (widgets ainda podem referenciá-lo)
    // mas fica parado em 0 — sem repaint contínuo em imagem grande.
    if (!_economico) {
      _animationController.repeat(reverse: true);
    }

    _carregarUmaFoto();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _trocaTelaTimer?.cancel();
    super.dispose();
  }

  /// BUG CORRIGIDO: era Timer.periodic — chamava aoTerminar() infinitamente.
  /// Agora é Timer simples: dispara uma única vez após 30 segundos.
  void _iniciarTimerSaida() {
    _trocaTelaTimer?.cancel();
    _trocaTelaTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) widget.aoTerminar();
    });
  }

  Future<void> _selecionarFotos() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null) {
        final pastaDestino =
            Directory('/storage/emulated/0/Pictures/MlionDroid');

        if (!await pastaDestino.exists()) {
          await pastaDestino.create(recursive: true);
        }

        for (var file in result.files) {
          if (file.path != null) {
            final origem = File(file.path!);
            final destino = File('${pastaDestino.path}/${file.name}');
            await origem.copy(destino.path);
          }
        }
        await _carregarUmaFoto();
      }
    } catch (e) {
      debugPrint('Erro ao selecionar fotos: $e');
    }
  }

  Future<void> _carregarUmaFoto() async {
    try {
      final diretorio = Directory('/storage/emulated/0/Pictures/MlionDroid');

      if (!await diretorio.exists()) {
        await diretorio.create(recursive: true);
      }

      final arquivos = diretorio.listSync();

      List<String> caminhosValidos = arquivos
          .where((item) =>
              item.path.toLowerCase().endsWith('.jpg') ||
              item.path.toLowerCase().endsWith('.png') ||
              item.path.toLowerCase().endsWith('.jpeg'))
          .map((item) => item.path)
          .toList();

      if (caminhosValidos.isNotEmpty && mounted) {
        setState(() {
          _fotoExibida =
              caminhosValidos[Random().nextInt(caminhosValidos.length)];
          _carregando = false;
        });
        _iniciarTimerSaida();
      } else {
        if (mounted) {
          setState(() {
            _carregando = false;
            _fotoExibida = null;
          });
          // Sai rápido se não tem fotos
          _trocaTelaTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) widget.aoTerminar();
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar foto: $e');
      if (mounted) {
        setState(() => _carregando = false);
        _trocaTelaTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) widget.aoTerminar();
        });
      }
    }
  }

  Widget _buildFotoPremium(String path) {
    final r = R(context);
    final perf = PerformanceManager.instance;

    // ── Decodifica a imagem já limitada ao tamanho máximo necessário.
    // Evita carregar na memória uma foto de 12MP+ quando ela só vai
    // ocupar uma fração da tela — ajuda tanto RAM quanto tempo de decode.
    final image = ResizeImage(
      FileImage(File(path)),
      width: perf.resolucaoMaximaDecodificacao,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // FUNDO — no modo visual completo: blur + Ken Burns animado.
        // No modo econômico: imagem estática + overlay sólido (sem
        // BackdropFilter, que é o item mais caro desta tela).
        ClipRect(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final scale = perf.animacoesDecorativasAtivas
                  ? 1.05 + (_animationController.value * 0.02)
                  : 1.05;
              return Transform.scale(
                scale: scale,
                child: Image(image: image, fit: BoxFit.cover),
              );
            },
          ),
        ),
        if (perf.preferirOverlaySolido)
          // Overlay sólido — visualmente "escurece e acalma" o fundo
          // de forma parecida ao blur, mas sem custo de GPU por pixel.
          Container(color: Colors.black.withValues(alpha: 0.62))
        else
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: perf.sigmaBlur(45),
                sigmaY: perf.sigmaBlur(45),
              ),
              child: Container(color: Colors.black.withValues(alpha: 0.50)),
            ),
          ),

        // GRADIENTE DE PROFUNDIDADE (barato — mantém em qualquer modo)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.25),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.30),
              ],
            ),
          ),
        ),

        // BOTÃO DA GALERIA — posicionado abaixo da barra com SafeArea
        Positioned(
          top: 12,
          left: 12,
          child: SafeArea(
            child: GestureDetector(
              onTap: _selecionarFotos,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/icons/google_photos.png',
                        width: r.icon(22), height: r.icon(22)),
                    const SizedBox(width: 8),
                    Text(
                      'Galeria',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.90),
                        fontSize: r.fs(13),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // CARD CENTRAL COM EFEITO KEN BURNS (só anima no modo completo)
        Center(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final kenBurnsScale = perf.animacoesDecorativasAtivas
                  ? 1.0 + (_animationController.value * 0.15)
                  : 1.0;
              return Container(
                width: r.w(r.isCompact ? 0.92 : 0.85),
                height: r.h(r.isCompact ? 0.55 : 0.75),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(r.radius(36)),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: perf.sombrasReduzidas ? 18 : 50,
                      spreadRadius: perf.sombrasReduzidas ? 1 : 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(r.radius(36)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Transform.scale(
                        scale: kenBurnsScale,
                        child: Image(image: image, fit: BoxFit.cover),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.center,
                              radius: 1.0,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.2),
                              ],
                              stops: const [0.6, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 140,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.12),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // LABEL MEMÓRIAS (Canto Inferior Direito)
        Positioned(
          bottom: 15,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome,
                    color: Colors.cyanAccent, size: r.icon(18)),
                const SizedBox(width: 8),
                Text(
                  'Memórias',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: r.fs(17),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    if (_carregando) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_fotoExibida == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: GestureDetector(
            onTap: _selecionarFotos,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/icons/google_photos.png',
                    width: r.icon(70)),
                const SizedBox(height: 20),
                const Text(
                  'Toque para adicionar fotos',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Sem Scaffold — o MlionShell já gerencia o layout com BarraInfo no topo.
    // ClipRect garante que o BackdropFilter não vaze para fora da área da tela.
    return ColoredBox(
      color: Colors.black,
      child: _buildFotoPremium(_fotoExibida!),
    );
  }
}
