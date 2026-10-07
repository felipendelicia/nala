# Progress — 2026-10-07 study tools

Authorization: Felipe requested all nine proposed features autonomously. Current checkout was clean at a483c00. Use the existing feature checkout and preserve user data. Tasks and decisions persist here across context compaction.

- Design and implementation plan saved; feature work starts with the document foundation.
- Shared interfaces: immutable PageObject, NotebookRecording and StudyCard; optional additions to Notebook/Page/InkStroke; shared media enumeration for sync/export.
- Execution: foundation first; disjoint workspace/search/templates and audio/study modules can be delegated after interfaces exist; parent owns editor integration and verification. All Flutter executions serialized by tool/flutter-safe.

## Implementado y comprobado en módulos

- Fundación: objetos, grabaciones, tarjetas, fondos y codec opcional de esquema1; recursos incluidos en sync; canvas/exportación PNG/JPEG/texto. 39 pruebas enfocadas pasaron.
- Espacio de trabajo: pestañas/vista dividida con estados montados; plantillas persistidas; búsqueda PDF/texto con huellas para rechazar OCR desactualizado; puente Android ML Kit español y disponibilidad Linux. 24 pruebas enfocadas y 9 adicionales pasaron; análisis de sus módulos limpio.
- Audio/estudio: primer grupo de 17 pruebas pasó. La integración encontró una carrera entre dos paneles; reproducción/captura ahora comparten un coordinador y se vuelven a comprobar.
- Editor: integración de formas/regla, selección, texto/imágenes, favoritos y acceso a búsqueda/audio/estudio. Pruebas escritas primero y fallos esperados observados; comprobación integrada pendiente.
- Revisión independiente del producto iniciada. Se detuvo solamente un servicio viejo propio de pruebas que seguía esperando; no se tocaron procesos del usuario.

## Siguiente verificación

Pruebas del editor y suite completa, recorrido Linux nativo con exportación y reapertura, análisis, compilaciones Android ARM64/Linux x64, inspección de capturas y documentación de límites físicos. No publicar externamente.

## Correcciones de revisión

La revisión independiente detectó cuatro casos concretos: pérdida del WAV al fallar su almacenamiento, primer gesto cancelado al activar un panel, teclado dirigido al panel anterior y medidas negativas al insertar en una plantilla pequeña. Las reproducciones de audio/plantilla fallaron antes de corregir; el gesto también necesitó conservar el centro de la cámara al dividir el espacio. El caso de teclado falló una vez que se pudo completar el primer trazo. Se corrigen y se volverán a ejecutar.

La primera prueba de texto usó un controlador creado fuera de la zona de tiempo del widget y esperaba su cola de guardado; se trasladó la creación al cuerpo de la prueba. La selección de objetos se presenta inmediatamente tras la edición en memoria, mientras la cola existente guarda la revisión.

- Revisión: los cuatro hallazgos y dos interacciones de recuperación posteriores quedaron corregidos; el revisor confirmó que no quedan hallazgos de código en el alcance revisado.
- Audio/estudio final: 34 pruebas pasaron y análisis enfocado limpio, incluidas retención/reintento/descarte y controles bloqueados durante guardado pendiente.
- Editor: 75 de 78 pruebas inicialmente pasaron; dos menús nuevos no restablecían la goma temporal y el recentrado cambiaba la cámara en lectura. Se reprodujeron y corrigieron; el grupo enfocado final pasó 26/26. La cámara ahora sólo se recentra si cambia el tamaño real del panel/ventana.
- Reconocimiento de formas: una reproducción con muestras pequeñas mientras la punta permanece quieta falló (12 puntos frente a 2). El temporizador tolera movimientos de hasta 2 píxeles y conserva la forma reconocida; las cinco pruebas de herramientas UI pasaron.
- Guía de las nueve funciones guardada en docs/study-tools.md. La compilación sube a0.5.0+5. Análisis global en curso, después suite completa y binarios/recorridos nativos.

## Suite completa

Análisis global sin incidencias, salida0. Suite completa **205/205** pasó en1min39s usando tool/flutter-safe y un worker. Código de aplicación congelado para la entrega salvo fallos nuevos demostrados en recorridos nativos. Build Linux release inicial en curso para usar PDFium real y generar capturas/exportación de las funciones nuevas. Flutter permanece secuencial y limitado.

## Recorridos y entrega final

- Linux release compiló después de regenerar una caché de Flutter que había dejado vacío su directorio de cabeceras; no se cambió CMake ni el SDK. Log: /tmp/nala-study-linux-rebuild.log.
- El recorrido nativo nuevo alcanzó plantillas y búsqueda. Se corrigieron los selectores del test que tocaban el texto de la hoja detrás del diálogo y un campo con etiqueta semántica combinada; se vuelve a ejecutar.
- Se demostró una interacción adicional: en lectura, una marca de comentario sobre tinta con audio era interceptada por el audio. Los comentarios visibles ahora tienen prioridad de toque. La reproducción falló antes de corregir y el grupo de comentarios pasó **3/3** (/tmp/nala-audio-pin-red.log y /tmp/nala-audio-pin-green.log). La suite completa se repetirá con esta corrección.
- Recorrido nativo de estudio pasó **1/1**, en40,3s incluyendo compilación: texto/duplicación/deshacer, rectángulo vectorial, Cornell, búsqueda sin acentos, creación/repaso de tarjeta, imagen y exportación, vista dividida y reapertura desde SQLite. Se inspeccionaron tres capturas y el PDF con Poppler; se conservan texto Unicode, imagen, forma y guías Cornell. Log: /tmp/nala-study-native-pass.log.
- El test PDF anterior esperaba un solo título global; ahora también existe el título de la pestaña. La aserción se limita al editor del PDF, conservando la comprobación de título. Se repite el recorrido.
- Recorrido PDF final pasó **1/1** en36,6s incluyendo compilación. Importó, dibujó, intercaló una hoja, exportó mientras seguía la escritura, abrió el PDF de tres páginas y conservó el apunte al cancelar otra exportación. Log: /tmp/nala-study-pdf-native-final.log.
- Recorrido nativo de carpetas/comentarios pasó **1/1** en39,0s incluyendo compilación: jerarquía, comentario, salida, reapertura y lectura. Log: /tmp/nala-study-organization-native.log. El acceso instalado del menú apunta a este repositorio.
- Verificación final de código: análisis global sin incidencias, salida0 (/tmp/nala-study-analyze-delivery.log), y suite completa **206/206** en1min34,1s (/tmp/nala-study-all-tests-delivery.log). Incluye la regresión de comentario superpuesto a audio. Se conserva respaldo de los binarios0.4 en dist/previous-v0.4.0. Compilaciones finales pendientes.
