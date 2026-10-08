package com.example.flutter_application_1

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL

/**
 * A voz do Jarvis (Qwen3-TTS 0.6B, Apache-2.0) gerada NO APARELHO, com a voz
 * clonada do dono (um arquivo de 4 KB com o "timbre").
 *
 * É uma voz de altíssima qualidade (risada, emoção), mas pesada: neste tablet
 * leva ~6x o tempo da fala. Por isso ela NÃO fala ao vivo — o app gera antes
 * (Bom Dia às 4h, resumo da noite, frases frequentes) e guarda os áudios.
 *
 * O motor é um executável (motor em C "qwen3-tts", MIT + OpenBLAS, BSD)
 * empacotado como libqwentts.so: o Android só deixa executar o que vem na
 * pasta de bibliotecas nativas do app. Ele roda como um servidor HTTP que só
 * aceita conexões do próprio aparelho (127.0.0.1); o lado Dart pede as frases.
 *
 * O modelo (~2,4 GB) vem do Hugging Face (Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice)
 * e fica em filesDir/vozes/qwen3. O download continua de onde parou.
 */
object VozQwen {
    private const val TAG = "MlionVozQwen"
    const val PORTA = 18093
    private const val BASE =
        "https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice/resolve/main/"

    // (arquivo, tamanho aproximado em MB — só para o progresso)
    private val arquivos = listOf(
        "config.json" to 0, "generation_config.json" to 0, "merges.txt" to 2,
        "preprocessor_config.json" to 0, "tokenizer_config.json" to 0, "vocab.json" to 3,
        "speech_tokenizer/config.json" to 0, "speech_tokenizer/configuration.json" to 0,
        "speech_tokenizer/preprocessor_config.json" to 0,
        "speech_tokenizer/model.safetensors" to 682, "model.safetensors" to 1812,
    )

    private var processo: Process? = null

    private fun dir(ctx: Context) = File(ctx.filesDir, "vozes/qwen3")
    private fun motor(ctx: Context) = File(ctx.applicationInfo.nativeLibraryDir, "libqwentts.so")

    /** O aparelho consegue rodar (ARM 64 bits e o motor veio no app)? */
    fun suportado(ctx: Context) =
        Build.SUPPORTED_ABIS.contains("arm64-v8a") && motor(ctx).exists()

    fun instalado(ctx: Context) = File(dir(ctx), ".ok").exists()

    /** Baixa o modelo. [progresso] recebe 0..1. Continua um download interrompido. */
    fun baixar(ctx: Context, progresso: (Double) -> Unit): Boolean {
        val d = dir(ctx).apply { mkdirs() }
        val total = arquivos.sumOf { it.second.coerceAtLeast(1) }.toDouble()
        var feito = 0.0
        try {
            for ((nome, mb) in arquivos) {
                val peso = mb.coerceAtLeast(1)
                val f = File(d, nome).apply { parentFile?.mkdirs() }
                baixarArquivo(BASE + nome, f) { p -> progresso((feito + p * peso) / total) }
                feito += peso
                progresso(feito / total)
            }
            File(d, ".ok").writeText("ok")
            Log.i(TAG, "modelo instalado")
            return true
        } catch (e: Exception) {
            Log.w(TAG, "baixar: $e")
            return false
        }
    }

    private fun baixarArquivo(endereco: String, destino: File, progresso: (Double) -> Unit) {
        val parcial = File(destino.path + ".part")
        if (destino.exists()) return // já baixado numa tentativa anterior
        var url = URL(endereco)
        var con: HttpURLConnection
        var redirects = 0
        val jaTenho = if (parcial.exists()) parcial.length() else 0L
        while (true) {
            con = url.openConnection() as HttpURLConnection
            con.instanceFollowRedirects = false
            con.connectTimeout = 20_000
            con.readTimeout = 60_000
            if (jaTenho > 0) con.setRequestProperty("Range", "bytes=$jaTenho-")
            val code = con.responseCode
            if (code in 300..399 && redirects < 8) {
                url = URL(url, con.getHeaderField("Location"))
                con.disconnect()
                redirects++
                continue
            }
            if (code == 416 && jaTenho > 0) {
                // O pedaço já estava completo: só faltou renomear.
                con.disconnect()
                if (!parcial.renameTo(destino)) throw Exception("não consegui salvar ${destino.name}")
                return
            }
            if (code != 200 && code != 206) throw Exception("HTTP $code em ${destino.name}")
            break
        }
        val continuando = con.responseCode == 206
        val inicio = if (continuando) jaTenho else 0L
        val total = inicio + con.contentLengthLong
        RandomAccessFile(parcial, "rw").use { sai ->
            if (!continuando) sai.setLength(0)
            sai.seek(inicio)
            con.inputStream.use { ent ->
                val buf = ByteArray(256 * 1024)
                var lidos = inicio
                var ultimo = 0L
                while (true) {
                    val n = ent.read(buf)
                    if (n < 0) break
                    sai.write(buf, 0, n)
                    lidos += n
                    if (total > 0 && lidos - ultimo > 2 * 1024 * 1024) {
                        ultimo = lidos
                        progresso(lidos.toDouble() / total)
                    }
                }
            }
        }
        if (!parcial.renameTo(destino)) throw Exception("não consegui salvar ${destino.name}")
    }

    fun apagar(ctx: Context) {
        parar()
        dir(ctx).deleteRecursively()
    }

    fun rodando() = processo?.isAlive == true

    /**
     * Liga o servidor de voz com a voz [voz] (arquivo .bin de 4 KB). Retorna
     * logo; o lado Dart espera o /v1/health responder (~20 s para carregar).
     */
    @Synchronized
    fun iniciar(ctx: Context, voz: String, nucleos: Int): Boolean {
        if (rodando()) return true
        if (!suportado(ctx) || !instalado(ctx) || !File(voz).exists()) return false
        val cmd = mutableListOf<String>()
        // Prioridade baixa: a tela e o reconhecimento de voz continuam leves.
        if (File("/system/bin/nice").exists()) cmd += listOf("/system/bin/nice", "-n", "10")
        cmd += listOf(
            motor(ctx).absolutePath, "-d", dir(ctx).absolutePath,
            "--int4", "-j", nucleos.coerceIn(1, 8).toString(),
            "--load-voice", voz, "--xvector-only", "-l", "Portuguese",
            "--serve", PORTA.toString(), "--max-request-seconds", "0",
        )
        return try {
            val pb = ProcessBuilder(cmd)
                .redirectErrorStream(true)
                .redirectOutput(File(ctx.cacheDir, "voz_qwen.log"))
            pb.environment()["QWEN_SD_INT8"] = "1"
            processo = pb.start()
            Log.i(TAG, "servidor de voz ligado")
            true
        } catch (e: Exception) {
            Log.w(TAG, "iniciar: $e")
            false
        }
    }

    /** Desliga o servidor (libera ~2,5 GB de memória). */
    @Synchronized
    fun parar() {
        processo?.destroy()
        processo = null
    }
}
