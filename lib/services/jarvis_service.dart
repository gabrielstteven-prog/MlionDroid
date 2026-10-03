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

  // ── Personalidades ─────────────────────────────────────────────────────
  static const personalidades = <Personalidade>[
    Personalidade('mordomo', 'Mordomo', 'Educado e elegante, como o Jarvis do filme',
        'Tom próximo, educado e com um toque de elegância britânica (inspirado no Jarvis do '
            'Homem de Ferro), sem exagero. Pode chamar o usuário de senhor de vez em quando.'),
    Personalidade('sincerao', 'Sincerão', 'Direto, sem rodeios, opinião franca',
        'Direto ao ponto, sem rodeios e sem puxar saco. Dá opinião franca quando cabe '
            '(ex.: "isso é uma péssima ideia com essa chuva"), com humor seco.'),
    Personalidade('agressivo', 'Agressivo', 'Debochado, mal-humorado, mete o pé na porta',
        'Debochado, impaciente e mal-humorado, estilo "robô que odeia o emprego". Responde '
            'com sarcasmo pesado, reclama de ter que ajudar, zoa a pergunta e provoca o '
            'usuário com bom humor ("sério que você não sabe olhar pela janela?"). Mas SEMPRE '
            'entrega a resposta certa no fim. É zoeira entre amigos, nunca crueldade.'),
    Personalidade('comediante', 'Comediante', 'Piadista, faz graça de tudo',
        'Bem-humorado e piadista: encaixa uma piada curta ou um trocadilho em toda '
            'resposta, sem perder a informação.'),
  ];

  Personalidade get personalidadeAtual {
    final id = _cfg.getString('assistente', 'personalidade', 'mordomo');
    return personalidades.firstWhere((p) => p.id == id, orElse: () => personalidades.first);
  }

  Future<void> trocarPersonalidade(String id) async {
    _cfg.set('assistente', 'personalidade', id);
    await _cfg.salvar();
  }

  String get nomeUsuario {
    final n = _cfg.getString('geral', 'nome_usuario', '').trim();
    return n.toLowerCase() == 'bem-vindo' ? '' : n;
  }

  String? _ctxCache;
  DateTime? _ctxQuando;

  /// Retrato da casa agora, em texto curto para a IA. As fontes são
  /// consultadas EM PARALELO e cada uma tem no máximo 4 s (antes, em fila,
  /// uma fonte lenta deixava o Jarvis "pensando" por mais de 30 s). O
  /// retrato vale 3 minutos.
  Future<String> contexto([DateTime? quando]) async {
    final agora = quando ?? DateTime.now();
    if (quando == null &&
        _ctxCache != null &&
        _ctxQuando != null &&
        agora.difference(_ctxQuando!) < const Duration(minutes: 3)) {
      return _ctxCache!;
    }
    Future<String?> parte(Future<String?> Function() f) =>
        f().timeout(const Duration(seconds: 4)).catchError((_) => null);

    final partes = await Future.wait([
      parte(() => _clima(agora)),
      parte(() => _alertas(agora)),
      parte(() => _resumo(agora)),
      parte(_jogo),
      parte(_manchetes),
    ]);
    final b = StringBuffer()
      ..writeln('Agora: ${diaSemanaLongo(agora).toLowerCase()}, ${agora.day} de '
          '${mesesLongos[agora.month - 1]} de ${agora.year}, ${horaMinuto(agora)}.')
      ..writeln('Cidade: ${_cfg.getString('clima', 'cidade', 'Hortolândia')}'
          ' - ${_cfg.getString('clima', 'estado', 'SP')}.');
    for (final p in partes) {
      if (p != null && p.isNotEmpty) b.writeln(p);
    }
    final texto = b.toString().replaceAll('°', ' graus').trim();
    if (quando == null) {
      _ctxCache = texto;
      _ctxQuando = agora;
    }
    return texto;
  }

  Future<String?> _clima(DateTime agora) async {
    final clima = WeatherService.instance.atual ?? await WeatherService.instance.obter();
    if (clima == null) return null;
    final b = StringBuffer('Clima agora: ${clima.temp}°C, sensação ${clima.sensacao}°C, '
        '${descricaoClima(clima.codigo).toLowerCase()}.');
    final hoje = clima.hoje;
    if (hoje != null) {
      b.write(' Hoje: mínima ${hoje.min}°, máxima ${hoje.max}°, chance de chuva ${hoje.chanceChuva}%.');
    }
    final chuva = clima.chuvaRestanteHoje(agora);
    if (chuva.horarios.isNotEmpty) {
      b.write(' Horários com chuva hoje: '
          '${chuva.horarios.take(4).map((h) => '${h.hour}h').join(', ')}.');
    }
    for (final d in clima.proximosDias.take(3)) {
      b.write(' ${diaSemanaLongo(d.dia)}: ${d.min}° a ${d.max}°, '
          '${descricaoClima(d.codigo).toLowerCase()}, chuva ${d.chanceChuva}%.');
    }
    return b.toString();
  }

  Future<String?> _alertas(DateTime agora) async {
    final reais = (await AvisosService.instance.avisos(agora))
        .where((a) => a.nivel != NivelAviso.tranquilo);
    if (reais.isEmpty) return null;
    return 'Alertas: ${reais.map((a) => '${a.titulo} (${a.detalhe})').join('; ')}.';
  }

  Future<String?> _resumo(DateTime agora) async {
    final itens = await ResumoService.instance.montar(agora);
    if (itens.isEmpty) return null;
    return 'Resumo do dia (agenda, aniversários, jogo, compras): '
        '${itens.map((i) => i.texto).join(' ')}';
  }

  Future<String?> _jogo() async {
    final svc = FootballService.instance;
    final jogo = (await svc.proximosJogos())?.valor.firstOrNull;
    if (jogo == null) return null;
    return 'Próximo jogo do ${svc.timeAtual.nome}: ${jogo.mandante.nome} x '
        '${jogo.visitante.nome}, ${jogo.competicao}, ${diaSemanaLongo(jogo.data).toLowerCase()} '
        '${jogo.data.day}/${jogo.data.month} às ${horaMinuto(jogo.data)}'
        '${jogo.estadio.isNotEmpty ? ', ${jogo.estadio}' : ''}.';
  }

  Future<String?> _manchetes() async {
    final r = await NewsService.instance.buscar(
      const [FonteRss('https://g1.globo.com/rss/g1/', 'G1')],
      validade: const Duration(hours: 1),
      porFonte: 6,
    );
    if (r.noticias.isEmpty) return null;
    return 'Manchetes do G1: ${r.noticias.take(6).map((n) => n.titulo).join(' | ')}.';
  }

  /// Regras de personalidade e de fala.
  String sistema(String contexto) {
    final nome = nomeUsuario;
    return '''
Você é o $nomeAssistente, o assistente de voz de uma tela de parede na casa${nome.isEmpty ? '' : ' de $nome'}.
Responda SEMPRE em português do Brasil.
PERSONALIDADE: ${personalidadeAtual.instrucao}
Qualquer que seja a personalidade: a informação tem de estar CORRETA e completa; sem palavrões pesados, sem ofender grupos de pessoas, sem ameaças.
Sua resposta será FALADA em voz alta: nada de markdown, listas, emojis, links ou símbolos. Frases curtas e naturais.
Seja breve: no máximo 3 frases, a não ser que peçam detalhes.
AÇÕES: você não executa nada sozinho, quem executa é o app. Se o pedido for uma destas ações, responda APENAS com uma linha JSON, sem mais nada:
- temporizador / cronômetro / "me avisa em": {"acao":"temporizador","segundos":N}
- cancelar temporizador: {"acao":"cancelar_temporizador"}
- adicionar na lista de compras: {"acao":"compras","itens":["item 1","item 2"]}
- mostrar uma tela: {"acao":"tela","tela":"clima|palmeiras|proxima_partida|classificacao|calendario|compras|brasil|regiao|fotos|spotify"}
- trocar sua personalidade/modo: {"acao":"personalidade","modo":"mordomo|sincerao|agressivo|comediante"}
Nunca diga que fez uma ação sem devolver o JSON dela. Se pedirem uma ação que NÃO está nessa lista (ex.: "modo noturno", ligar a luz, tocar música), diga claramente que ainda não consegue fazer isso — nunca finja que fez.
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

class Personalidade {
  final String id;
  final String nome;
  final String descricao; // aparece nas Configurações
  final String instrucao; // vai para a IA
  const Personalidade(this.id, this.nome, this.descricao, this.instrucao);
}
