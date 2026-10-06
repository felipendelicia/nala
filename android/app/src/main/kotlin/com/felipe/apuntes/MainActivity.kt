package com.felipe.apuntes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var audio: AudioBridge
    private data class PendingPdf(val bytes: ByteArray, val result: MethodChannel.Result)
    private var pending: PendingPdf? = null
    private val writer = Executors.newSingleThreadExecutor()
    private val saveRequest = 40731

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audio = AudioBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nala/audio").setMethodCallHandler(audio)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nala/files").setMethodCallHandler { call, result ->
            if (call.method != "savePdf") {
                result.notImplemented()
            } else if (pending != null) {
                result.error("BUSY", "Ya hay un PDF en preparación.", null)
            } else {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null || bytes.isEmpty()) {
                    result.error("INVALID_PDF", "El PDF está vacío.", null)
                } else {
                    pending = PendingPdf(bytes, result)
                    val name = call.argument<String>("name") ?: "Nala.pdf"
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/pdf"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }
                    try { startActivityForResult(intent, saveRequest) }
                    catch (_: Exception) {
                        pending = null
                        result.error("PICKER_UNAVAILABLE", "No se pudo abrir el selector de archivos.", null)
                    }
                }
            }
        }
    }

    @Deprecated("Android callback required by this FlutterActivity integration")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequest) return
        val current = pending ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            current.result.success(false)
            return
        }
        writer.execute {
            try {
                val output = contentResolver.openOutputStream(uri, "w") ?: throw java.io.IOException()
                output.use { it.write(current.bytes) }
                runOnUiThread {
                    if (pending === current) { pending = null; current.result.success(true) }
                }
            } catch (_: Exception) {
                runOnUiThread {
                    if (pending === current) {
                        pending = null
                        current.result.error("SAVE_FAILED", "No se pudo guardar el PDF.", null)
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        if (::audio.isInitialized) audio.close()
        pending?.result?.error("ACTIVITY_CLOSED", "Se cerró el selector de archivos.", null)
        pending = null
        writer.shutdown()
        super.onDestroy()
    }
    override fun onStart() { super.onStart(); if (::audio.isInitialized) audio.onForeground() }
    override fun onStop() { if (::audio.isInitialized) audio.onBackground(); super.onStop() }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (::audio.isInitialized && audio.permissionsResult(requestCode, grantResults)) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
