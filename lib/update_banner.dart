import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'update_manager.dart';

const _accentUpdate = Color(0xFF00D4FF);

/// Abre a folha de atualização por baixo, acionada pelo ícone redondo na
/// barra superior. Fica escondida o tempo todo — só existe quando o
/// usuário decide tocar no ícone, o que combina melhor com um tablet que
/// fica ligado o dia inteiro em modo vitrine (nada de banner interrompendo
/// sozinho a visualização das telas).
void abrirFolhaAtualizacao(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _FolhaAtualizacao(),
  );
}

class _FolhaAtualizacao extends StatelessWidget {
  const _FolhaAtualizacao();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: UpdateManager.instance,
      builder: (context, _) {
        final mgr = UpdateManager.instance;

        // Se o usuário dispensar (fechar) enquanto ainda há atualização
        // disponível, a folha simplesmente fecha — o ícone continua na
        // barra até a pessoa decidir atualizar de verdade.
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF0d1420),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _accentUpdate.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5), blurRadius: 30),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.system_update_rounded,
                        color: _accentUpdate, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Atualização disponível',
                        style: GoogleFonts.rajdhani(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  mgr.info != null ? 'Versão ${mgr.info!.versao}' : '',
                  style: GoogleFonts.rajdhani(
                      color: _accentUpdate,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Text(
                  (mgr.info?.changelog.isNotEmpty ?? false)
                      ? mgr.info!.changelog
                      : 'Nova versão pronta para instalar.',
                  style: GoogleFonts.rajdhani(
                      color: Colors.white70, fontSize: 15, height: 1.5),
                ),
                if (mgr.erroDownload != null) ...[
                  const SizedBox(height: 12),
                  Text(mgr.erroDownload!,
                      style: GoogleFonts.rajdhani(
                          color: Colors.redAccent, fontSize: 15)),
                ],
                const SizedBox(height: 24),
                if (mgr.baixando) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: mgr.progresso > 0 ? mgr.progresso : null,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(_accentUpdate),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Baixando... ${(mgr.progresso * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.rajdhani(
                        color: Colors.white38, fontSize: 13),
                  ),
                ] else
                  GestureDetector(
                    onTap: mgr.baixado
                        ? mgr.abrirInstaladorNovamente
                        : mgr.baixarEInstalar,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: _accentUpdate,
                      ),
                      child: Center(
                        child: Text(
                          mgr.baixado ? 'Instalar agora' : 'Baixar e instalar',
                          style: GoogleFonts.rajdhani(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Fechar',
                      style: GoogleFonts.rajdhani(
                          color: Colors.white38, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
