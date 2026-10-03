package com.example.flutter_application_1

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CANAL_VOZ = "com.mlion_droid/speech"
    private val CANAL_SISTEMA = "com.mlion_droid/sistema"
    private val SPEECH_REQUEST_CODE = 100

    private var speechResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Painel de parede: a tela fica ligada por padrão. O Dart pode
        // desligar isso pelas Configurações (canal "sistema").
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, CANAL_VOZ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    val language = call.argument<String>("language") ?: "pt-BR"
                    val prompt = call.argument<String>("prompt") ?: "Fale agora..."
                    // Se já havia um pedido pendente, encerra antes de abrir outro.
                    speechResult?.success("")
                    speechResult = result
                    startSpeechRecognition(language, prompt)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, CANAL_SISTEMA).setMethodCallHandler { call, result ->
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
                    } else {
                        valor.toFloat().coerceIn(0.01f, 1f)
                    }
                    window.attributes = attrs
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
