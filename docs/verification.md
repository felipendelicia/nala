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

### Correcciones finales 0.3.0

Una revisión independiente nueva encontró dos problemas importantes, ninguno crítico y ninguna observación menor. Se reprodujeron antes de corregirlos:

- Agregar varias hojas y deshacerlas dejaba un índice fuera de rango y podía romper Ajustar hoja/ancho. Se conserva la página por identificador, se elige una vecina válida si desaparece y se restablece una vista utilizable. Deshacer tinta mantiene la cámara; insertar una hoja antes de la actual conserva su origen.
- Compartir durante un guardado podía tomar un trazo posterior todavía pendiente. Una prueba con dos guardados diferidos y fallo del segundo reabre/renderiza el PDF real: el píxel de ese trazo pasó de negro a blanco después de tomar la instantánea antes de esperar el guardado correspondiente. La revisión persistida contiene sólo el primer estado; el trazo fallido sigue en memoria para reintentar.

Se amplió la comprobación de accesibilidad con nombres largos de carpetas, materias y apuntes a 1.5 de texto en 800×1200. Reprodujo dos desbordes; anchos limitados y descripciones del nombre completo los corrigen y dejan accesible Mover a…/Cancelar. Una prueba adicional cancela el destino de compartir y sigue escribiendo sin exportar ni guardar otra copia.

Las pruebas enfocadas pasaron 11/11 y la suite completa posterior pasó 106/106; analyze no encontró problemas. No se solicitó una segunda revisión: las reproducciones y la suite verifican esta pasada de correcciones. La prueba física y las aplicaciones externas pendientes se conservan explícitas en decisiones.

La revisión de capturas detectó que limitar el filtro de materia a 260 px agregaba una fila y cortaba inicialmente los metadatos de las tarjetas a 1280×720. Una reproducción con la fuente Manrope real observó un título debajo del área visible (707 frente a 692 px). El filtro compacto mantiene los nombres completos en su descripción; la prueba de títulos/materias visibles y las de texto ampliado pasaron 5/5. La suite final pasó 107/107. El recorrido nativo PDF y el de apariencia/compartir/mover volvieron a pasar después de corregir la cámara y la instantánea.

El primer intento Android de esta etapa fue detenido por systemd-oomd al alcanzar presión de memoria en su servicio aislado; se detuvieron sólo sus procesos. Se redujo el heap Gradle de 768 a 512 MiB conservando metaspace 384 MiB, los workers secuenciales y el límite global de 2300 MiB. Los binarios sólo se entregan después de una compilación exitosa.

### Paleta blanco/negro solicitada por Felipe

La indicación posterior reemplaza la paleta verde de la interfaz por blanco, negro y grises. El tema oscuro tiene fondo negro real; claro usa blanco, con controles de contraste alto, paneles y avisos neutros. Las muestras de tinta mantienen sus colores seleccionables y el tema no recolorea los apuntes ni sus PDF. La prueba de colores reprodujo el tinte anterior y después pasó comprobando roles neutros y contraste de controles de al menos 7:1; las pruebas enfocadas de apariencia y layouts pasaron 14/14. La entrega se vuelve a compilar con esta paleta final.

La suite completa de la paleta final pasó 108/108. Se mantuvieron todas las comprobaciones de trazo, presión, geometría reutilizada, guardado, compartir, carpetas y cuentas.

El perfil de heap de 512 MiB mantuvo la protección, pero R8 ocupó todo el heap y dedicó 97 segundos a 159 recolecciones completas de memoria. La compilación terminó exitosamente antes de la orden de detención, que no afectó ningún proceso porque el servicio ya había finalizado. Se eligió un valor intermedio de 640 MiB, manteniendo metaspace 384 MiB y los límites globales anteriores; la compilación incremental posterior también terminó correctamente.

## Entregables finales 0.3.0

El código de ambas compilaciones es `aaac87201bc578e5354b70b2dd46620c0b63f127`, con el tema blanco/negro final solicitado por Felipe. Los cambios posteriores son documentación de entrega. La suite de 108/108 y analyze sin problemas cubren ese código de aplicación; el último recorrido nativo de apariencia/compartir/mover pasó 1/1 y regeneró cinco capturas, inspeccionadas en claro/oscuro, editor continuo y lectura. El recorrido PDF también pasó después de las correcciones de instantánea/cámara.

El APK final 0.3.0+3 ocupa 31 063 142 bytes; package com.felipe.apuntes, mínimo API24, target36 y bibliotecas Flutter ARM64. Firma APK v2 válida, certificado SHA-256 e92cb0c4bf598fbf0347d135efb275bfb381761f156c2984e2c796b63ff09887, idéntico al anterior. Permite actualizar sin desinstalar. El perfil512 completó en254.8s; el perfil final640 completó una compilación incremental en19.9s. Linux release terminó en54.3s. Todos mediante el wrapper secuencial, sin modificar el límite global.

El paquete Linux ocupa 17 549 754 bytes. Se comprobaron bibliotecas, rutas portables y permisos ejecutables, fuentes/licencias y el logo exacto en ambos binarios. El acceso del menú Nala y el lanzador son válidos; la versión0.2 permanece como respaldo local. La versión release abrió en una ventana real y siguió activa, con un SQLite aislado de los apuntes personales; PRAGMA quick_check devolvió ok. Se detuvo sólo el servicio propio de esa comprobación.

Sumas de los archivos finales:

```text
aff77e4086b58dffd5c6fcb683118f2ab58cd51cab675833c86ea45011fd2a8c  Nala.apk
e156a83331c1bc973640dcb66696b514895c3c504736082a94c65892300f41a2  Nala-Linux-x64.tar.gz
```

La comprobación física del S Pen y del selector/permisos Android queda para la tablet; recepción en aplicaciones externas y Drive real siguen con los límites documentados.

Se publicó la [prerelease v0.3.0](https://github.com/felipendelicia/nala/releases/tag/v0.3.0), con tag en `5b973184923d7b1aa82724c391b75b06aade92e9` (el código compilado y documentación de entrega). La API de GitHub confirmó que el repositorio continúa público, los tres archivos están subidos y sus tamaños/digests SHA-256 coinciden exactamente con los locales: APK, paquete Linux y SHA256SUMS. Main recibió el historial por avance directo.

La auditoría de los 164 archivos de código y los blobs históricos no encontró rutas privadas prohibidas ni patrones conocidos de credenciales. Las decisiones de este plan y sus costes están preservados en [decisiones](decisions.md); no quedaron observaciones menores diferidas. La última modificación sólo cierra documentación y el plan; no cambia los binarios verificados.


## S Pen y botón 0.4.0

Código de aplicación compilado: `30bc0d124a78d25bc2bae5210425f6ffd179f406`. Los commits posteriores sólo documentan la entrega. La suite completa pasó **130/130** unitarias/widget; análisis sin problemas. Incluye presión inmediata y sin estabilización inicial, tinta corta/directa y mosaicos a resolución de pantalla, transparencia del resaltador, antialias consistente al confirmar, límites de memoria y disposición de imágenes, botón nativo/Flutter, selección conservada, lectura/foco y preferencias guardadas.

Una revisión independiente encontró dos problemas importantes y ninguno crítico o menor: borrado del segmento anterior en el inicio sintético de la goma, y herramienta temporal activa tras cerrar menús. Ambos se reprodujeron antes de corregir. También se reprodujo una pulsación sostenida contada dos veces en modo alternar después de un modal. Las pruebas comprueban los trazos después de terminar la goma y que un contacto físico nuevo sí borra; seis menús reales (grosor, cuaderno, hoja, zoom, color y apariencia), mantener/alternar y liberación durante el modal. El grupo de botón/preferencias pasó 17/17, y la suite final 130/130 después de la única pasada de correcciones. No quedaron menores diferidos.

Los recorridos Linux nativos de presión/ajustes y PDF pasaron. El primero guardó más de 360 muestras variables y reabrió nota/preferencias; se inspeccionaron las capturas de ajustes y tinta. Se corrigió la entrada sintética para incluir pressureMin=0/pressureMax=1, como Android; no se cambió la normalización de producción para compensar una simulación incorrecta. La medición nativa usa 8000 muestras iniciales y 48 cuadros con ocho muestras nuevas por cuadro, orden alternado, salida 600×600 y lectura de píxeles: mediana 6846 frente a 10373 microsegundos; p95 14455 frente a 19555. Es trabajo de rasterizado/lectura en esta PC, **no latencia física del S Pen ni equivalencia con Notewise**. [Detalle reproducible](spen.md).

Los bordes iniciales de las máscaras acumulaban cobertura antialias al componer imágenes anteriores; se reprodujo y corrigió con un contorno vectorial local completo por mosaico. Se conserva el dibujo directo durante las primeras 96 muestras. La goma rechaza candidatos mediante límites geométricos en caché; tinta y exportación conservan los puntos originales.

Compilaciones finales consecutivas y limitadas: Android release ARM64 terminó en 59.7 segundos; Linux x64 release en 38.2 segundos. Antes, una compilación fría con heap640 fue detenida por systemd-oomd sólo dentro de su servicio propio. Se bajó el heap a512; al medir presión por el límite suave1800 se elevó a2200, dentro del techo total2300 MiB y swap256 MiB, con un worker y dos CPU. El primer build512 completo terminó en253.5 segundos. No se detuvieron procesos del usuario. El límite no garantiza un tiempo fijo de compilación.

APK final: **31 063 142 bytes**, versión0.4.0+4, package com.felipe.apuntes, API mínima24, target36. Firma válida con certificado SHA-256 e92cb0c4bf598fbf0347d135efb275bfb381761f156c2984e2c796b63ff09887, idéntico a0.3.0; actualización sin desinstalar. Firma de desarrollo para pruebas. Se verificaron biblioteca ARM64 y logo exacto dentro del APK, y que el código nativo de la app difiere del anterior.

Paquete Linux: **17 565 691 bytes**, 40 entradas, lanzador y binario ejecutables, todas las bibliotecas resueltas y logo exacto. El binario release abrió en una ventana real con datos temporales aislados; SQLite quick_check devolvió ok y el proceso siguió activo. Se detuvo sólo el servicio propio de verificación. El acceso Nala del menú mantiene su ruta y abre0.4; se conserva0.3 como respaldo local. La primera comprobación de sumas se ejecutó desde el directorio equivocado y no encontró los archivos; se repitió desde dist y ambos hashes fueron correctos.

```text
e41578706fb14a5c10f7aaa8b0a0d21efdc28a4264a41d8cb2c2fbf6e73f2339  Nala.apk
cacce35aa2b78659b0ad6a3e76214023e4157f323a44a0078875a4904d66c5d5  Nala-Linux-x64.tar.gz
```

La auditoría revisó archivos actuales e historial: ninguna ruta privada prohibida ni patrón conocido de credenciales. No se publican datos de notas ni claves de firma. Samsung, proximidad/botón y sensación punta-pantalla requieren el nuevo APK en la Tab S10. Sincronización continúa diferida; el binario público funciona localmente. Las decisiones y costes se conservan en [decisiones](decisions.md).

Se publicó la [prerelease v0.4.0](https://github.com/felipendelicia/nala/releases/tag/v0.4.0), con tag en `ae8201e4aac7b0d69f4b3151154478c4bf729d59`. La API de GitHub confirmó los tres archivos subidos y sus tamaños/digests SHA-256 exactos: APK, paquete Linux y SHA256SUMS. Main recibió el historial por avance directo; el repositorio continúa público. Se revisaron 173 archivos y 400 blobs históricos antes de publicar, sin patrones conocidos de credenciales ni rutas privadas prohibidas. El cierre posterior sólo documenta esta verificación y no modifica el producto compilado.


## Herramientas y estudio 0.5.0

Código compilado: `7455da3424e5352f65793dfdc86d799992bd1a2a`. El commit `c39e418` contiene la implementación verificada; los tres siguientes ajustan sólo el empaquetado Android y su documentación. Incorpora las nueve funciones del pedido autónomo: formas/regla, selección completa, texto/imágenes, favoritos, pestañas/vista dividida, plantillas/portadas, búsqueda, audio ligado a tinta y tarjetas con repetición espaciada. La [guía de uso](study-tools.md) describe cada control y los requisitos de reconocimiento/audio.

Verificación final de fuente: **206/206** pruebas unitarias/widget en 1min34,1s; análisis global sin incidencias. Se conservaron las pruebas anteriores de presión/S Pen, PDF, comentarios, organización y Drive simulado. Las nuevas cubren codec y medios, geometría/portapapeles, favoritos, imágenes/fondos, búsqueda PDF real y huellas de reconocimiento, foco y primer gesto entre paneles, plantillas pequeñas, recuperación de audio y programación de tarjetas.

La revisión independiente encontró cuatro defectos iniciales y dos interacciones posteriores, corregidos antes de esta suite: pérdida del WAV al fallar almacenamiento, primer gesto cancelado, teclado dirigido al panel anterior, medidas negativas con una plantilla pequeña, recuperación de audio con varios paneles laterales y borrado normal del audio pendiente que se deshacía al reintentar. Se reprodujeron también la goma temporal conservada al cerrar nuevos menús, el desplazamiento de cámara al entrar en lectura y el reconocimiento por mantener la punta con muestras pequeñas. Una última regresión demuestra que un comentario visible sobre tinta con audio mantiene prioridad al tocarlo. La [revisión](study-tools-review.md) conserva sus hallazgos y la comprobación posterior de código.

Pasaron tres recorridos nativos Linux, cada uno en un proceso Flutter: estudio (40,3s con compilación), PDF (36,6s) y carpetas/comentarios (39,0s). El primero crea texto, duplica/deshace, dibuja una forma, aplica Cornell, busca sin acentos, crea/repasa una tarjeta, agrega una imagen, exporta, divide dos apuntes y vuelve a cargar los datos de SQLite. El segundo importa PDF, intercala una hoja, escribe durante la exportación, abre la salida de tres páginas y cancela otra exportación. El tercero conserva carpetas anidadas y comentarios tras cerrar/reabrir y leer. El test PDF ahora busca su título dentro del editor, porque también aparece en la pestaña.

Se inspeccionaron las capturas de editor, estudio y dos paneles. Poppler confirmó el PDF nuevo de una página A4, con texto Unicode seleccionable, imagen azul, forma vectorial y guías Cornell correctas. Un fallo inicial del build Linux se debía a una caché del SDK con el directorio de cabeceras vacío; regenerar la caché resolvió la compilación sin cambiar CMake.

Las pruebas usan apuntes temporales y audio sintético. No se activó el micrófono real ni se modificó la biblioteca personal. Android reconoce tinta escrita en Nala después de descargar explícitamente el modelo español; su precisión/descarga y el S Pen/micrófono/selector requieren comprobación en la Tab S10. Linux no tiene Tesseract con español en este equipo: informa que el OCR no está disponible y permite ingresar texto manualmente o buscar lo reconocido/guardado en Android. Drive real sigue pendiente de configurar OAuth y probar dos dispositivos.


### Paquetes locales verificados

Las compilaciones finales corresponden a `7455da3424e5352f65793dfdc86d799992bd1a2a`. Android ARM64 release terminó en 19,5 s después de los ajustes de empaquetado; Linux x64 release se regeneró en 2,3 s aprovechando su compilación anterior de 48,5 s. Todas las tareas Flutter fueron secuenciales con el techo de 2300 MiB, swap de 256 MiB, dos CPU y un worker de compilación.

El primer Android frío fue detenido por OOM dentro de su servicio propio. El siguiente completó Dart y ML Kit pero R8 agotó el heap de 512 MiB y repetía GC completo sin liberar espacio; se detuvo sólo ese servicio y se desactivó la minificación/reducción Java. La compilación sin R8 pasó en 2 min 14,1 s. El APK inicial de 57,3 MB anunciaba ARMv7/x86_64 por los JNI transitivos sin motor Flutter para ellos; se agregó el filtro ARM64 y la propiedad que conserva ese filtro frente al valor predeterminado del plugin Flutter 3.47. La entrega final incluye sólo ARM64, Dart AOT e iconos reducidos. [Decisiones y coste](decisions.md).

- APK: **43 867 003 bytes**, versión 0.5.0+5, nombre Nala, package `com.felipe.apuntes`, mínimo API 24 y target 36. Firma v2 válida y certificado SHA-256 `e92cb0c4bf598fbf0347d135efb275bfb381761f156c2984e2c796b63ff09887`, idéntico al anterior: permite actualizar sin desinstalar. Firma de desarrollo para pruebas. aapt y la inspección ZIP confirmaron sólo ARM64, los motores Flutter/PDF/ML Kit y el logo exacto.
- Linux: **17 782 232 bytes**, 41 entradas en el paquete, con binario, bibliotecas, recursos, icono, fuentes/licencias, guía y lanzador ejecutable. Versión0.5.0+5; todas las bibliotecas resueltas, logo idéntico y entrada del menú validada. El APK y el binario entregados coinciden byte por byte con las salidas compiladas.
- La versión Linux final abrió con datos temporales aislados y siguió activa; su SQLite `quick_check` devolvió `ok`. Se detuvo sólo el servicio propio y se borraron sus datos de prueba. La biblioteca personal no se abrió ni modificó.
- Los archivos locales están en `dist/`; el acceso Nala del menú apunta a la versión nueva. Se conserva 0.4 completa en `dist/previous-v0.4.0`. Esta etapa no publicó una release externa ni modificó main.

SHA-256 finales, comprobados desde los archivos entregados:

```text
1b66b2776ed6d689a49ba2298b15de0e2a8306673300d45f5623b1042cb60942  Nala.apk
9d50834771ba38389f6db5ccd31f55311959a77053ac3d27987923c246ab00cd  Nala-Linux-x64.tar.gz
```


## Encabezado compacto 0.5.1

Código compilado: `e2ef49510da57d6e43fa969fa1f4b88c37ffb0e1`. El pedido reduce la parte superior a AppBar de 56 y herramientas principales de 56 píxeles; lectura usa sólo AppBar. Las pestañas añaden 48 únicamente con varios documentos. El panel Más herramientas se superpone sin alterar el rectángulo ni el origen del papel y se cierra antes de ejecutar acciones. Exportar y abrir/dividir están en las opciones del cuaderno; compartir conserva acceso directo desde 600 de ancho.

La prueba inicial reprodujo seis fallas de altura: el editor con texto al 150% comenzaba la hoja en 197 y ahora lo hace en 112; en lectura, en 56. La revisión independiente detectó los menús de grosor/tipo de hoja con área de 37; una prueba reprodujo la falla y ambos recuperaron un mínimo de 48. Sus objetivos táctiles conservan la fila de 56.

Verificación final: **215/215** pruebas unitarias/widget, en 1 min 24 s (servicio 1 min 28,5 s); análisis sin incidencias. Incluye 400×650, 800×1200 y 1200×800 en claro/oscuro con texto al 150%, tamaño de botones con texto normal, estabilidad de papel/viewport al abrir/cerrar el panel y modo lectura. Las pruebas del workspace cubren 1500×1000 y 800×1200, con pestañas condicionales, mismo estado montado, primer trazo al activar el panel y deshacer dirigido al editor activo. Las pruebas de S Pen comprueban también abrir/cancelar Más herramientas y los menús secundarios dentro del modal.

Pasaron los recorridos nativos Linux de estudio (39,3s con compilación) y PDF (36,4s). El primero usa el panel para insertar/duplicar texto, elegir forma, plantillas, búsqueda y tarjetas; abre otro apunte desde las opciones y divide sin perder datos. El segundo exporta desde las opciones, permite tinta posterior mientras prepara el PDF, conserva el origen de la hoja y la salida de tres páginas. Se inspeccionaron las capturas de editor, panel y vista dividida en `.dart_tool/ui-qa/*v051.png`.

Compilaciones release con `tool/flutter-safe`, secuenciales y bajo los límites existentes: Android ARM64 en 70,2 s y Linux en 48,4 s. Paquetes comprobados:

- APK: **43 866 991 bytes**, versión 0.5.1+6, `com.felipe.apuntes`, Nala, API mínima 24 y target 36; seis bibliotecas sólo ARM64. Firma v2 válida con certificado SHA-256 `e92cb0c4bf598fbf0347d135efb275bfb381761f156c2984e2c796b63ff09887`, el mismo que 0.5.0. Logo idéntico al seleccionado.
- Linux: **17 798 280 bytes**, 40 entradas, recursos/manifiesto de bibliotecas, fuentes/licencias, icono, guía y lanzador. APK/binario/libapp/guía coinciden con las salidas y fuentes compiladas, hashes correctos y bibliotecas resueltas. El paquete omite el antiguo `lib/native_assets.json` sobrante; el `NativeAssetsManifest.json` usado en ejecución conserva los nombres portables de PDFium y SQLite presentes en lib/.
- La versión final arrancó con un directorio temporal propio y continuó activa; SQLite `quick_check` devolvió `ok`. El servicio terminó después sin fallo registrado y se borró la base de prueba. El menú y lanzador existentes conservan sus rutas y ahora abren 0.5.1.
- `dist/previous-v0.5.0` conserva la entrega anterior completa y sus hashes. Entrega local, sin publicar una nueva release externa. No se comprobó el S Pen ni el micrófono físicos en la tablet.

SHA-256 de los archivos entregados de **0.5.1**:

```text
228acd0bb0a3b13759ade0400eb6929c2afca6d10753c1680c985b920ad06c33  Nala.apk
83dae03ac9865129274723a4f7f624612c1721bc4329cbcee7dbe8c707d483bb  Nala-Linux-x64.tar.gz
```

## Herramientas para apuntes 0.6.0

Se incorporan elementos reutilizables, enlaces a páginas de otros apuntes, recorte/opacidad/restablecimiento de imágenes, bloqueo de objetos, orden/visibilidad/ubicación de la barra, backups `.nala.zip` y edición de fórmulas LaTeX con render transparente local. Se conserva el encabezado compacto y las pestañas estables. La [guía](notebook-workflow.md) describe los accesos; la [revisión](notebook-workflow-review.md) registra los hallazgos corregidos y sus comprobaciones.

Análisis final sin incidencias (`.dart_tool/workflow-analyze-final.log`). Suite completa: **270/270** pruebas unitarias y widget en 2 min 14 s, servicio de 2 min 18,3 s (`.dart_tool/workflow-suite-final.log`). Incluye decodificación de apuntes anteriores, selecciones obsoletas sobre objetos bloqueados, recorte/restablecimiento de imágenes, captura y edición LaTeX, píxeles/opacidad en PDF, sincronización de originales/enlaces/fórmulas, biblioteca de elementos, navegación de pestañas, gestos de enlaces y barra persistida/reordenada. Se corrigieron dos pruebas previas del botón S Pen para distinguir la barra principal de la barra de controles ocultos dentro del modal; las 22 comprobaciones de enlaces/S Pen pasan (`.dart_tool/workflow-links-spen.log`).

Los casos de backup cubren SQLite, carpetas, versiones concurrentes, revisiones retenidas durante audio, grabaciones descartadas/interrumpidas, recursos originales y fórmulas, registros y preferencias. Se comprueban hashes dañados, rutas duplicadas/no permitidas, ZIP solapado, límites previos a lectura, remapeo de identificadores/enlaces y recuperación sin sobrescribir datos actuales. Si la combinación supera la capacidad de un registro, la recuperación conserva el registro activo y guarda el entrante aparte con un aviso.

Recorrido nativo Linux de las seis funciones: **1/1**, 27 s de interacción y 59,8 s de servicio (`.dart_tool/workflow-native-final.log`). Usa archivos y SQLite temporales, render PNG de fórmulas, PDF exportado y backup guardado/inspeccionado/restaurado por los servicios de producción; reemplaza únicamente el selector del sistema. Comprueba inserciones independientes, edición/crop/reset/bloqueo, navegación hacia una página de un editor ya abierto con tinta conservada, barra lateral reordenada/oculta y reapertura de preferencias. El ZIP contiene exactamente la imagen original y el PNG final compartido por ambas fórmulas y el elemento; sus bytes coinciden con AssetStore. La recuperación agrega dos cuadernos y un elemento, remapea el enlace y mantiene los originales. Las capturas están en `.dart_tool/ui-qa/workflow-*-v060.png`, junto a `workflow-v060.pdf` y `workflow-v060.nala.zip`.

Regresiones nativas: herramientas de estudio **1/1** (12 s; servicio 46,4 s, `.dart_tool/workflow-study-native.log`) y recorrido de importación/anotación/hoja intercalada/exportación PDF **1/1** (6 s; servicio 37,1 s, `.dart_tool/workflow-pdf-native.log`). Ambos usan bibliotecas temporales y motores nativos. Las ejecuciones fueron seriales y no usaron apuntes personales, cuentas ni micrófono real.

Entrega local compilada del commit **bbd21ec40504b8308c8b97c95ae493d2cc1d1b97**, Flutter 3.47.6/Dart 3.13.5, versión **0.6.0+7**. Ambos builds se ejecutaron sin `--no-pub` para regenerar los plugins de producción: Android 96,6 s (servicio 97,8 s, `.dart_tool/workflow-build-apk.log`) y Linux 53,7 s (`.dart_tool/workflow-build-linux.log`). Se conservaron los límites de memoria y los ajustes de Gradle.

- APK: **45 554 336 bytes**, `com.felipe.apuntes`, Nala, API mínima 24/target 36, seis bibliotecas exclusivamente ARM64 y veinte fuentes KaTeX. Firma v2 válida con certificado SHA-256 `e92cb0c4bf598fbf0347d135efb275bfb381761f156c2984e2c796b63ff09887`, idéntico al anterior; permite actualizar sin desinstalar. Firma de desarrollo para pruebas. Manifiesto y certificado registrados en `.dart_tool/workflow-apk-{manifest,signature}.log`.
- Linux: **18 739 132 bytes**, 65 entradas en el paquete, con recursos/fuentes/licencias, bibliotecas, logo, lanzador y ambas guías. Los archivos entregados coinciden byte por byte con el bundle release y APK compilados. El paquete omite el sidecar legado con rutas de compilación; el manifiesto de recursos nativos referencia sus bibliotecas por nombre y fue verificado. Todas las bibliotecas resuelven y el logo coincide.
- El paquete se descomprimió en una carpeta temporal y se abrió por su lanzador con XDG de prueba: proceso activo, una base SQLite y `quick_check=ok`. Se detuvo únicamente el servicio propio y se limpiaron esos archivos. Resultado en `.dart_tool/release-smoke-v060.json`; verificación de contenido/hashes/tar/permisos/menú en `.dart_tool/workflow-delivery-check.log`.
- `dist/previous-v0.5.1/` conserva la entrega anterior completa, comprobada contra sus hashes originales. El acceso existente del menú conserva su ruta y apunta a la nueva entrega. Entrega local; no se publicó una release externa. Las pruebas físicas del S Pen, micrófono y selector Android siguen pendientes de la tablet.

Sumas SHA-256 de la entrega local original de 0.6.0, antes de actualizar las guías para su publicación:

```text
d24861470aae2f9d03e7800a3636651ab80455124c485c6753ee0c1f4e040251  Nala.apk
c88c321809c8f73c3ed4c757552aee6277d49d87835fde505b309d4874784535  Nala-Linux-x64.tar.gz
```

## Paquete público 0.6.0

Para publicar la misma aplicación compilada se corrigió el enlace de `GUIA-0.6.md` a `GUIA-0.5.md`, incluida en el tar, y se actualizó LEEME con la dirección de la release. El paquete final Linux mide **18 739 183 bytes**, con las mismas 65 entradas. La comparación del tar original/final confirmó que sólo cambiaron esas dos piezas de documentación; el APK, ejecutables, bibliotecas y recursos permanecen idénticos al build verificado. Se repitió el verificador completo de archivos, hashes, manifiestos, firma, librerías, permisos, logo y menú. La auditoría independiente confirmó que no se publican datos personales, claves ni cachés.

Notas en [release 0.6.0](releases/v0.6.0.md). El manifiesto vigente incluye instaladores, ambas guías y captura sintética del editor:

```text
d24861470aae2f9d03e7800a3636651ab80455124c485c6753ee0c1f4e040251  Nala.apk
f831a779c89d5ea8034629f4ca50d4fd27beecd04d610872d06c45ac98be045f  Nala-Linux-x64.tar.gz
094cfeb291035074953029d2c4087d198fcdc08c6c58c8119aa249db765549ca  GUIA-0.6.md
825e2c89af89140bb2a7caac4d54374b8b4155885092fcdc6c4a11e856ac5919  GUIA-0.5.md
ab03af0738987a1c9c67802aff5335d10763d3bfd73f5f9b1a3389789584c1c1  Vista-Nala-0.6.png
```

Publicación completada el **7 de octubre de 2026, 17:34:23 UTC**, en [GitHub v0.6.0](https://github.com/felipendelicia/nala/releases/tag/v0.6.0), como prerelease. `main` y `codex/study-tools` se actualizaron por avance directo y la etiqueta anotada `v0.6.0` identifica **56bfcfa1e6e29a7d17f84b7a2c56a9f9ed71df2b**, con el mismo código de aplicación compilado en bbd21ec.

Los seis adjuntos se descargaron mientras la release era borrador y se compararon byte por byte/hash/tamaño con `dist/`; todos coincidieron. Después de publicar, la API confirmó `isDraft=false`, la misma lista de IDs/tamaños/estado de los adjuntos y la URL final. El manifiesto se descargó sin autenticación y coincidió con el local; los cinco enlaces públicos restantes devolvieron HTTP 200. Evidencia en `.dart_tool/github-v060-{draft,published}.json`, `github-v060-draft-check.json` y `github-v060-public-SHA256SUMS`. No se publicó ninguna base de apuntes ni configuración privada.
