package com.example.flutter_application_1

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.mlion_droid/speech"
    private val SPEECH_REQUEST_CODE = 100

    private var speechResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    val language = call.argument<String>("language") ?: "pt-BR"
                    speechResult = result
                    startSpeechRecognition(language)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startSpeechRecognition(language: String) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, language)
            putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, language)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Fale seu comando para o Mlio...")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        try {
            startActivityForResult(intent, SPEECH_REQUEST_CODE)
        } catch (e: Exception) {
            speechResult?.error(
                "STT_UNAVAILABLE",
                "Reconhecimento de voz não disponível",
                null
            )
            speechResult = null
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == SPEECH_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val results = data.getStringArrayListExtra(
                    RecognizerIntent.EXTRA_RESULTS
                )
                val texto = results?.firstOrNull() ?: ""
                speechResult?.success(texto)
            } else {
                speechResult?.success("")
            }
            speechResult = null
        }
    }
}
