package com.example.sign_language

import android.content.Context
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
import java.util.concurrent.Executors

/** Uses the hand_landmarker plugin's existing asset; no extra model download. */
class StillImageHandLandmarker(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    private val channel = MethodChannel(messenger, "latih_isyarat/image_hand_landmarker")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var landmarker: HandLandmarker? = null
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "detect") {
            result.notImplemented()
            return
        }
        val bytes = call.argument<ByteArray>("bytes")
        if (closed || bytes == null || bytes.isEmpty()) {
            result.error("invalid_image", "Gambar tidak dapat dibaca.", null)
            return
        }
        worker.execute {
            try {
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    ?: throw IllegalArgumentException("Gambar tidak dapat dibaca.")
                try {
                    val detector = landmarker ?: HandLandmarker.createFromOptions(
                        context,
                        HandLandmarker.HandLandmarkerOptions.builder()
                            .setBaseOptions(
                                BaseOptions.builder()
                                    .setModelAssetPath("hand_landmarker.task")
                                    .setDelegate(Delegate.CPU)
                                    .build()
                            )
                            .setRunningMode(RunningMode.IMAGE)
                            .setNumHands(2)
                            .setMinHandDetectionConfidence(0.35f)
                            .setMinHandPresenceConfidence(0.35f)
                            .build()
                    ).also { landmarker = it }
                    val image = BitmapImageBuilder(bitmap).build()
                    val hands = try {
                        detector.detect(image).landmarks().map { hand ->
                            hand.map { point ->
                                listOf(point.x().toDouble(), point.y().toDouble())
                            }
                        }
                    } finally {
                        image.close()
                    }
                    main.post { if (!closed) result.success(hands) }
                } finally {
                    if (!bitmap.isRecycled) bitmap.recycle()
                }
            } catch (error: Exception) {
                main.post {
                    if (!closed) result.error("hand_detection", error.message, null)
                }
            }
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        worker.execute {
            landmarker?.close()
            landmarker = null
        }
        worker.shutdown()
    }
}
