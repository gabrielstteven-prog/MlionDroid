import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:googleapis/tasks/v1.dart' as tasks;

import '../config_manager.dart';
import '../sistema.dart';
import '../util.dart';
import 'football_service.dart';
import 'google_auth_service.dart';
import 'ia_service.dart';
import 'jarvis_service.dart';
import 'resumo_service.dart';
import 'voz_service.dart';
import 'weather_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Assistente de voz — o "Alexa" do painel, 100% local.
//
//  Fluxo: toque no microfone → reconhecimento de voz do Android → texto →
//  [interpretar] (regras em português) → ação + resposta falada.
//
//  Tudo o que ele não entende cai em [TipoComando.desconhecido]. É aí que
//  um cérebro maior (Jarvis / um modelo de linguagem) pode ser plugado no
//  futuro, sem mudar o resto do app.
// ═══════════════════════════════════════════════════════════════════════════

enum TipoComando {
  temporizador,
  cancelarTemporizador,
  adicionarCompra,
  clima,
  jogo,
  hora,
  data,
  resumo,
  abrirTela,
  personalidade,
  olhar, // "olha o que eu tenho na mão": foto + IA
  sair, // "estou saindo": modo ausente
  chegar, // "cheguei"
  desconhecido,
}

class Comando {
  final TipoComando tipo;
  final Duration? duracao;
  final List<String> itens;
  final String? tela;
  final String? personalidade; // id: mordomo, sincerao, agressivo, comediante
  final String textoOriginal;
  const Comando(this.tipo, this.textoOriginal,
      {this.duracao, this.itens = const [], this.tela, this.personalidade});
}

const _numeros = {
  'um': 1, 'uma': 1, 'dois': 2, 'duas': 2, 'tres': 3, 'quatro': 4,
  'cinco': 5, 'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9, 'dez': 10,
  'onze': 11, 'doze': 12, 'quinze': 15, 'vinte': 20, 'vinte e cinco': 25,
  'trinta': 30, 'quarenta': 40, 'quarenta e cinco': 45, 'cinquenta': 50,
  'sessenta': 60, 'noventa': 90,
};

const _telas = {
  'clima': 'clima', 'tempo': 'clima', 'previsao': 'clima',
  'noticias do brasil': 'brasil', 'brasil': 'brasil',
  'regiao': 'regiao', 'noticias da regiao': 'regiao',
  'calendario': 'calendario', 'agenda': 'calendario', 'compromissos': 'calendario',
  'compras': 'compras', 'lista': 'compras', 'mercado': 'compras',
  'fotos': 'fotos', 'memorias': 'fotos',
  'tabela': 'classificacao', 'classificacao': 'classificacao',
  'jogo': 'proxima_partida', 'partida': 'proxima_partida',
  'time': 'palmeiras', 'noticias do time': 'palmeiras',
  'musica': 'spotify', 'spotify': 'spotify',
};

/// Interpreta a frase falada. Função pura — coberta por testes.
Comando interpretar(String falado) {
  final f = normalizar(falado);
  if (f.isEmpty) return Comando(TipoComando.desconhecido, falado);

  // Temporizador: "timer de 10 minutos", "temporizador de meia hora"
  // O reconhecimento de voz às vezes escreve "time"/"taimer" no lugar de
  // "timer"; com uma duração junto ("time de um minuto") é temporizador.
  final ehTimer = RegExp(r'\b(timer|taimer|time|temporizador|cronometro|cronometra|'
          r'cronometrar|cronometre|alarme|despertador|contagem|conta|contar)\b')
      .hasMatch(f);
  if (ehTimer && RegExp(r'\b(cancela|cancelar|para|parar|desliga|desligar)\b').hasMatch(f)) {
    return Comando(TipoComando.cancelarTemporizador, falado);
  }
  if (ehTimer ||
      RegExp(r'\b(me avisa|me avise|me lembra|me lembre)\b|\bdaqui a\b').hasMatch(f)) {
    final d = _duracao(f);
    if (d != null) return Comando(TipoComando.temporizador, falado, duracao: d);
  }

  // Compras: "adiciona leite e pão na lista", "comprar arroz"
  // Usa o texto original (com acentos) para os itens: "pão", não "pao".
  final original = falado
      .toLowerCase()
      .replaceAll(RegExp(r'[.!?]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final compra = RegExp(
          r'^(?:adiciona|adicionar|adicione|coloca|colocar|coloque|põe|poe|bota|anota|anotar|inclui|incluir|comprar|compra)\s+(.+?)(?:\s+(?:na|à|a|para a)\s+lista(?:\s+de\s+compras)?)?$')
      .firstMatch(original);
  if (compra != null) {
    final itens = compra
        .group(1)!
        .split(RegExp(r',| e '))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (itens.isNotEmpty) {
      return Comando(TipoComando.adicionarCompra, falado, itens: itens);
    }
  }

  // Visão: "olha o que eu tenho na mão", "o que é isso?", "veja isso aqui"
  if (RegExp(r'\b(olha|olhe|olhar|veja|enxerga|identifica|reconhece)\b.*\b(isso|aqui|mao|segurando|mostrando|tenho)\b|'
          r'\bo que (e|eh) isso\b|\bque (objeto|coisa) e essa\b|\bna minha mao\b|\bestou segurando\b|'
          r'\bto segurando\b|\bestou mostrando\b')
      .hasMatch(f)) {
    return Comando(TipoComando.olhar, falado);
  }

  // Saindo / chegando em casa
  if (RegExp(r'\b(estou|to|ja vou|vou)\s+(saindo|sair|embora)\b|\bsaindo de casa\b|'
          r'\bmodo ausente\b|\bvou trabalhar\b')
      .hasMatch(f)) {
    return Comando(TipoComando.sair, falado);
  }
  if (RegExp(r'\b(cheguei|voltei|ja cheguei|estou em casa|to em casa)\b').hasMatch(f)) {
    return Comando(TipoComando.chegar, falado);
  }

  // Personalidade: "modo agressivo", "fica sincerão", "volta ao modo normal"
  final modo = RegExp(r'\b(?:modo|personalidade|fica|seja|vira)\s+(agressivo|bravo|sincerao|'
          r'sincero|mordomo|educado|normal|comediante|engracado|piadista)\b')
      .firstMatch(f);
  if (modo != null) {
    final id = switch (modo.group(1)) {
      'agressivo' || 'bravo' => 'agressivo',
      'sincerao' || 'sincero' => 'sincerao',
      'comediante' || 'engracado' || 'piadista' => 'comediante',
      _ => 'mordomo',
    };
    return Comando(TipoComando.personalidade, falado, personalidade: id);
  }

  if (RegExp(r'\b(que horas|horas sao|hora agora)\b').hasMatch(f)) {
    return Comando(TipoComando.hora, falado);
  }
  if (RegExp(r'\b(que dia|dia e hoje|data de hoje)\b').hasMatch(f)) {
    return Comando(TipoComando.data, falado);
  }
  if (RegExp(r'\b(resumo|como esta o (meu )?dia|meu dia)\b').hasMatch(f)) {
    return Comando(TipoComando.resumo, falado);
  }

  // Abrir tela: "mostra o clima", "abre a agenda"
  final abrir = RegExp(r'^(?:mostra|mostrar|mostre|abre|abrir|abra|vai para|ir para)\s+(?:o |a |os |as )?(.+)$')
      .firstMatch(f);
  if (abrir != null) {
    final alvo = abrir.group(1)!;
    for (final e in _telas.entries) {
      if (alvo.contains(e.key)) return Comando(TipoComando.abrirTela, falado, tela: e.value);
    }
  }

  if (RegExp(r'\b(jogo|joga|partida|placar)\b').hasMatch(f)) {
    return Comando(TipoComando.jogo, falado);
  }
  if (RegExp(r'\b(chover|chuva|clima|tempo|temperatura|frio|calor|graus)\b').hasMatch(f)) {
    return Comando(TipoComando.clima, falado);
  }
  return Comando(TipoComando.desconhecido, falado);
}

Duration? _duracao(String f) {
  if (RegExp(r'\bmeia hora\b').hasMatch(f)) return const Duration(minutes: 30);
  final m = RegExp(r'(\d+|[a-z]+(?: e [a-z]+)?)\s+(segundos?|minutos?|horas?)').firstMatch(f);
  if (m == null) return null;
  final bruto = m.group(1)!;
  final n = int.tryParse(bruto) ?? _numeros[bruto] ?? _numeros[bruto.split(' ').last];
  if (n == null || n <= 0) return null;
  final unidade = m.group(2)!;
  if (unidade.startsWith('seg')) return Duration(seconds: n);
  if (unidade.startsWith('hora')) return Duration(hours: n);
  return Duration(minutes: n);
}

String descreverDuracao(Duration d) {
  if (d.inHours >= 1 && d.inMinutes % 60 == 0) {
    return d.inHours == 1 ? '1 hora' : '${d.inHours} horas';
  }
  if (d.inMinutes >= 1 && d.inSeconds % 60 == 0) {
    return d.inMinutes == 1 ? '1 minuto' : '${d.inMinutes} minutos';
  }
  return '${d.inSeconds} segundos';
}

class Temporizador {
  final int id;
  final String rotulo;
  final DateTime fim;
  bool tocando = false;
  Temporizador(this.id, this.rotulo, this.fim);
  Duration get restante {
    final r = fim.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }
}

enum EstadoAssistente { parado, ouvindo, pensando, respondendo }

class AssistenteService extends ChangeNotifier {
  AssistenteService._() {
    // A palavra "Jarvis" só é ouvida com o assistente parado: enquanto ele
    // ouve a frase ou fala, o microfone fica com ele (e ele não se chama
    // sozinho ao dizer o próprio nome).
    addListener(_sincronizarPalavra);
    Sistema.palavraOuvida.addListener(() {
      if (estado == EstadoAssistente.parado) ouvir();
    });
  }

  final _cfg = ConfigManager();
  bool _palavraLigada = false;

  /// Motivo de a palavra "Jarvis" não estar funcionando ("" = funcionando).
  final ValueNotifier<String> statusPalavra = ValueNotifier('');

  bool get _palavraConfigurada => _cfg.getBool('assistente', 'palavra_ativacao', true);

  /// Liga/desliga a escuta da palavra conforme o estado e as Configurações.
  /// [forcar] religa mesmo se já estava ligada (chave ou sensibilidade mudou).
  Future<void> sincronizarPalavra({bool forcar = false}) async {
    final deve = _palavraConfigurada && estado == EstadoAssistente.parado;
    if (forcar && _palavraLigada) {
      _palavraLigada = false;
      await Sistema.desligarPalavra();
    }
    if (deve == _palavraLigada) return;
    _palavraLigada = deve;
    if (!deve) {
      await Sistema.desligarPalavra();
      return;
    }
    final erro = await Sistema.ligarPalavra(
        _cfg.getDouble('assistente', 'palavra_sensibilidade', 0.6));
    if (erro != null) _palavraLigada = false;
    statusPalavra.value = switch (erro) {
      null => '',
      'sem_permissao' => 'Falta a permissão do microfone. Aceite e tente de novo.',
      _ => 'Não consegui ligar a escuta: $erro',
    };
  }

  void _sincronizarPalavra() => sincronizarPalavra();
  static final AssistenteService instance = AssistenteService._();

  EstadoAssistente estado = EstadoAssistente.parado;
  String ultimaFala = '';
  String ultimaResposta = '';

  final List<Temporizador> temporizadores = [];
  int _proximoId = 1;
  final Map<int, Timer> _timers = {};

  /// Pedido para o rodízio mostrar uma tela ("mostra o clima").
  final ValueNotifier<String?> pedidoDeTela = ValueNotifier(null);

  /// Foto que o Jarvis acabou de tirar (aparece no orbe).
  Uint8List? ultimaFoto;

  /// Modo ausente ("estou saindo"): a tela descansa até alguém chegar.
  final ValueNotifier<bool> ausente = ValueNotifier(false);

  /// Boas-vindas quando alguém chega com o modo ausente ligado.
  Future<void> boasVindas() async {
    final nome = JarvisService.instance.nomeUsuario;
    final h = DateTime.now().hour;
    final saudacao = h < 12 ? 'Bom dia' : (h < 18 ? 'Boa tarde' : 'Boa noite');
    ultimaFala = '';
    ultimaResposta = '$saudacao${nome.isEmpty ? '' : ', $nome'}! Bem-vindo de volta.';
    estado = EstadoAssistente.respondendo;
    notifyListeners();
    await VozService.instance.falar(ultimaResposta);
    Timer(const Duration(seconds: 4), () {
      if (estado == EstadoAssistente.respondendo) {
        estado = EstadoAssistente.parado;
        notifyListeners();
      }
    });
  }

  bool get algumTocando => temporizadores.any((t) => t.tocando);

  /// Toque no microfone.
  Future<void> ouvir() async {
    if (estado == EstadoAssistente.ouvindo) return;
    await Sistema.pararFala();
    estado = EstadoAssistente.ouvindo;
    ultimaFala = '';
    ultimaResposta = '';
    ultimaFoto = null;
    notifyListeners();
    // Mostra no orbe o que já foi entendido, palavra por palavra.
    void parcial() {
      if (estado != EstadoAssistente.ouvindo) return;
      ultimaFala = Sistema.falaParcial.value;
      notifyListeners();
    }

    Sistema.falaParcial.addListener(parcial);
    final String falado;
    try {
      falado = await Sistema.ouvir(prompt: 'Como posso ajudar?');
    } finally {
      Sistema.falaParcial.removeListener(parcial);
    }
    if (falado.trim().isEmpty) {
      ultimaFala = '';
      ultimaResposta = 'Não ouvi nada. Toque no microfone e fale de novo.';
      estado = EstadoAssistente.respondendo;
      notifyListeners();
      Timer(const Duration(seconds: 3), () {
        if (estado == EstadoAssistente.respondendo) {
          estado = EstadoAssistente.parado;
          notifyListeners();
        }
      });
      return;
    }
    await executarTexto(falado);
  }

  Future<void> executarTexto(String falado) async {
    ultimaFala = falado;
    estado = EstadoAssistente.pensando;
    notifyListeners();
    String resposta;
    try {
      resposta = await _executar(interpretar(falado));
    } catch (e) {
      debugPrint('Assistente: $e');
      resposta = 'Não consegui fazer isso agora. Verifique a internet e tente de novo.';
    }
    ultimaResposta = resposta;
    estado = EstadoAssistente.respondendo;
    notifyListeners();
    final inicio = DateTime.now();
    await VozService.instance.falar(resposta);
    // A voz premium só retorna quando termina; a do Android retorna na hora,
    // então estima o tempo de fala (~14 letras por segundo) para o orbe.
    final falando = DateTime.now().difference(inicio);
    final estimado = Duration(milliseconds: 1500 + resposta.length * 70);
    final resta = falando > const Duration(seconds: 1) ? const Duration(seconds: 2) : estimado;
    Timer(resta, () {
      if (estado == EstadoAssistente.respondendo) {
        estado = EstadoAssistente.parado;
        notifyListeners();
      }
    });
  }

  void fechar() {
    estado = EstadoAssistente.parado;
    VozService.instance.parar();
    notifyListeners();
  }

  Future<String> _executar(Comando c) async {
    switch (c.tipo) {
      case TipoComando.temporizador:
        final d = c.duracao!;
        iniciarTemporizador(d);
        return 'Temporizador de ${descreverDuracao(d)} começando agora.';
      case TipoComando.cancelarTemporizador:
        if (temporizadores.isEmpty) return 'Não há temporizador ativo.';
        cancelarTodos();
        return 'Temporizador cancelado.';
      case TipoComando.adicionarCompra:
        final ok = await _adicionarCompras(c.itens);
        return ok
            ? 'Adicionei ${_juntar(c.itens)} na lista de compras.'
            : 'Não encontrei a lista de compras. Conecte sua conta Google nas configurações.';
      case TipoComando.hora:
        final a = DateTime.now();
        return 'Agora são ${a.hour} horas e ${a.minute} minutos.';
      case TipoComando.data:
        final a = DateTime.now();
        return 'Hoje é ${diaSemanaLongo(a).toLowerCase()}, ${a.day} de ${mesesLongos[a.month - 1]}.';
      case TipoComando.clima:
        return _respostaClima(c.textoOriginal);
      case TipoComando.jogo:
        return _respostaJogo();
      case TipoComando.resumo:
        final briefing = await JarvisService.instance.briefing(saudacaoDaHora());
        if (briefing != null) return briefing;
        final itens = await ResumoService.instance.montar();
        if (itens.isEmpty) return 'Ainda não tenho informações do seu dia.';
        return itens.map((i) => i.texto).join(' ').replaceAll('°', ' graus');
      case TipoComando.olhar:
        ultimaResposta = 'Deixa eu ver...';
        notifyListeners();
        final caminho = await Sistema.tirarFoto();
        ultimaResposta = '';
        if (caminho == 'sem_permissao') {
          return 'Preciso de permissão para usar a câmera. Toque em Permitir e peça de novo.';
        }
        if (caminho == null) return 'Não consegui usar a câmera agora.';
        final foto = await File(caminho).readAsBytes();
        ultimaFoto = foto;
        notifyListeners();
        final visto = await JarvisService.instance.olhar(c.textoOriginal, foto);
        return visto ?? IaService.instance.motivoFalha;
      case TipoComando.sair:
        // Dá tempo de falar a despedida antes de apagar a tela.
        Timer(const Duration(seconds: 5), () => ausente.value = true);
        return 'Até mais! Vou descansar a tela. Quando você chegar, eu acendo.';
      case TipoComando.chegar:
        ausente.value = false;
        final nome = JarvisService.instance.nomeUsuario;
        return 'Bem-vindo de volta${nome.isEmpty ? '' : ', $nome'}!';
      case TipoComando.personalidade:
        await JarvisService.instance.trocarPersonalidade(c.personalidade!);
        return switch (c.personalidade) {
          'agressivo' => 'Modo agressivo ligado. Agora aguenta.',
          'sincerao' => 'Modo sincerão. Vou falar a verdade, goste ou não.',
          'comediante' => 'Modo comediante ativado. Prepare-se para piadas ruins.',
          _ => 'De volta ao modo mordomo, às suas ordens.',
        };
      case TipoComando.abrirTela:
        pedidoDeTela.value = c.tela;
        return 'Abrindo.';
      case TipoComando.desconhecido:
        // O cérebro local não entendeu: pergunta para a IA (Gemini / Groq).
        final ia = await JarvisService.instance.responder(c.textoOriginal);
        if (ia != null) {
          // A IA entendeu um pedido de AÇÃO (ex.: "time de um minuto"): o app
          // executa de verdade em vez de só responder "ok, contando".
          final acao = acaoDaIa(ia, c.textoOriginal);
          if (acao != null) return _executar(acao);
          return ia;
        }
        if (IaService.instance.configurado) return IaService.instance.motivoFalha;
        return 'Ainda não sei responder isso. Tente: timer de 10 minutos, '
            'vai chover hoje, adiciona leite na lista, ou quando é o próximo jogo. '
            'Para perguntas livres, configure a inteligência artificial nas Configurações.';
    }
  }

  String _juntar(List<String> l) =>
      l.length == 1 ? l.first : '${l.sublist(0, l.length - 1).join(', ')} e ${l.last}';

  Future<String> _respostaClima(String pergunta) async {
    final c = await WeatherService.instance.obter();
    if (c == null) return 'Estou sem dados de clima agora.';
    final chuva = c.chuvaRestanteHoje();
    final f = normalizar(pergunta);
    if (f.contains('amanha') && c.proximosDias.isNotEmpty) {
      final a = c.proximosDias.first;
      return 'Amanhã: entre ${a.min} e ${a.max} graus, ${descricaoClima(a.codigo).toLowerCase()}, '
          '${a.chanceChuva}% de chance de chuva.';
    }
    final base = 'Agora faz ${c.temp} graus, sensação de ${c.sensacao}.';
    if (chuva.horarios.isNotEmpty) {
      return '$base Pode chover a partir das ${chuva.horarios.first.hour} horas, '
          'com ${chuva.maxima}% de chance.';
    }
    return '$base Sem chuva prevista para o resto do dia.';
  }

  Future<String> _respostaJogo() async {
    final svc = FootballService.instance;
    final r = await svc.proximosJogos();
    final p = r?.valor.firstOrNull;
    if (p == null) return 'Não encontrei o próximo jogo do ${svc.timeAtual.nome}.';
    final adv = p.adversarioDe(svc.timeAtual.espnId).nome;
    if (p.aoVivo) {
      return 'Está rolando agora: ${p.mandante.nome} ${p.mandante.gols} a '
          '${p.visitante.gols} ${p.visitante.nome}, ${p.relogio}.';
    }
    final quando = etiquetaDias(p.data).toLowerCase();
    return 'O ${svc.timeAtual.nome} joga ${quando == 'hoje' || quando == 'amanhã' ? quando : 'em ${diaSemanaLongo(p.data).toLowerCase()}, dia ${p.data.day},'} '
        'às ${p.data.hour} horas${p.data.minute > 0 ? ' e ${p.data.minute}' : ''}, contra o $adv'
        '${p.estadio.isNotEmpty ? ', no ${p.estadio}' : ''}.';
  }

  Future<bool> _adicionarCompras(List<String> itens) async {
    final client = await GoogleAuthService.instance.cliente();
    if (client == null) return false;
    try {
      final api = tasks.TasksApi(client);
      final listas = await api.tasklists.list();
      final alvo = (listas.items ?? <tasks.TaskList>[])
          .where((l) => l.id != null && ehListaDeCompras(l.title ?? ''))
          .firstOrNull;
      if (alvo == null) return false;
      for (final i in itens) {
        final titulo = i[0].toUpperCase() + i.substring(1);
        await api.tasks.insert(tasks.Task(title: titulo), alvo.id!);
      }
      return true;
    } finally {
      client.close();
    }
  }

  // ── Temporizadores ───────────────────────────────────────────────────────
  void iniciarTemporizador(Duration d) {
    final t = Temporizador(_proximoId++, descreverDuracao(d), DateTime.now().add(d));
    temporizadores.add(t);
    _timers[t.id] = Timer(d, () => _tocar(t));
    notifyListeners();
  }

  void _tocar(Temporizador t) {
    t.tocando = true;
    notifyListeners();
    Sistema.tocarAlarme();
    // Para sozinho depois de 2 minutos, se ninguém tocar na tela.
    _timers[t.id] = Timer(const Duration(minutes: 2), () => dispensar(t.id));
  }

  void dispensar(int id) {
    _timers.remove(id)?.cancel();
    temporizadores.removeWhere((t) => t.id == id);
    if (!algumTocando) Sistema.pararAlarme();
    notifyListeners();
  }

  void cancelarTodos() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    temporizadores.clear();
    Sistema.pararAlarme();
    notifyListeners();
  }
}

/// Lê o comando em JSON que a IA devolve quando o pedido é uma ação
/// ({"acao":"temporizador","segundos":60}...). null = é só uma resposta
/// falada. Função pura — testada.
Comando? acaoDaIa(String resposta, String falado) {
  final m = RegExp(r'\{[^{}]*"acao"[^{}]*\}').firstMatch(resposta);
  if (m == null) return null;
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(m.group(0)!) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  switch (j['acao']) {
    case 'temporizador':
      final s = (j['segundos'] as num?)?.toInt() ?? 0;
      if (s <= 0 || s > 24 * 3600) return null;
      return Comando(TipoComando.temporizador, falado, duracao: Duration(seconds: s));
    case 'cancelar_temporizador':
      return Comando(TipoComando.cancelarTemporizador, falado);
    case 'personalidade':
      const modos = {'mordomo', 'sincerao', 'agressivo', 'comediante'};
      final modo = '${j['modo'] ?? ''}';
      if (!modos.contains(modo)) return null;
      return Comando(TipoComando.personalidade, falado, personalidade: modo);
    case 'compras':
      final itens = (j['itens'] as List? ?? const [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (itens.isEmpty) return null;
      return Comando(TipoComando.adicionarCompra, falado, itens: itens);
    case 'tela':
      const validas = {
        'clima', 'palmeiras', 'proxima_partida', 'classificacao', 'calendario',
        'compras', 'brasil', 'regiao', 'fotos', 'spotify',
      };
      final tela = '${j['tela'] ?? ''}';
      if (!validas.contains(tela)) return null;
      return Comando(TipoComando.abrirTela, falado, tela: tela);
  }
  return null;
}
