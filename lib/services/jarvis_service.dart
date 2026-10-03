import '../config_manager.dart';
import '../util.dart';
import 'avisos_service.dart';
import 'football_service.dart';
import 'ia_service.dart';
import 'news_service.dart';
import 'resumo_service.dart';
import 'weather_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  JarvisService — a personalidade e o contexto do assistente.
//
//  Monta um "retrato da casa agora" (clima, alertas, agenda, jogo, compras,
//  manchetes) a partir do que o app já tem em cache e entrega para a IA
//  junto com as regras de fala. A IA não navega na internet: ela responde
//  com ESTES dados — por isso as respostas batem com o que está na tela.
// ═══════════════════════════════════════════════════════════════════════════

class JarvisService {
  JarvisService._();
  static final JarvisService instance = JarvisService._();

  final _cfg = ConfigManager();

  String get nomeAssistente {
    final n = _cfg.getString('assistente', 'nome', 'Jarvis').trim();
    return n.isEmpty ? 'Jarvis' : n;
  }

  String get nomeUsuario {
    final n = _cfg.getString('geral', 'nome_usuario', '').trim();
    return n.toLowerCase() == 'bem-vindo' ? '' : n;
  }

  /// Retrato da casa agora, em texto curto para a IA.
  Future<String> contexto([DateTime? quando]) async {
    final agora = quando ?? DateTime.now();
    final b = StringBuffer()
      ..writeln('Agora: ${diaSemanaLongo(agora).toLowerCase()}, ${agora.day} de '
          '${mesesLongos[agora.month - 1]} de ${agora.year}, ${horaMinuto(agora)}.')
      ..writeln('Cidade: ${_cfg.getString('clima', 'cidade', 'Hortolândia')}'
          ' - ${_cfg.getString('clima', 'estado', 'SP')}.');

    final clima = WeatherService.instance.atual ?? await WeatherService.instance.obter();
    if (clima != null) {
      b.writeln('Clima agora: ${clima.temp}°C, sensação ${clima.sensacao}°C, '
          '${descricaoClima(clima.codigo).toLowerCase()}.');
      final hoje = clima.hoje;
      if (hoje != null) {
        b.writeln('Hoje: mínima ${hoje.min}°, máxima ${hoje.max}°, '
            'chance de chuva ${hoje.chanceChuva}%.');
      }
      final chuva = clima.chuvaRestanteHoje(agora);
      if (chuva.horarios.isNotEmpty) {
        b.writeln('Horários com chuva hoje: '
            '${chuva.horarios.take(4).map((h) => '${h.hour}h').join(', ')}.');
      }
      for (final d in clima.proximosDias.take(3)) {
        b.writeln('${diaSemanaLongo(d.dia)}: ${d.min}° a ${d.max}°, '
            '${descricaoClima(d.codigo).toLowerCase()}, chuva ${d.chanceChuva}%.');
      }
    }

    try {
      final avisos = await AvisosService.instance.avisos(agora);
      final reais = avisos.where((a) => a.nivel != NivelAviso.tranquilo);
      if (reais.isNotEmpty) {
        b.writeln('Alertas: ${reais.map((a) => '${a.titulo} (${a.detalhe})').join('; ')}.');
      }
    } catch (_) {}

    try {
      final itens = await ResumoService.instance.montar(agora);
      if (itens.isNotEmpty) {
        b.writeln('Resumo do dia (agenda, aniversários, jogo, compras): '
            '${itens.map((i) => i.texto).join(' ')}');
      }
    } catch (_) {}

    try {
      final svc = FootballService.instance;
      final jogo = (await svc.proximosJogos())?.valor.firstOrNull;
      if (jogo != null) {
        b.writeln('Próximo jogo do ${svc.timeAtual.nome}: ${jogo.mandante.nome} x '
            '${jogo.visitante.nome}, ${jogo.competicao}, ${diaSemanaLongo(jogo.data).toLowerCase()} '
            '${jogo.data.day}/${jogo.data.month} às ${horaMinuto(jogo.data)}'
            '${jogo.estadio.isNotEmpty ? ', ${jogo.estadio}' : ''}.');
      }
    } catch (_) {}

    try {
      final r = await NewsService.instance.buscar(
        const [FonteRss('https://g1.globo.com/rss/g1/', 'G1')],
        validade: const Duration(hours: 1),
        porFonte: 6,
      );
      if (r.noticias.isNotEmpty) {
        b.writeln('Manchetes do G1: ${r.noticias.take(6).map((n) => n.titulo).join(' | ')}.');
      }
    } catch (_) {}

    return b.toString().replaceAll('°', ' graus').trim();
  }

  /// Regras de personalidade e de fala.
  String sistema(String contexto) {
    final nome = nomeUsuario;
    return '''
Você é o $nomeAssistente, o assistente de voz de uma tela de parede na casa${nome.isEmpty ? '' : ' de $nome'}.
Responda SEMPRE em português do Brasil, com tom próximo, educado e um toque de elegância (inspirado no Jarvis do Homem de Ferro), sem exagero.
Sua resposta será FALADA em voz alta: nada de markdown, listas, emojis, links ou símbolos. Frases curtas e naturais.
Seja breve: no máximo 3 frases, a não ser que peçam detalhes.
Use os dados abaixo quando forem relevantes. Se a resposta não estiver nos dados e for algo que muda (preço, resultado, notícia), diga que não tem essa informação agora em vez de inventar.
Dados da casa agora:
$contexto''';
  }

  /// Pergunta livre (o que o cérebro local não entendeu). null = sem IA.
  Future<String?> responder(String pergunta) async {
    if (!IaService.instance.configurado) return null;
    final ctx = await contexto();
    return IaService.instance.responder(sistema: sistema(ctx), pergunta: pergunta);
  }

  /// Briefing da manhã: um texto de 40 a 60 segundos escrito pela IA com os
  /// dados do dia. Sem IA, devolve null e o Bom Dia usa o resumo pronto.
  Future<String?> briefing(String saudacao) async {
    if (!IaService.instance.configurado) return null;
    final ctx = await contexto();
    final nome = nomeUsuario;
    return IaService.instance.responder(
      sistema: sistema(ctx),
      pergunta: 'Faça o briefing da manhã, como um mordomo pessoal. Comece com '
          '"$saudacao${nome.isEmpty ? '' : ', $nome'}". Em 5 a 8 frases (40 a 60 segundos falados): '
          'clima e se precisa de guarda-chuva, alertas da Defesa Civil se houver, '
          'compromissos e aniversários de hoje, o jogo do time se for hoje ou amanhã, '
          'e uma ou duas manchetes importantes. Pule o que não tiver. Termine com uma frase curta e simpática.',
    );
  }
}
