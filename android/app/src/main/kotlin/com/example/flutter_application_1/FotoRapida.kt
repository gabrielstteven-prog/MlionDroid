package com.example.flutter_application_1

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import java.io.File

/**
 * "Jarvis, olha o que eu tenho na mão": tira UMA foto com a câmera da frente
 * e devolve o caminho do JPEG (no cache do app). Abre a câmera, deixa a
 * exposição se ajustar por ~1,2 s e captura. Nada fica salvo além do cache.
 */
object FotoRapida {
    private const val TAG = "MlionFoto"

    fun tirar(ctx: Context, aoTerminar: (String?) -> Unit) {
        val cm = ctx.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val id = try {
            cm.cameraIdList.firstOrNull {
                cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_FRONT
            } ?: cm.cameraIdList.firstOrNull()
        } catch (e: Exception) {
            null
        }
        if (id == null) {
            aoTerminar(null)
            return
        }
        val carac = cm.getCameraCharacteristics(id)
        val mapa = carac.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        // Até ~1280 px: suficiente para a IA reconhecer objetos, leve para enviar.
        val tam = mapa?.getOutputSizes(ImageFormat.JPEG)
            ?.filter { it.width <= 1280 }
            ?.maxByOrNull { it.width * it.height }
        if (tam == null) {
            aoTerminar(null)
            return
        }
        val ht = HandlerThread("foto-rapida").also { it.start() }
        val h = Handler(ht.looper)
        val leitor = ImageReader.newInstance(tam.width, tam.height, ImageFormat.JPEG, 1)
        val textura = SurfaceTexture(false).apply { setDefaultBufferSize(640, 480) }
        val previa = Surface(textura)
        var device: CameraDevice? = null
        var entregue = false

        fun encerrar(caminho: String?) {
            if (entregue) return
            entregue = true
            try { device?.close() } catch (_: Exception) {}
            try { leitor.close() } catch (_: Exception) {}
            previa.release()
            textura.release()
            ht.quitSafely()
            aoTerminar(caminho)
        }

        leitor.setOnImageAvailableListener({ r ->
            val img = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val buf = img.planes[0].buffer
                val bytes = ByteArray(buf.remaining()).also { buf.get(it) }
                val arq = File(ctx.cacheDir, "jarvis_olhar.jpg")
                arq.writeBytes(bytes)
                Log.i(TAG, "foto ${tam.width}x${tam.height}, ${bytes.size / 1024} KB")
                encerrar(arq.absolutePath)
            } catch (e: Exception) {
                Log.w(TAG, "falha ao salvar: $e")
                encerrar(null)
            } finally {
                img.close()
            }
        }, h)

        // Rotação: a foto sai "em pé" de acordo com como o tablet está.
        val sensor = carac.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        @Suppress("DEPRECATION")
        val rot = when ((ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
            .defaultDisplay.rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        val orientacao = (sensor + rot) % 360

        try {
            @Suppress("MissingPermission")
            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(d: CameraDevice) {
                    device = d
                    @Suppress("DEPRECATION")
                    d.createCaptureSession(listOf(previa, leitor.surface),
                        object : CameraCaptureSession.StateCallback() {
                            override fun onConfigured(s: CameraCaptureSession) {
                                val prev = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                                    .apply { addTarget(previa) }.build()
                                s.setRepeatingRequest(prev, null, h)
                                h.postDelayed({
                                    try {
                                        val foto = d.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                                            addTarget(leitor.surface)
                                            set(CaptureRequest.JPEG_ORIENTATION, orientacao)
                                            set(CaptureRequest.JPEG_QUALITY, 85.toByte())
                                        }.build()
                                        s.capture(foto, null, h)
                                    } catch (e: Exception) {
                                        Log.w(TAG, "captura: $e")
                                        encerrar(null)
                                    }
                                }, 1200)
                                h.postDelayed({ encerrar(null) }, 8000) // garantia
                            }

                            override fun onConfigureFailed(s: CameraCaptureSession) = encerrar(null)
                        }, h)
                }

                override fun onDisconnected(d: CameraDevice) = encerrar(null)
                override fun onError(d: CameraDevice, error: Int) {
                    Log.w(TAG, "câmera erro $error")
                    encerrar(null)
                }
            }, h)
        } catch (e: Exception) {
            Log.w(TAG, "abrir câmera: $e")
            encerrar(null)
        }
    }
}
