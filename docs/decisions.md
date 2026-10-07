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
