package com.felipe.apuntes

import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognition
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModel
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModelIdentifier
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizer
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizerOptions
import com.google.mlkit.vision.digitalink.recognition.Ink
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Local Spanish digital ink recognition. No model download is implicit. */
class InkRecognitionBridge : MethodChannel.MethodCallHandler {
    private val manager = RemoteModelManager.getInstance()
    private val model: DigitalInkRecognitionModel? =
        DigitalInkRecognitionModelIdentifier.fromLanguageTag("es")?.let {
            DigitalInkRecognitionModel.builder(it).build()
        }
    private var recognizer: DigitalInkRecognizer? = null
    private var pending: MethodChannel.Result? = null
    private var closed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) { result.error("CLOSED", "Reconocimiento cerrado.", null); return }
        val selected = model
        if (selected == null) {
            if (call.method == "status") result.success(mapOf("available" to false, "downloaded" to false))
            else result.error("UNAVAILABLE", "No existe el modelo español.", null)
            return
        }
        when (call.method) {
            "status" -> manager.isModelDownloaded(selected)
                .addOnSuccessListener { result.success(mapOf("available" to true, "downloaded" to it)) }
                .addOnFailureListener { result.error("MODEL_STATUS", "No se pudo consultar el modelo.", null) }
            "download" -> manager.download(selected, DownloadConditions.Builder().build())
                .addOnSuccessListener { result.success(true) }
                .addOnFailureListener { result.error("MODEL_DOWNLOAD", "No se pudo descargar el modelo español. Revisá la conexión y el espacio.", null) }
            "delete" -> {
                cancel()
                recognizer?.close()
                recognizer = null
                manager.deleteDownloadedModel(selected)
                    .addOnSuccessListener { result.success(true) }
                    .addOnFailureListener { result.error("MODEL_DELETE", "No se pudo eliminar el modelo español.", null) }
            }
            "cancel" -> { cancel(); result.success(null) }
            "recognize" -> {
                if (pending != null) { result.error("BUSY", "Ya hay una página en reconocimiento.", null); return }
                val ink = try { parseInk(call) } catch (_: Exception) {
                    result.error("INVALID_INK", "Los trazos no son válidos o la página es demasiado grande.", null)
                    return
                }
                pending = result
                manager.isModelDownloaded(selected).addOnSuccessListener { downloaded ->
                    if (pending !== result || closed) return@addOnSuccessListener
                    if (!downloaded) {
                        pending = null
                        result.error("MODEL_MISSING", "Primero descargá el modelo español.", null)
                    } else {
                        val client = recognizer ?: DigitalInkRecognition.getClient(
                            DigitalInkRecognizerOptions.builder(selected).build()).also { recognizer = it }
                        client.recognize(ink).addOnSuccessListener { recognized ->
                            if (pending === result && !closed) {
                                pending = null
                                result.success(recognized.candidates.firstOrNull()?.text ?: "")
                            }
                        }.addOnFailureListener {
                            if (pending === result && !closed) {
                                pending = null
                                result.error("RECOGNITION_FAILED", "No se pudo reconocer esta página.", null)
                            }
                        }
                    }
                }.addOnFailureListener {
                    if (pending === result && !closed) {
                        pending = null
                        result.error("MODEL_STATUS", "No se pudo consultar el modelo español.", null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun parseInk(call: MethodCall): Ink {
        val strokes = call.argument<List<List<Map<String, Number>>>>("strokes") ?: error("No ink")
        require(strokes.isNotEmpty() && strokes.size <= 10000)
        var pointCount = 0
        val ink = Ink.builder()
        for (points in strokes) {
            require(points.isNotEmpty())
            pointCount += points.size
            require(pointCount <= 200000)
            val stroke = Ink.Stroke.builder()
            for (point in points) {
                val x = point["x"]?.toFloat() ?: error("No x")
                val y = point["y"]?.toFloat() ?: error("No y")
                require(x.isFinite() && y.isFinite())
                // Stored notebook ink has no individual sample timestamps.
                stroke.addPoint(Ink.Point.create(x, y))
            }
            ink.addStroke(stroke.build())
        }
        return ink.build()
    }

    private fun cancel() {
        val current = pending
        pending = null
        current?.error("CANCELLED", "Reconocimiento cancelado.", null)
    }
    fun close() {
        cancel()
        closed = true
        recognizer?.close()
        recognizer = null
    }
}
