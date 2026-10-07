# Audio de clase y tarjetas de estudio

Implementación de la tarea 4 del plan `docs/superpowers/plans/2026-10-07-study-tools.md`.

## Interfaces de integración

- `NotebookAudioSession(device, assets, directory, controller, now?, newId?)`: `ChangeNotifier` que inicia solamente con `start()`. Expone `recording`, `busy`, `pendingSave`, `error`, `durationMs`, `positionMs`, `activeRecordingId`, `playing` y `activePlaybackId`. `stop()` valida el WAV, guarda el recurso por hash y agrega una grabación con `EditorController.apply`. Si falla el almacenamiento de un WAV válido, conserva el archivo y todos los vínculos temporales; `retrySave()` reintenta sin duplicar la grabación. `start()` evita reemplazar audio pendiente. `cancel()` permite descartarlo explícitamente y limpia sus vínculos en la tinta y cualquier adjunto pendiente. `suspend()` termina y guarda una captura activa, cancela un inicio pendiente y detiene solamente la reproducción propia; lanza un error si todavía hay audio pendiente de guardar, impidiendo un cierre silencioso. `dispose()` inicia esa finalización sin notificar una sesión cerrada ni borrar un WAV válido pendiente. **AppServices conserva la propiedad y vida útil del AudioDevice compartido**.
- `markStroke(stroke)` agrega el ID y la posición temporal actuales. Para vincular el comienzo del trazo, el editor debe capturar `activeRecordingId` y `positionMs` al comenzar y copiar esos valores al trazo terminado.
- `playStroke(stroke)` encuentra la grabación vinculada y reproduce desde su posición; una referencia todavía pendiente durante la captura no produce reproducción. `playRecording(recording, offsetMs: 0)` y `stopPlayback()` permiten controles explícitos.
- `SeekAudioPlayer(device, assets, directory)` reproduce WAV validados desde un desplazamiento. `WavAudio.parse(bytes)` comprueba RIFF, los límites de sus chunks, formato PCM/float sin comprimir, frecuencia, alineación y longitud. `seek(offsetMs)` crea otro WAV con muestras completas. El recurso original permanece intacto; el archivo temporal se elimina al terminar, detener o fallar. Un reproductor inactivo no detiene audio perteneciente a otro panel.
- `AudioDeviceLease(device)` coordina adquisiciones entre paneles por dispositivo. `acquire(owner, releasePrevious, isCurrent, activate)` espera a que termine la captura o reproducción del propietario anterior antes del nuevo inicio; la cola cubre solamente la transición. `owns(owner)` y `release(owner)` impiden que una cancelación o finalización anterior afecte al siguiente panel. La captura pendiente puede cancelar el pedido de permiso sin bloquearse detrás de su propio inicio. Las cancelaciones de sesión y detenciones de reproducción simultáneas comparten una misma finalización.
- `CommentAudioPlayer` reutiliza `SeekAudioPlayer`, incluida la coordinación compartida, y conserva el comportamiento de tocar una nota ya activa para detenerla. El modal de grabación de comentarios sigue usando su sesión previa; el editor suspende la clase y detiene la reproducción antes de abrirlo.
- `RecordingPanel(session, controller, onClose)` ofrece iniciar/detener/guardar, lista de clases, escuchar, renombrar y eliminar. Eliminar conserva la tinta y limpia sus vínculos de audio. Si queda audio pendiente por un fallo de almacenamiento, presenta Reintentar guardar y un descarte explícito con confirmación; mantiene el panel abierto y deshabilita renombrar/eliminar grabaciones durante ese estado. Cerrar termina la sesión antes de llamar `onClose` y permanece abierto cuando el guardado falla. Los errores muestran instrucciones en español sin rutas internas de archivos.
- `StudyScheduler(now?)` expone `due(cards)` y `review(card, StudyRating)` con valoraciones `again`, `hard`, `good` y `easy`. Otra vez programa 10 minutos y reinicia las repeticiones; Difícil/Bien/Fácil empiezan en 1/2/4 días. Las revisiones correctas aumentan los intervalos y la dificultad se adapta. El límite de intervalo es 100 años para mantener fechas representables.
- `StudyPanel(controller, initialFront?, onClose?)` permite crear desde texto seleccionado, editar, eliminar y repasar tarjetas pendientes. La respuesta se oculta hasta solicitarla. Todas las ediciones y valoraciones usan `EditorController.apply` y conservan los cambios simultáneos del cuaderno.

## Verificación

Se observaron fallos iniciales por ausencia de los módulos en la ejecución RED compartida del padre (`/tmp/nala-study-red.log`). Las regresiones de propiedad compartida también se ejecutaron en RED: suspender una sesión inactiva detenía reproducción ajena y una captura nueva empezaba antes de terminar la captura saliente; el reproductor de comentarios inactivo también detenía audio ajeno (`/tmp/nala-audio-ownership-red.log`, `/tmp/nala-audio-lease-red.log`). Se corrigieron con propiedad por generación, adquisición coordinada y sin disponer el dispositivo compartido. La prueba de cancelaciones simultáneas fue una cobertura adicional de la invariancia de ocupado y no falló en el RED compartido.

`tool/flutter-safe test --no-pub test/audio test/study`: **34 pruebas pasaron**, salida 0, incluidas todas las pruebas de audio anteriores. Cubren:

- WAV recortado por cuadros completos, original intacto y rechazo de datos inválidos.
- Grabación explícita, vínculo temporal, guardado por hash y persistencia en el repositorio.
- Inicio tardío al perder foco, segundo plano, permiso denegado y cancelación.
- Descarte de vínculos huérfanos, finalización al disponer y fallo tardío sin notificaciones después de cerrar.
- Limpieza de reproducción temporal y respeto por captura/reproducción de otro panel.
- Transferencia de micrófono después de un fallo saliente, cancelaciones simultáneas y conservación del comportamiento de notas de voz anteriores.
- Rechazo del almacenamiento: WAV y vínculos conservados, cierre bloqueado, reintento correcto y descarte explícito. Rechazo del repositorio: reintento sin duplicar adjuntos. Panel con controles de reintento/descarte operativos y controles normales de edición deshabilitados mientras sigue pendiente.
- Renombrar/eliminar grabaciones conservando tinta en ancho de 360 píxeles.
- Intervalos de estudio, tarjetas pendientes ordenadas, pregunta desde selección, mostrar respuesta y fecha de repaso persistida en ancho de 360 píxeles.

`tool/flutter-safe analyze --no-pub lib/audio/notebook_audio_session.dart lib/audio/recording_panel.dart lib/audio/seek_audio_player.dart lib/audio/comment_audio_player.dart lib/study/study_scheduler.dart lib/study/study_panel.dart test/audio/notebook_audio_test.dart test/audio/recording_panel_test.dart test/audio/comment_player_ownership_test.dart test/study`: **sin incidencias**, salida 0.

El dispositivo de prueba genera WAV sintético; ninguna verificación utiliza micrófono ni parlantes reales. El panel de recuperación construye controlador, sesión y adquisición en la misma zona real de `tester.runAsync` que su captura inicial; las interacciones con I/O también corren allí. Evita esperar una cola creada en la zona simulada desde la zona real, lo que detenía la prueba. Las pruebas de panel que no capturan usan `tester.runAsync` solamente para crear/eliminar sus directorios.

La corrección P1 de almacenamiento se verificó RED en `/tmp/nala-small-and-audio-red.log`: ambas pruebas de conservación fallaron porque el archivo temporal se había borrado. El comportamiento corregido conserva los datos hasta una escritura confirmada o un descarte explícito. Evidencia final: `/tmp/nala-audio-preserve-green.log` y `/tmp/nala-audio-preserve-analyze.log`.

## Decisiones y límites

- Una clase no tiene corte automático por duración; termina por pedido explícito o al suspender la sesión.
- Las referencias de audio pueden ser pendientes mientras se graba o se reintenta un guardado fallido. El codec de la tarea 1 permite esa situación; la cancelación explícita, el audio inválido y la eliminación limpian vínculos. Los fallos de persistencia conservan los vínculos y el WAV.
- El cambio de foco entre editores suspende al propietario previo; la adquisición coordinada protege además el caso en que ese cierre todavía esté pendiente. AppServices dispone el dispositivo al terminar la aplicación.
- La programación de estudio es local y determinista; no requiere cuenta ni servicios externos.
- El recorte acepta PCM y float WAV sin comprimir. Los formatos WAV comprimidos no se reproducen mediante este camino y presentan un error explícito.
- La integración de editor/espacio de trabajo, la ejecución de la suite completa, el formato global y los binarios Android/Linux quedan a cargo del padre; esta tarea no modificó esos archivos ni ejecutó compilaciones simultáneas.
