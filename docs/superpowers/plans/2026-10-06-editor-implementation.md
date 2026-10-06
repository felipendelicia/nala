# Nala Editor Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, with one fresh final reviewer. Steps use checkbox syntax.

**Goal:** Mejorar escritura, lectura, zoom, comentarios y jerarquías de Nala, verificar PDF y entregar Android/Linux; Drive al final.
**Architecture:** Documento inmutable con metadatos opcionales compatibles; buffer incremental Listenable para tinta activa; SQLite para directorios; adaptadores de audio detrás de un puerto; editor con controles de vista separados.
**Tech Stack:** Flutter 3.47.6, Dart 3.13.5, SQLite, pdfrx, pdf, canales Android y PipeWire/ALSA en Linux.
**Spec:** [Diseño](../specs/2026-10-06-editor-design.md).

## Global Constraints

- Cada muestra del lápiz amplía una geometría incremental y repinta únicamente la capa de tinta activa.
- Los trazos antiguos conservan su curva de presión; los nuevos usan una curva expresiva ajustable.
- Bloquear zoom conserva la escala frente a gestos, rueda y cambios de página; permite desplazar.
- Se rechazan ciclos, destinos inexistentes y borrado de carpetas no vacías.
- La grabación empieza sólo al pulsar el botón de micrófono.
- Nunca se graba en segundo plano.
- Las compilaciones y pruebas se ejecutan de a una mediante tool/flutter-safe.
- La conexión real requiere credenciales OAuth del proyecto de Google Cloud.

## Review Focus

1. Miles de muestras por trazo y muchos trazos por hoja: cada muestra no debe reconstruir la interfaz ni serializar SVG.
2. Cerrar o suspender durante escritura/grabación: no confirmar datos incompletos ni dejar el micrófono abierto.
3. Bloqueo de zoom al cambiar de hoja o abrir un panel: conservar escala y permitir desplazamiento sin edición en lectura.
4. Mover carpetas con descendientes o apuntes: impedir ciclos y conservar referencias al volver a abrir.
5. Exportar PDF protegido mientras se escribe: conservar la instantánea y permitir desbloquear/reintentar sin perder apuntes.

### Task 1: Tinta incremental y presión

**Files:** lib/editor/draft_ink.dart, stroke_geometry.dart, paper_canvas.dart, editor_screen.dart, lib/document/notebook.dart; test/editor/fluency_test.dart.
**Interfaces:** PressureCurve {legacy, expressive, uniform}; InkStroke optional pressureCurve=legacy, sensitivity=1; StrokeGeometry.strokeWidth(stroke, pressure); DraftInk begin/add/finish/cancel, path, points, ChangeNotifier.

- [ ] RED: crear tests que verifiquen curva expresiva, codec compatible y miles de muestras sin reconstruir PaperCanvas/EditorToolbar. Run tool/flutter-safe test --no-pub --concurrency=1 test/editor/fluency_test.dart. Expected: missing interfaces or active painter changes on every sample.
```dart
expect(StrokeGeometry.strokeWidth(stroke, .8), greaterThan(StrokeGeometry.strokeWidth(stroke, .1) * 2));
expect(identical(beforePainter, afterPainter), isTrue);
```
- [ ] GREEN: añadir enum y metadatos opcionales; incremental Path.addOval/addPolygon usando la fórmula compartida; CustomPainter(repaint: draft); finish copia una vez, cancel limpia; SVG se construye sólo al exportar. Presión mouse/resaltador constante.
```dart
void updateInk(InkPoint point) { draft.add(point); }
```
- [ ] Verificar tests y suite completa; commit de la etapa.

### Task 2: Lectura y zoom

**Files:** editor_screen.dart, input_router.dart, viewport.dart, editor_toolbar.dart; test/editor/reading_zoom_test.dart.
**Interfaces:** InputRouter.readOnly bool; Viewport.zoomLocked, setScale, fitWidth; controles de lectura/escala no mutan Notebook.

- [ ] RED: lectura con stylus/mouse navega sin trazos; atajos no modifican; zoom bloqueado conserva escala tras pinch/rueda/página; pan funciona; presets y ancho cambian escala al desbloquear.
```dart
view.zoomLocked = true;
view.zoom(2, const Point(100.0, 100.0));
expect(view.scale, oldScale);
```
- [ ] GREEN: router de lectura navega; desactivar acciones/atajos de edición; controles adaptados; cambios de layout actualizan tamaño sin refit automático salvo primera apertura/ajuste explícito. Run tests y suite. Commit.

### Task 3: Jerarquías

**Files:** document/folders.dart, sqlite_notebook_repository.dart, notebook.dart, notebook_codec.dart; library_controller.dart, library_screen.dart, folder_dialog.dart; test/library/folders_test.dart.
**Interfaces:** Notebook.folderId opcional; NoteFolder(id,name,parentId); FolderRepository.listFolders/saveFolder/deleteFolder; LibraryController.currentFolderId, childFolders, breadcrumbs, createFolder/moveNotebook/moveFolder/renameFolder.

- [ ] RED: crear raíz→materia→unidad y cuaderno, mover y reabrir SQLite; rechazar ciclo y borrar carpeta no vacía; antiguos cuadernos raíz; búsqueda y UI de ruta.
```dart
await library.createFolder('Unidad 1', parentId: materia.id);
expect(library.breadcrumbs.last.name, 'Unidad 1');
```
- [ ] GREEN: tabla folders y validación de ancestros en worker; ubicación optional en codec; revisiones para movimientos; navegación por carpeta, breadcrumbs, menú de mover/renombrar. Run tests y suite. Commit.

### Task 4: Comentarios de texto y voz

**Files:** document/page_comment.dart, notebook.dart/codec; audio/audio_service.dart, audio_comment_session.dart; editor/comments_panel.dart; MainActivity.kt/manifest; test/editor/comments_test.dart y test/audio/audio_session_test.dart.
**Interfaces:** PageComment(id,x,y,text,createdAt,audioAssetId?,audioDurationMs?); NotebookPage.comments; AudioDevice.start/stop/cancel/play/stopPlayback/dispose; AudioCommentSession.commit almacena bytes por hash y borra temporales.

- [ ] RED: comentarios codec/reabrir, editar/eliminar y consulta lectura; permiso denegado y cancelación no crean comentario; audio guardado por hash; dispose/suspensión cierra captura; máximo una grabación/reproducción.
```dart
await session.cancel();
expect(await assets.contains(hash), isFalse);
```
- [ ] GREEN: adaptadores Android con permiso/MediaRecorder/MediaPlayer y Linux pw-record/pw-play; estados explícitos y temporales; pins y lista por página; diálogo de texto/grabación con guardar/cancelar. Run tests y suite. Commit.

### Task 5: PDF y entrega local

**Files:** integration_test/pdf_round_trip_test.dart, pdf/*.dart según causa; docs/verification.md/status.md/README, pubspec.yaml, dist ignorado.

- [ ] Investigar fallo nativo con log verbose y condiciones reales; corregir la causa con reproducción antes del cambio.
- [ ] Verificar crear/reabrir y flujo PDF Linux. Inspeccionar exportación y escenas de lectura/carpeta/comentarios; pruebas sin activar micrófono real.
- [ ] Suite completa y analyze limpios; build Android release y Linux release de a uno. Version 0.2.0+2, actualizar entregables y documentar límites de prueba física.

### Task 6: Drive al final

**Files:** contratos, motor, auth y UI de las tareas 5–6 del plan inicial; docs/drive-setup.md.

- [ ] Leer briefs del plan inicial y ejecutar RED→GREEN del motor con dos repositorios y remoto de prueba: ramas, reintento perdido, assets PDF/audio, paginación y carpetas.
- [ ] Implementar adaptadores Drive/OAuth configurables sin credenciales inventadas; preservar notas y colas ante revocación/cambio de cuenta; mostrar conexión/configuración y estados reales.
- [ ] Verificar las pruebas y documentar qué comprobación exige OAuth externo; no afirmar sincronización real sin cuenta configurada.

### Final

- [ ] Una revisión de contexto fresco sobre todo el cambio. Corregir Important/Critical con tests RED→GREEN y suite.
- [ ] Compilaciones finales si el código cambió tras las primeras builds; commits/push al repositorio público autorizado, prerelease con APK/Linux/checksums.
- [ ] Informe conciso de funciones entregadas, verificación y requisitos externos restantes.
