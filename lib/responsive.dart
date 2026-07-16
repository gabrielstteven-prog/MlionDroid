// ─────────────────────────────────────────────────────────────────────────────
//  responsive.dart — utilitário de responsividade para MlionDroid
//
//  Uso:
//    final r = R(context);
//    r.w(0.5)       → 50% da largura da tela
//    r.h(0.3)       → 30% da altura da tela
//    r.fs(18)       → fontSize 18 escalado pelo menor lado da tela
//    r.sp(16)       → padding/spacing escalado
//    r.icon(32)     → ícone escalado
//    r.useSideBySide → true em tablets landscape; false em celular/retrato
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class R {
  final BuildContext context;
  late final double _sw;
  late final double _sh;
  late final double _shortSide;
  late final double _longSide;
  late final double _base;
  late final EdgeInsets _padding;
  late final bool _isPortrait;

  R(this.context) {
    final size = MediaQuery.of(context).size;
    _sw = size.width;
    _sh = size.height;
    _shortSide = _sw < _sh ? _sw : _sh;
    _longSide = _sw < _sh ? _sh : _sw;
    _isPortrait = _sh > _sw;
    _padding = MediaQuery.of(context).padding;

    // Referência: tablet 10" landscape (~1280x800). Escala pelo menor lado.
    _base = (_shortSide / 800.0).clamp(0.55, 1.35);
  }

  /// Largura proporcional (desconta padding horizontal do SafeArea)
  double w(double frac) => _sw * frac;

  /// Altura proporcional (desconta padding vertical do SafeArea)
  double h(double frac) => _sh * frac;

  double get sw => _sw;
  double get sh => _sh;
  double get shortSide => _shortSide;
  double get longSide => _longSide;

  bool get isPortrait => _isPortrait;
  bool get isLandscape => !_isPortrait;

  /// Celular ou tela estreita (< 600px no menor lado)
  bool get isCompact => _shortSide < 600;

  /// Tablet médio/grande (>= 900px no menor lado)
  bool get isLarge => _shortSide >= 900;

  /// Layout lado a lado (mapa + painel, calendário + lista, etc.)
  bool get useSideBySide => !isCompact && !isPortrait && _sw >= 720;

  /// Largura útil após SafeArea
  double get usableWidth => _sw - _padding.left - _padding.right;

  /// Altura útil após SafeArea
  double get usableHeight => _sh - _padding.top - _padding.bottom;

  /// Container principal padrão das telas (96% x 92% com limites)
  double get panelWidth =>
      (usableWidth * (isCompact ? 0.98 : 0.96)).clamp(280.0, usableWidth);

  double get panelHeight =>
      (usableHeight * (isCompact ? 0.96 : 0.92)).clamp(400.0, usableHeight);

  /// Divisor decorativo — nunca maior que a tela
  double dividerWidth([double fraction = 0.45]) =>
      (usableWidth * fraction).clamp(120.0, 350.0);

  double fs(double size) => (size * _base).clamp(size * 0.55, size * 1.35);

  double sp(double size) => (size * _base).clamp(size * 0.45, size * 1.5);

  double icon(double size) => (size * _base).clamp(size * 0.6, size * 1.3);

  double radius(double r) => (r * _base).clamp(r * 0.55, r * 1.4);

  /// Altura mínima de cards de notícia adaptada à tela
  double newsCardHeight([double frac = 0.21]) {
    if (isCompact) return (usableHeight * 0.14).clamp(88.0, 130.0);
    return (usableHeight * frac).clamp(100.0, 220.0);
  }

  /// Padding padrão das bordas
  EdgeInsets screenPadding({double horizontal = 20, double vertical = 14}) {
    return EdgeInsets.symmetric(
      horizontal: sp(horizontal),
      vertical: sp(vertical),
    );
  }
}
