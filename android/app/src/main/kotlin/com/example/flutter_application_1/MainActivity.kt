package com.example.flutter_application_1

import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.Manifest
import android.content.pm.PackageManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.graphics.Color
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.widget.FrameLayout
import android.view.WindowManager
import java.util.Locale
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CANAL_VOZ = "com.mlion_droid/speech"
    private val CANAL_SISTEMA = "com.mlion_droid/sistema"
    private val SPEECH_REQUEST_CODE = 100
    private val EXTRA_ACORDAR = "mlion_acordar"

    private var speechResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Painel de parede: a tela fica ligada por padrão. O Dart pode
        // desligar isso pelas Configurações (canal "sistema").
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (intent?.getBooleanExtra(EXTRA_ACORDAR, false) == true) acordarTela()
    }

    // Tela em descanso (luz de fundo desligada): qualquer toque acende, e o
    // toque não "vaza" para o botão que estiver embaixo do dedo.
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (cortina != null) {
            if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
                DescansoService.parar(this)
                acordarTela()
                canalSistema?.invokeMethod("acordouPorSensor", "toque")
            }
            return true
        }
        return super.dispatchTouchEvent(ev)
    }

    // O alarme do fim do Modo Noite reabre o app com este extra.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(EXTRA_ACORDAR, false)) acordarTela()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        canalVoz = MethodChannel(messenger, CANAL_VOZ)
        canalVoz!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "ligarPalavra" -> {
                    val sens = (call.argument<Double>("sensibilidade") ?: 0.6).toFloat()
                    result.success(ligarPalavra(sens))
                }
                "desligarPalavra" -> {
                    pararPalavra()
                    result.success(null)
                }
                "startListening" -> {
                    val language = call.argument<String>("language") ?: "pt-BR"
                    val prompt = call.argument<String>("prompt") ?: "Fale agora..."
                    // Se já havia um pedido pendente, encerra antes de abrir outro.
                    speechResult?.success("")
                    speechResult = result
                    idiomaPendente = language
                    promptPendente = prompt
                    ouvirNoApp()
                }
                else -> result.notImplemented()
            }
        }

        canalSistema = MethodChannel(messenger, CANAL_SISTEMA)
        // Sensor do descanso acendeu a tela: acorda o painel e avisa o Dart.
        DescansoService.aoAcordar = { motivo ->
            runOnUiThread {
                acordarTela()
                canalSistema?.invokeMethod("acordouPorSensor", motivo)
            }
        }
        DescansoService.aoPresenca = {
            runOnUiThread { canalSistema?.invokeMethod("presenca", null) }
        }
        DescansoService.aoPosicao = { x ->
            runOnUiThread { canalSistema?.invokeMethod("posicao", x) }
        }
        canalSistema!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "manterTelaLigada" -> {
                    val ligada = call.argument<Boolean>("ligada") ?: true
                    if (ligada) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "brilho" -> {
                    // -1 = volta ao brilho do sistema; 0.0..1.0 = brilho fixo
                    // só enquanto o app estiver na frente (não altera a
                    // configuração do aparelho, então não precisa permissão).
                    val valor = call.argument<Double>("valor") ?: -1.0
                    val attrs = window.attributes
                    attrs.screenBrightness = if (valor < 0) {
                        WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    } else if (valor == 0.0) {
                        // 0 = luz de fundo DESLIGADA (descanso da tela), sem bloquear.
                        WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_OFF
                    } else {
                        valor.toFloat().coerceIn(0.01f, 1f)
                    }
                    window.attributes = attrs
                    result.success(null)
                }
                "falar" -> {
                    // Responde só quando a fala TERMINA: a conversa contínua do
                    // Jarvis volta a ouvir depois, sem escutar a própria voz.
                    val texto = call.argument<String>("texto") ?: ""
                    concluirFala()
                    falaResult = result
                    falar(texto)
                }
                "pararFala" -> {
                    tts?.stop()
                    concluirFala()
                    pararAudio()
                    result.success(null)
                }
                "tocarAudio" -> {
                    // Responde só quando o áudio termina (ou falha): o Dart sabe
                    // quando a fala acabou para apagar o orbe.
                    val caminho = call.argument<String>("caminho") ?: ""
                    tocarAudio(caminho, result)
                }
                "desligarTela" -> {
                    val acordarEm = call.argument<Number>("acordarEm")?.toLong() ?: 0L
                    if (acordarEm > 0) agendarDespertar(acordarEm)
                    val luz = call.argument<Boolean>("luz") ?: false
                    val prox = call.argument<Boolean>("proximidade") ?: false
                    val cam = call.argument<Boolean>("camera") ?: false
                    if (luz || prox || cam) DescansoService.iniciar(this, luz, prox, cam)
                    result.success(desligarTela())
                }
                "acordarTela" -> {
                    DescansoService.parar(this)
                    acordarTela()
                    result.success(null)
                }
                "cameraPermitida" -> result.success(
                    checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                )
                "tirarFoto" -> {
                    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.CAMERA), 78)
                        result.success("sem_permissao")
                    } else {
                        // A câmera atende um de cada vez: pausa a vigilância do
                        // descanso (se estiver ligada) antes da foto.
                        DescansoService.parar(this)
                        window.decorView.postDelayed({
                            FotoRapida.tirar(this) { caminho -> runOnUiThread { result.success(caminho) } }
                        }, 500)
                    }
                }
                "gravarAudio" -> {
                    // "/audio" do Telegram: grava N segundos do microfone em AAC (.m4a).
                    val seg = (call.argument<Int>("segundos") ?: 15).coerceIn(3, 60)
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        result.success(null)
                    } else {
                        gravarAudio(seg) { caminho -> runOnUiThread { result.success(caminho) } }
                    }
                }
                "pedirCamera" -> {
                    requestPermissions(arrayOf(Manifest.permission.CAMERA), 78)
                    result.success(null)
                }
                "observarPresenca" -> {
                    // Antes de apagar: a câmera confere se há alguém em casa.
                    if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        DescansoService.iniciar(this, false, false, true, soPresenca = true)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "inverterOlhar" -> {
                    DescansoService.inverterOlhar = call.argument<Boolean>("inverter") ?: false
                    result.success(null)
                }
                "pararDescanso" -> {
                    DescansoService.parar(this)
                    result.success(null)
                }
                "tocarAlarme" -> {
                    tocarAlarme()
                    result.success(null)
                }
                "pararAlarme" -> {
                    alarme?.stop()
                    alarme = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Gravação de áudio (Telegram /audio) ─────────────────────────────────
    private fun gravarAudio(segundos: Int, aoTerminar: (String?) -> Unit) {
        // O microfone é um só: pausa a escuta do "Hey Jarvis" durante a gravação.
        pararPalavra()
        val arq = java.io.File(cacheDir, "audio_casa.m4a")
        val rec = try {
            ("DEPRECATION")
            android.media.MediaRecorder().apply {
                setAudioSource(android.media.MediaRecorder.AudioSource.MIC)
                setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(44100)
                setAudioEncodingBitRate(96_000)
                setOutputFile(arq.absolutePath)
                prepare()
                start()
            }
        } catch (e: Exception) {
            android.util.Log.w("MlionCasa", "gravação: $e")
            aoTerminar(null)
            return
        }
        window.decorView.postDelayed({
            try { rec.stop() } catch (_: Exception) {}
            rec.release()
            aoTerminar(if (arq.exists() && arq.length() > 0) arq.absolutePath else null)
        }, segundos * 1000L)
    }

    // ── Palavra de ativação "Hey Jarvis" (openWakeWord, roda no tablet) ──────
    // Sem conta e sem chave: os modelos ficam dentro do app.
    private var ouvido: OuvidoJarvis? = null
    private var limiarOuvido = 0f

    /** null = ligou; senão, o motivo da falha. */
    private fun ligarPalavra(sensibilidade: Float): String? {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PEDIDO_MICROFONE)
            return "sem_permissao"
        }
        // Sensibilidade alta = limiar baixo (ouve mais fácil, mais alarme falso).
        val limiar = (1.1f - sensibilidade).coerceIn(0.2f, 0.85f)
        return try {
            // Os modelos são carregados uma vez; só a escuta liga/desliga.
            if (ouvido == null || limiar != limiarOuvido) {
                ouvido?.liberar()
                // Sensibilidade alta também aumenta o ganho (ouvir do meio da sala).
                val ganho = (1f + (sensibilidade - 0.4f) * 2.5f).coerceIn(1f, 2.2f)
                ouvido = OuvidoJarvis(applicationContext, limiar, ganho) {
                    runOnUiThread { aoOuvirPalavra() }
                }
                limiarOuvido = limiar
            }
            ouvido!!.iniciar()
            null
        } catch (e: Exception) {
            android.util.Log.w("MlionJarvis", "não ligou: ${e.message}")
            e.message ?: "erro"
        }
    }

    private fun pararPalavra() {
        ouvido?.parar()
    }

    private fun aoOuvirPalavra() {
        android.util.Log.i("MlionJarvis", "ouvi: Hey Jarvis")
        // O microfone vai para o reconhecimento da frase: solta a escuta.
        pararPalavra()
        if (cortina != null) {
            // Tela em descanso: acende antes de ouvir.
            DescansoService.parar(this)
            acordarTela()
            canalSistema?.invokeMethod("acordouPorSensor", "toque")
        }
        canalVoz?.invokeMethod("palavraAtivacao", null)
    }

    // ── Escuta dentro do app (SpeechRecognizer, sem a janela do Google) ──────
    private var canalVoz: MethodChannel? = null
    private var canalSistema: MethodChannel? = null
    private var reconhecedor: SpeechRecognizer? = null
    private var idiomaPendente = "pt-BR"
    private var promptPendente = ""
    private val PEDIDO_MICROFONE = 77

    private fun ouvirNoApp() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            // Sem serviço de reconhecimento: usa a janela do Google mesmo.
            startSpeechRecognition(idiomaPendente, promptPendente)
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PEDIDO_MICROFONE)
            return
        }
        reconhecedor?.destroy()
        val r = SpeechRecognizer.createSpeechRecognizer(this)
        reconhecedor = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {
                canalVoz?.invokeMethod("volume", rmsdB.toDouble())
            }
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onError(error: Int) {
                canalVoz?.invokeMethod("erro", error)
                entregarFala("")
            }
            override fun onResults(results: Bundle?) {
                val t = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""
                entregarFala(t)
            }
            override fun onPartialResults(partial: Bundle?) {
                val t = partial?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""
                if (t.isNotBlank()) canalVoz?.invokeMethod("parcial", t)
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, idiomaPendente)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, idiomaPendente)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        r.startListening(i)
    }

    private fun entregarFala(texto: String) {
        reconhecedor?.destroy()
        reconhecedor = null
        speechResult?.success(texto)
        speechResult = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PEDIDO_MICROFONE) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) ouvirNoApp()
            else entregarFala("")
        }
    }

    // ── Voz (Text-to-Speech nativo do Android, sem custo) ──────────────────
    private var tts: TextToSpeech? = null
    private var ttsPronto = false
    private var falaPendente: String? = null

    private fun volumeMaximo() = Bundle().apply {
        putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1f)
    }

    private var falaResult: MethodChannel.Result? = null

    private fun concluirFala() {
        falaResult?.success(null)
        falaResult = null
    }

    private val ouvinteFala = object : android.speech.tts.UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {}
        override fun onDone(utteranceId: String?) {
            runOnUiThread {
                // A fala foi gerada em arquivo: toca medindo o volume (boca sincronizada).
                if (utteranceId == "sintese") tocarArquivo(arquivoFala.path) { concluirFala() }
                else concluirFala()
            }
        }
        @Deprecated("Mantido por compatibilidade")
        override fun onError(utteranceId: String?) { runOnUiThread { concluirFala() } }
        override fun onStop(utteranceId: String?, interrupted: Boolean) { runOnUiThread { concluirFala() } }
    }

    private val arquivoFala by lazy { java.io.File(cacheDir, "fala_tts.wav") }

    /** Gera a fala num arquivo e toca com o medidor (a boca acompanha o som). */
    private fun sintetizar(texto: String) {
        val ok = tts?.synthesizeToFile(texto, volumeMaximo(), arquivoFala, "sintese")
        if (ok != TextToSpeech.SUCCESS) tts?.speak(texto, TextToSpeech.QUEUE_FLUSH, volumeMaximo(), "mlion")
    }

    private fun falar(texto: String) {
        if (texto.isBlank()) { concluirFala(); return }
        if (tts == null) {
            falaPendente = texto
            tts = TextToSpeech(this) { status ->
                ttsPronto = status == TextToSpeech.SUCCESS
                if (ttsPronto) {
                    tts?.language = Locale("pt", "BR")
                    tts?.setOnUtteranceProgressListener(ouvinteFala)
                    // Mesmo canal (e volume) das músicas: o padrão do TTS em alguns
                    // tablets é um canal com volume baixo.
                    tts?.setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    falaPendente?.let { sintetizar(it) }
                    falaPendente = null
                } else {
                    concluirFala() // sem motor de voz: não deixa ninguém esperando
                }
            }
            return
        }
        if (ttsPronto) sintetizar(texto)
        else concluirFala()
    }

    // ── Áudio pronto (voz da ElevenLabs em MP3) ────────────────────────────
    private var player: MediaPlayer? = null
    private var playerFim: ((Boolean) -> Unit)? = null

    private fun tocarAudio(caminho: String, result: MethodChannel.Result) =
        tocarArquivo(caminho) { ok -> result.success(ok) }

    /** Toca um arquivo de voz e mede o volume para a boca do Jarvis mexer junto. */
    private fun tocarArquivo(caminho: String, aoTerminar: (Boolean) -> Unit) {
        pararAudio()
        tts?.stop()
        playerFim = aoTerminar
        try {
            val p = MediaPlayer()
            p.setAudioAttributes(
                AudioAttributes.Builder()
                    // Canal de MÍDIA: o "assistente" tem volume próprio e baixo.
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            p.setDataSource(caminho)
            p.setOnCompletionListener { terminarAudio(true) }
            p.setOnErrorListener { _, _, _ -> terminarAudio(false); true }
            p.prepare()
            reforcarVolume(p.audioSessionId)
            medirVoz(p.audioSessionId)
            p.start()
            player = p
        } catch (e: Exception) {
            terminarAudio(false)
        }
    }

    private fun terminarAudio(ok: Boolean) {
        reforco?.release()
        reforco = null
        medidor?.release()
        medidor = null
        canalSistema?.invokeMethod("nivelFala", 0.0)
        player?.release()
        player = null
        val fim = playerFim
        playerFim = null
        fim?.invoke(ok)
    }

    // ── Volume da voz em tempo real (boca do Jarvis sincronizada) ───────────
    private var medidor: android.media.audiofx.Visualizer? = null
    private var ultimoNivel = 0L

    private fun medirVoz(sessao: Int) {
        try {
            medidor?.release()
            val faixa = android.media.audiofx.Visualizer.getCaptureSizeRange()
            medidor = android.media.audiofx.Visualizer(sessao).apply {
                captureSize = 256.coerceIn(faixa[0], faixa[1])
                setDataCaptureListener(object : android.media.audiofx.Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        v: android.media.audiofx.Visualizer?, onda: ByteArray?, taxa: Int
                    ) {
                        if (onda == null) return
                        val agora = android.os.SystemClock.elapsedRealtime()
                        if (agora - ultimoNivel < 30) return
                        ultimoNivel = agora
                        // Onda em 8 bits sem sinal (128 = silêncio): volume RMS 0..1.
                        var soma = 0.0
                        for (b in onda) {
                            val x = ((b.toInt() and 0xFF) - 128) / 128.0
                            soma += x * x
                        }
                        val nivel = (Math.sqrt(soma / onda.size) * 3.2).coerceIn(0.0, 1.0)
                        runOnUiThread { canalSistema?.invokeMethod("nivelFala", nivel) }
                    }

                    override fun onFftDataCapture(
                        v: android.media.audiofx.Visualizer?, fft: ByteArray?, taxa: Int
                    ) {}
                }, android.media.audiofx.Visualizer.getMaxCaptureRate(), true, false)
                enabled = true
            }
        } catch (e: Exception) {
            medidor = null // sem medidor: a boca usa o ritmo simulado
        }
    }

    // Reforço de volume (+8 dB) na voz: alto-falante de tablet é fraco.
    private var reforco: android.media.audiofx.LoudnessEnhancer? = null

    private fun reforcarVolume(sessao: Int) {
        try {
            reforco?.release()
            reforco = android.media.audiofx.LoudnessEnhancer(sessao).apply {
                setTargetGain(800)
                enabled = true
            }
        } catch (_: Exception) {
        }
    }

    private fun pararAudio() {
        if (player != null) terminarAudio(true)
    }

    // ── Descanso da tela (Modo Noite) ─────────────────────────────────────
    /** true = apagou na hora (admin ativo); false = só liberou o tempo de espera. */
    // Descanso SEM bloquear o tablet: o app continua na frente, a tela fica
    // preta e a luz de fundo é desligada. Antes usava o bloqueio do Android
    // (lockNow), que deixava o tablet na tela de senha.
    private var cortina: View? = null

    private fun desligarTela(): Boolean {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val attrs = window.attributes
        // Alguns tablets ignoram o "desligar" e só vão ao brilho mínimo; por
        // isso, além do brilho, uma cortina preta cobre o app inteiro.
        attrs.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_OFF
        window.attributes = attrs
        if (cortina == null) {
            val v = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
            addContentView(v, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            cortina = v
        }
        esconderBarras(true)
        return true
    }

    private fun esconderBarras(esconder: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val c = window.insetsController ?: return
        if (esconder) {
            c.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
            c.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            c.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
        }
    }

    // Alarme do Android como garantia: se o sistema congelar o app durante a
    // noite, o alarme reabre o app na hora de acordar.
    private fun agendarDespertar(quando: Long) {
        val i = Intent(this, MainActivity::class.java).apply {
            putExtra(EXTRA_ACORDAR, true)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val pi = PendingIntent.getActivity(
            this, 41, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, quando, pi)
    }

    private fun acordarTela() {
        cortina?.let { (it.parent as? ViewGroup)?.removeView(it) }
        cortina = null
        // As barras do sistema ficam escondidas, como o painel sempre fica.
        val a = window.attributes
        if (a.screenBrightness == WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_OFF) {
            a.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            window.attributes = a
        }
        // Mostra o painel por cima da tela de bloqueio (sem pedir a senha para
        // VER o painel; abrir outros apps continua pedindo).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val wl = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "mliondroid:acordar"
        )
        wl.acquire(10_000)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // "Acender ao aparecer" só vale para este despertar.
        window.decorView.postDelayed({
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) setTurnScreenOn(false)
            else @Suppress("DEPRECATION")
            window.clearFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }, 3000)
    }

    // ── Alarme do temporizador ─────────────────────────────────────────────
    private var alarme: Ringtone? = null

    private fun tocarAlarme() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            alarme?.stop()
            alarme = RingtoneManager.getRingtone(this, uri)
            alarme?.play()
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        ouvido?.liberar()
        ouvido = null
        tts?.shutdown()
        DescansoService.aoAcordar = null
        reconhecedor?.destroy()
        pararAudio()
        alarme?.stop()
        super.onDestroy()
    }

    private fun startSpeechRecognition(language: String, prompt: String) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, language)
            putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, language)
            putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        try {
            startActivityForResult(intent, SPEECH_REQUEST_CODE)
        } catch (e: Exception) {
            speechResult?.error("STT_UNAVAILABLE", "Reconhecimento de voz não disponível", null)
            speechResult = null
        }
    }

    @Deprecated("Mantido para o fluxo de reconhecimento de voz")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SPEECH_REQUEST_CODE) {
            val texto = if (resultCode == Activity.RESULT_OK && data != null) {
                data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() ?: ""
            } else ""
            speechResult?.success(texto)
            speechResult = null
        }
    }
}
