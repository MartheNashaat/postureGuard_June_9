// android/app/src/main/kotlin/com/postureguard/postureguard/MainActivity.kt
package com.postureguard.postureguard

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Rational
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.postureguard/overlay"
    private val TAG = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestOverlayPermission" -> {
                    if (Settings.canDrawOverlays(this)) {
                        result.success(true)
                    } else {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(false)
                    }
                }
                "showOverlay" -> {
                    val show = call.argument<Boolean>("show") ?: false
                    if (show) {
                        startService(Intent(this, OverlayService::class.java))
                    } else {
                        stopService(Intent(this, OverlayService::class.java))
                    }
                    result.success(true)
                }
                "updatePosture" -> {
                    val score = call.argument<Int>("score") ?: 100
                    val status = call.argument<String>("status") ?: "good"
                    OverlayService.updatePosture(score, status)
                    result.success(true)
                }
                "updateBaseline" -> {
                    try {
                        // Get the landmarks as Map<String, Double> from Flutter
                        val landmarks = call.arguments as? Map<String, Double>
                        if (landmarks != null) {
                            Log.d(TAG, "Received baseline: $landmarks")
                            // Convert Double to Float
                            val floatLandmarks = landmarks.mapValues { it.value.toFloat() }
                            OverlayService.updateBaseline(floatLandmarks)
                            result.success(true)
                        } else {
                            Log.e(TAG, "Landmarks is null")
                            result.error("ERROR", "Landmarks is null", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error updating baseline: ${e.message}")
                        result.error("ERROR", e.message, null)
                    }
                }
                "isOverlayEnabled" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "getBrightness" -> {
                    val brightness = Settings.System.getInt(
                        contentResolver, Settings.System.SCREEN_BRIGHTNESS, 255
                    )
                    result.success(brightness)
                }
                "setBrightness" -> {
                    val brightness = (call.argument<Int>("brightness") ?: 255).coerceIn(0, 255)
                    if (Settings.System.canWrite(this)) {
                        Settings.System.putInt(
                            contentResolver, Settings.System.SCREEN_BRIGHTNESS, brightness
                        )
                        result.success(true)
                    } else {
                        result.error("PERMISSION", "Cannot write settings", null)
                    }
                }
                "isWriteSettingsEnabled" -> {
                    result.success(Settings.System.canWrite(this))
                }
                "requestWriteSettings" -> {
                    if (!Settings.System.canWrite(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_WRITE_SETTINGS,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                "getScreenTimeout" -> {
                    val timeout = Settings.System.getInt(
                        contentResolver, Settings.System.SCREEN_OFF_TIMEOUT, 30000
                    )
                    result.success(timeout)
                }
                "setScreenTimeout" -> {
                    val timeout = call.argument<Int>("timeout") ?: 30000
                    if (Settings.System.canWrite(this)) {
                        Settings.System.putInt(
                            contentResolver, Settings.System.SCREEN_OFF_TIMEOUT, timeout
                        )
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onResume() {
        super.onResume()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onPause() {
        super.onPause()
        // onPause fires when entering PiP — re-assert the flag so the screen
        // stays on inside the PiP window (it can be cleared during the transition)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Keep screen on in both PiP and normal mode
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onUserLeaveHint() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))
                .build()
            enterPictureInPictureMode(params)
        }
    }
}
