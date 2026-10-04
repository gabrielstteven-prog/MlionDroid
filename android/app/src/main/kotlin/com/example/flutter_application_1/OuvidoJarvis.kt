package com.example.flutter_application_1

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Ouve a palavra de ativação "Hey Jarvis" com o openWakeWord, rodando
 * inteiro no tablet (sem conta, sem chave, sem internet).
 *
 * Mesmo caminho do openWakeWord original (utils.py):
 *  áudio 16 kHz em blocos de 1280 amostras (80 ms)
 *   → espectrograma mel (com 480 amostras de sobreposição), x/10 + 2
 *   → "embedding" de 96 números a cada bloco, sobre os últimos 76 quadros
 *   → modelo "hey jarvis" sobre os últimos 16 embeddings → nota de 0 a 1.
 *
 * Modelos: github.com/dscripka/openWakeWord (CC BY-NC-SA 4.0).
 */
class OuvidoJarvis(
    ctx: Context,
    private val limiar: Float,
    private val aoOuvir: () -> Unit,
) {
    companion object {
        private const val TAG = "MlionJarvis"
        private const val TAXA = 16000
        private const val BLOCO = 1280
        private const val SOBRA = 480 // 160 * 3
    }

    private val mel = Interpreter(carregar(ctx, "wakeword/melspectrogram.tflite"))
    private val emb = Interpreter(carregar(ctx, "wakeword/embedding_model.tflite"))
    private val palavra = Interpreter(carregar(ctx, "wakeword/hey_jarvis_v0.1.tflite"))

    @Volatile private var rodando = false
    private var thread: Thread? = null

    private val bruto = FloatArray(BLOCO + SOBRA)
    private val quadrosMel = ArrayList<FloatArray>()
    private val recursos = ArrayList<FloatArray>()
    private var blocos = 0
    private var ultimoDisparo = 0L

    init {
        mel.resizeInput(0, intArrayOf(1, BLOCO + SOBRA))
        mel.allocateTensors()
        emb.resizeInput(0, intArrayOf(1, 76, 32, 1))
        emb.allocateTensors()
        repeat(76) { quadrosMel.add(FloatArray(32) { 1f }) } // igual ao original
    }

    private fun carregar(ctx: Context, nome: String): ByteBuffer {
        val bytes = ctx.assets.open(nome).use { it.readBytes() }
        return ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).apply {
            put(bytes)
            rewind()
        }
    }

    @SuppressLint("MissingPermission") // o chamador confere a permissão
    fun iniciar() {
        if (rodando) return
        rodando = true
        thread = Thread({
            val min = AudioRecord.getMinBufferSize(
                TAXA, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            val rec = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, TAXA,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                maxOf(min, BLOCO * 2 * 4))
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                Log.w(TAG, "microfone indisponível")
                rodando = false
                rec.release()
                return@Thread
            }
            val amostras = ShortArray(BLOCO)
            rec.startRecording()
            Log.i(TAG, "ouvindo \"Hey Jarvis\" (limiar $limiar)")
            try {
                while (rodando) {
                    var lidas = 0
                    while (lidas < BLOCO && rodando) {
                        val n = rec.read(amostras, lidas, BLOCO - lidas)
                        if (n <= 0) break
                        lidas += n
                    }
                    if (lidas == BLOCO) processar(amostras)
                }
            } catch (e: Exception) {
                Log.w(TAG, "escuta parou: $e")
            } finally {
                try { rec.stop() } catch (_: Exception) {}
                rec.release()
            }
        }, "ouvido-jarvis").also { it.start() }
    }

    fun parar() {
        rodando = false
        thread?.join(1500)
        thread = null
    }

    fun liberar() {
        parar()
        mel.close()
        emb.close()
        palavra.close()
    }

    private fun processar(bloco: ShortArray) {
        // Janela de áudio: as últimas 480 amostras + o bloco novo.
        System.arraycopy(bruto, BLOCO, bruto, 0, SOBRA)
        for (i in 0 until BLOCO) bruto[SOBRA + i] = bloco[i].toFloat()

        // 1) Espectrograma mel
        val entradaMel = ByteBuffer.allocateDirect(bruto.size * 4).order(ByteOrder.nativeOrder())
        bruto.forEach { entradaMel.putFloat(it) }
        entradaMel.rewind()
        val saidaMel = ByteBuffer.allocateDirect(mel.getOutputTensor(0).numBytes())
            .order(ByteOrder.nativeOrder())
        mel.run(entradaMel, saidaMel)
        saidaMel.rewind()
        val nQuadros = mel.getOutputTensor(0).numElements() / 32
        repeat(nQuadros) {
            quadrosMel.add(FloatArray(32) { saidaMel.float / 10f + 2f })
        }
        while (quadrosMel.size > 970) quadrosMel.removeAt(0)

        // 2) Embedding dos últimos 76 quadros
        val entradaEmb = ByteBuffer.allocateDirect(76 * 32 * 4).order(ByteOrder.nativeOrder())
        for (q in quadrosMel.subList(quadrosMel.size - 76, quadrosMel.size)) q.forEach { entradaEmb.putFloat(it) }
        entradaEmb.rewind()
        val saidaEmb = ByteBuffer.allocateDirect(emb.getOutputTensor(0).numBytes())
            .order(ByteOrder.nativeOrder())
        emb.run(entradaEmb, saidaEmb)
        saidaEmb.rewind()
        recursos.add(FloatArray(96) { saidaEmb.float })
        while (recursos.size > 120) recursos.removeAt(0)

        // 3) "Hey Jarvis"? Espera ~2 s de áudio real antes de valer.
        blocos++
        if (recursos.size < 16 || blocos < 25) return
        val entrada = ByteBuffer.allocateDirect(16 * 96 * 4).order(ByteOrder.nativeOrder())
        for (r in recursos.subList(recursos.size - 16, recursos.size)) r.forEach { entrada.putFloat(it) }
        entrada.rewind()
        val saida = ByteBuffer.allocateDirect(palavra.getOutputTensor(0).numBytes())
            .order(ByteOrder.nativeOrder())
        palavra.run(entrada, saida)
        saida.rewind()
        val nota = saida.float
        if (nota > 0.2f) Log.i(TAG, "nota ${"%.2f".format(nota)}")
        val agora = SystemClock.elapsedRealtime()
        if (nota >= limiar && agora - ultimoDisparo > 2000) {
            ultimoDisparo = agora
            aoOuvir()
        }
    }
}
