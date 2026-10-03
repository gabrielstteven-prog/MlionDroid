import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Utilitários compartilhados — antes copiados em várias telas.
// ─────────────────────────────────────────────────────────────────────────────

const _comAcento = 'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ';
const _semAcento = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';

/// Remove acentos, deixa minúsculo e troca pontuação por espaço.
/// "São Paulo" → "sao paulo", "Athletico-PR" → "athletico pr".
String normalizar(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = _comAcento.indexOf(ch);
    b.write(i >= 0 ? _semAcento[i] : ch);
  }
  return b
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9 ]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// true se [texto] menciona [termo] como palavra(s) inteira(s), ignorando
/// acentos e maiúsculas. "Sumaré" casa com "...em Sumaré, ..." mas
/// "Paulo" não casa com "Paulínia".
bool mencionaTermo(String texto, String termo) {
  final t = normalizar(termo);
  if (t.isEmpty) return false;
  return RegExp('(^| )${RegExp.escape(t)}( |\$)').hasMatch(normalizar(texto));
}

/// Converte "0xFF00441B" em Color, com fallback.
Color parseCor(dynamic raw, int fallback) {
  try {
    if (raw is String && raw.isNotEmpty) return Color(int.parse(raw));
    if (raw is int) return Color(raw);
  } catch (_) {}
  return Color(fallback);
}

const diasSemanaCurtos = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
const diasSemanaLongos = [
  'Segunda-feira',
  'Terça-feira',
  'Quarta-feira',
  'Quinta-feira',
  'Sexta-feira',
  'Sábado',
  'Domingo',
];
const mesesCurtos = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

const mesesLongos = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String diaSemanaCurto(DateTime d) => diasSemanaCurtos[d.weekday - 1];
String diaSemanaLongo(DateTime d) => diasSemanaLongos[d.weekday - 1];

String doisDigitos(int n) => n.toString().padLeft(2, '0');
String horaMinuto(DateTime d) => '${doisDigitos(d.hour)}:${doisDigitos(d.minute)}';

DateTime soData(DateTime d) => DateTime(d.year, d.month, d.day);

/// "HOJE", "AMANHÃ" ou "EM 5 DIAS" — calculado pela data civil, não por
/// múltiplos de 24h (um jogo amanhã às 21h a partir de hoje 8h é "AMANHÃ").
String etiquetaDias(DateTime data, [DateTime? agora]) {
  final dias = soData(data).difference(soData(agora ?? DateTime.now())).inDays;
  if (dias <= 0) return 'HOJE';
  if (dias == 1) return 'AMANHÃ';
  return 'EM $dias DIAS';
}

/// Limpa HTML de descrições de RSS.
String limparHtml(String s) => s
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
