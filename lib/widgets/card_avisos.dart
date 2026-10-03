import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tema.dart';
import '../performance_manager.dart';
import '../responsive.dart';
import '../services/avisos_service.dart';

/// Card de avisos do clima. Alterna entre os avisos a cada 6s.
/// Avisos graves (tempestade, chuva forte, Defesa Civil) chegam com um
/// "choque": a tela pisca na cor do aviso e o card treme; depois a borda
/// segue pulsando enquanto ele estiver visível.
class CardAvisos extends StatefulWidget {
  final List<Aviso> avisos;

  /// Chamado quando todos os avisos já passaram pela tela ao menos uma vez
  /// (com um aviso só, logo depois de ele aparecer). A tela de clima espera
  /// por isso antes de seguir para a próxima.
  final VoidCallback? aoCompletarCiclo;

  static const tempoPorAviso = Duration(seconds: 6);

  const CardAvisos({super.key, required this.avisos, this.aoCompletarCiclo});

  @override
  State<CardAvisos> createState() => _CardAvisosState();
}

class _CardAvisosState extends State<CardAvisos> with TickerProviderStateMixin {
  int _indice = 0;
  int _vistos = 0;
  Timer? _troca;
  late final AnimationController _choque = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _pulso = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  bool get _animar => PerformanceManager.instance.animacoesDecorativasAtivas;
  Aviso get _atual => widget.avisos[_indice % widget.avisos.length];

  @override
  void initState() {
    super.initState();
    _recomecar();
  }

  @override
  void didUpdateWidget(CardAvisos old) {
    super.didUpdateWidget(old);
    // Os avisos oficiais chegam depois dos da previsão: a lista muda e o
    // rodízio recomeça do primeiro (antes o relógio só nascia no initState
    // e o card ficava parado no primeiro aviso).
    final mudou = old.avisos.length != widget.avisos.length ||
        !_mesmosTitulos(old.avisos, widget.avisos);
    if (!mudou) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recomecar();
    });
  }

  static bool _mesmosTitulos(List<Aviso> a, List<Aviso> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i].titulo != b[i].titulo) return false;
    }
    return true;
  }

  void _recomecar() {
    _troca?.cancel();
    _vistos = 0;
    _mostrar(0);
    _troca = Timer.periodic(CardAvisos.tempoPorAviso, (_) {
      if (mounted) _passar(1);
    });
  }

  /// Avança (ou volta) um aviso. O toque e o deslize vertical usam isto.
  void _passar(int passo) {
    _vistos++;
    if (_vistos >= widget.avisos.length) widget.aoCompletarCiclo?.call();
    if (widget.avisos.length > 1) _mostrar(_indice + passo);
  }

  void _naMao(int passo) {
    if (widget.avisos.length < 2) return;
    _troca?.cancel();
    _passar(passo);
    _troca = Timer.periodic(CardAvisos.tempoPorAviso, (_) {
      if (mounted) _passar(1);
    });
  }

  void _mostrar(int i) {
    final n = widget.avisos.length;
    setState(() => _indice = ((i % n) + n) % n);
    if (_atual.grave && _animar) {
      _choque.forward(from: 0);
      _pulso.repeat(reverse: true);
    } else {
      _pulso.stop();
      _pulso.value = 0;
    }
  }

  @override
  void dispose() {
    _troca?.cancel();
    _choque.dispose();
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final t = Tipo(r);
    final aviso = _atual;
    final cor = corDoNivel(aviso.nivel);
    final tranquilo = aviso.nivel == NivelAviso.tranquilo;

    return GestureDetector(
      // Toque ou deslize para cima/baixo passa os avisos na mão.
      behavior: HitTestBehavior.opaque,
      onTap: () => _naMao(1),
      onVerticalDragEnd: (d) => _naMao((d.primaryVelocity ?? 0) > 0 ? -1 : 1),
      child: AnimatedBuilder(
        animation: Listenable.merge([_choque, _pulso]),
        builder: (context, filho) {
          // Choque: 3 piscadas + tremida curta no início.
          final c = _choque.value;
          final piscada = _choque.isAnimating
              ? (math.sin(c * math.pi * 6).abs() * (1 - c))
              : 0.0;
          final tremida = _choque.isAnimating
              ? math.sin(c * math.pi * 14) * 8 * (1 - c)
              : 0.0;
          final pulso = _pulso.value;
          return Transform.translate(
            offset: Offset(tremida, 0),
            child: Container(
              decoration: BoxDecoration(
                // Cor sólida (não transparente): sobre o céu azul, transparência
                // deixava o coral arroxeado e apagado.
                color: Color.lerp(
                    tranquilo
                        ? cor.withValues(alpha: 0.16)
                        : Color.lerp(cor, const Color(0xFF1A0E10), 0.38)!,
                    cor,
                    piscada * 0.85),
                borderRadius: BorderRadius.circular(r.sp(22)),
                border: Border.all(
                  color: cor.withValues(
                      alpha: tranquilo ? 0.45 : 0.75 + 0.25 * pulso),
                  width: aviso.grave ? 2.5 + 2 * pulso : 2,
                ),
              ),
              child: filho,
            ),
          );
        },
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: r.sp(20), vertical: r.sp(16)),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: Row(
              key: ValueKey('${aviso.titulo}$_indice'),
              children: [
                Icon(aviso.icone,
                    color: tranquilo ? cor : Cores.texto, size: r.icon(42)),
                SizedBox(width: r.sp(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(aviso.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.subtitulo()),
                      Text(aviso.detalhe,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.apoio(cor: Cores.texto)),
                    ],
                  ),
                ),
                if (widget.avisos.length > 1) ...[
                  SizedBox(width: r.sp(12)),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.avisos.length; i++)
                        Container(
                          width: r.sp(8),
                          height: r.sp(8),
                          margin: EdgeInsets.symmetric(vertical: r.sp(2)),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _indice
                                ? Cores.texto
                                : Cores.texto.withValues(alpha: 0.3),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
