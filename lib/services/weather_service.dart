import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../cache_manager.dart';
import '../config_manager.dart';

/// Previsão de um dia.
class PrevisaoDia {
  final DateTime dia;
  final int max;
  final int min;
  final int chanceChuva;
  final int codigo;
  const PrevisaoDia(this.dia, this.max, this.min, this.chanceChuva, this.codigo);
}

/// Dados de clima já interpretados. Construído a partir do JSON bruto do
/// Open-Meteo (que é o que fica salvo no cache).
class DadosClima {
  final int temp;
  final int sensacao;
  final int codigo;
  final bool ehDia;
  final List<PrevisaoDia> dias; // dias[0] = hoje
  final List<DateTime> horas;
  final List<int> chuvaPorHora;
  final DateTime atualizadoEm;

  const DadosClima({
    required this.temp,
    required this.sensacao,
    required this.codigo,
    required this.ehDia,
    required this.dias,
    required this.horas,
    required this.chuvaPorHora,
    required this.atualizadoEm,
  });

  PrevisaoDia? get hoje => dias.isNotEmpty ? dias.first : null;
  List<PrevisaoDia> get proximosDias => dias.length > 1 ? dias.sublist(1) : [];

  /// Maior chance de chuva no resto do dia e os horários com chance ≥ 30%.
  /// Calculado na hora de exibir (não no momento da busca), para não ficar
  /// mostrando horários que já passaram.
  ({int maxima, List<DateTime> horarios}) chuvaRestanteHoje([DateTime? agora]) {
    final now = agora ?? DateTime.now();
    var maxima = 0;
    final horarios = <DateTime>[];
    for (var i = 0; i < horas.length && i < chuvaPorHora.length; i++) {
      final h = horas[i];
      if (h.isAfter(now) && h.day == now.day && h.month == now.month) {
        final p = chuvaPorHora[i];
        if (p > maxima) maxima = p;
        if (p >= 30) horarios.add(h);
      }
    }
    return (maxima: maxima, horarios: horarios);
  }

  static int _int(dynamic v, [int fb = 0]) => (v as num?)?.round() ?? fb;

  static DadosClima? fromJson(Map<String, dynamic> d, DateTime atualizadoEm) {
    final cur = d['current'] as Map<String, dynamic>?;
    if (cur == null) return null;
    final daily = d['daily'] as Map<String, dynamic>? ?? {};
    final hourly = d['hourly'] as Map<String, dynamic>? ?? {};

    final diasRaw = (daily['time'] as List?) ?? [];
    final dias = <PrevisaoDia>[];
    for (var i = 0; i < diasRaw.length; i++) {
      List l(String k) => (daily[k] as List?) ?? const [];
      dias.add(PrevisaoDia(
        DateTime.tryParse(diasRaw[i] as String) ?? DateTime.now(),
        _int(l('temperature_2m_max').elementAtOrNull(i)),
        _int(l('temperature_2m_min').elementAtOrNull(i)),
        _int(l('precipitation_probability_max').elementAtOrNull(i)),
        _int(l('weather_code').elementAtOrNull(i)),
      ));
    }

    return DadosClima(
      temp: _int(cur['temperature_2m']),
      sensacao: _int(cur['apparent_temperature']),
      codigo: _int(cur['weather_code']),
      ehDia: _int(cur['is_day'], 1) == 1,
      dias: dias,
      horas: ((hourly['time'] as List?) ?? [])
          .map((t) => DateTime.tryParse(t as String) ?? DateTime(2000))
          .toList(),
      chuvaPorHora: ((hourly['precipitation_probability'] as List?) ?? [])
          .map((p) => _int(p))
          .toList(),
      atualizadoEm: atualizadoEm,
    );
  }
}

/// Fonte única de clima do app. A barra superior, a tela de Clima e o
/// Bom Dia leem daqui — uma só requisição para os três.
class WeatherService extends ChangeNotifier {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  final _cfg = ConfigManager();
  DadosClima? _atual;
  Future<DadosClima?>? _emAndamento;

  DadosClima? get atual => _atual;

  String get _lat => _cfg.getString('clima', 'lat', '-22.889');
  String get _lon => _cfg.getString('clima', 'lon', '-47.222');
  String get _chave => 'clima_${_lat}_$_lon';

  /// Retorna o clima, buscando na internet só se o dado tiver mais que
  /// [maxIdade]. Sem internet, devolve o último dado conhecido.
  Future<DadosClima?> obter({Duration? maxIdade, bool forcar = false}) {
    final validade =
        maxIdade ?? _cfg.getIntervaloAtualizacao('clima');
    final emMemoria = _atual;
    if (!forcar &&
        emMemoria != null &&
        DateTime.now().difference(emMemoria.atualizadoEm) < validade) {
      return Future.value(emMemoria);
    }
    // Várias telas pedindo ao mesmo tempo → uma requisição só.
    return _emAndamento ??= _buscar(validade, forcar).whenComplete(() {
      _emAndamento = null;
    });
  }

  Future<DadosClima?> _buscar(Duration validade, bool forcar) async {
    final entrada = await buscarComCache<Map<String, dynamic>>(
      chave: _chave,
      validade: validade,
      forcar: forcar,
      buscar: () async {
        final url = Uri.parse('https://api.open-meteo.com/v1/forecast'
            '?latitude=$_lat&longitude=$_lon'
            '&current=temperature_2m,apparent_temperature,weather_code,is_day'
            '&hourly=precipitation_probability'
            '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
            '&forecast_days=6'
            '&timezone=America%2FSao_Paulo');
        final res = await http.get(url).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) {
          throw Exception('Open-Meteo respondeu ${res.statusCode}');
        }
        return jsonDecode(res.body) as Map<String, dynamic>;
      },
    );
    if (entrada == null) return _atual;
    final dados = DadosClima.fromJson(entrada.dados, entrada.salvoEm);
    if (dados != null) {
      _atual = dados;
      notifyListeners();
    }
    return _atual;
  }

  /// Chamado quando o usuário troca de cidade nas configurações.
  void localizacaoMudou() {
    _atual = null;
    unawaited(obter(forcar: true));
  }
}

/// Emoji simples por código WMO, considerando dia/noite.
String emojiClima(int code, {bool ehDia = true}) {
  if (code == 0) return ehDia ? '☀️' : '🌙';
  if (code <= 2) return ehDia ? '⛅' : '☁️';
  if (code == 3) return '☁️';
  if (code <= 48) return '🌫️';
  if (code <= 67) return '🌧️';
  if (code <= 77) return '❄️';
  if (code <= 82) return '🌦️';
  if (code <= 86) return '❄️';
  return '⛈️';
}

/// Descrição em português do código WMO.
String descricaoClima(int code) {
  if (code == 0) return 'Céu limpo';
  if (code <= 2) return 'Parcialmente nublado';
  if (code == 3) return 'Nublado';
  if (code <= 48) return 'Neblina';
  if (code <= 57) return 'Garoa';
  if (code <= 67) return 'Chuva';
  if (code <= 77) return 'Neve';
  if (code <= 82) return 'Pancadas de chuva';
  if (code <= 86) return 'Neve';
  return 'Tempestade';
}
