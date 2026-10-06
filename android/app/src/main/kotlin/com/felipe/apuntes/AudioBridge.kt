package com.felipe.apuntes

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.Executors

class AudioBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private var capture: PcmRecording? = null
    private var pendingStart: Pair<String, MethodChannel.Result>? = null
    private var player: MediaPlayer? = null
    private var playbackResult: MethodChannel.Result? = null
    private var foreground = true
    private val micRequest = 41013

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val path = call.argument<String>("path")
                if (path == null || !privatePath(path) || !foreground) {
                    result.error("INVALID_PATH", "No se puede iniciar esta grabación.", null)
                } else if (capture != null || pendingStart != null) {
                    result.error("BUSY", "Ya hay una grabación en curso.", null)
                } else {
                    stopPlayback(null)
                    if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        pendingStart = Pair(path, result)
                        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), micRequest)
                    } else startCapture(path, result)
                }
            }
            "stop" -> stopCapture(false, result)
            "cancel" -> {
                cancelPermission()
                stopCapture(true, result)
            }
            "play" -> {
                val path = call.argument<String>("path")
                if (path == null || !privatePath(path) || capture != null || pendingStart != null) {
                    result.error("BUSY", "Terminá la grabación antes de escuchar.", null)
                } else play(path, result)
            }
            "stopPlayback" -> stopPlayback(result)
            else -> result.notImplemented()
        }
    }
    private fun privatePath(path: String): Boolean = try {
        val canonical = File(path).canonicalPath
        canonical.startsWith(activity.filesDir.canonicalPath + File.separator) || canonical.startsWith(activity.cacheDir.canonicalPath + File.separator)
    } catch (_: Exception) { false }
    fun permissionsResult(code: Int, grants: IntArray): Boolean {
        if (code != micRequest) return false
        val request = pendingStart ?: return true
        pendingStart = null
        if (foreground && grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) startCapture(request.first, request.second)
        else request.second.error("MIC_PERMISSION_DENIED", "Necesitás permitir el micrófono.", null)
        return true
    }
    private fun startCapture(path: String, result: MethodChannel.Result) {
        try {
            capture = PcmRecording(File(path))
            result.success(null)
        } catch (_: Exception) {
            capture = null
            result.error("MIC_UNAVAILABLE", "No se pudo acceder al micrófono.", null)
        }
    }
    private fun cancelPermission() {
        pendingStart?.second?.error("CANCELLED", "Grabación cancelada.", null)
        pendingStart = null
    }
    private fun stopCapture(cancel: Boolean, result: MethodChannel.Result?) {
        val current = capture
        if (current == null) { result?.success(null); return }
        current.stop()
        worker.execute {
            current.thread.join()
            if (cancel) current.file.delete()
            activity.runOnUiThread {
                if (capture === current) capture = null
                if (!cancel && current.error != null) result?.error("RECORD_FAILED", "La grabación se interrumpió.", null)
                else result?.success(null)
            }
        }
    }
    private fun play(path: String, result: MethodChannel.Result) {
        stopPlayback(null)
        try {
            val current = MediaPlayer()
            player = current
            playbackResult = result
            current.setAudioAttributes(AudioAttributes.Builder().setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).setUsage(AudioAttributes.USAGE_MEDIA).build())
            current.setDataSource(path)
            current.setOnPreparedListener { if (player === current) current.start() }
            current.setOnCompletionListener { if (player === current) stopPlayback(null) }
            current.setOnErrorListener { _, _, _ ->
                if (player === current) {
                    playbackResult?.error("PLAY_FAILED", "No se pudo escuchar la nota de voz.", null)
                    playbackResult = null
                    stopPlayback(null)
                }
                true
            }
            current.prepareAsync()
        } catch (_: Exception) {
            playbackResult = null
            stopPlayback(null)
            result.error("PLAY_FAILED", "No se pudo escuchar la nota de voz.", null)
        }
    }
    private fun stopPlayback(result: MethodChannel.Result?) {
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
        playbackResult?.success(null)
        playbackResult = null
        result?.success(null)
    }
    fun onForeground() { foreground = true }
    fun onBackground() {
        foreground = false
        cancelPermission()
        stopCapture(false, null)
        stopPlayback(null)
    }
    fun close() { onBackground(); worker.shutdown() }
}

private class PcmRecording(val file: File) {
    private val size = maxOf(4096, AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT) * 4)
    private val source = AudioRecord(MediaRecorder.AudioSource.MIC, 16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size)
    @Volatile private var running = true
    @Volatile var error: Exception? = null
    val thread: Thread
    init {
        if (source.state != AudioRecord.STATE_INITIALIZED) { source.release(); throw IllegalStateException() }
        try { source.startRecording() }
        catch (e: Exception) { source.release(); throw e }
        thread = Thread({
            try {
                RandomAccessFile(file, "rw").use { output ->
                    output.setLength(0)
                    header(output, 0)
                    val buffer = ByteArray(size)
                    var bytes = 0
                    try {
                        while (running) {
                            val count = source.read(buffer, 0, buffer.size)
                            if (count > 0) { output.write(buffer, 0, count); bytes += count }
                            else if (running) throw java.io.IOException()
                        }
                    } finally {
                        output.seek(0)
                        header(output, bytes)
                        output.fd.sync()
                    }
                }
            } catch (e: Exception) { error = e }
            finally { source.release() }
        }, "nala-voice-capture")
        thread.start()
    }
    fun stop() { running = false; runCatching { source.stop() } }
    private fun header(out: RandomAccessFile, bytes: Int) {
        fun intLE(value: Int) { out.write(byteArrayOf(value.toByte(), (value shr 8).toByte(), (value shr 16).toByte(), (value shr 24).toByte())) }
        fun shortLE(value: Int) { out.write(byteArrayOf(value.toByte(), (value shr 8).toByte())) }
        out.writeBytes("RIFF"); intLE(36 + bytes); out.writeBytes("WAVEfmt "); intLE(16)
        shortLE(1); shortLE(1); intLE(16000); intLE(32000); shortLE(2); shortLE(16)
        out.writeBytes("data"); intLE(bytes)
    }
}
