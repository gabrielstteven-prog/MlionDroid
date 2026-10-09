import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'config_manager.dart';
import 'design/icones.dart';
import 'design/tema.dart';
import 'info_hub.dart';
import 'performance_manager.dart';
import 'responsive.dart';
import 'services/assistente_service.dart';
import 'services/football_service.dart';
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

  /// Telas do rodízio, na ordem (para os pontinhos de navegação).
  final List<String> telasRodizio;

  const BarraInfo({
    super.key,
    this.modoManual = false,
    this.telaAtual = 'clima',
    this.aoAbrirConfig,
    this.telasRodizio = const [],
  });

  static double alturaTotal(BuildContext context) {
    final sh = MediaQuery.of(context).size.height;
    // +4: a folguinha entre o relógio e a faixa de notícias.
    return (sh * 0.15).clamp(104.0, 164.0) + 4;
  }

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    final altura = alturaTotal(context);
    final alturaFaixa = ((altura - 4) * 0.30).clamp(34.0, 50.0) + 4;
    final destaque = (iconesTelas[telaAtual] ?? (Icons.dashboard_rounded, Destaques.clima)).$2;
    final comPontos = telasRodizio.length > 1 &&
        ConfigManager().getBool('barra_info', 'mostrar_pontos', true);

    return SizedBox(
      height: altura,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: r.sp(32)),
              child: Row(
                children: [
                  // Relógio à esquerda, clima ao centro, ações à direita.
                  const Expanded(
                      child: Align(alignment: Alignment.centerLeft, child: _Relogio())),
                  // Na tela de Clima o tempo já está em destaque: o topo fica
                  // livre.
                  if (telaAtual != 'clima') const _Clima(),
                  const Expanded(child: SizedBox()),
                  // Em dia de jogo, o cartão do jogo fica à direita, junto das
                  // ações (na tela da Próxima Partida ele seria repetido).
                  if (telaAtual != 'proxima_partida') const _PlacarAoVivo(),
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
          // Faixa de frases/notícias em cápsula arredondada, "flutuando", com
          // os pontinhos de navegação numa pílula própria ao lado.
          Padding(
            // Folga em cima: a cápsula não fica "embutida" no cabeçalho.
            padding: EdgeInsets.fromLTRB(r.sp(24), 4, r.sp(24), r.sp(8)),
            child: SizedBox(
              height: alturaFaixa - 4 - r.sp(8), // mesma altura da cápsula de antes
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _Faixa(destaque: destaque)),
                  if (comPontos) ...[
                    SizedBox(width: r.sp(10)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: r.sp(14)),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(r.sp(40)),
                        border: Border.all(color: Cores.contorno),
                      ),
                      child: _Pontos(
                          telas: telasRodizio, atual: telaAtual, cor: destaque),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
          return hub.climaCarregando
              ? const SizedBox.shrink()
              : Text('Sem dados de clima', style: t.apoio());
        }
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconeClima(codigo: c.codigo, ehDia: c.ehDia, tamanho: r.icon(60)),
              SizedBox(width: r.sp(8)),
              Text('${c.temp}°', style: t.numero()),
              SizedBox(width: r.sp(16)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(hub.cidadeLabel, style: t.corpo(peso: FontWeight.w700)),
                  Text('Sensação de ${c.sensacao}°', style: t.apoio()),
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
          padding: EdgeInsets.symmetric(horizontal: r.sp(20)),
          clipBehavior: Clip.antiAlias, // o texto rolando respeita a curva
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(r.sp(40)),
            border: Border.all(color: Cores.contorno),
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
  final List<String> telasRodizio;

  const MlionShell({
    super.key,
    required this.child,
    this.modoManual = false,
    this.mostrarBarra = true,
    this.telaAtual = 'clima',
    this.aoAbrirConfig,
    this.telasRodizio = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: InfoHub.instance.relogio,
      builder: (context, agora, conteudo) =>
          CeuDeFundo(
        agora: agora,
        // Material transparente: dá a todos os textos um estilo base. Sem
        // ele o Flutter desenhava o sublinhado amarelo de aviso (o
        // "tracinho" que aparecia embaixo do ícone do clima).
        child: Material(type: MaterialType.transparency, child: conteudo!),
      ),
      child: mostrarBarra
          ? Column(
              children: [
                BarraInfo(
                  modoManual: modoManual,
                  telaAtual: telaAtual,
                  aoAbrirConfig: aoAbrirConfig,
                  telasRodizio: telasRodizio,
                ),
                Expanded(child: child),
              ],
            )
          : child,
    );
  }
}

/// Cartão do jogo no topo: aparece sozinho perto do jogo do time (até 90 min
/// antes, durante e 30 min depois). Escudo × escudo e, embaixo, discreto:
/// "começa em 25 min", o minuto ao vivo ou "Fim".
class _PlacarAoVivo extends StatefulWidget {
  const _PlacarAoVivo();

  @override
  State<_PlacarAoVivo> createState() => _PlacarAoVivoState();
}

class _PlacarAoVivoState extends State<_PlacarAoVivo> {
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    // A contagem ("começa em 24 min") anda sozinha.
    _relogio = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && FootballService.instance.jogoDoMomento.value?.agendada == true) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tipo.de(context);
    final r = t.r;
    return ValueListenableBuilder<Partida?>(
      valueListenable: FootballService.instance.jogoDoMomento,
      builder: (context, p, _) {
        if (p == null) return const SizedBox.shrink();
        final tam = r.icon(36);
        Widget escudo(TimePartida time) => time.escudo.isEmpty
            ? Icon(Icons.shield_rounded, color: Cores.textoApagado, size: tam)
            : CachedNetworkImage(
                imageUrl: time.escudo,
                width: tam,
                height: tam,
                errorWidget: (_, __, ___) =>
                    Icon(Icons.shield_rounded, color: Cores.textoApagado, size: tam),
              );
        final aoVivo = p.aoVivo;
        final cor = aoVivo ? Cores.alerta : Cores.textoSecundario;
        final meio = p.agendada
            ? Text('×', style: t.subtitulo(cor: Cores.textoSecundario))
            : Text('${p.mandante.gols ?? 0} × ${p.visitante.gols ?? 0}',
                style: t.subtitulo().copyWith(fontWeight: FontWeight.w800));
        final status = aoVivo
            ? (p.detalhe.isNotEmpty && p.relogio.isEmpty ? p.detalhe : p.relogio)
            : p.encerrada
                ? 'Fim de jogo'
                : textoContagem(p.data, DateTime.now());
        return Padding(
          padding: EdgeInsets.only(right: r.sp(14)),
          child: Container(
            padding: EdgeInsets.fromLTRB(r.sp(20), r.sp(6), r.sp(20), r.sp(6)),
            // Mesmo vidro escuro das cápsulas da barra (faixa e pontinhos).
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(r.sp(22)),
              border: Border.all(color: aoVivo ? cor.withValues(alpha: 0.7) : Cores.contorno),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    escudo(p.mandante),
                    SizedBox(width: r.sp(12)),
                    meio,
                    SizedBox(width: r.sp(12)),
                    escudo(p.visitante),
                  ],
                ),
                SizedBox(height: r.sp(3)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (aoVivo)
                      Container(
                        width: r.sp(8),
                        height: r.sp(8),
                        margin: EdgeInsets.only(right: r.sp(6)),
                        decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                      )
                    else if (p.agendada)
                      Padding(
                        padding: EdgeInsets.only(right: r.sp(5)),
                        child: Icon(Icons.schedule_rounded, size: r.icon(14), color: cor),
                      ),
                    Text(status, style: t.legenda(cor: cor)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "começa em 25 min", "começa em 1h05", "começa em instantes", "às 21:30".
/// Função pura — testada.
String textoContagem(DateTime inicio, DateTime agora) {
  final min = inicio.difference(agora).inSeconds / 60;
  if (min <= 1) return 'começa em instantes';
  final m = min.ceil();
  if (m < 60) return 'começa em $m min';
  if (m <= 180) return 'começa em ${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
  return 'às ${horaMinuto(inicio)}';
}

/// Pontinhos de navegação do rodízio: a tela atual vira um tracinho na cor
/// dela; as outras são pontos apagados.
class _Pontos extends StatelessWidget {
  final List<String> telas;
  final String atual;
  final Color cor;
  const _Pontos({required this.telas, required this.atual, required this.cor});

  @override
  Widget build(BuildContext context) {
    final r = R(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in telas)
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.symmetric(horizontal: r.sp(3)),
            width: r.sp(t == atual ? 22 : 7),
            height: r.sp(7),
            decoration: BoxDecoration(
              color: t == atual ? cor : Colors.white.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(r.sp(4)),
            ),
          ),
      ],
    );
  }
}
