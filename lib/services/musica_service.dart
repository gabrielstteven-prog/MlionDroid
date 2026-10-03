import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../cache_manager.dart';

class LinhaLetra {
  final Duration tempo;
  final String texto;
  const LinhaLetra(this.tempo, this.texto);
}

class Letra {
  final List<LinhaLetra> linhas; // vazio se só houver letra sem tempo
  final String simples;
  const Letra(this.linhas, this.simples);
  bool get sincronizada => linhas.isNotEmpty;

  /// Índice da linha que está sendo cantada em [posicao].
  int indiceEm(Duration posicao) {
    var idx = -1;
    for (var i = 0; i < linhas.length; i++) {
      if (linhas[i].tempo <= posicao) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }
}

/// Letras (LRCLIB — gratuito, sem chave) e cor da capa para o Spotify.
class MusicaService {
  MusicaService._();
  static final MusicaService instance = MusicaService._();

  /// "[00:20.32] Todos os dias quando acordo" → LinhaLetra. Função pura.
  static List<LinhaLetra> parseLrc(String lrc) {
    final linhas = <LinhaLetra>[];
    final re = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\](.*)');
    for (final l in const LineSplitter().convert(lrc)) {
      final m = re.firstMatch(l.trim());
      if (m == null) continue;
      final frac = m.group(3) ?? '0';
      final ms = int.parse(frac.padRight(3, '0').substring(0, 3));
      linhas.add(LinhaLetra(
        Duration(
            minutes: int.parse(m.group(1)!),
            seconds: int.parse(m.group(2)!),
            milliseconds: ms),
        m.group(4)!.trim(),
      ));
    }
    linhas.sort((a, b) => a.tempo.compareTo(b.tempo));
    return linhas;
  }

  Future<Letra?> letra({
    required String id,
    required String titulo,
    required String artista,
    required String album,
    required int duracaoMs,
  }) async {
    if (titulo.isEmpty) return null;
    final entrada = await buscarComCache<Map<String, dynamic>>(
      chave: 'letra_$id',
      validade: const Duration(days: 60),
      buscar: () async {
        final principal = artista.split(',').first.trim();
        final uri = Uri.https('lrclib.net', '/api/get', {
          'track_name': titulo,
          'artist_name': principal,
          if (album.isNotEmpty) 'album_name': album,
          if (duracaoMs > 0) 'duration': '${(duracaoMs / 1000).round()}',
        });
        final res = await http.get(uri, headers: {
          'User-Agent': 'MlionDroid Center (painel para tablet)'
        }).timeout(const Duration(seconds: 10));
        if (res.statusCode == 404) return {'sincronizada': '', 'simples': ''};
        if (res.statusCode != 200) throw Exception('LRCLIB ${res.statusCode}');
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return {
          'sincronizada': j['syncedLyrics'] as String? ?? '',
          'simples': j['plainLyrics'] as String? ?? '',
        };
      },
    );
    if (entrada == null) return null;
    final sinc = entrada.dados['sincronizada'] as String? ?? '';
    final simples = entrada.dados['simples'] as String? ?? '';
    if (sinc.isEmpty && simples.isEmpty) return null;
    return Letra(parseLrc(sinc), simples);
  }

  /// Cor marcante da capa (média das cores mais saturadas), escurecida o
  /// bastante para texto branco continuar legível por cima.
  static Future<Color?> corDaCapa(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24, targetHeight: 24);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      double r = 0, g = 0, b = 0, peso = 0;
      for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
        final c = HSLColor.fromColor(Color.fromARGB(
            255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)));
        // Prioriza cores vivas e de luminosidade média.
        final w = c.saturation * (1 - (c.lightness - 0.5).abs() * 2) + 0.02;
        r += data.getUint8(i) * w;
        g += data.getUint8(i + 1) * w;
        b += data.getUint8(i + 2) * w;
        peso += w;
      }
      final media = Color.fromARGB(
          255, (r / peso).round(), (g / peso).round(), (b / peso).round());
      final hsl = HSLColor.fromColor(media);
      return hsl
          .withLightness(hsl.lightness.clamp(0.18, 0.32))
          .withSaturation((hsl.saturation * 1.1).clamp(0.0, 0.85))
          .toColor();
    } catch (_) {
      return null;
    }
  }
}
