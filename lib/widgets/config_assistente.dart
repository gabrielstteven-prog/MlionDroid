import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config_manager.dart';
import '../services/ia_service.dart';
import '../services/jarvis_service.dart';
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

  @override
  void initState() {
    super.initState();
    _atualizarUso();
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
        const SizedBox(height: 20),
        Text(
          'As chaves ficam guardadas só neste tablet. Não compartilhe prints desta tela.',
          style: _txt(13, cor: Colors.white38),
        ),
      ],
    );
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
          ? 'Não respondeu. Confira a chave e a internet.'
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
      {bool secreto = false}) {
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
            key: ValueKey('assistente_$chave'),
            initialValue: _cfg.getString('assistente', chave, ''),
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
            onChanged: (v) => _cfg.set('assistente', chave, v.trim()),
          ),
        ],
      ),
    );
  }
}
