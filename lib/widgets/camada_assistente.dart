
import 'package:flutter/material.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

import '../design/tema.dart';
import '../responsive.dart';
import '../services/assistente_service.dart';
import '../services/jarvis_service.dart';
import '../config_manager.dart';
import 'rosto_jarvis.dart';

/// Camada que fica por cima de todas as telas:
///  • balão do assistente (o que você falou e a resposta);
///  • aviso de tela cheia quando um temporizador termina.
/// Sem nada para mostrar, não intercepta toques.
class CamadaAssistente extends StatelessWidget {
  const CamadaAssistente({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AssistenteService.instance,
      builder: (context, _) {
        final a = AssistenteService.instance;
        final tocando = a.temporizadores.where((t) => t.tocando).toList();
        if (tocando.isNotEmpty) return _AlarmeTela(t: tocando.first);
        if (a.estado == EstadoAssistente.parado) return const SizedBox.shrink();
        return _Balao(a: a);
      },
    );
  }
}

class _Balao extends StatelessWidget {
  final AssistenteService a;
  const _Balao({required this.a});

  String get _status => switch (a.estado) {
        EstadoAssistente.ouvindo => 'Ouvindo...',
        EstadoAssistente.pensando => 'Pensando...',
        _ => '',
      };

  String get _dica => a.emConversa
      ? 'Pode continuar falando · diga "tchau" para encerrar · toque para fechar'
      : 'Toque para fechar';

  @override
  Widget build(BuildContext context) {
    if (a.ultimoCard != null) return _comCartao(context);
    if (a.telaAberta) return _compacto(context);
    return _centralizado(context);
  }

  /// Modo padrão: tela escurecida, orbe grande no centro.
  Widget _centralizado(BuildContext context) {
    final t = Tipo.de(context);
    final r = t.r;
    final nome = JarvisService.instance.nomeAssistente.toUpperCase();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: a.fechar,
      child: ColoredBox(
        color: const Color(0xE6060B16),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(r.sp(40)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: r.sp(1100)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Com foto ("olha o que eu tenho na mão"): orbe menor e a
                  // foto ao lado, para a pessoa ver o que o Jarvis viu.
                  if (a.ultimaFoto != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AvatarJarvis(estado: a.estado, tamanho: r.sp(160)),
                        SizedBox(width: r.sp(28)),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(r.sp(20)),
                          child: Image.memory(a.ultimaFoto!,
                              height: r.sp(260), fit: BoxFit.contain, gaplessPlayback: true),
                        ),
                      ],
                    )
                  else
                    AvatarJarvis(estado: a.estado, tamanho: r.sp(240)),
                  SizedBox(height: r.sp(18)),
                  Text(nome,
                      style: t.legenda(cor: _corDoEstado(a.estado)).copyWith(
                          letterSpacing: 6, fontWeight: FontWeight.w800)),
                  ..._textos(t, r, TextAlign.center),
                  SizedBox(height: r.sp(24)),
                  Text(_dica, style: t.legenda()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// O Jarvis abriu uma tela (clima, notícias, jogo): barra compacta embaixo,
  /// a tela fica visível enquanto ele fala.
  Widget _compacto(BuildContext context) {
    final t = Tipo.de(context);
    final r = t.r;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: a.fechar,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(r.sp(32), r.sp(60), r.sp(32), r.sp(24)),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00060B16), Color(0xE6060B16), Color(0xF5060B16)],
              stops: [0, 0.35, 1],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AvatarJarvis(estado: a.estado, tamanho: r.sp(120)),
              SizedBox(width: r.sp(24)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._textos(t, r, TextAlign.left, maxLinhas: 4),
                    SizedBox(height: r.sp(10)),
                    Text(_dica, style: t.legenda()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Receita, lista, passo a passo: orbe e fala à esquerda, cartão à direita.
  Widget _comCartao(BuildContext context) {
    final t = Tipo.de(context);
    final r = t.r;
    final card = a.ultimoCard!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: a.fechar,
      child: ColoredBox(
        color: const Color(0xE6060B16),
        child: Padding(
          padding: EdgeInsets.all(r.sp(36)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AvatarJarvis(estado: a.estado, tamanho: r.sp(170)),
                    ..._textos(t, r, TextAlign.center, maxLinhas: 6),
                    SizedBox(height: r.sp(18)),
                    Text(_dica, textAlign: TextAlign.center, style: t.legenda()),
                  ],
                ),
              ),
              SizedBox(width: r.sp(32)),
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: () {}, // tocar no cartão (para rolar) não fecha
                  child: Container(
                    padding: EdgeInsets.all(r.sp(28)),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(r.sp(28)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.12),
                          Colors.white.withValues(alpha: 0.04),
                        ],
                      ),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (card.titulo.isNotEmpty) Text(card.titulo, style: t.titulo()),
                        for (final (titulo, itens) in card.secoes) ...[
                          SizedBox(height: r.sp(22)),
                          if (titulo.isNotEmpty)
                            Text(titulo.toUpperCase(),
                                style: t
                                    .legenda(cor: const Color(0xFF7FE3FF))
                                    .copyWith(letterSpacing: 3, fontWeight: FontWeight.w800)),
                          SizedBox(height: r.sp(10)),
                          for (var i = 0; i < itens.length; i++)
                            Padding(
                              padding: EdgeInsets.only(bottom: r.sp(10)),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: r.sp(34),
                                    child: Text(
                                        _numerado(titulo) ? '${i + 1}.' : '•',
                                        style: t.corpo(cor: const Color(0xFF7FE3FF))),
                                  ),
                                  Expanded(child: Text(itens[i], style: t.corpo())),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Modo de preparo" e "passo a passo" ganham números; o resto, marcadores.
  static bool _numerado(String titulo) {
    final s = titulo.toLowerCase();
    return s.contains('preparo') || s.contains('passo') || s.contains('etapa');
  }

  List<Widget> _textos(Tipo t, R r, TextAlign alinhamento, {int? maxLinhas}) => [
        if (a.ultimaFala.isNotEmpty) ...[
          SizedBox(height: r.sp(14)),
          Text('"${a.ultimaFala}"',
              textAlign: alinhamento,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.corpo(cor: Cores.textoSecundario)),
        ],
        if (_status.isNotEmpty) ...[
          SizedBox(height: r.sp(10)),
          Text(_status, style: t.subtitulo()),
        ],
        if (a.ultimaResposta.isNotEmpty) ...[
          SizedBox(height: r.sp(12)),
          Text(a.ultimaResposta,
              textAlign: alinhamento,
              maxLines: maxLinhas,
              overflow: maxLinhas == null ? null : TextOverflow.ellipsis,
              style: t.subtitulo()),
        ],
      ];
}

Color _corDoEstado(EstadoAssistente e) => switch (e) {
      EstadoAssistente.ouvindo => const Color(0xFF4FD8FF),
      EstadoAssistente.pensando => const Color(0xFF9C8CFF),
      EstadoAssistente.respondendo => const Color(0xFF5CF2C8),
      EstadoAssistente.parado => const Color(0xFF4FD8FF),
    };

/// Orbe do Jarvis: os orbes pontilhados do "thinking-orbs" (Jakub Antalik,
/// licença MIT; versão Flutter de Leo Marciano). Um desenho para cada
/// momento: respirando parado, ouvindo, pensando e falando. O desenho
/// original tem 64 px; aqui ele é ampliado para o tamanho do Jarvis.
class OrbeJarvis extends StatelessWidget {
  final EstadoAssistente estado;
  final double tamanho;
  const OrbeJarvis({super.key, required this.estado, required this.tamanho});

  @override
  Widget build(BuildContext context) {
    final forma = switch (estado) {
      EstadoAssistente.parado => OrbState.breathing,
      EstadoAssistente.ouvindo => OrbState.listening,
      EstadoAssistente.pensando => OrbState.solving,
      EstadoAssistente.respondendo => OrbState.composing,
    };
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: tamanho,
        child: FittedBox(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: ThinkingOrb(
              key: ValueKey(forma),
              state: forma,
              color: _corDoEstado(estado),
              semanticLabel: 'Jarvis',
            ),
          ),
        ),
      ),
    );
  }
}

class _AlarmeTela extends StatelessWidget {
  final Temporizador t;
  const _AlarmeTela({required this.t});

  @override
  Widget build(BuildContext context) {
    final tipo = Tipo.de(context);
    final r = tipo.r;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AssistenteService.instance.dispensar(t.id),
      child: ColoredBox(
        color: const Color(0xF20E1628),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.alarm_on_rounded,
                  color: Cores.aviso, size: r.icon(96)),
              SizedBox(height: r.sp(16)),
              Text('Temporizador de ${t.rotulo} terminou',
                  textAlign: TextAlign.center, style: tipo.titulo()),
              SizedBox(height: r.sp(12)),
              Text('Toque em qualquer lugar para parar o alarme',
                  style: tipo.corpo(cor: Cores.textoSecundario)),
            ],
          ),
        ),
      ),
    );
  }
}

/// O "corpo" do Jarvis na tela: o rosto com emoções (padrão, estilo
/// Stack-chan) ou o orbe antigo (Configurações > Assistente > Visual).
class AvatarJarvis extends StatelessWidget {
  final EstadoAssistente estado;
  final double tamanho;
  final Emocao? emocao;
  const AvatarJarvis({super.key, required this.estado, required this.tamanho, this.emocao});

  @override
  Widget build(BuildContext context) {
    if (ConfigManager().getString('assistente', 'visual', 'rosto') == 'orbe') {
      return OrbeJarvis(estado: estado, tamanho: tamanho);
    }
    return RostoJarvis(
      estado: estado,
      emocao: emocao ?? AssistenteService.instance.emocao,
      tamanho: tamanho * 1.25,
    );
  }
}
