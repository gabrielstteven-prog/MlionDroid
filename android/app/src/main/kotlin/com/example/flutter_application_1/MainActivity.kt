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
                    val texto = call.argument<String>("texto") ?: ""
                    falar(texto)
                    result.success(null)
                }
                "pararFala" -> {
                    tts?.stop()
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
                "pedirCamera" -> {
                    requestPermissions(arrayOf(Manifest.permission.CAMERA), 78)
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

    private fun falar(texto: String) {
        if (texto.isBlank()) return
        if (tts == null) {
            falaPendente = texto
            tts = TextToSpeech(this) { status ->
                ttsPronto = status == TextToSpeech.SUCCESS
                if (ttsPronto) {
                    tts?.language = Locale("pt", "BR")
                    // Mesmo canal (e volume) das músicas: o padrão do TTS em alguns
                    // tablets é um canal com volume baixo.
                    tts?.setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    falaPendente?.let { tts?.speak(it, TextToSpeech.QUEUE_FLUSH, volumeMaximo(), "mlion") }
                    falaPendente = null
                }
            }
            return
        }
        if (ttsPronto) tts?.speak(texto, TextToSpeech.QUEUE_FLUSH, volumeMaximo(), "mlion")
    }

    // ── Áudio pronto (voz da ElevenLabs em MP3) ────────────────────────────
    private var player: MediaPlayer? = null
    private var playerResult: MethodChannel.Result? = null

    private fun tocarAudio(caminho: String, result: MethodChannel.Result) {
        pararAudio()
        tts?.stop()
        playerResult = result
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
            p.start()
            player = p
        } catch (e: Exception) {
            terminarAudio(false)
        }
    }

    private fun terminarAudio(ok: Boolean) {
        reforco?.release()
        reforco = null
        player?.release()
        player = null
        playerResult?.success(ok)
        playerResult = null
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
