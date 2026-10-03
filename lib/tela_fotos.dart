import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'config_manager.dart';
import 'design/tema.dart';
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

  int get _segPorFoto =>
      _cfg.getInt('fotos', 'duracao_por_foto_seg', 8).clamp(3, 60);
  int get _porVisita =>
      _cfg.getInt('fotos', 'fotos_por_visita', 4).clamp(1, 30);

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

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    if (_carregando) return const Carregando(cor: Destaques.fotos);
    if (_fotos.isEmpty) {
      return const EstruturaTela(
        icone: Icons.photo_library_rounded,
        titulo: 'Memórias',
        destaque: Destaques.fotos,
        child: AvisoTela(
          icone: Icons.add_photo_alternate_rounded,
          titulo: 'Nenhuma foto ainda',
          texto: 'Adicione fotos em Configurações, na parte Memórias. Elas '
              'aparecem aqui e como "Recordação do dia" no Bom Dia.',
          cor: Destaques.fotos,
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
        ),
      ),
    );
  }

  /// Selo das Memórias no canto da foto, no estilo "stories": o título e uma
  /// barrinha por foto (a atual acesa). Com muitas fotos vira "3 de 40".
  Widget _rodape(R r) {
    final t = Tipo(r);
    final total = _fotos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome_rounded,
              color: Destaques.fotos, size: r.icon(26)),
          SizedBox(width: r.sp(10)),
          Text('Memórias', style: t.subtitulo()),
          if (total > 12) ...[
            SizedBox(width: r.sp(12)),
            Text('${_indice + 1} de $total', style: t.apoio()),
          ],
        ]),
        if (total > 1 && total <= 12) ...[
          SizedBox(height: r.sp(10)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < total; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: r.sp(i == _indice ? 36 : 18),
                height: r.sp(5),
                margin: EdgeInsets.only(right: r.sp(6)),
                decoration: BoxDecoration(
                  color: i == _indice
                      ? Cores.texto
                      : Cores.texto.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(r.sp(3)),
                ),
              ),
          ]),
        ],
      ],
    );
  }
}

class _FotoComMoldura extends StatelessWidget {
  final ImageProvider imagem;
  final AnimationController kenBurns;
  final Widget rodape;

  const _FotoComMoldura({
    super.key,
    required this.imagem,
    required this.kenBurns,
    required this.rodape,
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
        ColoredBox(
            color: Colors.black
                .withValues(alpha: perf.preferirOverlaySolido ? 0.62 : 0.45)),
        RepaintBoundary(
          child: Center(
            child: Container(
              width: r.w(r.isCompact ? 0.92 : 0.85),
              height: r.h(r.isCompact ? 0.55 : 0.75),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(r.radius(36)),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: perf.sombrasReduzidas ? 18 : 40,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(r.radius(36)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedBuilder(
                      animation: kenBurns,
                      builder: (_, child) => Transform.scale(
                          scale: 1.0 + kenBurns.value * 0.12, child: child),
                      child: Image(
                          image: imagem,
                          fit: BoxFit.cover,
                          gaplessPlayback: true),
                    ),
                    // Degradê embaixo para o selo ler bem sobre qualquer foto.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: r.sp(170),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xB3000000)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(left: r.sp(28), bottom: r.sp(24), child: rodape),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
