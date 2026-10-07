# Decisiones y límites de esta entrega

El trabajo y la publicación pública se hicieron con la autorización de Felipe, conservando su checkout y sin incluir datos personales, credenciales ni SDK.

- Comentarios anclados a la hoja con lista por página. Permite ubicarlos en el apunte; una lista global requeriría otra vista.
- Carpetas con fechas y borrado lógico para reconciliar cambios entre dispositivos. Una versión anterior de la app ignora ese catálogo.
- Voz en WAV mono16kHz con AudioRecord en Android y PipeWire/ALSA en Linux. Evita instalar otra biblioteca nativa; ocupa más espacio que audio comprimido.
- Archivos Drive identificados como nala-v1, coherentes con el nombre final. Un experimento previo sin publicar con otra identidad necesitaría migración.
- Fondos PDF exportados a200dpi y originales preservados. La tinta es vectorial y los comentarios tienen anexo; el texto del fondo exportado no es seleccionable. El audio se escucha desde Nala.
- Sincronización mientras la app está activa. Los pendientes quedan guardados y se envían al volver a abrir; no hay un servicio de fondo con la aplicación cerrada.
- La comprobación física del S Pen, micrófono/altavoz y selector Android queda para la tablet. Las pruebas de Linux no certifican la sensación de Notewise; puede requerir ajuste con el dispositivo.
- Drive real requiere registrar clientes OAuth y comprobar dos dispositivos. El binario público funciona localmente hasta configurarlo; no contiene identificadores inventados ni afirma una conexión real verificada.

La revisión independiente de la versión 0.2.0 encontró seis problemas importantes, todos corregidos con reproducciones previas y pruebas pasando. No quedaron observaciones menores diferidas. Los resultados y los archivos de prueba se describen en [verificación](verification.md).

## Editor continuo y apariencia 0.3.0

- Ejecución y publicación autónomas bajo la autorización previa de Felipe. Los valores visuales elegidos pueden necesitar ajustes después de probar la tablet.
- Páginas continuas, montando sólo las visibles. La rueda desplaza y Ctrl+rueda cambia el zoom; el coste es cambiar el comportamiento anterior de la rueda.
- Compartir en Android abre el selector del sistema. En Linux ofrece copiar el archivo o abrir un correo con adjunto; la aplicación receptora debe aceptar archivos pegados o existir una integración de correo.
- Compartir y diseño visual se entregan como un cambio conjunto porque comparten cabecera y biblioteca; el historial es menos granular, sin diferencia funcional.
- Oscuro, claro o sistema se guardan como preferencia de la app. Papel y PDF conservan sus colores para mantener legibilidad y fidelidad; el papel blanco sigue siendo brillante de noche.
- Se aplicó exactamente el logo minimalista que Felipe eligió. No se introdujo otra variante después de su aprobación.

## Correcciones de la revisión 0.3.0

La revisión nueva encontró dos problemas importantes y ninguno crítico o menor. Ambos se reprodujeron y corrigieron: deshacer hojas ahora conserva una página válida y su origen; compartir toma la instantánea antes de esperar su guardado y excluye trazos posteriores pendientes. Cancelar compartir permite seguir escribiendo.

- Se trató también el desborde anterior de rutas y materias largas como un problema importante de accesibilidad. Los nombres tienen un ancho limitado y su texto completo aparece en la descripción; el coste es necesitar esa descripción para leer nombres muy largos.
- S Pen, selector Android y recepción real por portapapeles/correo quedan como comprobaciones físicas o de aplicaciones externas. Las pruebas disponibles no pueden certificar esa sensación o compatibilidad; el coste es poder necesitar ajustes específicos después.
- Drive real sigue requiriendo clientes OAuth registrados y dos dispositivos. Se conserva el alcance local verificable; el coste es que la descarga pública no sincroniza hasta configurarla.
- Se conserva la exportación existente de fondos PDF a 200 dpi y referencias de voz, con originales preservados y tinta vectorial. El coste es que el texto del fondo exportado no es seleccionable y el audio se escucha en Nala.

No quedaron observaciones menores diferidas. Los binarios y sus hashes se comprueban después de esta revisión; los resultados finales están en [verificación](verification.md).

- El compilador Android usa un heap reducido a 640 MiB y mantiene los límites globales y las tareas secuenciales. Una compilación fue detenida por la protección de memoria de su servicio; el coste es que compilar puede tardar más.


## S Pen 0.4.0: decisiones y costes

- La mejora se comprueba con el renderizador nativo y píxeles, sin agregar un contador de producción sólo para tests. Coste si la evidencia de escritorio no se traslada: será necesario medir y ajustar en la tablet.
- Android no trata la salida de hover como liberación del botón, porque también precede al contacto; vuelve a muestrear al tocar. Coste: Samsung puede necesitar ajustes de proximidad propios.
- Cada mosaico modificado vuelve a dibujar su contorno local completo; usa 128 píxeles físicos, y los trazos de menos de 96 muestras se dibujan directamente. Evita bordes que engordan y cambian al soltar. Coste: insistir dentro de un mismo mosaico puede demandar más trabajo que los casos medidos.
- La compilación conserva su techo de 2300 MiB y eleva el límite suave de 1800 a 2200 MiB tras medir presión de memoria; Gradle baja a 512 MiB y continúa con un worker. Coste: más memoria residente antes de reclamarla y compilaciones más lentas. Sólo se operaron servicios propios de Nala.
- Entrega física del botón, proximidad y latencia punta-pantalla quedan pendientes de la Tab S10. La compilación Android y eventos de Linux verifican software. Coste: pueden necesitarse ajustes específicos de Samsung.
- Notewise permanece como referencia subjetiva; la mejora medida de rasterizado no afirma equivalencia. Coste: la sensación puede diferir aun con menos trabajo en escritorio.
- Sincronización sigue diferida, con funcionamiento local y sin clientes OAuth configurados. Coste: esta descarga no sincroniza entre dispositivos.

La revisión independiente encontró dos problemas importantes y ninguno crítico o menor. Se reprodujeron antes de corregir: la goma sintética borraba el segmento recién confirmado, y cerrar menús podía dejarla activa. También se reprodujo una pulsación sostenida contada dos veces en modo alternar. La goma ahora empieza a borrar al mover o hacer un contacto físico nuevo; todos los menús restauran la herramienta temporal; los modales conservan el estado físico de alternar y reciben las liberaciones. Las pruebas verifican las notas después de finalizar el gesto, no sólo al confirmar el segmento inicial.

No quedaron observaciones menores diferidas. Los resultados finales y la decisión de publicación están en [verificación](verification.md).

- Los binarios y publicación que el revisor no certificó se verifican por el ejecutor: versión, firma/ID preservados, logo exacto, apertura Linux aislada y hashes locales/remotos. Coste: un problema específico del dispositivo o de distribución aún podría requerir una versión correctiva.

## Herramientas de estudio 0.5 — pedido autónomo del 7 de octubre

Felipe pidió agregar las nueve funciones propuestas tomando Goodnotes/Notewise como referencia. Se conservaron el editor y los datos existentes; los nuevos objetos, portadas, grabaciones y tarjetas son campos opcionales del documento, con recursos identificados por SHA-256. Las versiones anteriores siguen siendo legibles; para editar los campos nuevos entre dispositivos se debe actualizar ambos a0.5.

Las formas usan tinta vectorial y la regla restringe el ángulo. La selección transforma tinta/objetos y el portapapeles se limita a la biblioteca de la cuenta. Los favoritos y la biblioteca de plantillas se guardan en el dispositivo. Pestañas y paneles conservan estados independientes; teclado, S Pen y audio cambian de propietario al activar el panel. Las tarjetas usan una programación local, sin servicios pagos.

Se eligió ML Kit Digital Ink español en Android: la descarga del modelo es explícita y después el reconocimiento es local. Linux usa Tesseract con español cuando está instalado, para impresos/escaneos; el equipo de desarrollo no lo tiene y la interfaz informa esa disponibilidad. La caché reconocida guarda una huella de la página para rechazar resultados atrasados y viaja con el apunte. Esto no garantiza precisión manuscrita equivalente a las aplicaciones de referencia.

El audio de clase empieza por una acción explícita y marca cada nuevo trazo con el instante de inicio. La reproducción recorta un WAV temporal sin alterar el original. Un fallo de almacenamiento conserva captura/vínculos, permite reintentar o descartar y bloquea el cierre hasta resolverlo. La revisión independiente encontró y permitió reproducir errores en esa recuperación, foco inicial/teclado y plantillas pequeñas; se corrigieron antes de entregar. Las verificaciones usan audio sintético y apuntes temporales, nunca el micrófono ni la biblioteca personal.

La entrega de esta etapa es local (APK ARM64 y Linux x64); no se publica una nueva release externa ni se configura OAuth como parte de este pedido. Las pruebas físicas de S Pen, micrófono y descarga/calidad del modelo Android requieren la tablet; la configuración y sincronización real de Drive continúan como pendiente previo.

- La primera compilación Android alcanzó el límite del servicio. El reintento completó Dart y el puente ML Kit, pero R8 llenó el heap512 y sólo repetía GC completo sin liberar espacio. Se detuvo ese servicio propio y se desactivó la minificación/reducción de recursos Java en release, manteniendo Dart AOT y la reducción de iconos. Coste: APK más grande y clases Java sin ofuscar; se conservan los límites globales, un worker y la firma previa.

- El APK se limita a ARM64 en la configuración Android, además del objetivo Flutter. ML Kit y JNI agregaban bibliotecas ARMv7/x86_64 que no tenían motor Flutter correspondiente; filtrarlas evita anunciar soporte incompleto y reduce el tamaño. Esta entrega sigue dirigida a la Tab S10; otros ABI requieren una compilación preparada para ellos.
