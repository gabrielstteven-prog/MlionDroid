package com.example.flutter_application_1

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * Descanso inteligente: enquanto a tela está apagada no Modo Noite, vigia o
 * sensor de LUZ (alguém acendeu a luz do cômodo) e o de PROXIMIDADE (mão
 * perto da tela) e acende a tela quando um deles dispara.
 *
 * Roda como serviço em primeiro plano (com aviso fixo na barra) porque, com a
 * tela apagada, o Android congela apps comuns — e aí ninguém ouviria o
 * sensor. Os dois sensores gastam praticamente nada.
 */
class DescansoService : Service(), SensorEventListener {

    companion object {
        const val TAG = "MlionDescanso"
        const val EXTRA_LUZ = "luz"
        const val EXTRA_PROXIMIDADE = "proximidade"
        private const val CANAL = "descanso"
        private const val ID = 4242

        /** Quem acordou a tela ("luz" / "proximidade"); a Activity avisa o Dart. */
        var aoAcordar: ((String) -> Unit)? = null

        fun iniciar(ctx: Context, luz: Boolean, proximidade: Boolean) {
            val i = Intent(ctx, DescansoService::class.java)
                .putExtra(EXTRA_LUZ, luz)
                .putExtra(EXTRA_PROXIMIDADE, proximidade)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i)
            else ctx.startService(i)
        }

        fun parar(ctx: Context) {
            ctx.stopService(Intent(ctx, DescansoService::class.java))
        }
    }

    private var sensores: SensorManager? = null
    private var luzBase = -1f // luz do cômodo quando a tela apagou
    private var acordou = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        mostrarAviso()
        val usarLuz = intent?.getBooleanExtra(EXTRA_LUZ, true) ?: true
        val usarProx = intent?.getBooleanExtra(EXTRA_PROXIMIDADE, true) ?: true
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensores?.unregisterListener(this)
        sensores = sm
        luzBase = -1f
        acordou = false
        // Prefere a versão "wake-up" do sensor: ela entrega a leitura mesmo
        // com o processador do tablet dormindo.
        if (usarLuz) {
            val s = sm.getDefaultSensor(Sensor.TYPE_LIGHT, true) ?: sm.getDefaultSensor(Sensor.TYPE_LIGHT)
            s?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
            Log.i(TAG, "sensor de luz: ${s?.name ?: "não tem"}")
        }
        if (usarProx) {
            val s = sm.getDefaultSensor(Sensor.TYPE_PROXIMITY, true) ?: sm.getDefaultSensor(Sensor.TYPE_PROXIMITY)
            s?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
            Log.i(TAG, "sensor de proximidade: ${s?.name ?: "não tem"} (alcance ${s?.maximumRange})")
        }
        return START_STICKY
    }

    override fun onSensorChanged(e: SensorEvent) {
        if (acordou) return
        when (e.sensor.type) {
            Sensor.TYPE_LIGHT -> {
                val lux = e.values[0]
                if (luzBase < 0) {
                    luzBase = lux
                    Log.i(TAG, "luz de referência: $lux lux")
                    return
                }
                // Acendeu a luz: bem mais claro que quando a tela apagou.
                // (Uma lâmpada de sala passa fácil de 30 lux; o escuro fica
                // perto de 0. O "x3" evita disparar com um carro passando.)
                if (lux >= 15f && lux > luzBase * 3f + 10f) acordar("luz", "luz $luzBase -> $lux lux")
                else if (lux < luzBase) luzBase = lux // ficou mais escuro: nova referência
            }
            Sensor.TYPE_PROXIMITY -> {
                val distancia = e.values[0]
                Log.i(TAG, "proximidade: $distancia (máx ${e.sensor.maximumRange})")
                if (distancia < e.sensor.maximumRange) acordar("proximidade", "objeto a $distancia")
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun acordar(motivo: String, detalhe: String) {
        acordou = true
        Log.i(TAG, "acordando por $motivo ($detalhe)")
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val wl = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "mliondroid:descanso"
        )
        wl.acquire(10_000)
        aoAcordar?.invoke(motivo)
        stopSelf() // o Dart religa o descanso quando a tela apagar de novo
    }

    private fun mostrarAviso() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CANAL, "Descanso da tela", NotificationManager.IMPORTANCE_MIN)
            )
        }
        val n = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CANAL)
        else @Suppress("DEPRECATION") Notification.Builder(this))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Descanso da tela")
            .setContentText("A tela acende quando a luz acender ou alguém chegar perto.")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID, n)
        }
    }

    override fun onDestroy() {
        sensores?.unregisterListener(this)
        sensores = null
        super.onDestroy()
    }
}
