import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config_manager.dart';
import '../sistema.dart';
import '../services/assistente_service.dart';
import '../services/ia_service.dart';
import '../services/jarvis_service.dart';
import '../services/telegram_service.dart';
import '../services/voz_jarvis_service.dart';
import '../services/voz_service.dart';

/// Seção "Assistente (Jarvis)" das Configurações: chaves de IA e de voz,
/// escolha da voz, testes e o quanto da cota de voz já foi usado no mês.
/// As chaves ficam só neste tablet (no arquivo de configurações do app).
class ConfigAssistente extends StatefulWidget {
  const ConfigAssistente({super.key});

  @override
  State<ConfigAssistente> createState() => _ConfigAssistenteState();
}

class _ConfigAssistenteState extends State<ConfigAssistente> {
  static const _border = Color(0xFF1E2D45);
  static const _accent = Color(0xFF00D4FF);

  final _cfg = ConfigManager();
  List<VozPremium> _vozes = [];
  bool _buscandoVozes = false;
  String _statusVozes = '';
  String _statusIa = '';
  String _statusVoz = '';
  bool _testandoIa = false;
  bool _testandoVoz = false;
  int _uso = 0;
  String _statusPalavra = '';

  @override
  void initState() {
    super.initState();
    _atualizarUso();
    _verVozesInstaladas();
  }

  // ── Voz no aparelho (Supertonic 3 / Piper) ──────────────────────────────
  static const _vozesLocais = [
    ('supertonic', 'Supertonic 3', '10 vozes, a mais natural · ~130 MB'),
    ('piper_faber', 'Piper "Faber"', 'Masculina, clara · ~70 MB'),
    ('piper_miro', 'Piper "Miro"', 'Alta qualidade · ~70 MB'),
  ];
  final Map<String, bool> _instaladas = {};
  String? _baixando;
  String _statusMotor = '';
  bool _previando = false;

  Future<void> _verVozesInstaladas() async {
    for (final (id, _, _) in _vozesLocais) {
      _instaladas[id] = await Sistema.vozLocalInstalado(id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _baixarVoz(String id) async {
    setState(() {
      _baixando = id;
      _statusMotor = '';
    });
    final ok = await Sistema.vozLocalBaixar(id);
    if (!mounted) return;
    setState(() {
      _baixando = null;
      _instaladas[id] = ok;
      _statusMotor = ok
          ? 'Voz instalada! Toque em Prévia para ouvir.'
          : 'Não consegui baixar (internet?). Tente de novo.';
    });
  }

  Future<void> _previa(String id) async {
    await _cfg.salvar();
    setState(() => _previando = true);
    final nome = JarvisService.instance.nomeUsuario;
    const texto = 'Olá! Eu sou o Jarvis. Hoje faz vinte e três graus em Hortolândia, '
        'com chance de chuva no fim da tarde. O Palmeiras joga às nove e meia da noite. '
        'Quer que eu prepare alguma coisa pra você?';
    final ok = await VozService.instance
        .falarNoAparelho(nome.isEmpty ? texto : texto.replaceFirst('Olá!', 'Olá, $nome!'), id);
    if (!mounted) return;
    setState(() {
      _previando = false;
      if (!ok) _statusMotor = VozService.instance.ultimoErro;
    });
  }

  // ── Voz do Jarvis (Qwen3, voz clonada, gravada antes) ───────────────────
  bool _baixandoJarvis = false;
  String _statusJarvis = '';

  Future<void> _baixarJarvis() async {
    setState(() {
      _baixandoJarvis = true;
      _statusJarvis = '';
    });
    final ok = await VozJarvis.instance.baixar();
    if (ok) {
      _cfg.set('assistente', 'motor_voz', 'jarvis');
      await _cfg.salvar(); // já fica valendo, sem precisar tocar em Salvar
    }
    if (!mounted) return;
    setState(() {
      _baixandoJarvis = false;
      _statusJarvis = ok
          ? 'Pronto! O Jarvis está gravando as frases dele agora (alguns minutos). '
              'O Bom Dia sai na voz dele a partir de amanhã.'
          : 'O download parou (internet?). Toque de novo: ele continua de onde parou.';
    });
  }

  Future<void> _ouvirJarvis() async {
    final audios = await VozJarvis.instance.audios(VozJarvis.frasesFixas.first);
    if (audios == null) {
      setState(() => _statusJarvis = 'Ainda gravando a primeira frase. Tente em alguns minutos.');
      return;
    }
    for (final a in audios) {
      await Sistema.tocarAudio(a.path);
    }
  }

  Widget _secaoVozJarvis() {
    final jarvis = VozJarvis.instance;
    final rapida = _cfg.getString('assistente', 'voz_rapida', 'android');
    return _card([
      Text(
        'A voz do Jarvis: natural, com risada e emoção, gerada no próprio tablet. '
        'Ela é pesada, então o Jarvis grava ANTES: o Bom Dia às 4h, o resumo da noite '
        'uma hora antes e as frases que ele mais fala. O que ainda não foi gravado sai '
        'na voz rápida, sem esperar.',
        style: _txt(14),
      ),
      const SizedBox(height: 14),
      if (!jarvis.suportado)
        Text('Este aparelho não roda a voz do Jarvis (precisa de ARM 64 bits).',
            style: _txt(14, cor: Colors.orangeAccent))
      else if (_baixandoJarvis)
        ValueListenableBuilder<(String, double)?>(
          valueListenable: Sistema.vozProgresso,
          builder: (_, p, __) {
            final v = p != null && p.$1 == 'qwen3' ? p.$2 : null;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LinearProgressIndicator(value: v, minHeight: 8),
              const SizedBox(height: 6),
              Text('Baixando a voz do Jarvis... ${v == null ? '' : '${(v * 100).round()}%'} '
                  '(2,4 GB — deixe no Wi-Fi)', style: _txt(13)),
            ]);
          },
        )
      else if (!jarvis.disponivel)
        Row(children: [
          _botao('Baixar a voz do Jarvis', Icons.download_rounded, _baixarJarvis),
          const SizedBox(width: 14),
          Expanded(child: Text('2,4 GB, uma vez só. Use o Wi-Fi.', style: _txt(13))),
        ])
      else
        Row(children: [
          _botao('Ouvir', Icons.play_arrow_rounded, _ouvirJarvis),
          const SizedBox(width: 14),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: jarvis.naFila,
              builder: (_, n, __) => Text(
                  n == 0 ? 'Voz instalada. Nada na fila para gravar.' : 'Gravando: $n frases na fila.',
                  style: _txt(14, cor: Colors.white)),
            ),
          ),
          IconButton(
            tooltip: 'Apagar a voz do Jarvis do tablet',
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
            onPressed: () async {
              await jarvis.apagar();
              if (_cfg.getString('assistente', 'motor_voz', 'auto') == 'jarvis') {
                _cfg.set('assistente', 'motor_voz', 'auto');
              }
              setState(() {});
            },
          ),
        ]),
      if (_statusJarvis.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(_statusJarvis, style: _txt(14, cor: Colors.white)),
      ],
      const SizedBox(height: 16),
      Text('Voz rápida (enquanto a frase não foi gravada)',
          style: _txt(15, peso: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (id, rotulo) in const [
          ('android', 'Voz do Android'),
          ('supertonic', 'Supertonic 3'),
          ('piper_faber', 'Piper Faber'),
          ('piper_miro', 'Piper Miro'),
        ])
          ChoiceChip(
            label: Text(rotulo),
            selected: rapida == id,
            onSelected: id == 'android' || _instaladas[id] == true
                ? (_) => setState(() => _cfg.set('assistente', 'voz_rapida', id))
                : null,
          ),
      ]),
      const SizedBox(height: 6),
      Text('As vozes do aparelho precisam ser baixadas logo abaixo.',
          style: _txt(12.5, cor: Colors.white38)),
    ]);
  }

  Widget _secaoMotorVoz() {
    final motor = _cfg.getString('assistente', 'motor_voz', 'auto');
    return _card([
      Text(
        'Vozes "no aparelho" são grátis, sem conta e sem limite: baixam uma vez e '
        'funcionam sem internet. Teste e compare com a ElevenLabs.',
        style: _txt(14),
      ),
      const SizedBox(height: 14),
      Text('Motor de voz', style: _txt(15, peso: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (id, rotulo) in [
          ('auto', 'Automático'),
          if (VozJarvis.instance.disponivel) ('jarvis', 'Voz do Jarvis (gravada)'),
          ('supertonic', 'Supertonic 3 (aparelho)'),
          ('piper_faber', 'Piper Faber (aparelho)'),
          ('piper_miro', 'Piper Miro (aparelho)'),
          ('elevenlabs', 'ElevenLabs'),
          ('android', 'Voz do Android'),
        ])
          ChoiceChip(
            label: Text(rotulo),
            selected: motor == id,
            onSelected: (_) => setState(() => _cfg.set('assistente', 'motor_voz', id)),
          ),
      ]),
      const SizedBox(height: 18),
      for (final (id, nome, desc) in _vozesLocais) ...[
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nome, style: _txt(15, cor: Colors.white, peso: FontWeight.w600)),
              Text(desc, style: _txt(12.5, cor: Colors.white54)),
            ]),
          ),
          if (_baixando == id)
            SizedBox(
              width: 160,
              child: ValueListenableBuilder<(String, double)?>(
                valueListenable: Sistema.vozProgresso,
                builder: (_, p, __) => Column(children: [
                  LinearProgressIndicator(
                      value: p != null && p.$1 == id ? p.$2 : null, minHeight: 6),
                  const SizedBox(height: 4),
                  Text(
                      p != null && p.$1 == id && p.$2 > 0.9
                          ? 'Instalando...'
                          : 'Baixando ${p != null && p.$1 == id ? (p.$2 * 100).round() : 0}%',
                      style: _txt(12)),
                ]),
              ),
            )
          else if (_instaladas[id] == true) ...[
            _botao(_previando ? 'Falando...' : 'Prévia', Icons.play_arrow_rounded,
                _previando ? null : () => _previa(id)),
            IconButton(
              tooltip: 'Apagar a voz do tablet',
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
              onPressed: () async {
                await Sistema.vozLocalApagar(id);
                setState(() => _instaladas[id] = false);
              },
            ),
          ] else
            _botao('Baixar', Icons.download_rounded,
                _baixando == null ? () => _baixarVoz(id) : null),
        ]),
        const SizedBox(height: 12),
      ],
      if (_statusMotor.isNotEmpty) ...[
        Text(_statusMotor, style: _txt(14, cor: Colors.white)),
        const SizedBox(height: 12),
      ],
      Text('Voz da Supertonic', style: _txt(15, peso: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < 10; i++)
          ChoiceChip(
            label: Text('Voz ${i + 1}'),
            selected: _cfg.getInt('assistente', 'voz_local_voz', 0) == i,
            onSelected: (_) => setState(() => _cfg.set('assistente', 'voz_local_voz', i)),
          ),
      ]),
      const SizedBox(height: 14),
      Text('Velocidade', style: _txt(15, peso: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, children: [
        for (final (v, rotulo) in const [(0.9, 'Calma'), (1.0, 'Normal'), (1.1, 'Ágil')])
          ChoiceChip(
            label: Text(rotulo),
            selected: (_cfg.getDouble('assistente', 'voz_local_velocidade', 1.0) - v).abs() < 0.01,
            onSelected: (_) => setState(() => _cfg.set('assistente', 'voz_local_velocidade', v)),
          ),
      ]),
      const SizedBox(height: 14),
      Text('Qualidade (Supertonic)', style: _txt(15, peso: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Mais qualidade soa mais natural, mas demora mais para começar a falar.',
          style: _txt(12.5, cor: Colors.white38)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, children: [
        for (final (v, rotulo) in const [(3, 'Rápida'), (5, 'Normal'), (8, 'Caprichada')])
          ChoiceChip(
            label: Text(rotulo),
            selected: _cfg.getInt('assistente', 'voz_local_qualidade', 5) == v,
            onSelected: (_) => setState(() => _cfg.set('assistente', 'voz_local_qualidade', v)),
          ),
      ]),
    ]);
  }

  Future<void> _atualizarUso() async {
    final u = await VozService.instance.usoNoMes();
    if (mounted) setState(() => _uso = u);
  }

  TextStyle _txt(double size, {Color cor = Colors.white70, FontWeight peso = FontWeight.w500}) =>
      GoogleFonts.figtree(color: cor, fontSize: size, fontWeight: peso, height: 1.45);

  @override
  Widget build(BuildContext context) {
    final voz = VozService.instance;
    final uso = _uso;
    final limite = voz.limiteMensal;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _titulo('🧠 Inteligência (o cérebro do Jarvis)'),
        const SizedBox(height: 14),
        _card([
          Text(
            'Perguntas que o assistente não sabe responder sozinho vão para a IA, '
            'junto com o clima, a agenda, o jogo e as manchetes da tela. '
            'Gemini primeiro; o Groq entra se o Gemini falhar. Ambos têm plano gratuito.',
            style: _txt(14),
          ),
          const SizedBox(height: 16),
          _campo('nome', 'Nome do assistente', 'Jarvis', Icons.smart_toy_rounded),
          Text('Personalidade', style: _txt(15, peso: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Também dá para trocar falando: "modo agressivo", "modo sincerão"...',
              style: _txt(12.5, cor: Colors.white38)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final p in JarvisService.personalidades)
              Tooltip(
                message: p.descricao,
                child: ChoiceChip(
                  label: Text(p.nome),
                  selected: JarvisService.instance.personalidadeAtual.id == p.id,
                  onSelected: (_) =>
                      setState(() => _cfg.set('assistente', 'personalidade', p.id)),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(JarvisService.instance.personalidadeAtual.descricao,
              style: _txt(13, cor: Colors.white54)),
          const SizedBox(height: 16),
          Text('Visual', style: _txt(15, peso: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            for (final (id, rotulo) in const [
              ('rosto', 'Rosto com emoções'),
              ('orbe', 'Orbe (HUD)'),
            ])
              ChoiceChip(
                label: Text(rotulo),
                selected: _cfg.getString('assistente', 'visual', 'rosto') == id,
                onSelected: (_) => setState(() => _cfg.set('assistente', 'visual', id)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text('Olhar para quem está na frente (usa a câmera)',
                  style: _txt(15, peso: FontWeight.w600)),
            ),
            Switch(
              value: _cfg.getBool('assistente', 'olhar_pessoa', true),
              onChanged: (v) => setState(() => _cfg.set('assistente', 'olhar_pessoa', v)),
            ),
          ]),
          Row(children: [
            Expanded(
              child: Text('Ele olha para o lado errado? Inverter',
                  style: _txt(14, cor: Colors.white60)),
            ),
            Switch(
              value: _cfg.getBool('assistente', 'inverter_olhar', false),
              onChanged: (v) {
                setState(() => _cfg.set('assistente', 'inverter_olhar', v));
                Sistema.inverterOlhar(v);
              },
            ),
          ]),
          Row(children: [
            Expanded(
              child: Text('Conversa contínua (ele volta a ouvir depois de responder)',
                  style: _txt(15, peso: FontWeight.w600)),
            ),
            Switch(
              value: _cfg.getBool('assistente', 'conversa_continua', true),
              onChanged: (v) => setState(() => _cfg.set('assistente', 'conversa_continua', v)),
            ),
          ]),
          const SizedBox(height: 16),
          _campo('gemini_chave', 'Chave do Gemini',
              'aistudio.google.com → Get API key', Icons.key_rounded,
              secreto: true),
          _campo('groq_chave', 'Chave do Groq (reserva, opcional)',
              'console.groq.com → API Keys', Icons.key_rounded,
              secreto: true),
          Text(
            'Privacidade: no plano gratuito o Google pode usar o conteúdo para '
            'melhorar os produtos dele. Por isso só vão textos curtos já '
            'resumidos pelo app — nada de fotos, áudio ou corpo de e-mail.',
            style: _txt(12.5, cor: Colors.white38),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _botao(_testandoIa ? 'Testando...' : 'Testar a IA', Icons.bolt_rounded,
                _testandoIa ? null : _testarIa),
            const SizedBox(width: 14),
            Expanded(child: Text(_statusIa, style: _txt(14, cor: Colors.white))),
          ]),
        ]),
        const SizedBox(height: 28),
        _titulo('🗣️ Chamar pelo nome ("Hey Jarvis")'),
        const SizedBox(height: 14),
        _card([
          Text(
            'Diga "Hey Jarvis" de qualquer lugar da sala e ele começa a ouvir, sem tocar '
            'no microfone. Não precisa de conta nem chave: a escuta da palavra roda '
            'dentro do tablet (o áudio não sai dele); só depois do "Hey Jarvis" a '
            'frase vai para o reconhecimento de voz.',
            style: _txt(14),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Ouvir "Hey Jarvis"', style: _txt(15, peso: FontWeight.w600))),
            Switch(
              value: _cfg.getBool('assistente', 'palavra_ativacao', true),
              onChanged: (v) => setState(() => _cfg.set('assistente', 'palavra_ativacao', v)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Sensibilidade', style: _txt(15, peso: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            for (final (v, rotulo) in const [
              (0.4, 'Baixa (menos alarmes falsos)'),
              (0.6, 'Média'),
              (0.8, 'Alta (ouve de mais longe)'),
            ])
              ChoiceChip(
                label: Text(rotulo),
                selected: (_cfg.getDouble('assistente', 'palavra_sensibilidade', 0.6) - v).abs() < 0.01,
                onSelected: (_) => setState(() => _cfg.set('assistente', 'palavra_sensibilidade', v)),
              ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _botao('Aplicar', Icons.hearing_rounded, () async {
              await _cfg.salvar();
              await AssistenteService.instance.sincronizarPalavra(forcar: true);
              if (!mounted) return;
              final s = AssistenteService.instance.statusPalavra.value;
              setState(() => _statusPalavra = s.isEmpty
                  ? (_cfg.getBool('assistente', 'palavra_ativacao', true)
                      ? 'Pronto! Diga "Hey Jarvis" para testar.'
                      : 'Escuta da palavra desligada.')
                  : s);
            }),
            const SizedBox(width: 14),
            Expanded(child: Text(_statusPalavra, style: _txt(14, cor: Colors.white))),
          ]),
          const SizedBox(height: 10),
          Text('Modelo "hey jarvis" do projeto openWakeWord (David Scripka), '
              'licença CC BY-NC-SA 4.0.',
              style: _txt(12, cor: Colors.white30)),
        ]),
        const SizedBox(height: 28),
        _titulo('🔊 Voz do Jarvis'),
        const SizedBox(height: 14),
        _secaoVozJarvis(),
        const SizedBox(height: 14),
        _secaoMotorVoz(),
        const SizedBox(height: 28),
        _titulo('🎙️ Voz premium (ElevenLabs)'),
        const SizedBox(height: 14),
        _card([
          Text(
            'Uma voz natural para o briefing, as respostas e os gols. O plano '
            'gratuito dá ~20 minutos de fala por mês; perto do limite, o app '
            'volta sozinho para a voz do Android. Avisos curtos repetidos não gastam '
            'de novo (ficam guardados).',
            style: _txt(14),
          ),
          const SizedBox(height: 16),
          _campo('elevenlabs_chave', 'Chave da ElevenLabs',
              'elevenlabs.io → Developers → API Keys', Icons.key_rounded,
              secreto: true),
          Row(children: [
            _botao(_buscandoVozes ? 'Buscando...' : 'Carregar vozes',
                Icons.record_voice_over_rounded, _buscandoVozes ? null : _carregarVozes),
            const SizedBox(width: 14),
            Expanded(child: Text(_statusVozes, style: _txt(14))),
          ]),
          if (_vozes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Voz', style: _txt(15, peso: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final v in _vozes)
                  ChoiceChip(
                    // "padrão" = voz da própria ElevenLabs: funciona no plano gratuito.
                    label: Text(v.tipo == 'premade' ? '${v.nome} (padrão)' : v.nome),
                    selected: _cfg.getString('assistente', 'elevenlabs_voz', '') == v.id,
                    onSelected: (_) => setState(
                        () => _cfg.set('assistente', 'elevenlabs_voz', v.id)),
                  ),
              ],
            ),
          ] else if (_cfg.getString('assistente', 'elevenlabs_voz', '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Voz escolhida: ${_cfg.getString('assistente', 'elevenlabs_voz', '')}',
                style: _txt(13, cor: Colors.white54)),
          ],
          const SizedBox(height: 16),
          Text('Qualidade', style: _txt(15, peso: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            _modelo('eleven_flash_v2_5', 'Rápida e econômica (recomendada)'),
            _modelo('eleven_multilingual_v2', 'Mais expressiva (gasta 2x)'),
          ]),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: limite == 0 ? 0 : (uso / limite).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white10,
              color: uso > limite * 0.85 ? Colors.orangeAccent : _accent,
            ),
          ),
          const SizedBox(height: 6),
          Text('Usado este mês: $uso de $limite letras', style: _txt(13, cor: Colors.white54)),
          const SizedBox(height: 14),
          Row(children: [
            _botao(_testandoVoz ? 'Falando...' : 'Testar a voz', Icons.volume_up_rounded,
                _testandoVoz ? null : _testarVoz),
            const SizedBox(width: 14),
            Expanded(child: Text(_statusVoz, style: _txt(14, cor: Colors.white))),
          ]),
        ]),
        const SizedBox(height: 28),
        _titulo('📱 Casa pelo celular (Telegram)'),
        const SizedBox(height: 14),
        _secaoTelegram(),
        const SizedBox(height: 20),
        Text(
          'As chaves ficam guardadas só neste tablet. Não compartilhe prints desta tela.',
          style: _txt(13, cor: Colors.white38),
        ),
      ],
    );
  }

  Widget _secaoTelegram() {
    final tg = TelegramService.instance;
    return _card([
      Text(
        'Peça pelo celular, de qualquer lugar: /foto (foto agora pela câmera do painel), '
        '/audio 15 (15 segundos de áudio da casa) e /status. No Modo Ausente, se a câmera '
        'vir movimento, o painel manda uma foto sozinho.',
        style: _txt(14),
      ),
      const SizedBox(height: 14),
      Text('Como configurar (uma vez só):', style: _txt(14, peso: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
        '1. No Telegram do celular, abra o @BotFather e mande /newbot.\n'
        '2. Escolha um nome (ex.: Casa do Gabriel) e um usuário terminado em "bot".\n'
        '3. Ele responde com um TOKEN: copie e cole abaixo, depois toque em Conectar.\n'
        '4. Abra o seu bot no Telegram e mande o código de pareamento que vai aparecer aqui.',
        style: _txt(13.5, cor: Colors.white60),
      ),
      const SizedBox(height: 14),
      _campo('token', 'Token do bot', '123456789:ABC...', Icons.key_rounded,
          secreto: true, categoria: 'telegram'),
      Row(children: [
        _botao('Conectar', Icons.link_rounded, () async {
          await _cfg.salvar();
          await tg.reiniciar();
          if (mounted) setState(() {});
        }),
        const SizedBox(width: 14),
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: tg.status,
            builder: (_, s, __) => Text(s, style: _txt(14, cor: Colors.white)),
          ),
        ),
      ]),
      if (tg.configurado && !tg.pareado) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.pin_rounded, color: _accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text('No seu bot, mande:  /parear ${tg.codigo}',
                  style: _txt(18, cor: Colors.white, peso: FontWeight.w700)),
            ),
          ]),
        ),
      ],
      if (tg.pareado) ...[
        const SizedBox(height: 14),
        Row(children: [
          const Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text('Pareado com o seu celular.', style: _txt(14, cor: Colors.white))),
          TextButton(
            onPressed: () async {
              await tg.desparear();
              if (mounted) setState(() {});
            },
            child: const Text('Desparear'),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _botao('Testar: mandar uma foto', Icons.photo_camera_rounded,
              () => tg.enviarFotoAgora('Teste do painel 👋')),
        ]),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: Text('Alerta com foto no Modo Ausente', style: _txt(15, peso: FontWeight.w600)),
        ),
        Switch(
          value: _cfg.getBool('telegram', 'alerta_ausente', true),
          onChanged: (v) => setState(() => _cfg.set('telegram', 'alerta_ausente', v)),
        ),
      ]),
    ]);
  }

  Future<void> _testarIa() async {
    await _cfg.salvar();
    setState(() {
      _testandoIa = true;
      _statusIa = '';
    });
    String status;
    if (!IaService.instance.configurado) {
      status = 'Cole a chave do Gemini (ou do Groq) primeiro.';
    } else {
      final r = await JarvisService.instance
          .responder('Apresente-se em uma frase e diga como está o tempo agora.');
      status = r == null
          ? IaService.instance.motivoFalha
          : '${IaService.instance.ultimoProvedor}: $r';
    }
    if (!mounted) return;
    setState(() {
      _testandoIa = false;
      _statusIa = status;
    });
  }

  Future<void> _carregarVozes() async {
    final chave = _cfg.getString('assistente', 'elevenlabs_chave', '');
    if (chave.trim().isEmpty) {
      setState(() => _statusVozes = 'Cole a chave da ElevenLabs primeiro.');
      return;
    }
    setState(() {
      _buscandoVozes = true;
      _statusVozes = '';
    });
    try {
      final vozes = await VozService.instance.listarVozes(chave);
      if (!mounted) return;
      setState(() {
        _vozes = vozes;
        _statusVozes = vozes.isEmpty ? 'Nenhuma voz na conta.' : '${vozes.length} vozes. Escolha uma:';
        if (_cfg.getString('assistente', 'elevenlabs_voz', '').isEmpty && vozes.isNotEmpty) {
          _cfg.set('assistente', 'elevenlabs_voz', vozes.first.id);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusVozes = 'Não consegui buscar as vozes: confira a chave.');
    } finally {
      if (mounted) setState(() => _buscandoVozes = false);
    }
  }

  Future<void> _testarVoz() async {
    await _cfg.salvar();
    setState(() {
      _testandoVoz = true;
      _statusVoz = '';
    });
    final premium = VozService.instance.premiumConfigurado;
    await VozService.instance.falar(
        'Olá! Eu sou o ${JarvisService.instance.nomeAssistente}. É assim que eu vou falar com você.');
    await _atualizarUso();
    if (!mounted) return;
    setState(() {
      _testandoVoz = false;
      final erro = VozService.instance.ultimoErro;
      _statusVoz = !premium
          ? 'Sem chave/voz da ElevenLabs: usando a voz do Android.'
          : erro.isEmpty
              ? 'Voz premium funcionando.'
              : erro;
    });
  }

  Widget _modelo(String id, String rotulo) => ChoiceChip(
        label: Text(rotulo),
        selected: _cfg.getString('assistente', 'elevenlabs_modelo', 'eleven_flash_v2_5') == id,
        onSelected: (_) => setState(() => _cfg.set('assistente', 'elevenlabs_modelo', id)),
      );

  Widget _titulo(String t) => Row(children: [
        Container(width: 3, height: 20, color: _accent),
        const SizedBox(width: 12),
        Text(t, style: _txt(19, cor: Colors.white, peso: FontWeight.w700)),
      ]);

  Widget _card(List<Widget> filhos) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: filhos),
      );

  Widget _botao(String rotulo, IconData icone, VoidCallback? aoTocar) => FilledButton.icon(
        onPressed: aoTocar,
        icon: Icon(icone, size: 18),
        label: Text(rotulo),
        style: FilledButton.styleFrom(
          backgroundColor: _accent.withValues(alpha: 0.18),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      );

  Widget _campo(String chave, String rotulo, String dica, IconData icone,
      {bool secreto = false, String categoria = 'assistente'}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icone, color: _accent, size: 16),
            const SizedBox(width: 8),
            Text(rotulo, style: _txt(15, peso: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('${categoria}_$chave'),
            initialValue: _cfg.getString(categoria, chave, ''),
            obscureText: secreto,
            autocorrect: false,
            enableSuggestions: !secreto,
            style: GoogleFonts.figtree(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: dica,
              hintStyle: GoogleFonts.figtree(color: Colors.white24, fontSize: 14),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accent)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (v) => _cfg.set(categoria, chave, v.trim()),
          ),
        ],
      ),
    );
  }
}
