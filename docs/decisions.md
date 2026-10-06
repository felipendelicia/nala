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

La revisión independiente encontró seis problemas importantes, todos corregidos con reproducciones previas y pruebas pasando. No quedaron observaciones menores diferidas. Los resultados y los archivos de prueba se describen en [verificación](verification.md).
