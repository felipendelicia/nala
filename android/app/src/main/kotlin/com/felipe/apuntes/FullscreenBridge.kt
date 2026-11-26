package com.felipe.apuntes

import android.view.Window
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class FullscreenBridge(private val window: Window) : MethodChannel.MethodCallHandler {
    private var fullscreen = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getFullscreen" -> result.success(fullscreen)
            "setFullscreen" -> {
                val enabled = call.arguments as? Boolean
                if (enabled == null) {
                    result.error("INVALID_ARGUMENT", "La pantalla completa requiere un valor booleano.", null)
                    return
                }
                updateSystemBars(enabled)
                fullscreen = enabled
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun restore() {
        if (fullscreen) updateSystemBars(true)
    }

    private fun updateSystemBars(enabled: Boolean) {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        val systemBars = WindowInsetsCompat.Type.systemBars()
        if (enabled) {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(systemBars)
        } else {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
            controller.show(systemBars)
        }
    }
}
