package com.felipe.apuntes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.MotionEvent
import android.app.Activity
import android.content.Intent
import android.content.ClipData
import androidx.core.content.FileProvider
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var audio: AudioBridge
    private var stylusChannel: MethodChannel? = null
    private var stylusListening = false
    private var stylusPressed = false
    private data class PendingPdf(val bytes: ByteArray, val result: MethodChannel.Result)
    private var pending: PendingPdf? = null
    private val writer = Executors.newSingleThreadExecutor()
    private val saveRequest = 40731

    private fun stylusEvent(event: MotionEvent) {
        if (!stylusListening) return
        val index = event.actionIndex
        val type = event.getToolType(index)
        if (type != MotionEvent.TOOL_TYPE_STYLUS && type != MotionEvent.TOOL_TYPE_ERASER) return
        // Hover exit also occurs when the tip makes contact. It is not a
        // release/cancel and must not turn one physical press into two toggles.
        if (event.actionMasked == MotionEvent.ACTION_HOVER_EXIT) return
        if (event.actionMasked == MotionEvent.ACTION_CANCEL) {
            resetStylus()
            return
        }
        val pressed = event.buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY != 0
        if (pressed != stylusPressed || event.actionMasked == MotionEvent.ACTION_DOWN ||
            event.actionMasked == MotionEvent.ACTION_POINTER_DOWN) {
            stylusPressed = pressed
            stylusChannel?.invokeMethod("button", pressed)
        }
    }

    private fun resetStylus() {
        stylusPressed = false
        if (stylusListening) stylusChannel?.invokeMethod("reset", null)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        stylusEvent(event)
        return super.dispatchTouchEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        stylusEvent(event)
        val handled = super.dispatchGenericMotionEvent(event)
        // Flutter ignores these two generic-motion actions. Consume only stylus
        // button edges when an editor is listening; hover/scroll follow Flutter.
        val buttonAction = event.actionMasked == MotionEvent.ACTION_BUTTON_PRESS ||
            event.actionMasked == MotionEvent.ACTION_BUTTON_RELEASE
        return handled || (stylusListening && buttonAction &&
            (event.getToolType(event.actionIndex) == MotionEvent.TOOL_TYPE_STYLUS ||
             event.getToolType(event.actionIndex) == MotionEvent.TOOL_TYPE_ERASER))
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) resetStylus()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        stylusChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nala/stylus").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "listen") {
                    stylusListening = call.arguments == true
                    stylusPressed = false
                    result.success(null)
                } else result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nala/share").setMethodCallHandler { call, result ->
            if (call.method != "sharePdf") { result.notImplemented() }
            else {
                try {
                    val file = File(call.argument<String>("path") ?: "")
                    if (!file.isFile) throw java.io.IOException()
                    val uri = FileProvider.getUriForFile(this, "$packageName.nala.share", file)
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "application/pdf"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        clipData = ClipData.newRawUri("PDF", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(send, "Compartir PDF"))
                    result.success(true)
                } catch (_: Exception) { result.error("SHARE_FAILED", "No se pudo abrir Compartir PDF.", null) }
            }
        }
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
