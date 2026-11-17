package com.example.sign_language

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/** Independent VIDEO tracker for complete J/Z clips, never the static-letter tracker. */
class DynamicHandLandmarker(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    private val channel = MethodChannel(messenger, "latih_isyarat/dynamic_hand_landmarker")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)
    @Volatile private var disposed = false
    private var landmarker: HandLandmarker? = null
    private var lastTimestampMs: Long? = null
    private var framesProcessed = 0
    private var verifiedModelAsset = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("startClip", "detectFrame", "finishClip", "dispose")) {
            result.notImplemented()
            return
        }
        if (disposed) {
            if (call.method == "dispose") {
                result.success(mapOf("status" to "disposed"))
            } else {
                result.error("disposed", "Pendeteksi gerakan telah ditutup.", null)
            }
            return
        }
        if (!busy.compareAndSet(false, true)) {
            result.error("busy", "Tunggu operasi sebelumnya selesai.", null)
            return
        }
        try {
            worker.execute {
                try {
                    if (disposed) throw DetectorException("disposed", "Pendeteksi gerakan telah ditutup.")
                    val response = when (call.method) {
                        "startClip" -> startClip()
                        "detectFrame" -> detectFrame(call)
                        "finishClip" -> finishClip()
                        else -> {
                            disposeDetector()
                            mapOf("status" to "disposed")
                        }
                    }
                    busy.set(false)
                    main.post {
                        if (disposed) {
                            result.error("disposed", "Pendeteksi gerakan telah ditutup.", null)
                        } else {
                            result.success(response)
                        }
                    }
                } catch (error: DetectorException) {
                    busy.set(false)
                    main.post { result.error(error.code, error.message, null) }
                } catch (error: Exception) {
                    // A native failure can leave VIDEO timestamp/tracking state unusable.
                    disposeDetector()
                    busy.set(false)
                    main.post {
                        result.error(
                            "hand_detection",
                            error.message ?: "Pendeteksian gerakan gagal. Mulai clip baru.",
                            mapOf("clipReset" to true),
                        )
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            busy.set(false)
            result.error("disposed", "Pendeteksi gerakan telah ditutup.", null)
        }
    }

    private fun startClip(): Map<String, Any> {
        if (landmarker != null) {
            throw DetectorException("clip_already_started", "Akhiri clip aktif sebelum memulai clip baru.")
        }
        // Recreate VIDEO mode for every clip so timestamps and tracking cannot leak across clips.
        disposeDetector()
        verifyModelAsset()
        landmarker = HandLandmarker.createFromOptions(
            context,
            HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder()
                        .setModelAssetPath(MODEL_ASSET)
                        .setDelegate(Delegate.CPU)
                        .build()
                )
                .setRunningMode(RunningMode.VIDEO)
                .setNumHands(2)
                .setMinHandDetectionConfidence(0.5f)
                .setMinHandPresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .build()
        )
        return mapOf("status" to "started", "modelSha256" to MODEL_SHA256)
    }

    private fun detectFrame(call: MethodCall): Map<String, Any> {
        val detector = landmarker
            ?: throw DetectorException("clip_not_started", "Panggil startClip sebelum mengirim frame.")
        val arguments = call.arguments as? Map<*, *>
            ?: throw DetectorException("invalid_image", "Argumen frame harus berupa map.")
        val bytes = arguments["bytes"] as? ByteArray
        if (bytes == null || bytes.size < 4 || bytes.size > MAX_JPEG_BYTES ||
            (bytes[0].toInt() and 0xff) != 0xff || (bytes[1].toInt() and 0xff) != 0xd8
        ) {
            throw DetectorException("invalid_image", "Frame harus berupa JPEG, maksimal 4 MiB.")
        }
        val timestamp = when (val value = arguments["timestampMs"]) {
            is Int -> value.toLong()
            is Long -> value
            else -> throw DetectorException("invalid_timestamp", "timestampMs harus berupa bilangan bulat.")
        }
        if (timestamp < 0 || timestamp > Long.MAX_VALUE / 1000 ||
            lastTimestampMs?.let { timestamp <= it } == true
        ) {
            throw DetectorException("invalid_timestamp", "timestampMs harus positif atau nol dan selalu meningkat.")
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth !in 1..MAX_IMAGE_SIDE || bounds.outHeight !in 1..MAX_IMAGE_SIDE ||
            bounds.outMimeType != "image/jpeg"
        ) {
            throw DetectorException("invalid_image", "JPEG harus tegak, tanpa mirror, dan sisi maksimal 640 piksel.")
        }
        val bitmap = BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 },
        ) ?: throw DetectorException("invalid_image", "Frame JPEG tidak dapat dibaca.")
        try {
            val image = BitmapImageBuilder(bitmap).build()
            val hands = try {
                detector.detectForVideo(image, timestamp).landmarks().map { hand ->
                    hand.map { point ->
                        listOf(point.x().toDouble(), point.y().toDouble(), point.z().toDouble())
                    }
                }
            } finally {
                image.close()
            }
            lastTimestampMs = timestamp
            framesProcessed += 1
            return mapOf(
                "timestampMs" to timestamp,
                "width" to bitmap.width,
                "height" to bitmap.height,
                "hands" to hands,
            )
        } finally {
            if (!bitmap.isRecycled) bitmap.recycle()
        }
    }

    private fun finishClip(): Map<String, Any> {
        if (landmarker == null) {
            throw DetectorException("clip_not_started", "Tidak ada clip gerakan yang sedang aktif.")
        }
        val frameCount = framesProcessed
        disposeDetector()
        return mapOf("status" to "finished", "framesProcessed" to frameCount)
    }

    private fun verifyModelAsset() {
        if (verifiedModelAsset) return
        val digest = MessageDigest.getInstance("SHA-256")
        context.assets.open(MODEL_ASSET).use { input ->
            val buffer = ByteArray(16 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
        if (actualHash != MODEL_SHA256) {
            throw DetectorException("model_mismatch", "Model MediaPipe berbeda dari kontrak training J/Z.")
        }
        verifiedModelAsset = true
    }

    private fun disposeDetector() {
        val detector = landmarker
        landmarker = null
        lastTimestampMs = null
        framesProcessed = 0
        // Always finish teardown, even when MediaPipe is already in an error state.
        try {
            detector?.close()
        } catch (_: Exception) {
            // The detector is detached and cannot be reused.
        }
    }

    /** Called by the engine lifecycle, including when a method is still running. */
    fun close() {
        disposed = true
        channel.setMethodCallHandler(null)
        try {
            worker.execute { disposeDetector() }
        } catch (_: RejectedExecutionException) {
            // A previous lifecycle close has already shut down the worker.
        } finally {
            worker.shutdown()
        }
    }

    private class DetectorException(val code: String, message: String) : Exception(message)

    private companion object {
        const val MODEL_ASSET = "hand_landmarker.task"
        const val MODEL_SHA256 = "fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1"
        const val MAX_IMAGE_SIDE = 640
        const val MAX_JPEG_BYTES = 4 * 1024 * 1024
    }
}
