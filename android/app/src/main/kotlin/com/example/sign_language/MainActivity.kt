package com.example.sign_language

import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugins.camerax.CameraAndroidCameraxPlugin
import io.flutter.plugins.camerax.LatihIsyaratPreviewBridge

class MainActivity : FlutterActivity() {
    private var stillImageHandLandmarker: StillImageHandLandmarker? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        stillImageHandLandmarker = StillImageHandLandmarker(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        val cameraPlugin =
            flutterEngine.plugins.get(CameraAndroidCameraxPlugin::class.java)
                as? CameraAndroidCameraxPlugin
        LatihIsyaratPreviewBridge.install(
            flutterEngine.dartExecutor.binaryMessenger,
            cameraPlugin,
        )
    }

    override fun cleanUpFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        stillImageHandLandmarker?.close()
        stillImageHandLandmarker = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
