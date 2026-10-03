import 'dart:async';

import 'package:flutter/material.dart';

import 'design/tema.dart';
import 'info_hub.dart';
import 'performance_manager.dart';
import 'responsive.dart';
import 'services/assistente_service.dart';
import 'services/football_service.dart';
import 'services/weather_service.dart';
import 'tela_spotify.dart' show SpotifyManager;
import 'update_banner.dart';
import 'update_manager.dart';
import 'util.dart';

/// Ícone e cor de destaque de cada tela (usado pela barra).
const Map<String, (IconData, Color)> iconesTelas = {
  'bom_dia': (Icons.wb_sunny_rounded, Destaques.bomDia),
  'clima': (Icons.cloud_rounded, Destaques.clima),
  'palmeiras': (Icons.sports_soccer_rounded, Destaques.time),
  'proxima_partida': (Icons.stadium_rounded, Destaques.partida),
  'classificacao': (Icons.leaderboard_rounded, Destaques.tabela),
  'calendario': (Icons.calendar_month_rounded, Destaques.agenda),
  'compras': (Icons.shopping_cart_rounded, Destaques.compras),
  'brasil': (Icons.public_rounded, Destaques.brasil),
  'regiao': (Icons.location_city_rounded, Destaques.regiao),
  'fotos': (Icons.photo_library_rounded, Destaques.fotos),
  'spotify': (Icons.music_note_rounded, Destaques.musica),
};

// ─────────────────────────────────────────────────────────────────────────────
//  Barra superior — transparente sobre o céu do app.
//  Esquerda: hora e data. Centro: clima. Direita: assistente, timers e
//  ajustes. Embaixo: faixa com frase, notícia, música ou lance do jogo.
//  Cada parte se redesenha sozinha (relógio só na virada do minuto).
// ─────────────────────────────────────────────────────────────────────────────
class BarraInfo extends StatelessWidget {
  final bool modoManual;
  final String telaAtual;
  final VoidCallback? aoAbrirConfig;

  const BarraInfo({
    super.key,
    this.modoManual = false,
    this.telaAtual = 'clima',
    this.aoAbrirConfig,
  });

  static double alturaTotal(BuildContext context) {
    final sh = MediaQuery.of(context).size.height;
    return (sh * 0.15).clamp(104.0, 164.0);
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final altura = alturaTotal(context);
    final alturaFaixa = (altura * 0.30).clamp(34.0, 50.0);
    final destaque = (iconesTelas[telaAtual] ?? (Icons.dashboard_rounded, Destaques.clima)).$2;

    return SizedBox(
      height: altura,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: r.sp(32)),
              child: Row(
                children: [
                  const _Relogio(),
                  SizedBox(width: r.sp(28)),
                  const Expanded(child: _Clima()),
                  ListenableBuilder(
                    listenable: UpdateManager.instance,
                    builder: (context, _) => UpdateManager.instance.disponivel
                        ? _BotaoRedondo(
                            icone: Icons.system_update_rounded,
                            cor: Cores.chuva,
                            dica: 'Atualização disponível',
                            aoTocar: () => abrirFolhaAtualizacao(context),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const _Temporizadores(),
                  if (modoManual)
                    Padding(
                      padding: EdgeInsets.only(right: r.sp(10)),
                      child: const Selo('Modo manual', cor: Cores.aviso, icone: Icons.touch_app_rounded),
                    ),
                  _BotaoAssistente(destaque: destaque),
                  if (aoAbrirConfig != null)
                    _BotaoRedondo(
                      icone: Icons.settings_rounded,
                      cor: Cores.textoSecundario,
                      dica: 'Configurações',
                      aoTocar: aoAbrirConfig!,
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: alturaFaixa, child: _Faixa(destaque: destaque)),
        ],
      ),
    );
  }
}

class _Relogio extends StatelessWidget {
  const _Relogio();

  @override
  Widget build(BuildContext context) {
    final t = Tipo.de(context);
    return ValueListenableBuilder<DateTime>(
      valueListenable: InfoHub.instance.relogio,
      builder: (context, agora, _) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(horaMinuto(agora), style: t.numero().copyWith(fontWeight: FontWeight.w400)),
          Text('${diaSemanaLongo(agora)}, ${agora.day} de ${mesesLongos[agora.month - 1]}',
              style: t.apoio()),
        ],
      ),
    );
  }
}

class _Clima extends StatelessWidget {
  const _Clima();

  @override
  Widget build(BuildContext context) {
    final t = Tipo.de(context);
    final r = t.r;
    return ListenableBuilder(
      listenable: InfoHub.instance,
      builder: (context, _) {
        final hub = InfoHub.instance;
        final c = hub.clima;
        if (c == null) {
          return Align(
            alignment: Alignment.centerLeft,
            child: hub.climaCarregando
                ? const SizedBox.shrink()
                : Text('Sem dados de clima', style: t.apoio()),
          );
        }
        final chuva = c.chuvaRestanteHoje();
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(emojiClima(c.codigo, ehDia: c.ehDia),
                  style: TextStyle(fontSize: r.fs(34))),
              SizedBox(width: r.sp(12)),
              Text('${c.temp}°', style: t.numero()),
              SizedBox(width: r.sp(14)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(hub.cidadeLabel, style: t.corpo(peso: FontWeight.w600)),
                  Text(
                    chuva.maxima >= 30
                        ? 'Sensação ${c.sensacao}°, chuva ${chuva.maxima}%'
                        : 'Sensação ${c.sensacao}°, ${descricaoClima(c.codigo).toLowerCase()}',
                    style: t.apoio(cor: chuva.maxima >= 30 ? Cores.chuva : Cores.textoSecundario),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BotaoRedondo extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String dica;
  final VoidCallback aoTocar;
  final bool cheio;
  const _BotaoRedondo({
    required this.icone,
    required this.cor,
    required this.dica,
    required this.aoTocar,
    this.cheio = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Padding(
      padding: EdgeInsets.only(left: r.sp(10)),
      child: Tooltip(
        message: dica,
        child: GestureDetector(
          onTap: aoTocar,
          child: Container(
            width: r.sp(52),
            height: r.sp(52),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cheio ? cor : cor.withValues(alpha: 0.14),
            ),
            child: Icon(icone, color: cheio ? Colors.black : cor, size: r.icon(26)),
          ),
        ),
      ),
    );
  }
}

/// Botão do assistente de voz — o "Alexa" do painel.
class _BotaoAssistente extends StatelessWidget {
  final Color destaque;
  const _BotaoAssistente({required this.destaque});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AssistenteService.instance,
      builder: (context, _) {
        final a = AssistenteService.instance;
        final ativo = a.estado != EstadoAssistente.parado;
        return _BotaoRedondo(
          icone: ativo ? Icons.graphic_eq_rounded : Icons.mic_rounded,
          cor: destaque,
          cheio: ativo,
          dica: 'Falar com o assistente',
          aoTocar: a.ouvir,
        );
      },
    );
  }
}

/// Temporizadores ativos, com contagem regressiva.
class _Temporizadores extends StatefulWidget {
  const _Temporizadores();

  @override
  State<_Temporizadores> createState() => _TemporizadoresState();
}

class _TemporizadoresState extends State<_Temporizadores> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    AssistenteService.instance.addListener(_mudou);
    _mudou();
  }

  void _mudou() {
    final tem = AssistenteService.instance.temporizadores.isNotEmpty;
    if (tem && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!tem) {
      _tick?.cancel();
      _tick = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AssistenteService.instance.removeListener(_mudou);
    _tick?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '$h:${doisDigitos(m)}:${doisDigitos(s)}' : '$m:${doisDigitos(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Tipo.de(context);
    final r = t.r;
    final lista = AssistenteService.instance.temporizadores;
    if (lista.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final tm in lista)
          Padding(
            padding: EdgeInsets.only(left: r.sp(10)),
            child: GestureDetector(
              onTap: () => AssistenteService.instance.dispensar(tm.id),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: r.sp(14), vertical: r.sp(8)),
                decoration: BoxDecoration(
                  color: tm.tocando ? Cores.aviso : Cores.superficieElevada,
                  borderRadius: BorderRadius.circular(r.sp(30)),
                ),
                child: Row(children: [
                  Icon(tm.tocando ? Icons.alarm_on_rounded : Icons.timer_outlined,
                      size: r.icon(20),
                      color: tm.tocando ? Colors.black : Cores.aviso),
                  SizedBox(width: r.sp(8)),
                  Text(tm.tocando ? 'Terminou' : _fmt(tm.restante),
                      style: t.corpo(
                          cor: tm.tocando ? Colors.black : Cores.texto,
                          peso: FontWeight.w700)),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

/// Faixa inferior da barra. Prioridade: lance de jogo ao vivo → música
/// tocando → frases e manchetes.
class _Faixa extends StatefulWidget {
  final Color destaque;
  const _Faixa({required this.destaque});

  @override
  State<_Faixa> createState() => _FaixaState();
}

class _FaixaState extends State<_Faixa> {
  String? _lance;
  Timer? _limparLance;

  @override
  void initState() {
    super.initState();
    FootballService.instance.ultimoLance.addListener(_novoLance);
  }

  void _novoLance() {
    final l = FootballService.instance.ultimoLance.value;
    if (l == null) return;
    setState(() => _lance = l);
    _limparLance?.cancel();
    _limparLance = Timer(const Duration(minutes: 3), () {
      if (mounted) setState(() => _lance = null);
    });
  }

  @override
  void dispose() {
    FootballService.instance.ultimoLance.removeListener(_novoLance);
    _limparLance?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tipo.de(context);
    final r = t.r;
    return ListenableBuilder(
      listenable: InfoHub.instance,
      builder: (context, _) {
        final hub = InfoHub.instance;
        final IconData icone;
        final Color cor;
        final String texto;
        Widget? capa;
        if (_lance != null) {
          icone = Icons.sports_soccer_rounded;
          cor = Destaques.partida;
          texto = _lance!;
        } else if (hub.spotifyTocando) {
          icone = Icons.music_note_rounded;
          cor = Destaques.musica;
          texto = 'Tocando agora: ${hub.spotifyTitulo}, de ${hub.spotifyArtista}';
          final bytes = SpotifyManager.instance.albumArtBytes;
          if (bytes != null) {
            capa = ClipRRect(
              borderRadius: BorderRadius.circular(r.sp(6)),
              child: Image.memory(bytes,
                  width: r.sp(28), height: r.sp(28), fit: BoxFit.cover, gaplessPlayback: true),
            );
          }
        } else {
          final atual = hub.tickerAtual;
          final frase = atual.startsWith('💡');
          icone = frase ? Icons.format_quote_rounded : Icons.article_outlined;
          cor = widget.destaque;
          texto = atual.replaceFirst(RegExp(r'^(💡|📰|🎵)\s*'), '');
        }
        return Container(
          padding: EdgeInsets.symmetric(horizontal: r.sp(32)),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.16),
            border: Border(top: BorderSide(color: Cores.contorno)),
          ),
          child: Row(
            children: [
              capa ?? Icon(icone, color: cor, size: r.icon(20)),
              SizedBox(width: r.sp(12)),
              Expanded(
                child: RepaintBoundary(
                  child: _TextoRolante(
                    key: ValueKey(texto),
                    texto: texto,
                    estilo: t.apoio(cor: Cores.texto),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Texto que rola quando não cabe na largura.
class _TextoRolante extends StatefulWidget {
  final String texto;
  final TextStyle estilo;
  const _TextoRolante({super.key, required this.texto, required this.estilo});

  @override
  State<_TextoRolante> createState() => _TextoRolanteState();
}

class _TextoRolanteState extends State<_TextoRolante>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);
  double _larguraTexto = 0;
  double _larguraVista = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _medir());
  }

  void _medir() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final tp = TextPainter(
      text: TextSpan(text: widget.texto, style: widget.estilo),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    _larguraTexto = tp.width;
    _larguraVista = box.size.width;
    if (_larguraTexto > _larguraVista - 8 &&
        !PerformanceManager.instance.modoEconomico) {
      _ctrl.duration = Duration(
          seconds: ((_larguraTexto + _larguraVista) / 70).clamp(8.0, 30.0).round());
      _ctrl.repeat();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ctrl.isAnimating) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(widget.texto,
            style: widget.estilo, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return ClipRect(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.translate(
          offset: Offset(_larguraVista - _ctrl.value * (_larguraTexto + _larguraVista), 0),
          child: child,
        ),
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: Text(widget.texto, style: widget.estilo, maxLines: 1, softWrap: false),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MlionShell — céu + barra superior + tela atual
// ─────────────────────────────────────────────────────────────────────────────
class MlionShell extends StatelessWidget {
  final Widget child;
  final bool modoManual;
  final bool mostrarBarra;
  final String telaAtual;
  final VoidCallback? aoAbrirConfig;

  const MlionShell({
    super.key,
    required this.child,
    this.modoManual = false,
    this.mostrarBarra = true,
    this.telaAtual = 'clima',
    this.aoAbrirConfig,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: InfoHub.instance.relogio,
      builder: (context, agora, conteudo) =>
          CeuDeFundo(agora: agora, child: conteudo!),
      child: mostrarBarra
          ? Column(
              children: [
                BarraInfo(
                  modoManual: modoManual,
                  telaAtual: telaAtual,
                  aoAbrirConfig: aoAbrirConfig,
                ),
                Expanded(child: child),
              ],
            )
          : child,
    );
  }
}
