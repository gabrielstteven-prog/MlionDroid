package com.example.flutter_application_1

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
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
        const val EXTRA_CAMERA = "camera"
        const val EXTRA_SO_PRESENCA = "so_presenca"
        private const val CANAL = "descanso"
        private const val ID = 4242

        /** Quem acordou a tela ("luz" / "proximidade"); a Activity avisa o Dart. */
        var aoAcordar: ((String) -> Unit)? = null

        /** Depois de acender: a câmera ainda vê alguém na frente (a cada ~10 s). */
        var aoPresenca: (() -> Unit)? = null

        /** Posição horizontal da pessoa vista da tela (-1 esquerda .. 1 direita). */
        var aoPosicao: ((Double) -> Unit)? = null

        /** Se os olhos seguirem para o lado contrário, inverte (Configurações). */
        var inverterOlhar = false

        /** [soPresenca]: tela acesa, só observa se há alguém (antes de apagar). */
        fun iniciar(ctx: Context, luz: Boolean, proximidade: Boolean, camera: Boolean,
                    soPresenca: Boolean = false) {
            val i = Intent(ctx, DescansoService::class.java)
                .putExtra(EXTRA_LUZ, luz)
                .putExtra(EXTRA_PROXIMIDADE, proximidade)
                .putExtra(EXTRA_CAMERA, camera)
                .putExtra(EXTRA_SO_PRESENCA, soPresenca)
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

    // Depois de acender, a câmera continua olhando só para saber se ainda há
    // alguém na frente: enquanto houver, a tela não apaga.
    private var presenca = false
    private var ultimaPresenca = 0L
    private var camHandler: Handler? = null
    private var orientacaoSensor = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val usarCamera = (intent?.getBooleanExtra(EXTRA_CAMERA, false) ?: false) &&
            checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        mostrarAviso(usarCamera)
        fecharCamera()
        if (usarCamera) abrirCamera()
        val usarLuz = intent?.getBooleanExtra(EXTRA_LUZ, true) ?: true
        val usarProx = intent?.getBooleanExtra(EXTRA_PROXIMIDADE, true) ?: true
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensores?.unregisterListener(this)
        sensores = sm
        luzBase = -1f
        val soPresenca = intent?.getBooleanExtra(EXTRA_SO_PRESENCA, false) ?: false
        acordou = soPresenca // já "acordado": não tenta acender a tela
        presenca = soPresenca
        if (soPresenca) return START_STICKY // sem sensores de luz/proximidade
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
        sensores?.unregisterListener(this)
        val h = camHandler
        if (camDevice != null && h != null) {
            // Modo presença: destrava a exposição (a luz pode ter acendido) e
            // segue avisando enquanto houver movimento na frente.
            h.post {
                presenca = true
                camInicio = SystemClock.elapsedRealtime()
                exposicaoTravada = false
                anterior = null
                repetir(travar = false, h)
            }
        } else {
            fecharCamera()
            stopSelf() // o Dart religa o descanso quando a tela apagar de novo
        }
    }

    // ── Câmera: luz acendendo e movimento ─────────────────────────────────
    // Analisa ~3 quadros por segundo, em baixa resolução, só a luminância
    // (preto e branco). Nada é gravado nem sai do tablet.
    private var camThread: HandlerThread? = null
    private var camDevice: CameraDevice? = null
    private var camSessao: CameraCaptureSession? = null
    private var leitor: ImageReader? = null
    private var camInicio = 0L
    private var ultimaAnalise = 0L
    private var ultimoLog = 0L
    private var exposicaoTravada = false
    private var baseLum = -1.0
    private var anterior: IntArray? = null
    private var movimentoSeguido = 0

    private fun abrirCamera() {
        try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = cm.cameraIdList.firstOrNull {
                cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_FRONT
            } ?: cm.cameraIdList.firstOrNull() ?: return
            orientacaoSensor = cm.getCameraCharacteristics(id)
                .get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            val mapa = cm.getCameraCharacteristics(id)
                .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return
            // Menor tamanho com pelo menos 240 px de largura (leve e suficiente).
            val tam = mapa.getOutputSizes(ImageFormat.YUV_420_888)
                .filter { it.width >= 240 }
                .minByOrNull { it.width * it.height } ?: return
            val ht = HandlerThread("descanso-camera").also { it.start() }
            camThread = ht
            val h = Handler(ht.looper)
            camHandler = h
            val r = ImageReader.newInstance(tam.width, tam.height, ImageFormat.YUV_420_888, 2)
            leitor = r
            r.setOnImageAvailableListener({ rd ->
                val img = rd.acquireLatestImage() ?: return@setOnImageAvailableListener
                try { analisar(img, h) } catch (e: Exception) { Log.w(TAG, "análise: $e") }
                finally { img.close() }
            }, h)
            camInicio = SystemClock.elapsedRealtime()
            exposicaoTravada = false
            baseLum = -1.0
            anterior = null
            movimentoSeguido = 0
            @Suppress("MissingPermission")
            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(d: CameraDevice) {
                    camDevice = d
                    @Suppress("DEPRECATION")
                    d.createCaptureSession(listOf(r.surface), object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(s: CameraCaptureSession) {
                            camSessao = s
                            repetir(travar = false, h)
                            Log.i(TAG, "câmera ligada (${tam.width}x${tam.height})")
                        }
                        override fun onConfigureFailed(s: CameraCaptureSession) {
                            Log.w(TAG, "câmera: falha ao configurar")
                        }
                    }, h)
                }
                override fun onDisconnected(d: CameraDevice) { d.close() }
                override fun onError(d: CameraDevice, error: Int) {
                    Log.w(TAG, "câmera: erro $error")
                    d.close()
                }
            }, h)
        } catch (e: Exception) {
            Log.w(TAG, "câmera indisponível: $e")
        }
    }

    /**
     * Converte o centro do movimento (coordenadas do sensor, -1..1) na posição
     * horizontal da pessoa vista DA TELA (-1 = esquerda, 1 = direita), para os
     * olhos do Jarvis seguirem quem está na frente. Considera a rotação do
     * sensor e da tela; a câmera da frente "espelha" esquerda e direita.
     */
    private fun avisarPosicao(u: Double, v: Double) {
        @Suppress("DEPRECATION")
        val rotTela = when ((getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager)
            .defaultDisplay.rotation) {
            android.view.Surface.ROTATION_90 -> 90
            android.view.Surface.ROTATION_180 -> 180
            android.view.Surface.ROTATION_270 -> 270
            else -> 0
        }
        // Gira a imagem do sensor até ela ficar "em pé" (como numa foto).
        val (uEmPe, _) = when ((orientacaoSensor + rotTela) % 360) {
            90 -> Pair(-v, u)
            180 -> Pair(-u, -v)
            270 -> Pair(v, -u)
            else -> Pair(u, v)
        }
        // Na foto da câmera da frente, quem está à esquerda da tela aparece à
        // direita da imagem.
        val x = (if (inverterOlhar) uEmPe else -uEmPe).coerceIn(-1.0, 1.0)
        aoPosicao?.invoke(x)
    }

    private fun repetir(travar: Boolean, h: Handler) {
        val d = camDevice ?: return
        val s = camSessao ?: return
        val r = leitor ?: return
        val req = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
            addTarget(r.surface)
            // Exposição travada: a câmera não "se acostuma" com o escuro, então
            // a luz do cômodo acendendo vira um salto enorme de brilho.
            set(CaptureRequest.CONTROL_AE_LOCK, travar)
            set(CaptureRequest.CONTROL_AWB_LOCK, travar)
        }.build()
        s.setRepeatingRequest(req, null, h)
    }

    private fun analisar(img: Image, h: Handler) {
        if (acordou && !presenca) return
        val agora = SystemClock.elapsedRealtime()
        if (agora - ultimaAnalise < 330) return
        ultimaAnalise = agora
        val plano = img.planes[0]
        val buf = plano.buffer
        val passo = 8
        val w = img.width
        val hgt = img.height
        val amostras = IntArray((w / passo) * (hgt / passo))
        var n = 0
        var soma = 0L
        var y = 0
        while (y < hgt - passo + 1 && n < amostras.size) {
            var x = 0
            while (x < w - passo + 1 && n < amostras.size) {
                val v = buf.get(y * plano.rowStride + x * plano.pixelStride).toInt() and 0xFF
                amostras[n++] = v
                soma += v
                x += passo
            }
            y += passo
        }
        if (n == 0) return
        val media = soma.toDouble() / n

        // 3 s para a exposição automática se ajustar; depois trava.
        if (agora - camInicio < 3000) return
        if (!exposicaoTravada) {
            exposicaoTravada = true
            repetir(travar = true, h)
            baseLum = media
            anterior = amostras
            Log.i(TAG, "câmera: referência de brilho ${"%.0f".format(media)}")
            return
        }

        // Mudou quantos pontos da imagem (movimento)? E onde (centro da mudança)?
        val ant = anterior
        var mudaram = 0
        var somaU = 0.0
        var somaV = 0.0
        val colunas = (w - passo) / passo + 1
        val linhas = maxOf(1, n / colunas)
        if (ant != null) {
            for (i in 0 until n) {
                if (kotlin.math.abs(amostras[i] - ant[i]) > 28) {
                    mudaram++
                    somaU += (i % colunas).toDouble() / colunas * 2 - 1
                    somaV += (i / colunas).toDouble() / linhas * 2 - 1
                }
            }
        }
        if (presenca && mudaram > n * 0.02 && media > 30) {
            avisarPosicao(somaU / mudaram, somaV / mudaram)
        }
        anterior = amostras
        val fracao = mudaram.toDouble() / n
        if (agora - ultimoLog > 10_000) {
            ultimoLog = agora
            Log.i(TAG, "câmera: brilho ${"%.0f".format(media)} (ref ${"%.0f".format(baseLum)}), mudança ${"%.2f".format(fracao)}")
        }

        if (presenca) {
            if (media > 30 && fracao > 0.05 && agora - ultimaPresenca > 10_000) {
                ultimaPresenca = agora
                Log.i(TAG, "presença: alguém na frente (mudança ${"%.2f".format(fracao)})")
                aoPresenca?.invoke()
            }
            return
        }

        // 1) Luz do cômodo acendeu: brilho bem acima da referência.
        if (media > baseLum + 35 && media > 50) {
            acordar("luz", "câmera ${"%.0f".format(baseLum)} -> ${"%.0f".format(media)}")
            return
        }
        // 2) Movimento: com luz suficiente para enxergar, parte da imagem
        //    mudou em dois quadros seguidos (um só pode ser ruído).
        if (media > 30 && fracao > 0.07) {
            movimentoSeguido++
            if (movimentoSeguido >= 2) acordar("movimento", "mudança ${"%.2f".format(fracao)}")
        } else {
            movimentoSeguido = 0
        }
        if (media < baseLum) baseLum = media
    }

    private fun fecharCamera() {
        try { camSessao?.close() } catch (_: Exception) {}
        try { camDevice?.close() } catch (_: Exception) {}
        try { leitor?.close() } catch (_: Exception) {}
        camThread?.quitSafely()
        camSessao = null
        camDevice = null
        leitor = null
        camThread = null
        camHandler = null
    }

    private fun mostrarAviso(comCamera: Boolean) {
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
            .setContentText(
                if (comCamera) "A tela acende quando a luz acender ou a câmera notar alguém (nada é gravado)."
                else "A tela acende quando a luz do cômodo acender."
            )
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            val tipo = if (comCamera)
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            else ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            startForeground(ID, n, tipo)
        } else if (Build.VERSION.SDK_INT >= 30 && comCamera) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } else {
            startForeground(ID, n)
        }
    }

    override fun onDestroy() {
        fecharCamera()
        sensores?.unregisterListener(this)
        sensores = null
        super.onDestroy()
    }
}
