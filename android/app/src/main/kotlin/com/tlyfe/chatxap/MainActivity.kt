package com.tlyfe.chatxap

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val PIP_CHANNEL = "com.tlyfe.chatxap/pip"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "enterPiP" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val width  = call.argument<Int>("width")  ?: 9
                            val height = call.argument<Int>("height") ?: 16
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(width, height))
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }

                    "exitPiP" -> {
                        // Exit happens automatically when user taps expand
                        result.success(true)
                    }

                    "isPiPSupported" -> {
                        val supported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.hasSystemFeature(
                                PackageManager.FEATURE_PICTURE_IN_PICTURE)
                        } else {
                            false
                        }
                        result.success(supported)
                    }

                    "setSecureFlag" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        runOnUiThread {
                            if (secure) {
                                window.setFlags(
                                    WindowManager.LayoutParams.FLAG_SECURE,
                                    WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
