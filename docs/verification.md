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


## Drive y cuentas

Se implementó un motor con dos repositorios SQLite reales y recursos PDF/audio por hash. Los tests de red simulada cubren ediciones concurrentes, reintento de confirmación perdida, descarga dañada, hijo recibido antes del padre, carpetas borradas y movimientos cruzados. El planificador agrupa guardados, suspende sondeos al pasar la app al fondo y respeta el backoff del servidor.

El adaptador HTTP cubre paginación, multipart idempotente, 401/revocación, Retry-After, subidas de recursos en bloques reanudables, consulta de rango 308 y sesiones expiradas. OAuth Linux se prueba con un callback HTTP real en loopback, PKCE, state incorrecto, cancelación y almacenamiento de credenciales simulado. Se reprodujo una renovación tardía que devolvía el token de otra sesión; ahora se rechaza. También se reprodujo una superposición de desconexión y nueva conexión; ambas operaciones quedaron serializadas.

Las pruebas de cuenta usan particiones SQLite y directorios reales: primera adopción, copia de recursos y carpetas, datos offline después de salir, cambio A/B, reinicio y cancelación de peticiones antiguas. El editor aplica sólo un avance remoto descendiente de su versión guardada, después de soltar el lápiz; conserva la edición actual cuando existen dos ramas. El panel no muestra una conexión ficticia si faltan clientes OAuth.

No se conectó una cuenta Google real. La compilación pública no contiene clientes OAuth; requiere los pasos de docs/drive-setup.md para habilitar Drive. Los tests del SDK Android, los permisos de micrófono y el S Pen necesitan comprobación física.


## Revisión final y correcciones

Una revisión independiente de los seis commits detectó seis problemas importantes y ninguno crítico. Se reprodujeron todos antes de corregirlos: audio que seguía en hidden/inactive de Linux, copia local cancelada que ignoraba notas posteriores, restauración tras desconexión si fallaba el borrado del llavero, codec completo ejecutándose en el hilo de escritura, comentarios omitidos del PDF y salto de coordenadas al abrir paneles durante un trazo. Las pruebas específicas pasaron 27/27 después de los cambios.

El trabajo real del codec y la composición se instrumentan mediante un puerto de diagnóstico que identifica el isolate; los tests comprueban que confirmación perdida, duplicados y exportación ocurren fuera del hilo principal, sin umbrales dependientes de la PC. Se conserva la prueba de repintado sin reconstrucción por muestra. Los avisos de exportación/error se muestran sobre el área de trabajo y no cambian su origen; cambiar paneles cancela un gesto incompleto.

El PDF incluye marcas numeradas y un anexo con texto Unicode usando DejaVu Sans, distribuida con su licencia. El anexo identifica las notas de voz y su duración; el audio se escucha en Nala. Los originales PDF permanecen preservados y el fondo exportado es una imagen a 200 dpi.

Linux detiene captura y reproducción al ocultarse o perder foco, y cancela un inicio pendiente. El proceso nativo de audio recibe SIGINT del kernel si termina Nala; la prueba usa un grabador sintético y nunca abre un micrófono real. La desconexión se guarda independientemente de la limpieza del llavero y no se restaura automáticamente al reiniciar. Una adopción interrumpida vuelve a copiar el último estado local antes de seleccionar una cuenta.

Suite final: 88/88 unitarias/widget; análisis estático sin problemas. La prueba nativa de organización/comentarios pasó otra vez después de las correcciones. El control de proceso de audio pasó con el binario Linux real y un grabador sintético. Se renderizaron e inspeccionaron ambas páginas del PDF con comentarios: marcadores 1/2, anexo, acento, λ y duración 0:03 correctos. La prueba nativa PDF también incorpora escritura durante la exportación y comprueba que su aviso no cambia el origen de la hoja.

La prueba nativa PDF final pasó 1/1 con el origen de la hoja estable durante el inicio y fin de exportación y con un segundo trazo guardado mientras se preparaba la salida. La simulación inicial reutilizaba un identificador entre lápiz y dedo; se corrigió el test antes de repetir exitosamente.

## Entregables finales 0.2.0

Ambas compilaciones finales corresponden al código `a9c5cc7d13487843c8205058a8b04aa5e0ccfba3`, después de corregir la revisión. Los commits posteriores sólo documentan la entrega. Se ejecutaron consecutivamente mediante `tool/flutter-safe`, con los límites de recursos descritos arriba: Android release ARM64 terminó en 63 segundos y Linux x64 release en 45 segundos. Los datos OAuth no están configurados en estos binarios.

- APK: 31 164 727 bytes, versión 0.2.0+2, package `com.felipe.apuntes`, API mínima 24 y target 36. `apksigner verify` confirmó firma v2 válida; conserva el certificado de la primera versión y puede actualizarla. Es una firma de desarrollo para pruebas.
- Linux: archivo completo de 18 021 201 bytes con bibliotecas, recursos, icono, fuente/licencia y lanzador ejecutable. Se verificaron 35 entradas del paquete, resolución de todas las bibliotecas, sintaxis del lanzador y acceso del menú. La versión anterior se conserva como respaldo local.
- La versión Linux final abrió en una ventana real, creó su SQLite en un directorio temporal aislado y permaneció activa. `PRAGMA quick_check` devolvió `ok`. La prueba inicial omitió el directorio de trabajo del servicio de verificación; se corrigió ese comando y la apertura pasó. No se tocaron apuntes personales.
- El control de cierre del proceso de audio volvió a pasar con el binario Linux release y un grabador sintético, sin abrir el micrófono.

Se publicó la [prerelease v0.2.0](https://github.com/felipendelicia/nala/releases/tag/v0.2.0), con el tag en `e89c7122fa873a251a1a51646f1cc353e0e01e28` (código y documentación de entrega). La API de GitHub confirmó los tamaños y digests SHA-256 de los tres archivos: APK, paquete Linux y SHA256SUMS. Coinciden con los archivos locales; el APK también coincide exactamente con la salida de Flutter:

```text
ab221f87861c09f055a9bae2cfdc38279593d238b32f086f118bb974f0747161  Nala.apk
0f862e927450015f3bac7bf47fcd69f2737df3cbdb9fd813425f88e01edfadc6  Nala-Linux-x64.tar.gz
```

Antes de publicar se revisaron 149 archivos y 264 blobs históricos: ninguna ruta privada prohibida ni patrón conocido de credenciales. El repositorio sigue público y main recibió los commits sin sobrescribir cambios remotos.

La prueba física con S Pen, audio y selector Android, y una conexión Google real entre dos dispositivos, siguen pendientes. Las decisiones de alcance y sus costes están en [decisiones](decisions.md).

## Editor continuo y apariencia 0.3.0

La suite inicial de esta etapa pasó 101/101 pruebas unitarias/widget y analyze no encontró problemas. Incluye scroll a la segunda hoja, tinta en sus coordenadas, bloqueos X/zoom combinados, parámetros independientes del resaltador/lápiz, mil hojas con menos de cinco lienzos montados, reutilización de la geometría de un trazo de 5000 muestras y ausencia de reconstrucción de barra/hoja por muestra.

Compartir se comprueba abriendo el PDF real entregado por el botón, sin invocar savePdf, doble toque y error recuperable. Los archivos temporales se sanean, tienen sesión única, permanecen disponibles para receptores y sólo se limpian sesiones anteriores a 24 horas. Mover se verifica desde el menú con SQLite y reapertura. El tema se cambia desde Apariencia y se recupera al reiniciar; archivos de preferencias incompletos o inválidos vuelven a Seguir sistema sin tocar los apuntes.

Se comprobaron seis layouts de editor con texto a 1.5 en tamaños 1200×800, 800×1200 y 1440×900, para claro y oscuro, incluyendo paneles y acciones de compartir/exportar. La biblioteca también se prueba con texto ampliado.

Pasaron los recorridos nativos Linux de cuadernos locales, PDF con escritura durante exportación y organización/comentarios. El recorrido nuevo de apariencia/compartir/movimiento pasó con PDFium y SQLite reales: tres hojas compartidas, trazo en la segunda, carpeta y tema persistidos. La frontera GTK respondió al archivo ausente sin modificar el portapapeles del usuario. El selector Android y pegar el archivo en aplicaciones reales todavía requieren comprobación física.

Al ejecutar todos los archivos nativos en un mismo proceso Flutter, el primer caso pasó y los siguientes no llegaron a arrancar: el DesktopLogReader del SDK conserva un stream que se cierra al terminar el primer proceso. Ejecutar cada archivo en un proceso nuevo resolvió el problema, sin modificar la app ni el SDK.

Capturas nativas en .dart_tool/ui-qa: biblioteca clara/oscura, editor oscuro, navegación continua y lectura; la captura clara selecciona Claro explícitamente porque el sistema de la PC está en modo oscuro. Se inspeccionaron ambas bibliotecas, el editor continuo y lectura; controles legibles y papel conservado. No se interpreta el MemoryPeak impreso por systemd-run como una medida real de consumo; cada compilación mantiene límite de memoria y CPU.

La suite completa de cierre pasó 102/102 después de añadir orientaciones mixtas, separación sin tinta y origen estable al cruzarla. Se reprodujo un overflow del estado local de biblioteca con texto a 1.5 en 800×1200; ahora ese estado tiene ancho limitado o icono con descripción, como los controles de Drive. La suite posterior pasó y analyze siguió sin problemas.

También se reprodujo que los permisos por defecto de un PDF temporal Linux permitían lectura a grupo/otros. Compartir ahora usa carpetas 0700, archivos 0600 y rechaza una raíz temporal que sea enlace. La prueba examina los permisos reales antes del canal de entrega y pasó junto con compartir desde el editor (2/2). Android usa su caché privada y FileProvider limitado a nala-share/. No se abrió ningún cliente de correo ni se cambió el portapapeles real durante la automatización.
