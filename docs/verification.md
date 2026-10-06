# Nala 0.1.0 — versión de prueba, 2026-10-06

Se generaron y comprobaron estos archivos en la PC de Felipe:

- `dist/Nala.apk`: compilación Android debug, nombre Nala, mínimo Android 7 (API 24), target API 36 y firma APK v2 válida. El archivo entregado conserva el SHA-256 de la salida de Flutter. Felipe confirmó posteriormente que esta versión funciona bien en la Samsung Tab S10.
- `dist/Nala-Linux/`: compilación Linux x64 release completa, con sus bibliotecas y recursos.
- `dist/Abrir-Nala.sh`: abre la versión de escritorio. Entrada **Nala** instalada en el menú de aplicaciones y validada con `desktop-file-validate`.

Pasaron las 28 pruebas unitarias y la prueba de integración en Linux que crea un cuaderno, cierra el repositorio y vuelve a abrirlo conservando su título. La versión release se abrió en una ventana de 1280 × 720 y abrió su base SQLite real; el proceso seguía activo al terminar la verificación.

Las compilaciones y pruebas se ejecutaron de a una en servicios de systemd con un límite total de 2300 MiB de RAM, 256 MiB de swap y dos CPU. Android terminó en unos 39 segundos, con un pico registrado de 1.7 GiB y sin usar swap. Linux release terminó en unos 38 segundos. No se registraron nuevos eventos de falta de memoria en el kernel durante estas comprobaciones. `tool/flutter-safe` conserva estos límites para las siguientes tareas e impide dos ejecuciones simultáneas del mismo proyecto.

Esta entrega permite probar cuadernos con guardado local y el editor. Importar/exportar PDF, sincronizar con Drive y validar el lápiz físico en la tablet siguen pendientes. No representa la finalización del plan de implementación completo.

## Publicación en GitHub y checkpoint de PDF

El repositorio público `felipendelicia/nala` conserva el historial de código. La versión de prueba [v0.1.0](https://github.com/felipendelicia/nala/releases/tag/v0.1.0) distribuye el APK y el paquete Linux del commit `c440928527417d2fbad1a8b6d4ff4e4d58c6313d`; se verificó que los archivos entregados coinciden con las salidas de esa compilación. Estos binarios todavía no incluyen PDF.

El código de PDF se publica como trabajo en curso junto con sus fixtures y pruebas. La suite de 36 pruebas unitarias pasó en Linux. El análisis estático no encontró problemas. El test nativo `integration_test/pdf_round_trip_test.dart` todavía no completó la verificación: la ejecución más reciente terminó con código 79, los casos fueron reportados como “did not complete” y Flutter mostró un `PathNotFoundException` durante la finalización del listener temporal. La causa está pendiente de investigación; no se afirma que el flujo completo de PDF esté validado. El selector Android de guardado también queda pendiente de una prueba física.

Los hashes de los binarios publicados son:

```text
c9c6c1e0baccda067c9e85feff9d752c8417daeb4a5d33ad79ea2ce0608fba8d  Nala.apk
65ddaaaccf74ed1bb1f8a76793c8c237236efcd1434b24d4bbc8c1422fa97d10  Nala-Linux-x64.tar.gz
```


## Verificación de editor 0.2.0

Las etapas de tinta, lectura/zoom, jerarquías y comentarios pasaron 49 pruebas antes de las nuevas comprobaciones de PDF/layout. El recorrido nativo de organización crea carpetas, guarda un comentario con SQLite, vuelve a abrir el apunte y lo consulta en modo lectura. El recorrido nativo de PDF importa dos páginas, dibuja, intercala una hoja, exporta mientras se navega, abre la salida de tres páginas, cancela una segunda exportación y comprueba el guardado.

Se reprodujo el cierre del PDF después de exportar (código 79); el error de listener de Flutter era posterior al cierre del proceso. La exportación inicial abría otra instancia PDFium desde compute. Se corrigió compartiendo el worker nativo existente; compresión JPEG y armado del PDF siguen en isolates de cálculo. El recorrido que fallaba terminó ahora exitosamente. La [documentación del motor](https://github.com/espresso3389/pdfrx/blob/master/doc/Low-Level-PDFium-Bindings-Access.md) explica la serialización de PDFium y su ciclo de vida compartido. Los tests de exportación verifican desbloqueo del recurso correcto, reintento de la misma instantánea y cancelación.

Se inspeccionaron las tres páginas de salida con Poppler: tamaños/orientación, marcas de color, resaltado, tinta y cuadrícula correctos. También se inspeccionaron capturas del editor nativo durante anotación y navegación, biblioteca con ruta Universidad/Álgebra y comentarios en lectura. Seis pruebas de layout pasaron en 1200×800, 800×1200 y 1440×900, incluyendo paneles de páginas/comentarios, título largo y texto ampliado a 1.5.

Dos intentos de APK release alcanzaron MemoryMax del servicio y fueron aislados. La configuración final usa heap Gradle de 768 MiB, metaspace de 384 MiB, code cache de 64 MiB, SerialGC y dos procesadores activos. El límite global de 2300 MiB se mantiene. Flutter debe regenerar registros de plugins release (no usar --no-pub en la compilación después de integration_test). Un intento intermedio encontró metaspace insuficiente al usar 256 MiB; se ajustó a 384 MiB. Las métricas finales impresas por systemd-run no se usan como medida precisa del pico de memoria.

La suite local completa terminó con 56/56 pruebas y analyze no encontró problemas. El APK release 0.2.0+2 de esta etapa se generó correctamente (29.7 MB), package com.felipe.apuntes, min API24 y target36; firma v2 válida y certificado idéntico al APK anterior, de modo que conserva la posibilidad de actualización. SHA-256 del checkpoint: 1bd16caaf9f1bb4ee7ad2f4a129c49b19591cd9ce6f5664078cd8cb77ebb7cbd. Se volverá a generar después de cualquier cambio adicional de código.

Las pruebas de audio usan el dispositivo externo simulado y almacenamiento real de archivos/hash; ninguna automatización encendió el micrófono real. La presión, latencia física, captura/reproducción y selector Android quedan pendientes de validación en la Tab S10.

La compilación Linux x64 release de esta etapa terminó correctamente. Los instaladores de checkpoint están en dist/editor-checkpoint; los entregables finales se regenerarán después de Drive/revisión. El editor nuevo conserva la base y recursos de las versiones previas.
