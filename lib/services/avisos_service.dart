import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../cache_manager.dart';
import '../config_manager.dart';
import '../util.dart';
import 'weather_service.dart';

/// Gravidade de um aviso. Os níveis oficiais seguem o INMET:
/// Perigo Potencial (amarelo) → Perigo (laranja) → Grande Perigo (vermelho).
enum NivelAviso { tranquilo, informativo, atencao, perigo, grandePerigo }

class Aviso {
  final String titulo;
  final String detalhe;
  final NivelAviso nivel;
  final IconData icone;
  final String fonte; // "Defesa Civil / INMET" ou "Previsão"
  const Aviso(this.titulo, this.detalhe, this.nivel, this.icone, this.fonte);

  /// Avisos graves ganham destaque visual (o "choque" na tela).
  bool get grave => nivel == NivelAviso.perigo || nivel == NivelAviso.grandePerigo;
}

/// Junta avisos oficiais (INMET — os mesmos que a Defesa Civil usa) e
/// avisos calculados a partir da previsão (tempestade, chuva forte,
/// calor, umidade baixa, vento, frio). Ordena do mais grave ao mais leve.
class AvisosService {
  AvisosService._();
  static final AvisosService instance = AvisosService._();

  final _cfg = ConfigManager();

  Future<List<Aviso>> avisos([DateTime? agora]) async {
    final now = agora ?? DateTime.now();
    final lista = <Aviso>[...await _oficiais(now)];
    final clima = WeatherService.instance.atual ?? await WeatherService.instance.obter();
    if (clima != null) lista.addAll(daPrevisao(clima, now));
    lista.sort((a, b) => b.nivel.index.compareTo(a.nivel.index));
    if (lista.isEmpty) {
      lista.add(const Aviso('Sem alertas para hoje', 'Tempo firme pelo resto do dia',
          NivelAviso.tranquilo, Icons.wb_sunny_rounded, 'Previsão'));
    }
    return lista;
  }

  // ── Avisos calculados pela previsão (função pura, testada) ───────────────
  static List<Aviso> daPrevisao(DadosClima c, DateTime agora) {
    final avisos = <Aviso>[];

    // Tempestade nas próximas 12 horas (código WMO 95–99).
    final proximas = c.proximasHoras(12, agora);
    final tempestade = proximas.where((h) => h.codigo >= 95).toList();
    if (tempestade.isNotEmpty) {
      avisos.add(Aviso('Tempestade às ${tempestade.first.hora.hour}h',
          'Raios e vento forte',
          NivelAviso.perigo, Icons.thunderstorm_rounded, 'Previsão'));
    }

    // Chuva hoje (horários) — e chuva forte pelo volume do dia.
    final chuva = c.chuvaRestanteHoje(agora);
    final hoje = c.hoje;
    if (chuva.horarios.isNotEmpty && tempestade.isEmpty) {
      final horas = chuva.horarios.take(3).map((h) => '${h.hour}h').toList();
      final quando = horas.length == 1
          ? horas.first
          : '${horas.sublist(0, horas.length - 1).join(', ')} e ${horas.last}';
      final forte = (hoje?.chuvaMm ?? 0) >= 30;
      avisos.add(Aviso(
          forte ? 'Chuva forte às $quando' : 'Chuva às $quando',
          forte
              ? 'Até ${hoje!.chuvaMm.round()} mm, risco de alagamento'
              : 'Até ${chuva.maxima}% de chance',
          forte ? NivelAviso.perigo : NivelAviso.atencao,
          Icons.umbrella_rounded,
          'Previsão'));
    }

    // Calor forte na semana.
    if (c.dias.isNotEmpty) {
      final maisQuente = c.dias.reduce((a, b) => b.max > a.max ? b : a);
      if (maisQuente.max >= 32) {
        final quando = soData(maisQuente.dia) == soData(agora)
            ? 'hoje'
            : diaSemanaLongo(maisQuente.dia).toLowerCase();
        avisos.add(Aviso('Calor forte: ${maisQuente.max}° $quando',
            'Evite o sol das 10h às 16h',
            maisQuente.max >= 36 ? NivelAviso.perigo : NivelAviso.atencao,
            Icons.local_fire_department_rounded, 'Previsão'));
      }
    }

    // Umidade baixa (régua da Defesa Civil).
    final umidade = [
      if (hoje != null && hoje.umidadeMin > 0) hoje,
      if (c.proximosDias.isNotEmpty && c.proximosDias.first.umidadeMin > 0)
        c.proximosDias.first,
    ];
    if (umidade.isNotEmpty) {
      final secoDia = umidade.reduce((a, b) => b.umidadeMin < a.umidadeMin ? b : a);
      final u = secoDia.umidadeMin;
      if (u < 30) {
        final quando = soData(secoDia.dia) == soData(agora) ? 'hoje' : 'amanhã';
        avisos.add(Aviso(
            'Umidade baixa: $u% $quando',
            u < 12
                ? 'Emergência: evite sair e beba água'
                : 'Beba água e umidifique a casa',
            u < 12
                ? NivelAviso.grandePerigo
                : (u < 20 ? NivelAviso.perigo : NivelAviso.atencao),
            Icons.water_drop_outlined,
            'Previsão'));
      }
    }

    // Vento forte.
    if (hoje != null && hoje.rajadaMax >= 60) {
      avisos.add(Aviso('Rajadas de ${hoje.rajadaMax} km/h hoje',
          'Recolha objetos soltos',
          hoje.rajadaMax >= 80 ? NivelAviso.perigo : NivelAviso.atencao,
          Icons.air_rounded, 'Previsão'));
    }

    // Frio.
    if (c.proximosDias.isNotEmpty) {
      final amanha = c.proximosDias.first;
      if (amanha.min <= 8) {
        avisos.add(Aviso('Frio: ${amanha.min}° amanhã cedo', 'Agasalhe-se e proteja os pets',
            amanha.min <= 3 ? NivelAviso.perigo : NivelAviso.atencao,
            Icons.ac_unit_rounded, 'Previsão'));
      }
    }
    return avisos;
  }

  // ── Avisos oficiais (INMET / Defesa Civil) ───────────────────────────────
  Future<List<Aviso>> _oficiais(DateTime agora) async {
    final ibge = await _codigoIbge();
    if (ibge == null) return [];
    final entrada = await buscarComCache<List<dynamic>>(
      chave: 'avisos_inmet_$ibge',
      validade: const Duration(minutes: 30),
      buscar: () async {
        final res = await http
            .get(Uri.parse('https://apiprevmet3.inmet.gov.br/avisos/ativos'))
            .timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) throw Exception('INMET ${res.statusCode}');
        return filtrarInmet(
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>, ibge);
      },
    );
    final unico = consolidarInmet(
        (entrada?.dados ?? []).cast<Map<String, dynamic>>(), agora);
    return [if (unico != null) unico];
  }

  /// O INMET publica vários avisos em sequência para a mesma região (0h,
  /// 0h01, 0h02…, um por tipo de risco). Na tela vira UM aviso só: o tipo e a
  /// cor do mais grave, o horário de início mais cedo e o fim mais tarde.
  /// Função pura — testada.
  static Aviso? consolidarInmet(List<Map<String, dynamic>> avisos, DateTime agora) {
    DateTime? data(Object? v) => DateTime.tryParse('$v'.replaceFirst(' ', 'T'));
    int peso(Map<String, dynamic> m) {
      final sev = '${m['severidade'] ?? ''}'.toLowerCase();
      final base = sev.contains('grande') ? 30 : (sev == 'perigo' ? 20 : 10);
      // No mesmo nível, tempestade fala mais alto que "acumulado de chuva".
      return base + (normalizar('${m['descricao']}').contains('tempestade') ? 1 : 0);
    }

    final ativos = avisos.where((m) {
      final fim = data(m['fim']);
      return fim == null || fim.isAfter(agora);
    }).toList();
    if (ativos.isEmpty) return null;

    final principal = ativos.reduce((a, b) => peso(b) > peso(a) ? b : a);
    DateTime? inicio;
    DateTime? fim;
    for (final m in ativos) {
      final i = data(m['inicio']);
      final f = data(m['fim']);
      if (i != null && (inicio == null || i.isBefore(inicio))) inicio = i;
      if (f != null && (fim == null || f.isAfter(fim))) fim = f;
    }
    return avisoInmet({
      ...principal,
      'inicio': inicio?.toIso8601String(),
      'fim': fim?.toIso8601String(),
    }, agora);
  }

  /// Guarda só os avisos que incluem o município (pelo código IBGE), num
  /// formato enxuto. Função pura — testada.
  static List<Map<String, dynamic>> filtrarInmet(Map<String, dynamic> json, String ibge) {
    final r = <Map<String, dynamic>>[];
    for (final grupo in ['hoje', 'futuro']) {
      for (final a in (json[grupo] as List? ?? []).cast<Map<String, dynamic>>()) {
        final codigos = '${a['geocodes'] ?? ''}'.split(',').map((s) => s.trim());
        if (!codigos.contains(ibge)) continue;
        r.add({
          'descricao': a['descricao'],
          'severidade': a['severidade'],
          'riscos': a['riscos'],
          'inicio': a['inicio'],
          'fim': a['fim'],
        });
      }
    }
    return r;
  }

  /// Aviso oficial em versão curta, para ler de longe:
  /// "Defesa Civil: Tempestade" / "Alerta laranja até terça, 23h59".
  static Aviso avisoInmet(Map<String, dynamic> m, [DateTime? agora]) {
    final now = agora ?? DateTime.now();
    final sev = '${m['severidade'] ?? ''}'.toLowerCase();
    final nivel = sev.contains('grande')
        ? NivelAviso.grandePerigo
        : sev == 'perigo'
            ? NivelAviso.perigo
            : NivelAviso.atencao;
    // Cores oficiais do INMET para cada nível.
    final cor = switch (nivel) {
      NivelAviso.grandePerigo => 'vermelho',
      NivelAviso.perigo => 'laranja',
      _ => 'amarelo',
    };
    final descricao = '${m['descricao'] ?? 'Aviso meteorológico'}';
    final inicio = DateTime.tryParse('${m['inicio']}'.replaceFirst(' ', 'T'));
    final fim = DateTime.tryParse('${m['fim']}'.replaceFirst(' ', 'T'));
    final String quando;
    if (inicio != null && inicio.isAfter(now)) {
      quando = ' a partir de ${quandoCurto(inicio, now)}';
    } else if (fim != null) {
      quando = ' até ${quandoCurto(fim, now)}';
    } else {
      quando = '';
    }
    final d = normalizar(descricao);
    final icone = d.contains('tempestade')
        ? Icons.thunderstorm_rounded
        : d.contains('chuva')
            ? Icons.umbrella_rounded
            : d.contains('umidade')
                ? Icons.water_drop_outlined
                : d.contains('calor') || d.contains('temperatura')
                    ? Icons.local_fire_department_rounded
                    : d.contains('vento') || d.contains('vendaval')
                        ? Icons.air_rounded
                        : Icons.warning_amber_rounded;
    return Aviso('Defesa Civil: $descricao', 'Alerta $cor$quando', nivel, icone, 'INMET');
  }

  /// "23h59", "amanhã, 6h" ou "terça, 23h59".
  static String quandoCurto(DateTime d, DateTime agora) {
    final hora = d.minute == 0 ? '${d.hour}h' : '${d.hour}h${doisDigitos(d.minute)}';
    final dias = soData(d).difference(soData(agora)).inDays;
    if (dias == 0) return hora;
    if (dias == 1) return 'amanhã, $hora';
    return '${diaSemanaLongo(d).split('-').first.toLowerCase()}, $hora';
  }

  /// Código IBGE da cidade configurada (resolvido uma vez e guardado).
  Future<String?> _codigoIbge() async {
    final salvo = _cfg.getString('clima', 'ibge', '');
    if (salvo.isNotEmpty) return salvo;
    final cidade = _cfg.getString('clima', 'cidade', 'Hortolândia');
    final uf = _cfg.getString('clima', 'estado', 'SP');
    final entrada = await buscarComCache<String>(
      chave: 'ibge_${uf}_${normalizar(cidade)}',
      validade: const Duration(days: 3650),
      buscar: () async {
        final res = await http
            .get(Uri.parse(
                'https://servicodados.ibge.gov.br/api/v1/localidades/estados/$uf/municipios'))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) throw Exception('IBGE ${res.statusCode}');
        final lista = jsonDecode(utf8.decode(res.bodyBytes)) as List;
        final alvo = normalizar(cidade);
        for (final m in lista) {
          if (normalizar('${m['nome']}') == alvo) return '${m['id']}';
        }
        return null;
      },
    );
    return entrada?.dados;
  }
}

/// Cor de cada nível de aviso.
Color corDoNivel(NivelAviso n) => switch (n) {
      NivelAviso.tranquilo => const Color(0xFF6FD6A0),
      NivelAviso.informativo => const Color(0xFF7CC6FF),
      NivelAviso.atencao => const Color(0xFFFF7A59), // coral: chama atenção
      NivelAviso.perigo => const Color(0xFFFF4B3E),
      NivelAviso.grandePerigo => const Color(0xFFE5243B),
    };
