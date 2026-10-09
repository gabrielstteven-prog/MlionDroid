package com.example.flutter_application_1

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/**
 * O som do Jarvis quando começa e termina de ouvir, no lugar do "bip" do
 * reconhecimento de voz do Google (que não dá para trocar: o app silencia
 * o som do sistema por um instante enquanto o Google toca o dele).
 *
 * O som é gerado aqui mesmo (sem arquivo): duas notas suaves com um leve
 * brilho — subindo ao começar a ouvir, descendo ao terminar.
 */
object SomJarvis {
    private const val TAXA = 44100
    private val principal = Handler(Looper.getMainLooper())

    // Arpejo rápido de sino: Mi5 → Si5 → Mi6 (abre) e o contrário (fecha).
    private val abrir by lazy { gerar(listOf(659.25 to 0.0, 987.77 to 0.06, 1318.5 to 0.12)) }
    private val fechar by lazy { gerar(listOf(1318.5 to 0.0, 987.77 to 0.06, 659.25 to 0.12)) }

    private fun gerar(notas: List<Pair<Double, Double>>): ShortArray {
        val dur = 0.55
        val n = (TAXA * dur).toInt()
        val pcm = ShortArray(n)
        for (i in 0 until n) {
            val t = i / TAXA.toDouble()
            var v = 0.0
            for ((freq, inicio) in notas) {
                val tt = t - inicio
                if (tt < 0) continue
                // Sino: ataque seco, cauda curta e harmônicos que somem antes.
                val env = (1 - exp(-tt * 400)) * exp(-tt * 7)
                v += env * (sin(2 * PI * freq * tt) +
                    0.45 * exp(-tt * 10) * sin(2 * PI * freq * 2 * tt) +
                    0.2 * exp(-tt * 18) * sin(2 * PI * freq * 3.01 * tt))
            }
            pcm[i] = (v * 0.42 * Short.MAX_VALUE).toInt().coerceIn(-32767, 32767).toShort()
        }
        return pcm
    }

    private fun tocar(pcm: ShortArray) {
        try {
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(TAXA)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcm.size * 2)
                .build()
            track.write(pcm, 0, pcm.size)
            track.play()
            principal.postDelayed({ track.release() }, 800)
        } catch (_: Exception) {
        }
    }

    // ── Silenciar o "bip" do Google por um instante ─────────────────────────
    // O bip sai pelo som do sistema/notificação; a música (Spotify) não é
    // tocada. Sempre volta ao normal sozinho, mesmo se algo der errado.
    // Em tablet o "som do sistema" sai pelo canal da MÍDIA: silencia os três.
    private val streams = intArrayOf(
        AudioManager.STREAM_MUSIC, AudioManager.STREAM_SYSTEM, AudioManager.STREAM_NOTIFICATION)
    private var mudo = false
    private val voltar = Runnable { desmutar() }

    private fun am(ctx: Context) = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun mutar(ctx: Context, porMs: Long = 1500) {
        val a = am(ctx)
        if (!mudo) {
            for (s in streams) try {
                a.adjustStreamVolume(s, AudioManager.ADJUST_MUTE, 0)
            } catch (_: Exception) {}
            mudo = true
            appCtx = ctx.applicationContext
        }
        principal.removeCallbacks(voltar)
        principal.postDelayed(voltar, porMs)
    }

    private var appCtx: Context? = null

    fun desmutar() {
        val ctx = appCtx ?: return
        if (!mudo) return
        val a = am(ctx)
        for (s in streams) try {
            a.adjustStreamVolume(s, AudioManager.ADJUST_UNMUTE, 0)
        } catch (_: Exception) {}
        mudo = false
    }

    /** Antes de ouvir: toca o som do Jarvis e, quando ele acaba, silencia
     *  para o bip do Google e chama [depois] (que liga o reconhecimento). */
    fun antesDeOuvir(ctx: Context, depois: () -> Unit) {
        tocar(abrir)
        principal.postDelayed({
            mutar(ctx, 3000)
            depois()
        }, 380)
    }

    /** O Google já tocou o bip dele (mudo): o som volta ao normal. */
    fun ouvindo() {
        principal.postDelayed({ desmutar() }, 700)
    }

    /** Terminou de ouvir. */
    fun terminou() {
        principal.postDelayed({
            desmutar()
            tocar(fechar)
        }, 350)
    }
}
