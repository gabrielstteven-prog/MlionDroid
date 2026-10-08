package com.example.flutter_application_1

import android.content.Context
import android.util.Log
import com.k2fsa.sherpa.onnx.GenerationConfig
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsSupertonicModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Voz no aparelho (grátis, sem conta, sem internet depois de baixar):
 * motor sherpa-onnx com vozes neurais em português.
 *
 *  • supertonic  — Supertonic 3 (Supertone, 10 vozes, a mais natural)
 *  • piper_faber — Piper pt-BR "Faber" (masculina)
 *  • piper_miro  — Piper pt-BR "Miro" (alta qualidade)
 *
 * Os pacotes vêm das releases públicas do sherpa-onnx no GitHub e ficam em
 * filesDir/vozes/<pasta>. A fala é gerada FRASE A FRASE: a primeira já toca
 * enquanto as próximas são preparadas (o Jarvis não fica mudo esperando).
 */
object VozLocal {
    private const val TAG = "MlionVozLocal"
    private const val BASE =
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/"

    data class Motor(val id: String, val pacote: String, val pasta: String)

    val motores = mapOf(
        "supertonic" to Motor(
            "supertonic",
            "sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2",
            "sherpa-onnx-supertonic-3-tts-int8-2026-05-11"
        ),
        "piper_faber" to Motor(
            "piper_faber", "vits-piper-pt_BR-faber-medium.tar.bz2", "vits-piper-pt_BR-faber-medium"
        ),
        "piper_miro" to Motor(
            "piper_miro", "vits-piper-pt_BR-miro-high.tar.bz2", "vits-piper-pt_BR-miro-high"
        ),
    )

    private var tts: OfflineTts? = null
    private var carregado: String? = null

    private fun dirVozes(ctx: Context) = File(ctx.filesDir, "vozes").apply { mkdirs() }

    fun instalado(ctx: Context, id: String): Boolean {
        val m = motores[id] ?: return false
        return File(dirVozes(ctx), "${m.pasta}/.ok").exists()
    }

    /** Baixa e descompacta o pacote. [progresso] recebe 0..1 (download). */
    fun baixar(ctx: Context, id: String, progresso: (Double) -> Unit): Boolean {
        val m = motores[id] ?: return false
        val destino = dirVozes(ctx)
        val tmp = File(ctx.cacheDir, m.pacote)
        try {
            var url = URL(BASE + m.pacote)
            var con: HttpURLConnection
            // O GitHub redireciona para o armazenamento dele: segue os redirects.
            var redirects = 0
            while (true) {
                con = url.openConnection() as HttpURLConnection
                con.instanceFollowRedirects = false
                con.connectTimeout = 20_000
                con.readTimeout = 60_000
                val code = con.responseCode
                if (code in 300..399 && redirects < 5) {
                    url = URL(url, con.getHeaderField("Location"))
                    con.disconnect()
                    redirects++
                    continue
                }
                if (code != 200) throw Exception("HTTP $code")
                break
            }
            val total = con.contentLengthLong
            con.inputStream.use { ent ->
                FileOutputStream(tmp).use { sai ->
                    val buf = ByteArray(64 * 1024)
                    var lidos = 0L
                    var ultimo = 0L
                    while (true) {
                        val n = ent.read(buf)
                        if (n < 0) break
                        sai.write(buf, 0, n)
                        lidos += n
                        if (total > 0 && lidos - ultimo > 512 * 1024) {
                            ultimo = lidos
                            progresso(lidos.toDouble() / total * 0.9)
                        }
                    }
                }
            }
            // Descompacta (.tar.bz2) — a última parte do progresso.
            progresso(0.92)
            File(destino, m.pasta).deleteRecursively()
            TarArchiveInputStream(BZip2CompressorInputStream(BufferedInputStream(tmp.inputStream()))).use { tar ->
                while (true) {
                    val e = tar.nextEntry ?: break
                    val f = File(destino, e.name)
                    // Proteção contra caminhos maliciosos ("../").
                    if (!f.canonicalPath.startsWith(destino.canonicalPath)) continue
                    if (e.isDirectory) {
                        f.mkdirs()
                    } else {
                        f.parentFile?.mkdirs()
                        FileOutputStream(f).use { tar.copyTo(it) }
                    }
                }
            }
            File(destino, "${m.pasta}/.ok").writeText("ok")
            progresso(1.0)
            Log.i(TAG, "voz $id instalada")
            return true
        } catch (e: Exception) {
            Log.w(TAG, "baixar $id: $e")
            return false
        } finally {
            tmp.delete()
        }
    }

    fun apagar(ctx: Context, id: String) {
        val m = motores[id] ?: return
        if (carregado == id) liberar()
        File(dirVozes(ctx), m.pasta).deleteRecursively()
    }

    fun liberar() {
        tts?.release()
        tts = null
        carregado = null
    }

    private fun carregar(ctx: Context, id: String): OfflineTts? {
        if (carregado == id && tts != null) return tts
        liberar()
        val m = motores[id] ?: return null
        val d = File(dirVozes(ctx), m.pasta).absolutePath
        val modelo = if (id == "supertonic") {
            OfflineTtsModelConfig(
                supertonic = OfflineTtsSupertonicModelConfig(
                    durationPredictor = "$d/duration_predictor.int8.onnx",
                    textEncoder = "$d/text_encoder.int8.onnx",
                    vectorEstimator = "$d/vector_estimator.int8.onnx",
                    vocoder = "$d/vocoder.int8.onnx",
                    ttsJson = "$d/tts.json",
                    unicodeIndexer = "$d/unicode_indexer.bin",
                    voiceStyle = "$d/voice.bin",
                ),
                numThreads = 4,
            )
        } else {
            val onnx = File(d).listFiles { f -> f.name.endsWith(".onnx") }?.firstOrNull()
                ?: return null
            OfflineTtsModelConfig(
                vits = OfflineTtsVitsModelConfig(
                    model = onnx.absolutePath,
                    tokens = "$d/tokens.txt",
                    dataDir = "$d/espeak-ng-data",
                ),
                numThreads = 4,
            )
        }
        return try {
            OfflineTts(config = OfflineTtsConfig(model = modelo)).also {
                tts = it
                carregado = id
            }
        } catch (e: Exception) {
            Log.w(TAG, "carregar $id: $e")
            null
        }
    }

    /**
     * Gera o áudio de UMA frase num .wav. [qualidade] (Supertonic): passos de
     * refinamento — mais passos = mais natural e mais lento.
     */
    @Synchronized
    fun gerarFrase(
        ctx: Context, id: String, texto: String, voz: Int, velocidade: Float,
        qualidade: Int, arquivo: File
    ): Boolean {
        val t = carregar(ctx, id) ?: return false
        return try {
            val audio = if (id == "supertonic") {
                t.generateWithConfig(
                    texto,
                    GenerationConfig(
                        sid = voz.coerceIn(0, 9),
                        speed = velocidade,
                        numSteps = qualidade.coerceIn(2, 12),
                        extra = mapOf("lang" to "pt"),
                    )
                )
            } else {
                t.generate(texto, sid = 0, speed = velocidade)
            }
            if (audio.samples.isEmpty()) return false
            audio.save(arquivo.absolutePath)
        } catch (e: Exception) {
            Log.w(TAG, "gerar: $e")
            false
        }
    }

    /** Divide em frases curtas (a primeira fica pronta logo). Função pura. */
    fun frases(texto: String): List<String> {
        val partes = texto.replace("\n", " ")
            .split(Regex("(?<=[.!?…])\\s+"))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        // Junta pedaços muito curtos com o seguinte ("Ok." + "Vamos lá.").
        val r = mutableListOf<String>()
        for (p in partes) {
            if (r.isNotEmpty() && r.last().length < 25) r[r.size - 1] = r.last() + " " + p
            else r.add(p)
        }
        return r
    }
}
