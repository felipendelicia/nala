# Apuntes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crear una app de apuntes con escritura y PDFs, editable en una Samsung Tab S10 y Linux, con guardado local y sincronización automática con Google Drive.

**Architecture:** Una aplicación Flutter comparte el modelo, el editor y la sincronización entre Android y Linux. SQLite confirma el documento y su revisión pendiente en una transacción; Drive almacena revisiones inmutables y PDFs originales identificados por contenido. La sincronización conserva ramas concurrentes y muestra sus versiones, sin sobrescribir notas.

**Tech Stack:** Flutter estable 3.47, Dart, sqlite3 3.7.0, pdfrx 2.6.5, pdf 3.13.1, google_sign_in 7.2.0 para Android, oauth2 2.0.5 para Linux, flutter_secure_storage 11.2.0 y file_selector 1.1.0. También http, crypto, uuid, path, path_provider, url_launcher y vector_math, resueltos y fijados en pubspec.lock al crear el proyecto.

**Spec:** [Diseño aprobado](../specs/2026-10-06-apuntes-design.md).

## Global Constraints

- "Tomar apuntes con el S Pen en una Samsung Tab S10 y continuar trabajando con los mismos documentos en una PC con Linux."
- "Las páginas de cuaderno ofrecen fondo blanco, rayado, cuadriculado o punteado."
- "El PDF se importa como parte del documento y mantiene sus páginas como fondo."
- "Los cambios se guardan automáticamente en el dispositivo."
- "El desplazamiento y el zoom no modifican esas coordenadas."
- "La actividad de red y la preparación de documentos no bloquean la escritura."
- "Solicita el alcance `drive.file` para trabajar con los archivos creados por la aplicación."
- "La primera versión garantiza este comportamiento con la aplicación activa; sincronizar con la aplicación cerrada requiere trabajo específico según el sistema operativo."
- "Volver a sincronizar no crea copias nuevas del mismo conflicto."
- "Los tokens se guardan en el almacenamiento seguro del dispositivo."

## Review Focus

1. Cierre inesperado o disco sin espacio: conservar la última edición confirmada y no marcar como guardado lo que no se confirmó. Pruebas en tarea 2.
2. Cancelación del lápiz y cambios de zoom: descartar el trazo cancelado y conservar la posición de todos los trazos confirmados. Pruebas en tarea 3.
3. PDFs dañados, protegidos y páginas rotadas o de distintos tamaños: conservar el documento previo y mantener fondos y tinta alineados. Pruebas en tarea 4.
4. Dos clientes sin conexión, respuestas perdidas y listados paginados: conservar ambas ramas y deduplicar reintentos. Pruebas en tareas 5 y 6.
5. Cambio de cuenta o autorización revocada: conservar los apuntes y no subir automáticamente notas de una cuenta a otra. Pruebas en tarea 6.

## Entregas y entorno

Las tareas 1–3 producen un editor local que se puede probar con el S Pen. La tarea 4 añade el flujo PDF completo. Las tareas 5–7 completan Drive y la entrega en ambos dispositivos. Son etapas del mismo proyecto porque comparten documentos, coordenadas y revisiones.

El código se creará en `apuntes/`, dentro del workspace actual. Los comandos de aplicación se ejecutan desde esa carpeta. El workspace todavía no contiene una app ni un repositorio Git válido. No se modifican los repositorios previos de Felipe.

Se encontraron Java 21, Android SDK y build-tools 36.0.0. Flutter no está en PATH. Linux tiene GTK 3 y SQLite de desarrollo; faltan clang, ninja y libsecret de desarrollo. La instalación de herramientas y las descargas se harán al ejecutar, respetando las aprobaciones del sandbox. La escritura real se valida en la tablet: una prueba con mouse o emulador no reemplaza esa comprobación.

## Estructura y contratos compartidos

```text
apuntes/
  lib/
    main.dart
    app.dart
    bootstrap.dart
    document/
      notebook.dart
      notebook_codec.dart
      revision.dart
      notebook_repository.dart
      sqlite_notebook_repository.dart
      asset_store.dart
    editor/
      editor_controller.dart
      editor_screen.dart
      paper_canvas.dart
      paper_background.dart
      stroke_geometry.dart
      input_router.dart
      viewport.dart
      editor_toolbar.dart
      page_panel.dart
    library/
      library_screen.dart
      library_controller.dart
    pdf/
      pdf_service.dart
      pdfrx_pdf_service.dart
      pdf_background_cache.dart
      pdf_export_service.dart
    sync/
      remote_store.dart
      sync_engine.dart
      sync_coordinator.dart
      sync_state.dart
      drive_remote_store.dart
      drive_http.dart
    account/
      account.dart
      auth_service.dart
      android_auth_service.dart
      linux_auth_service.dart
      token_store.dart
      account_controller.dart
    ui/
      app_theme.dart
      sync_indicator.dart
  test/
    support/fixtures.dart
    support/fake_remote_store.dart
    support/fake_auth_service.dart
    document/
    editor/
    library/
    pdf/
    sync/
    account/
  integration_test/
    local_notebook_test.dart
    pdf_round_trip_test.dart
  docs/
    drive-setup.md
    verification.md
  README.md
```

Los archivos se separan por responsabilidad. No concentrar el lienzo, OAuth y la persistencia en una pantalla o un servicio único.

### Tipos de documento, definidos en tarea 1

Usar Dart puro y `dart:math` para estos tipos; evitar referencias a widgets. Colecciones inmutables y `copyWith` con los mismos nombres de propiedad.

```dart
enum PaperPattern { blank, ruled, grid, dots }
enum InkTool { pen, highlighter }
enum EditorTool { pen, highlighter, eraser, selection }

// InkPoint: double x, y, pressure.
// InkStroke: String id; InkTool tool; int argb;
//            double width; List<InkPoint> points.
// PageBackground.paper(PaperPattern pattern).
// PageBackground.pdf(String assetId, int pageNumber): página de PDF desde 1.
// NotebookPage: String id; double width, height;
//               PageBackground background; List<InkStroke> strokes.
// Notebook: String id, title, subject; List<NotebookPage> pages;
//           DateTime updatedAt.
// Revision: String id, deviceId; String? parentId;
//           DateTime createdAt; Notebook notebook.
// DocumentEntry: Notebook notebook; String headId; bool isConflict.
```

Constructores con argumentos nombrados y requeridos para las propiedades anteriores; `parentId` admite null para la primera revisión. Revision expone `withParent(String? parentId)` para normalizar una revisión local pendiente conservando sus demás propiedades. Todas las fechas se serializan en UTC. Guardar las coordenadas en puntos de página, con origen arriba a la izquierda. Las hojas nuevas usan A4 vertical, 595.28 × 841.89 puntos; los PDFs conservan su tamaño y orientación.

`Notebook.blank({required String id, required String pageId, required String title, String subject = '', required PaperPattern pattern, required DateTime now})` crea una hoja. `NotebookCodec.encode(Notebook)` retorna String y `decode(String)` retorna Notebook. `NotebookCodec.encodeRevision(Revision)` y `decodeRevision(String)` usan un formato JSON con `schemaVersion: 1`. Rechazar versiones futuras, identificadores duplicados, páginas sin tamaño positivo y números no finitos, sin reemplazar un documento válido.

### Contratos de persistencia, definidos en tarea 2

```dart
abstract interface class NotebookRepository {
  Future<List<DocumentEntry>> list();
  Future<Notebook?> load(String documentId, {String? headId});
  Future<void> commit(Revision revision);
  Future<List<Revision>> pending();
  Future<List<Revision>> history(String documentId);
  Future<void> markUploaded(String revisionId);
  Future<void> acceptRemote(Revision revision);
  Future<void> close();
}

abstract interface class AssetStore {
  Future<String> put(Uint8List bytes);
  Future<Uint8List> read(String assetId);
  Future<bool> contains(String assetId);
}
```

`AssetStore.put` retorna SHA-256 hexadecimal del contenido. La implementación guarda bytes en un archivo temporal y lo renombra a su identificador después de confirmar la escritura. Nunca incorpora rutas locales a las revisiones sincronizadas.

## Task 1: Aplicación ejecutable con hojas y trazos

**Files:** Crear `apuntes/pubspec.yaml`, plataformas `android/` y `linux/`, `lib/main.dart`, `lib/app.dart`, `lib/bootstrap.dart`, los modelos y codec de `lib/document/`, `lib/editor/editor_screen.dart`, `lib/editor/paper_canvas.dart`, `lib/editor/paper_background.dart`, `test/document/notebook_codec_test.dart`, `test/support/fixtures.dart` y `README.md`.

**Interfaces:** Produce los tipos, constructores y codec definidos arriba. Produce `PaperCanvas({required NotebookPage page, required ValueChanged<InkStroke> onStroke, required EditorTool tool})`. `test/support/fixtures.dart` define `fixtureNotebook({String id = 'doc-1'})` y `fixtureStroke({String id = 'stroke-1'})`, con puntos (10,20,0.25) y (30,40,0.75), color 0xff202020 y ancho 2.

- [ ] Preparar Flutter estable siguiendo el archivo oficial; usar SDK y caches del proyecto si es compatible con la herramienta. Registrar la versión exacta de Flutter y Dart en README. Instalar solamente las dependencias de Linux que falten, con aprobación cuando la requiera el sandbox. Crear el proyecto, configurar Android con minSdk 24, compileSdk 36 y targetSdk 36, y establecer applicationId `com.felipe.apuntes`.

```bash
flutter create --platforms=android,linux --org com.felipe apuntes
```

Desde `apuntes/`, resolver dependencias y conservar `pubspec.lock`:

```bash
flutter pub add sqlite3:3.7.0 pdfrx:2.6.5 pdf:3.13.1
flutter pub add google_sign_in:7.2.0 oauth2:2.0.5 flutter_secure_storage:11.2.0 file_selector:1.1.0
flutter pub add http crypto uuid path path_provider url_launcher vector_math
flutter doctor -v
```

Si las restricciones del SDK de un paquete no admiten Flutter 3.47 estable, comprobar su changelog oficial y ajustar la dependencia concreta antes de cambiar la arquitectura. No instalar un canal experimental para resolver una dependencia.

- [ ] Escribir las pruebas del modelo antes de su implementación.

```dart
test('el codec conserva presión, patrón y coordenadas', () {
  final original = fixtureNotebook();
  final restored = NotebookCodec.decode(NotebookCodec.encode(original));
  expect(restored.pages.single.background.pattern, PaperPattern.grid);
  expect(restored.pages.single.strokes.single.points.last.pressure, 0.75);
  expect(restored.pages.single.strokes.single.points.last.x, 30);
});
test('cambiar el patrón conserva los trazos', () {
  final page = fixtureNotebook().pages.single;
  final changed = page.copyWith(background: PageBackground.paper(PaperPattern.ruled));
  expect(changed.strokes, page.strokes);
});
```

- [ ] Ejecutar `flutter test test/document/notebook_codec_test.dart` y comprobar que falla por los tipos ausentes; después implementar modelos y codec. El JSON serializa cada propiedad declarada y contiene `schemaVersion`, con validación al decodificar.

```dart
final json = <String, Object?>{
  'schemaVersion': 1,
  'id': notebook.id,
  'title': notebook.title,
  'subject': notebook.subject,
  'updatedAt': notebook.updatedAt.toUtc().toIso8601String(),
  'pages': notebook.pages.map((page) => page.toJson()).toList(),
};
```

`toJson` y `fromJson` se implementan en InkPoint, InkStroke, PageBackground y NotebookPage. Incluyen todos sus campos. PageBackground expone getters nullable `pattern`, `assetId` y `pageNumber`; exactamente una variante es válida.

- [ ] Crear una pantalla de hoja con selector de patrón y dibujo en memoria. Dibujar fondos separados de los trazos con CustomPainter y RepaintBoundary. Lápiz usa polilíneas con extremos redondos; resaltador usa color con alpha 0x55. Cambiar patrón o tamaño de ventana no borra los trazos.

```dart
final nextPage = page.copyWith(strokes: [...page.strokes, stroke]);
final nextNotebook = notebook.copyWith(
  pages: notebook.pages.map((p) => p.id == page.id ? nextPage : p).toList(),
);
```

- [ ] Ejecutar las pruebas y `flutter run -d linux`. Comprobar los cuatro patrones y un trazo al cambiar el patrón. Crear el repositorio Git dentro de `apuntes/` y confirmar esta entrega si el entorno permite escribir su metadata. No afirmar que hay commit si el sandbox lo impide.

## Task 2: Biblioteca y guardado local que resiste cierres

**Files:** Crear `lib/document/notebook_repository.dart`, `sqlite_notebook_repository.dart`, `asset_store.dart`, `lib/editor/editor_controller.dart`, `lib/library/library_controller.dart`, `library_screen.dart`, `test/document/repository_test.dart` y `test/library/library_test.dart`; modificar bootstrap, app y pantalla del editor.

**Interfaces:** Consume Notebook, Revision, DocumentEntry y NotebookCodec. Produce los contratos de persistencia arriba, `SqliteNotebookRepository.open(String path)`, `FileAssetStore(String directory)`, `EditorController({required Notebook notebook, required NotebookRepository repository, required String deviceId, required String Function() newId, required DateTime Function() now, String? headId})`, con getters `notebook`, `headId`, `savingError`, métodos `apply(Notebook Function(Notebook) edit)`, `undo()`, `redo()`, `flush()` y `dispose()`. Produce `LibraryController.refresh()` y `createNotebook({required String title, required String subject, required PaperPattern pattern})`, y un stream/listenable de entradas.

- [ ] Escribir pruebas que guarden un trazo, cierren y abran el repositorio, y recuperen documento y cola. Usar un directorio temporal por prueba y `addTearDown` para cerrar. Añadir prueba de transacción fallida mediante un disparador SQLite que aborte la inserción en la cola; verificar que la revisión tampoco aparece. Añadir caso de cien cambios locales seguidos: quedan el último estado y un único pendiente. Un pendiente que ya se intentó subir queda congelado y nunca se sustituye, aunque se pierda su respuesta.

```dart
test('un cierre conserva el cuaderno y el pendiente', () async {
  final repo = await SqliteNotebookRepository.open(dbPath);
  final revision = Revision(id: 'r1', deviceId: 'tablet', parentId: null,
    createdAt: DateTime.utc(2026, 10, 6), notebook: fixtureNotebook());
  await repo.commit(revision);
  await repo.close();
  final restored = await SqliteNotebookRepository.open(dbPath);
  expect((await restored.load('doc-1'))!.pages.single.strokes.length, 1);
  expect((await restored.pending()).single.id, 'r1');
  await restored.close();
});
```

- [ ] Ejecutar `flutter test test/document/repository_test.dart` y comprobar el fallo. Crear SQLite con WAL, busy_timeout y tablas de revisiones y cola. El historial es fuente de los heads: una revisión es head si su id no aparece como parentId de otra revisión del mismo documento.

```sql
CREATE TABLE revisions (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL,
  parent_id TEXT,
  payload TEXT NOT NULL,
  frozen INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX revisions_document ON revisions(document_id);
CREATE TABLE upload_queue (
  revision_id TEXT PRIMARY KEY REFERENCES revisions(id)
);
```

```dart
db.execute('BEGIN IMMEDIATE');
try {
  var effective = revision;
  final parent = db.select('SELECT * FROM revisions WHERE id = ?', [revision.parentId]);
  if (parent.isNotEmpty && parent.single['document_id'] != revision.notebook.id) {
    throw StateError('La revisión padre pertenece a otro cuaderno');
  }
  final children = db.select('SELECT id FROM revisions WHERE parent_id = ?', [revision.parentId]);
  if (parent.isNotEmpty && parent.single['frozen'] == 0 && children.isEmpty) {
    effective = revision.withParent(parent.single['parent_id'] as String?);
    db.execute('DELETE FROM upload_queue WHERE revision_id = ?', [revision.parentId]);
    db.execute('DELETE FROM revisions WHERE id = ?', [revision.parentId]);
  }
  db.execute('INSERT INTO revisions (id,document_id,parent_id,payload) VALUES (?, ?, ?, ?)',
    [effective.id, effective.notebook.id, effective.parentId,
     NotebookCodec.encodeRevision(effective)]);
  db.execute('INSERT INTO upload_queue VALUES (?)', [revision.id]);
  db.execute('COMMIT');
} catch (_) {
  db.execute('ROLLBACK');
  rethrow;
}
```

La conexión SQLite vive en un isolate dedicado. Mensajes al isolate: operación, requestId y datos serializables; respuestas: requestId, resultado o error. El objeto de conexión SQLite nunca cruza isolates. Serializar operaciones de escritura y drenar la cola antes de cerrar.

Antes de entregar revisiones a la red, `pending()` confirma `frozen = 1` para esas revisiones dentro de una transacción. `acceptRemote` también inserta frozen = 1. Esta marca nunca se revierte: una subida pudo haber terminado aunque no llegara su respuesta. La coalescencia solo descarta un padre local no congelado del mismo documento y sin otros hijos. Una revisión congelada se conserva y se reintenta con su mismo id y contenido. No almacenar un snapshot completo por cada movimiento del lápiz ni subir una revisión por cada trazo.

- [ ] Implementar el controlador: confirmar al terminar un trazo o una acción, no en cada movimiento. Undo/redo generan nuevas revisiones guardables. `headId` cambia solamente después de commit exitoso; `flush()` espera las escrituras pendientes. Ante disco lleno, conservar el estado en memoria, mostrar error de guardado y permitir reintentar sin confirmar falsamente éxito.

```dart
final revision = Revision(
  id: newId(), deviceId: deviceId, parentId: headId,
  createdAt: now().toUtc(), notebook: edited,
);
await repository.commit(revision);
```

- [ ] Conectar biblioteca: crear cuaderno, filtrar por materia, buscar título sin distinguir mayúsculas ni acentos, abrir y renombrar. Generar miniaturas a partir del mismo modelo. La lista muestra una entrada por head y marca los conflictos cuando hay más de uno. En listas vacías, mostrar Crear cuaderno y Abrir PDF.

- [ ] Ejecutar `flutter test test/document test/library`. Verificar recuperación después de cerrar y abrir la aplicación y confirmar esta entrega en Git cuando esté disponible.

## Task 3: Escritura, herramientas y navegación en la tablet

**Files:** Crear `lib/editor/input_router.dart`, `viewport.dart`, `stroke_geometry.dart`, `editor_toolbar.dart`, `page_panel.dart`, `test/editor/input_router_test.dart`, `viewport_test.dart`, `tools_test.dart` e `integration_test/local_notebook_test.dart`; modificar paper_canvas y editor_screen.

**Interfaces:** Consume EditorController y los modelos. Produce `Viewport.pagePoint(Point<double> viewportPoint)`, `pan(double dx, double dy)`, `zoom(double factor, Point<double> anchor)` y su matriz afín. Produce `InputRouter` con `down`, `move`, `up`, `cancel` y `hover` que reciben pointerId, clase de dispositivo y posición. Produce `StrokeGeometry.widthFor(double base, double pressure)`, `hitTest(InkStroke stroke, Point<double> point, double radius)`, `translate(InkStroke stroke, double dx, double dy)` y `svg(NotebookPage page)` para usar el mismo contorno de tinta en pantalla y exportación.

- [ ] Escribir pruebas del gesto cancelado, de la palma durante un trazo, de zoom anclado y de borrado con undo. La entrada táctil nunca produce tinta. La prueba de cancelación espera cero trazos confirmados.

```dart
test('el zoom conserva la posición de la hoja bajo el ancla', () {
  final view = Viewport();
  final anchor = Point<double>(120, 80);
  final before = view.pagePoint(anchor);
  view.zoom(2, anchor);
  final after = view.pagePoint(anchor);
  expect(after.x, closeTo(before.x, 0.0001));
  expect(after.y, closeTo(before.y, 0.0001));
});
test('la presión modifica el ancho sin llegar a cero', () {
  expect(StrokeGeometry.widthFor(4, 0), 1.4);
  expect(StrokeGeometry.widthFor(4, 1), 4);
});
```

- [ ] Ejecutar `flutter test test/editor`. Implementar conversión de coordenadas y ancho. Capturar eventos desde un Listener exterior al viewport y transformar su localPosition una sola vez. La matriz representa solo escala y traslación de la hoja, con la hoja anclada a un origen explícito.

```dart
Point<double> pagePoint(Point<double> point) =>
    Point((point.x - tx) / scale, (point.y - ty) / scale);

void zoom(double factor, Point<double> anchor) {
  final fixed = pagePoint(anchor);
  scale = (scale * factor).clamp(0.25, 6.0).toDouble();
  tx = anchor.x - fixed.x * scale;
  ty = anchor.y - fixed.y * scale;
}

double widthFor(double base, double pressure) =>
    base * (0.35 + 0.65 * pressure.clamp(0.0, 1.0));
```

Normalizar presión usando pressureMin y pressureMax; si no hay rango válido, usar 1. El router mantiene el id del lápiz activo, ignora gestos táctiles mientras escribe y descarta el borrador de trazo ante PointerCancelEvent. Un dedo desplaza y dos hacen zoom cuando no se escribe. En Linux, mouse primario dibuja, rueda amplía con ancla y botón central desplaza. No usar un recognizer que haga pan con el mismo pointer de lápiz.

- [ ] Implementar selección rectangular, movimiento y eliminación de trazos completos, borrador por intersección con segmento y deshacer/rehacer. Conservar ids al mover y crear ids nuevos al dibujar. Agrupar todo el gesto de movimiento o borrado en una sola entrada de historial.

```dart
final moved = selectedIds.contains(stroke.id)
    ? StrokeGeometry.translate(stroke, dx, dy)
    : stroke;
```

Implementar una geometría compartida que obtiene el contorno del trazo con ancho dependiente de presión y extremos redondos. `svg` serializa ese contorno, el color y alpha; el painter dibuja el mismo contorno. No recalcular todos los trazos durante cada evento: cachear geometría de trazos confirmados y repintar solo la tinta en progreso.

- [ ] Añadir panel de páginas, agregar hoja, cambiar patrón por página o para todas las hojas de cuaderno, colores y grosores, y atajos Ctrl+Z/Ctrl+Shift+Z, P, H, E, S y Delete. No cambiar un fondo PDF al aplicar un patrón a todo el cuaderno.

- [ ] Ejecutar pruebas y construir `flutter build apk --debug`. Probar en la Tab S10: apoyar la palma, trazos rápidos, presión, botón del lápiz si entrega eventos, dos dedos, cancelar un gesto, mover y borrar una selección, cerrar y volver a abrir. Registrar resultados en `docs/verification.md`; pedir la comprobación física solo cuando haya un APK descargable.

## Task 4: PDF importado, páginas mixtas y exportación

**Files:** Crear todos los archivos de `lib/pdf/`, `test/pdf/import_test.dart`, `export_test.dart` e `integration_test/pdf_round_trip_test.dart`; modificar biblioteca y editor para importar, renderizar y exportar.

**Interfaces:** Consume AssetStore, NotebookPage, PageBackground, StrokeGeometry. Produce `PdfService.importDocument({required Uint8List bytes, required String title, required String documentId, required String Function() newId, required DateTime now, String? password}) -> Future<Notebook>`, `renderBackground(String assetId, int pageNumber, {required double scale}) -> Future<Uint8List>` y `PdfExportService.export(Notebook notebook) -> Future<Uint8List>`. Devuelve PNG desde renderBackground y PDF desde export. PDF importado se guarda como asset completo dentro del documento.

- [ ] Crear fixtures PDF deterministas en las pruebas usando el paquete pdf: dos páginas, una A4 vertical y otra horizontal, con texto y marcas de esquina. Escribir prueba de importación de tamaños, prueba de bytes inválidos que no modifica el repositorio y prueba de insertar una hoja entre las dos páginas importadas.

```dart
test('PDF importado conserva tamaños y referencia de página', () async {
  final note = await service.importDocument(
    bytes: fixturePdfBytes, title: 'Guía', documentId: 'guide-1',
    newId: nextFixtureId, now: DateTime.utc(2026, 10, 6),
  );
  expect(note.pages.length, 2);
  expect(note.pages.first.background.pageNumber, 1);
  expect(note.pages.last.width, greaterThan(note.pages.last.height));
});
```

`nextFixtureId` en fixtures retorna sucesivamente `id-1`, `id-2` y siguientes. `fixturePdfBytes` es generado por un helper async `makeFixturePdf()` en fixtures, antes de ejecutar la prueba. Añadir además fixtures de PDF protegido y rotación de 90 grados generados para las pruebas del engine.

- [ ] Ejecutar la prueba de importación, comprobar su fallo e implementar lectura con pdfrx. Inicializar el engine antes de abrir documentos. No copiar APIs de visor Material dentro del editor propio: pdfrx 2.5+ usa material_ui y el lienzo no necesita sus menús.

```dart
final pdfDocument = await PdfDocument.openData(bytes);
try {
  final sizes = pdfDocument.pages.map((page) => (page.width, page.height)).toList();
  final assetId = await assets.put(bytes);
  return Notebook(
    id: documentId, title: title, subject: '', updatedAt: now.toUtc(),
    pages: [for (var i = 0; i < sizes.length; i++) NotebookPage(
      id: newId(), width: sizes[i].$1, height: sizes[i].$2,
      background: PageBackground.pdf(assetId, i + 1), strokes: const [],
    )],
  );
} finally {
  await pdfDocument.dispose();
}
```

Usar passwordProvider cuando se aporte password; si hace falta, pedirlo en un diálogo y no conservarlo en revisiones ni logs. Renderizar páginas rotadas con la misma orientación y tamaño que el modelo. Abrir y cerrar recursos explícitamente.

- [ ] Implementar caché LRU de fondos con clave (assetId, página, escala discretizada), presupuesto de 64 MiB y render cancelable. El último fondo válido sigue visible durante un nuevo render. Solo renderizar la página visible y sus vecinas; liberar imágenes expulsadas del caché.

- [ ] Exportar el cuaderno en orden, con tamaño exacto por página. En la primera versión los fondos PDF se renderizan a 200 dpi y la tinta se añade en vectores desde el SVG compartido. Es una copia visual para compartir: conserva aspecto y tamaño, aunque el texto del fondo exportado pasa a ser imagen. El original y los trazos editables siguen en el documento de la app. Procesar páginas fuera del isolate de interfaz y una por vez.

```dart
final output = pw.Document();
output.addPage(pw.Page(
  pageFormat: PdfPageFormat(page.width, page.height, marginAll: 0),
  build: (_) => pw.Stack(children: [
    if (backgroundPng != null)
      pw.Positioned.fill(child: pw.Image(pw.MemoryImage(backgroundPng))),
    pw.Positioned.fill(child: pw.SvgImage(svg: StrokeGeometry.svg(page))),
  ]),
));
final bytes = await output.save();
```

El SVG también incluye el patrón para las hojas de cuaderno. En PDFs, solo incluye tinta sobre fondo transparente. Verificar cómo pw.SvgImage trata transparencia con un resaltado sobre texto.

- [ ] Escribir y ejecutar la prueba de ida y vuelta: importar fixture, añadir tinta conocida en las esquinas, insertar hoja, exportar, abrir resultado con pdfrx y comparar número de páginas, tamaños y posiciones de las marcas. Probar escritura y navegación mientras se prepara la exportación. Guardar o compartir usando el selector nativo compatible con cada plataforma; cancelarlo no borra el documento.

## Task 5: Sincronización de revisiones con dos clientes

**Files:** Crear `lib/sync/remote_store.dart`, `sync_engine.dart`, `sync_coordinator.dart`, `sync_state.dart`, `test/support/fake_remote_store.dart`, `test/sync/sync_engine_test.dart` y `sync_coordinator_test.dart`; modificar biblioteca y controlador para mostrar estados y ramas.

**Interfaces:** Produce RemoteStore y SyncEngine. Consume los contratos de repositorio y assets y el codec de revisión.

```dart
abstract interface class RemoteStore {
  Future<List<Revision>> listRevisions();
  Future<void> putRevision(Revision revision);
  Future<bool> hasAsset(String assetId);
  Future<void> putAsset(String assetId, Uint8List bytes);
  Future<Uint8List> readAsset(String assetId);
}
enum SyncPhase { localOnly, pending, syncing, synced, error, needsSignIn }
// SyncStatus: SyncPhase phase; String? message; int pendingCount.
// SyncEngine(repository, assets, remote):
//   Future<void> synchronize(); Stream<SyncStatus> get states; void dispose().
// SyncCoordinator(engine): void start(); void stop();
//   void notifyLocalChange(); void dispose().
```

- [ ] Implementar primero el fake de RemoteStore con mapas de assetId y revisionId. Permitir simular caída antes de escribir y caída después de escribir pero antes de responder. Escribir la prueba de dos ramas desde una base y de reintento con respuesta perdida.

```dart
test('dos clientes offline conservan las dos ramas una sola vez', () async {
  await tablet.commit(Revision(id: 'base', deviceId: 'tablet', parentId: null,
    createdAt: clock, notebook: fixtureNotebook()));
  await tabletSync.synchronize();
  await pcSync.synchronize();
  await tablet.commit(Revision(id: 'tablet-edit', deviceId: 'tablet', parentId: 'base',
    createdAt: clock, notebook: fixtureNotebook().copyWith(title: 'Cambio tablet')));
  await pc.commit(Revision(id: 'pc-edit', deviceId: 'pc', parentId: 'base',
    createdAt: clock, notebook: fixtureNotebook().copyWith(title: 'Cambio PC')));
  await tabletSync.synchronize();
  await pcSync.synchronize();
  await tabletSync.synchronize();
  expect((await tablet.list()).map((e) => e.headId).toSet(),
    {'tablet-edit', 'pc-edit'});
  expect((await tablet.load('doc-1', headId: 'tablet-edit'))!.title, 'Cambio tablet');
  expect((await tablet.load('doc-1', headId: 'pc-edit'))!.title, 'Cambio PC');
  await tabletSync.synchronize();
  expect((await tablet.list()).length, 2);
});
```

Cada test crea dos SQLite reales en directorios temporales y un fake remoto compartido. `clock` es DateTime.utc(2026,10,6); tabletSync y pcSync usan su repositorio y AssetStore correspondiente.

- [ ] Ejecutar `flutter test test/sync/sync_engine_test.dart` y comprobar el fallo. Implementar un solo synchronize activo por engine. Primero traer revisiones y recursos desconocidos; después subir pendientes con assets completos, y volver a traer revisiones para detectar una rama que apareció durante la subida. Marcar subida solamente después de confirmación remota.

```dart
for (final revision in await repository.pending()) {
  final ids = revision.notebook.pages
      .map((page) => page.background.assetId).whereType<String>().toSet();
  for (final id in ids) {
    if (!await remote.hasAsset(id)) {
      await remote.putAsset(id, await assets.read(id));
    }
  }
  await remote.putRevision(revision);
  await repository.markUploaded(revision.id);
}
```

`acceptRemote` es idempotente y no mete revisiones remotas en upload_queue. Comprobar el hash de assets descargados antes de aceptar la revisión. Calcular heads a partir de todo el grafo, no del orden de llegada. Revisión idéntica tiene id único aunque se haya subido dos veces por un timeout.

- [ ] Añadir pruebas: falla de red conserva pendientes; asset incompleto no hace visible una revisión; hijo recibido antes del padre no crea conflicto falso; sincronizar mientras se escribe no reemplaza el estado en memoria; notas nuevas sin parentId aparecen en el otro cliente. Una actualización remota de un documento abierto se aplica después de guardar sus cambios locales, conservando ramas si se generaron dos heads.

- [ ] Implementar SyncCoordinator: sincronizar al iniciar o retomar la app; debounce de 2 segundos al confirmar cambios locales; sondeo cada 30 segundos mientras está activa. Así descubre cambios del otro dispositivo y recupera red aunque no haya ediciones nuevas. Pausar timers cuando la app no está activa y reanudar con AppLifecycleListener. Los tests usan tiempo simulado y comprueban debounce, retry y pausa, sin sleeps reales.

```dart
void notifyLocalChange() {
  debounce?.cancel();
  debounce = Timer(const Duration(seconds: 2), () {
    unawaited(engine.synchronize());
  });
}
```

El engine comunica fallos por SyncStatus y absorbe fallos de transporte esperables, para que un Timer no deje errores async sin capturar. Los reintentos de errores repetidos usan espera creciente hasta 60 segundos; un guardado nuevo no salta un Retry-After activo.

- [ ] Conectar estados al editor y biblioteca. Mostrar dos entradas con dispositivo y fecha ante conflicto; abrir una entrada usa su headId. Confirmar esta entrega con las pruebas de ambos clientes pasando.

## Task 6: Google Drive real y autenticación por plataforma

**Files:** Crear todos los archivos de `lib/account/`, `lib/sync/drive_remote_store.dart`, `drive_http.dart`, `test/account/auth_test.dart`, `test/sync/drive_remote_store_test.dart`, `test/support/fake_auth_service.dart` y `docs/drive-setup.md`; modificar bootstrap, biblioteca y AndroidManifest.xml.

**Interfaces:** `GoogleAccount` tiene `String id, email`. `AuthService` expone `Future<GoogleAccount?> restore()`, `Future<GoogleAccount> signIn()`, `Future<Map<String,String>> authorizationHeaders()`, `Future<void> signOut()`. `TokenStore` expone read/write/delete de credenciales serializadas en almacenamiento seguro. `DriveRemoteStore(AuthService auth, http.Client client)` implementa RemoteStore. `AccountController` cambia el repositorio y engine activos al cambiar de cuenta.

- [ ] Escribir pruebas HTTP con MockClient de `package:http/testing.dart`: dos páginas en files.list; multipart de revisión; asset existente; 401 y autorización revocada; creación con timeout después de éxito y deduplicación por appProperties.revisionId. Escribir prueba de cambio de cuenta con el fake de auth, confirmando que el engine antiguo se detiene y sus pendientes no se suben con la sesión nueva.

```dart
test('el adaptador consume todas las páginas del listado', () async {
  final client = MockClient((request) async {
    final second = request.url.queryParameters['pageToken'] == 'page-2';
    return Response(jsonEncode(second
      ? {'files': secondPageFiles}
      : {'files': firstPageFiles, 'nextPageToken': 'page-2'}), 200);
  });
  final remote = DriveRemoteStore(fakeAuth, client);
  final revisions = await remote.listRevisions();
  expect(revisions.map((r) => r.id).toSet(), {'r1', 'r2'});
});
```

firstPageFiles y secondPageFiles describen ids y appProperties de revisiones; MockClient también responde los GET `alt=media` con el JSON serializado de r1 y r2. La prueba distingue esos requests por alt, no devuelve metadata como contenido.

- [ ] Ejecutar los tests para confirmar el fallo. Implementar Drive API v3 con alcance drive.file. Crear carpeta visible `Apuntes Universidad` y appProperties `application: apuntes-v1, kind: root`. Revisión usa kind: revision, revisionId, documentId; recurso usa kind: asset, assetId. Consultar objetos por propiedades de aplicación además de carpeta para descubrir datos si dos dispositivos crearon carpetas al mismo tiempo.

```dart
final listUri = Uri.https('www.googleapis.com', '/drive/v3/files', {
  'q': "trashed = false and appProperties has { key='application' and value='apuntes-v1' }",
  'fields': 'nextPageToken,files(id,name,appProperties)',
  'pageSize': '1000',
  if (pageToken != null) 'pageToken': pageToken,
});
```

Consultar antes de crear y después de un timeout. Deduplicar revisiones por revisionId y recursos por SHA-256. Tratar todas las carpetas raíz encontradas como parte de la misma biblioteca y elegir una de forma determinista para subir nuevos archivos. Nunca reemplazar revisiones existentes con contenido diferente.

- [ ] Implementar subida multipart para JSON pequeño y subida resumable para PDFs, con reanudación y consulta de rango después de interrupción. Guardar localmente sesión y progreso de subida, vinculados a accountId y assetId. Después de subir, comprobar el hash de contenido usado para ese asset. Timeouts 30 s, reintentos con jitter para 429/5xx; 401 intenta renovar una vez y luego expone needsSignIn. Respetar Retry-After si está presente.

```dart
final startUpload = Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
  'uploadType': 'resumable',
});
final headers = {
  ...await auth.authorizationHeaders(),
  'Content-Type': 'application/json; charset=UTF-8',
  'X-Upload-Content-Type': 'application/pdf',
  'X-Upload-Content-Length': bytes.length.toString(),
};
```

La sesión retorna Location. Enviar bloques múltiplos de 256 KiB salvo el último, con Content-Range. Ante interrupción, consultar con un PUT vacío `Content-Range: bytes */TOTAL` y continuar después del último byte confirmado por Range. No loguear Location ni Authorization. Añadir prueba de respuesta 308 y de sesión expirada que crea una nueva sin perder el pendiente local.

- [ ] Implementar Android con google_sign_in 7.2.0 y el web OAuth client ID como serverClientId. Restaurar la cuenta con autenticación ligera y obtener autorización de drive.file a través de authorizationClient. Solo invocar autorización interactiva desde Conectar Drive o Reconectar.

```dart
await GoogleSignIn.instance.initialize(serverClientId: webClientId);
final account = await GoogleSignIn.instance.authenticate();
final authorization = await account.authorizationClient
    .authorizeScopes(['https://www.googleapis.com/auth/drive.file']);
final headers = {'Authorization': 'Bearer ${authorization.accessToken}'};
```

En authorizationHeaders, obtener un token vigente con authorizationForScopes, renovando según el SDK; no reutilizar de forma indefinida el accessToken del ejemplo.

- [ ] Implementar Linux con OAuth Authorization Code + PKCE, navegador del sistema y callback en 127.0.0.1 con puerto efímero. Validar state, limitar callback a esa interfaz, cerrar listener al cancelar o terminar y no copiar códigos a logs. Incluir openid y email para obtener un id de cuenta estable desde userinfo; Drive conserva únicamente drive.file para acceso a archivos.

```dart
final grant = oauth2.AuthorizationCodeGrant(
  desktopClientId,
  Uri.parse('https://accounts.google.com/o/oauth2/v2/auth'),
  Uri.parse('https://oauth2.googleapis.com/token'),
  secret: desktopClientSecret.isEmpty ? null : desktopClientSecret,
  basicAuth: false,
  onCredentialsRefreshed: (credentials) => tokenStore.write(credentials.toJson()),
);
```

Usar state generado con Random.secure y PKCE del paquete; pedir access_type=offline. Recuperar refresh token mediante Credentials.fromJson y mantenerlo en el llavero. Si el llavero no está disponible, no guardar tokens en texto plano: conservar la sesión en memoria y explicar que deberá reconectar al reiniciar.

- [ ] Separar almacenamiento por id de cuenta. Las notas creadas antes de conectar Drive se asocian a la primera cuenta elegida mediante una acción explícita de sincronización. Cerrar sesión conserva los datos de esa cuenta en el dispositivo; otra cuenta abre otra partición. Un cambio de cuenta cancela timers y peticiones del engine anterior antes de construir el nuevo.

- [ ] Documentar configuración real de Google Cloud: habilitar Drive API, pantalla de consentimiento y usuario de prueba, cliente Android con package y SHA del APK, cliente web para serverClientId y cliente Desktop para Linux. Proveer ids mediante dart-define/configuración local ignorada por Git; no inventar credenciales. Escribir los comandos de SHA para debug y release, y verificar configuración antes de habilitar el botón de conexión. Explicar que estas credenciales pertenecen a la app y no se obtienen del conector de esta conversación.

- [ ] Ejecutar `flutter test test/account test/sync`. Después de configurar OAuth, usar dos dispositivos reales con la misma cuenta y un cuaderno de prueba creado para esta app. Confirmar envío en ambas direcciones y desconexión/reconexión sin pérdida. Registrar el resultado real; pruebas con FakeRemoteStore no confirman acceso a Google Drive.

## Task 7: Interfaz coherente, empaquetado y verificación completa

**Files:** Crear `lib/ui/app_theme.dart`, `sync_indicator.dart`, `test/library/library_layout_test.dart`, `test/editor/editor_layout_test.dart` y `docs/verification.md`; modificar biblioteca, editor, README y configuración de builds.

**Interfaces:** Consume todos los contratos anteriores. Los widgets muestran SyncStatus y DocumentEntry sin interpretar respuestas HTTP u OAuth. Bootstrap elige implementaciones reales; las pruebas inyectan repositorio, assets y auth temporales.

- [ ] Definir una apariencia consistente: fondo cálido claro, papel blanco, tinta grafito y un único acento verde oscuro. Usar tipografía y espaciado de un mismo tema. Biblioteca con materias en panel lateral y editor con barra compacta y páginas plegables. Controles táctiles de al menos 48 dp, etiquetas accesibles, estados de foco y mensajes en español. El papel mantiene contraste legible aunque la interfaz esté en modo oscuro.

```dart
final scheme = ColorScheme.fromSeed(
  seedColor: const Color(0xff24584b),
  brightness: Brightness.light,
);
final theme = ThemeData(
  colorScheme: scheme,
  scaffoldBackgroundColor: const Color(0xfff5f3ed),
  useMaterial3: true,
);
```

Aplicar los tokens desde app_theme, evitando colores arbitrarios por widget. Leer la guía frontend-design al comenzar el trabajo visual, después de las aprobaciones de ejecución requeridas.

- [ ] Escribir pruebas de layout en 1200×800, 800×1200 y 1440×900: barra sin overflow, herramienta activa visible, botón de páginas alcanzable y biblioteca vacía utilizable. Añadir caso de título largo y texto con escala 1.5. No usar pruebas que solo repliquen las constantes de colores.

```dart
await tester.binding.setSurfaceSize(const Size(800, 1200));
await tester.pumpWidget(testApp);
expect(tester.takeException(), isNull);
expect(find.byTooltip('Lápiz'), findsOneWidget);
await tester.binding.setSurfaceSize(null);
```

- [ ] Ejecutar análisis, tests y builds:

```bash
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter build linux --release
flutter build apk --debug
```

El APK debug sirve para la primera prueba física con su SHA registrado. Una entrega release requiere su keystore y un cliente OAuth Android con el SHA correspondiente. No sustituir el release por una clave desconocida ni afirmar que una conexión validada en debug funciona en release sin probarla.

- [ ] En Linux, ejecutar el flujo completo de crear, escribir, cambiar patrón, cerrar y recuperar, importar PDF, insertar hoja, exportar y reconectar Drive. En la tablet repetir con S Pen y orientación vertical y horizontal. Tomar capturas de biblioteca, hoja y PDF anotado para revisar el conjunto visual; registrar limitaciones observadas, no supuestas.

- [ ] Verificar los seis criterios de entrega del spec en `docs/verification.md`, con comando/dispositivo, resultado y fecha. Si falta la tablet o la configuración OAuth, registrar explícitamente ese punto como pendiente de comprobación externa, preservar el resto de la entrega y proporcionar el APK y las instrucciones para probarlo.

- [ ] Realizar la revisión final según el método de ejecución elegido. Resolver defectos que puedan causar pérdida de datos, tinta desplazada o subida a una cuenta incorrecta, repetir solamente los checks afectados y entregar enlaces al código, build de Linux y APK que realmente existan.

## Revisión del plan

Cobertura del spec: biblioteca y materias (2,7); editor y herramientas (1,3,7); hojas y páginas mixtas (1,3,4); PDFs y exportación (4); guardado y recuperación (2); Drive, conflictos y errores (5,6); adaptación a plataformas (3,6,7); validación real (3,6,7).

La decisión adicional que debe quedar visible al revisar el plan es la exportación PDF: la primera entrega comparte una copia visual con el fondo rasterizado a 200 dpi y tinta vectorial. Mantener texto seleccionable del fondo exportado sería una ampliación del exportador; el original permanece completo en el documento de la app.

Ejecución recomendada: **Native**, implementando las tareas en esta sesión, porque el lienzo, el guardado y la sincronización dependen de los mismos contratos y conviene ajustar el comportamiento del S Pen con una primera entrega integrada. La alternativa **Subagent-driven** separa implementación y revisión por tarea, con mayor coste de coordinación y revisiones intermedias.

## Referencias para el ejecutor

- [Flutter y plataformas](https://docs.flutter.dev/reference/supported-platforms).
- [SDK estable y archivo de versiones](https://docs.flutter.dev/install/archive).
- [Preparar Linux](https://docs.flutter.dev/platform-integration/linux/setup).
- [pdfrx](https://pub.dev/packages/pdfrx) y [PdfPage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html).
- [pdf](https://pub.dev/packages/pdf).
- [sqlite3](https://pub.dev/packages/sqlite3).
- [google_sign_in](https://pub.dev/packages/google_sign_in) y [configuración Android](https://pub.dev/packages/google_sign_in_android).
- [OAuth PKCE](https://pub.dev/documentation/oauth2/latest/oauth2/AuthorizationCodeGrant/AuthorizationCodeGrant.html).
- [Almacenamiento seguro](https://pub.dev/packages/flutter_secure_storage).
- [Selector nativo de archivos](https://pub.dev/packages/file_selector).
- [Drive: alcances](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [subidas](https://developers.google.com/workspace/drive/api/guides/manage-uploads) y [OAuth Desktop](https://developers.google.com/identity/protocols/oauth2/native-app).
