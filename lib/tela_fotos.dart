import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'config_manager.dart';
import 'performance_manager.dart';
import 'responsive.dart';
import 'services/fotos_service.dart';

/// "Memórias": slideshow das fotos adicionadas ao app.
///
/// Mostra [fotos_por_visita] fotos, cada uma por [duracao_por_foto_seg]
/// (antes era uma única foto por 30s e essa configuração era ignorada).
class TelaFotos extends StatefulWidget {
  final VoidCallback aoTerminar;
  const TelaFotos({super.key, required this.aoTerminar});

  @override
  State<TelaFotos> createState() => _TelaFotosState();
}

class _TelaFotosState extends State<TelaFotos>
    with SingleTickerProviderStateMixin {
  final _cfg = ConfigManager();
  late final AnimationController _kenBurns =
      AnimationController(vsync: this, duration: const Duration(seconds: 12));

  List<String> _fotos = [];
  int _indice = 0;
  bool _carregando = true;
  Timer? _trocaTimer;

  int get _segPorFoto => _cfg.getInt('fotos', 'duracao_por_foto_seg', 8).clamp(3, 60);
  int get _porVisita => _cfg.getInt('fotos', 'fotos_por_visita', 4).clamp(1, 30);

  @override
  void initState() {
    super.initState();
    if (PerformanceManager.instance.animacoesDecorativasAtivas) {
      _kenBurns.repeat(reverse: true);
    }
    _carregar();
  }

  @override
  void dispose() {
    _kenBurns.dispose();
    _trocaTimer?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    final fotos = await FotosService.instance.sortear(_porVisita);
    if (!mounted) return;
    setState(() {
      _fotos = fotos;
      _indice = 0;
      _carregando = false;
    });
    if (fotos.isEmpty) {
      _trocaTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) widget.aoTerminar();
      });
      return;
    }
    if (fotos.length > 1 && mounted) {
      // Já decodifica a próxima para a troca ser instantânea.
      precacheImage(_provider(fotos[1]), context);
    }
    _agendarTroca();
  }

  void _agendarTroca() {
    _trocaTimer?.cancel();
    _trocaTimer = Timer(Duration(seconds: _segPorFoto), () {
      if (!mounted) return;
      if (_indice + 1 >= _fotos.length) {
        widget.aoTerminar();
        return;
      }
      setState(() => _indice++);
      if (_indice + 1 < _fotos.length) {
        precacheImage(_provider(_fotos[_indice + 1]), context);
      }
      _agendarTroca();
    });
  }

  ImageProvider _provider(String path) => ResizeImage(
        FileImage(File(path)),
        width: PerformanceManager.instance.resolucaoMaximaDecodificacao,
        policy: ResizeImagePolicy.fit,
      );

  Future<void> _adicionar() async {
    _trocaTimer?.cancel();
    try {
      final n = await FotosService.instance.adicionarDoSeletor();
      if (n > 0) {
        setState(() => _carregando = true);
        await _carregar();
        return;
      }
    } catch (e) {
      debugPrint('TelaFotos adicionar: $e');
    }
    _agendarTroca();
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    if (_carregando) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_fotos.isEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: GestureDetector(
            onTap: _adicionar,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_photo_alternate_rounded,
                    color: Colors.white70, size: r.icon(80)),
                const SizedBox(height: 20),
                Text('Toque para adicionar fotos às Memórias',
                    style: TextStyle(color: Colors.white, fontSize: r.fs(20))),
              ],
            ),
          ),
        ),
      );
    }

    final atual = _fotos[_indice];
    return ColoredBox(
      color: Colors.black,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 1200),
        child: _FotoComMoldura(
          key: ValueKey(atual),
          imagem: _provider(atual),
          kenBurns: _kenBurns,
          rodape: _rodape(r),
          aoAdicionar: _adicionar,
        ),
      ),
    );
  }

  Widget _rodape(R r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: r.icon(18)),
        const SizedBox(width: 8),
        Text('Memórias  ${_indice + 1}/${_fotos.length}',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: r.fs(17),
                fontWeight: FontWeight.w300)),
      ],
    );
  }
}

class _FotoComMoldura extends StatelessWidget {
  final ImageProvider imagem;
  final AnimationController kenBurns;
  final Widget rodape;
  final VoidCallback aoAdicionar;

  const _FotoComMoldura({
    super.key,
    required this.imagem,
    required this.kenBurns,
    required this.rodape,
    required this.aoAdicionar,
  });

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final perf = PerformanceManager.instance;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fundo: a própria foto desfocada. Fica PARADA (sem Ken Burns) e
        // dentro de um RepaintBoundary — assim o desfoque é calculado uma
        // vez, não a cada quadro como antes (BackdropFilter sobre imagem
        // animada era o efeito mais caro desta tela).
        RepaintBoundary(
          child: perf.preferirOverlaySolido
              ? Image(image: imagem, fit: BoxFit.cover)
              : ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Image(image: imagem, fit: BoxFit.cover),
                ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: perf.preferirOverlaySolido ? 0.62 : 0.45)),
        RepaintBoundary(
          child: Center(
          child: Container(
            width: r.w(r.isCompact ? 0.92 : 0.85),
            height: r.h(r.isCompact ? 0.55 : 0.75),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r.radius(36)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: perf.sombrasReduzidas ? 18 : 40,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(r.radius(36)),
              child: AnimatedBuilder(
                animation: kenBurns,
                builder: (_, child) =>
                    Transform.scale(scale: 1.0 + kenBurns.value * 0.12, child: child),
                child: Image(image: imagem, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
          ),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: GestureDetector(
            onTap: aoAdicionar,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_photo_alternate_rounded,
                      color: Colors.white70, size: r.icon(22)),
                  const SizedBox(width: 8),
                  Text('Adicionar fotos',
                      style: TextStyle(color: Colors.white70, fontSize: r.fs(13))),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 15,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: rodape,
          ),
        ),
      ],
    );
  }
}
