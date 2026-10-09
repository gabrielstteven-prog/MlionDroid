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

    // Mi5 → Si5 (abre) e Si5 → Mi5 (fecha): um intervalo de quinta, suave.
    private val abrir by lazy { gerar(listOf(659.25 to 0.0, 987.77 to 0.085)) }
    private val fechar by lazy { gerar(listOf(987.77 to 0.0, 659.25 to 0.085)) }

    private fun gerar(notas: List<Pair<Double, Double>>): ShortArray {
        val dur = 0.42
        val n = (TAXA * dur).toInt()
        val pcm = ShortArray(n)
        for (i in 0 until n) {
            val t = i / TAXA.toDouble()
            var v = 0.0
            for ((freq, inicio) in notas) {
                val tt = t - inicio
                if (tt < 0) continue
                // Ataque rápido e cauda curta, com um harmônico de "vidro".
                val env = (1 - exp(-tt * 180)) * exp(-tt * 9)
                v += env * (sin(2 * PI * freq * tt) + 0.25 * sin(2 * PI * freq * 2 * tt))
            }
            pcm[i] = (v * 0.22 * Short.MAX_VALUE).toInt().coerceIn(-32767, 32767).toShort()
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
    private val streams = intArrayOf(AudioManager.STREAM_SYSTEM, AudioManager.STREAM_NOTIFICATION)
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

    /** Começou a ouvir: o bip do Google já tocou (mudo); toca o do Jarvis. */
    fun ouvindo() {
        principal.postDelayed({
            desmutar()
            tocar(abrir)
        }, 250)
    }

    /** Terminou de ouvir. */
    fun terminou() {
        principal.postDelayed({
            desmutar()
            tocar(fechar)
        }, 350)
    }
}
