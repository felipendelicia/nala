# Editor continuo y visual de Nala: plan de implementación

> **For agentic workers:** Use superpowers:executing-plans inline; one fresh final reviewer. Steps use checkboxes.

**Goal:** Entregar navegación continua, bloqueo horizontal, herramientas independientes, compartir directo, movimiento de apuntes y un rediseño sustancial preservando la baja latencia.
**Architecture:** PageLayout calcula geometría y visibilidad; Viewport conserva cámara y bloqueos; EditorScreen traduce entrada a coordenadas locales y monta sólo páginas visibles. PdfShare conserva snapshots y ofrece adaptadores nativos; tema y componentes de biblioteca/editor comparten tokens.
**Tech Stack:** Flutter 3.47.6, Dart 3.13.5, SQLite/PDFium existente, Android FileProvider, GTK clipboard, xdg-email.
**Spec:** ../specs/2026-10-06-continuous-editor-design.md

## Global Constraints

- Separación entre páginas: 32 puntos; dimensiones originales y trazos locales preservados.
- Rueda desplaza; Ctrl+rueda hace zoom; bloqueos X/escala independientes.
- Muestras de lápiz no reconstruyen interfaz ni hojas; no temporizadores de tinta.
- Lápiz 2.5 pt grafito y resaltador 14 pt amarillo, ajustes independientes.
- Compartir requiere acción explícita; no envío automático; temporales únicos privados y saneados.
- Todas las tareas Flutter secuenciales mediante tool/flutter-safe.
- Interfaz blanco/negro/grises neutros solicitada por Felipe; tema claro/oscuro/sistema persistido; el papel/PDF conserva sus colores. Usar exactamente el segundo logo elegido por el usuario.

## Review Focus

1. Dibujo en la segunda página/separación y mezcla apaisada/vertical: guardar sólo en la página de origen.
2. Documento muy largo: widgets/PDF sólo visibles, sin reconstrucción por muestra.
3. Zoom bloqueado junto a X bloqueado: bajar/saltar de página sigue funcionando.
4. Compartir mientras se escribe o se cancela: snapshot correcto, UI utilizable y recursos intactos.
5. Opciones con títulos largos/texto grande: compartir/mover accesibles y sin overflow.

### Task 1: Cámara, tira continua y herramientas

**Files:** lib/editor/page_layout.dart (nuevo), viewport.dart, editor_screen.dart, zoom_controls.dart; test/editor/continuous_editor_test.dart y viewport_test.dart.
**Interfaces:** PageLayout(List<NotebookPage>), width/height, rect(int), visible(Rect), hit(Offset), nearest(double); Viewport.horizontalLocked bool. Editor traduce documentPoint - rect.topLeft y mantiene pageIndex estable durante un trazo.

- [x] RED: probar scroll rueda hasta segunda hoja y escribir allí; combinar bloqueos y gesto diagonal; documento 1000 páginas monta <5 PaperCanvas; cambiar resaltador/lápiz conserva ancho/color. Run tool/flutter-safe test --no-pub --concurrency=1 test/editor/continuous_editor_test.dart. Expected: scroll hace zoom, bloqueo ausente, ancho compartido.
```dart
expect(controller.notebook.pages[0].strokes.length, 1);
expect(controller.notebook.pages[1].strokes.single.tool, InkTool.highlighter);
expect(tester.widgetList<PaperCanvas>(find.byType(PaperCanvas)).length, lessThan(5));
```
- [x] GREEN: layout con búsqueda binaria; render sólo visible; cámara global con bloqueos; cada inicio selecciona hit válido y se conserva origen; rueda pan, Ctrl rueda zoom, trackpad pan/zoom; saltos explícitos; parámetros por herramienta.
```dart
final local = view.pagePoint(sample.position) - pageRect.topLeft;
view.pan(-event.scrollDelta.dx, -event.scrollDelta.dy);
```
- [x] Verificar tests nuevos y regresiones de fluidez/selección/lectura. Actualizar expectativas de rueda a desplazamiento y usar canvas de página explícita en documentos multipágina. Commit.

### Task 2: Compartir y mover

**Files:** lib/pdf/pdf_share.dart (nuevo), lib/bootstrap.dart/library/library_screen.dart/editor/editor_screen.dart; MainActivity.kt, manifest, res/xml/nala_share_paths.xml; linux/runner/my_application.cc; test/pdf/share_test.dart, test/library/folders_test.dart, integración.
**Interfaces:** PdfShare.share(bytes,name,target), ShareTarget {system,copyFile,email}; NativePdfShare usa tempDir/methodchannel nativos. EditorScreen optional share y AppServices share, sin cambiar DocumentFiles.

- [x] RED: PDF real enviado desde botón sin savePdf, snapshot sin duplicar ante dos toques; error muestra recuperación; archivo temporal saneado y único conservado; mover desde opciones persiste tras reabrir SQLite.
```dart
expect(files.saved, isNull);
expect((await PdfDocument.openData(sharedBytes)).pages.length, 2);
expect(reopened.notebook.folderId, target.id);
```
- [x] GREEN: Android FileProvider cache/nala-share limitado, ClipData/read permission, escritura fuera de main; Linux clipboard URI/gnome copied files y xdg-email adjunto; limpiar sólo temporales de más de 24 horas; crear instantánea/export en worker existente; opciones visibles para mover.
- [x] Verificar fronteras nativas con archivos reales/canales simulados y recorrido PDF/movimiento. Commit.

### Task 3: Diseño visual

**Files:** lib/ui/app_theme.dart, assets/fonts/Manrope.ttf/licencia, pubspec.yaml, lib/editor/editor_toolbar.dart/page_panel.dart/editor_screen.dart, lib/library/library_screen.dart; pruebas de layout y capturas.

- [x] Incorporar Manrope oficial y licencia; aplicar tokens, cabecera/estuche de herramientas/pie, papel con sombra discreta, biblioteca lateral y previews. No añadir listeners al trazo ni animaciones al canvas.
- [x] Comprobar overflow en 800x1200/1200x800 y 1.5 texto, capturar y revisar biblioteca/editor continuo/lectura. Repetir prueba de widgets estables por muestras y observar capa activa inmediatamente.
- [x] Suite completa, analyze y recorridos nativos PDF/organización. Commit.

### Final

- [x] Una revisión fresca. Corregir Important/Critical en una pasada con RED→GREEN; documentar decisiones/límites.
- [ ] Generar APK/Linux seguros versión 0.3.0+3, instalar acceso PC, publicar fuente y prerelease autorizadas, comprobar digests remotos.
- [ ] Documentar pruebas, latencia física pendiente y entrega con enlaces; limpiar sólo workspace temporal de este plan.
