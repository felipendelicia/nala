# Nala 0.5: herramientas para editar y estudiar

Abrí un apunte desde la biblioteca. Para editar, activá **Modo editor**; **Modo lectura** permite recorrer las hojas y escuchar audio vinculado. Las barras se desplazan horizontalmente cuando falta espacio. Podés escribir y seleccionar con lápiz o ratón; los dedos sirven para navegar y ampliar la hoja.

## 1. Formas y regla

En **Formas**, elegí **Línea**, **Rectángulo** o **Elipse** y arrastrá sobre la hoja. Usan el color y grosor actuales.

Con **Trazo libre · mantener para formar**, dibujá una forma y mantené la punta quieta unos 0,65 segundos antes de levantarla. Si Nala reconoce una línea, rectángulo o elipse, muestra la forma corregida; los trazos que no reconoce conservan su forma libre.

Activá **Regla** y elegí **Ángulo de la regla** entre 0° y 90°, en pasos de 15°. El trazo del lápiz se ajusta a esa dirección. Tocá **Regla** nuevamente para desactivarla.

## 2. Selección completa

Elegí **Selección** y arrastrá un rectángulo sobre tinta, texto o imágenes. Después, arrastrá desde dentro de la selección para moverla.

- **Copiar selección**, **Cortar selección** y **Pegar selección** permiten llevar contenido a otra hoja o a otro apunte de la misma biblioteca. **Duplicar selección** crea una copia cercana.
- **Tamaño de selección** ofrece reducir al 75% o ampliar al 125% y al 200%. **Girar selección** gira 90° cada vez.
- Elegí un color de tinta para cambiar el color de los trazos y cuadros de texto seleccionados. Usá **Eliminar selección** para borrarlos.

Con teclado: `Ctrl+C`, `Ctrl+X`, `Ctrl+V` y `Ctrl+D`; `Supr` elimina. **Deshacer** y **Rehacer** también están disponibles, con `Ctrl+Z` y `Ctrl+Mayús+Z`.

## 3. Texto e imágenes

En **Insertar texto**, escribí el contenido, elegí **Tamaño** y pulsá **Insertar**. Para corregirlo, seleccioná el cuadro y elegí **Editar texto seleccionado**; terminá con **Guardar**.

**Insertar imagen** abre el selector de archivos. Acepta PNG y JPEG de hasta 25 MB y aproximadamente 20 millones de píxeles. Las imágenes grandes se ajustan para trabajar en la hoja. Texto e imágenes se insertan en la zona visible y quedan seleccionados: podés moverlos, cambiar su tamaño o girarlos.

## 4. Lápices favoritos

Elegí lápiz o resaltador, color y grosor. Abrí **Lápices favoritos → Guardar lápiz actual…**, escribí un nombre y pulsá **Guardar**. Elegir ese favorito recupera esos tres ajustes.

Se conservan en el dispositivo entre sesiones. Podés guardar hasta doce y eliminarlos con **Quitar favorito**.

## 5. Pestañas y vista dividida

Desde la fila superior, **Abrir otro apunte** agrega una pestaña. Tocá su nombre para cambiar de documento; cada uno conserva su navegación y zoom.

**Vista dividida** muestra dos apuntes: lado a lado en pantallas amplias y uno encima del otro en las más estrechas. Tocá el panel que querés usar para activarlo. **Una sola vista** vuelve al apunte activo.

La cruz de cada pestaña la cierra; **Cerrar espacio de trabajo** vuelve a la biblioteca. Nala intenta guardar antes de cerrar y mantiene abierta la pestaña si necesita resolver un error de guardado.

## 6. Plantillas y portadas

Abrí **Plantillas y portadas**. Hay hojas en blanco, rayadas, cuadriculadas, punteadas, **Cornell** y **Agenda semanal**.

**Importar PDF** e **Importar imagen** agregan plantillas propias para reutilizar en esta biblioteca del dispositivo. Admiten archivos de hasta 50 MB; las imágenes deben ser PNG/JPEG y los PDF deben abrirse sin contraseña. Cada página de un PDF multipágina queda disponible como plantilla.

Al elegir una plantilla, seleccioná **Aplicar a esta hoja**, que cambia el fondo y conserva su contenido, o **Agregar hoja con esta plantilla**, que crea una hoja con las dimensiones de la plantilla. Para las plantillas importadas también aparece **Usar como portada**; la portada identifica el apunte en la biblioteca.

## 7. Buscar y reconocer texto

En la biblioteca, **Buscar en todos los apuntes** busca en títulos, materias, comentarios, texto insertado, texto original de PDF y texto reconocido guardado. **Buscar en apunte** limita la búsqueda al documento abierto. Tocá una coincidencia para ir a su página. Los PDF escaneados necesitan reconocimiento; los protegidos deben desbloquearse en el editor para leer su texto original.

Dentro de la búsqueda, desplegá **Reconocer y corregir texto**, elegí **Apunte** y **Página**, y pulsá **Reconocer página**. Revisá el resultado, corregilo y elegí **Guardar texto**. También podés usar **Editar texto reconocido** para ingresarlo manualmente. Si modificás el contenido de la página, volvé a reconocerla o corregir su texto para mantener la búsqueda actualizada.

En Android, el reconocimiento de tinta manuscrita requiere **Descargar modelo español**: la descarga es explícita, necesita conexión y la interfaz indica unos 20 MB. Después procesa localmente la tinta escrita en Nala. **Eliminar modelo** libera ese recurso.

En Linux, el OCR local requiere Tesseract con el idioma español `spa`, instalado desde el sistema. Está orientado a texto impreso y escaneos; puede fallar con manuscritos. Si falta el motor o el idioma, Nala lo indica y permite editar el texto manualmente. El texto guardado forma parte del apunte: podés buscar en Linux el texto reconocido y guardado en Android, incluso si Linux no tiene un motor OCR disponible.

## 8. Audio de clase vinculado a la tinta

Abrí **Audio de clase** y pulsá **Grabar clase**. En Android, permití el micrófono cuando el sistema lo solicite. Los trazos nuevos quedan vinculados al momento en que empezaste a escribirlos. Pulsá **Detener y guardar** al terminar.

En **Modo lectura**, tocá un trazo vinculado para escuchar desde ese momento. En el panel, **Escuchar** reproduce una grabación guardada; también podés detenerla, renombrarla o eliminarla. Al eliminar el audio se conserva la tinta.

Cambiar de panel activo, cerrar el panel o salir intenta detener y guardar el audio. Si aparece **Grabación pendiente de guardar**, mantené la pestaña abierta y usá **Reintentar guardar**. **Descartar grabación pendiente** requiere confirmación y conserva la tinta sin sus vínculos a ese audio.

En Linux se necesitan herramientas de audio de PipeWire o ALSA: `pw-record`/`pw-play` o `arecord`/`aplay`, además de un micrófono disponible.

## 9. Tarjetas y repetición espaciada

Abrí **Tarjetas de estudio → Nueva tarjeta**, completá **Pregunta** y **Respuesta**, y pulsá **Guardar tarjeta**. Si antes seleccionaste cuadros de texto, su contenido se propone como pregunta. Podés editar o eliminar tarjetas desde la lista.

En **Repasar pendientes**, intentá responder antes de pulsar **Mostrar respuesta**. Valorá lo que recordaste con **Otra vez**, **Difícil**, **Bien** o **Fácil**. Nala guarda la próxima revisión según esa valoración; **Otra vez** vuelve a programar la tarjeta para dentro de diez minutos. **Ver tarjetas** regresa a la lista.

## Guardado y alcance

Las herramientas funcionan con guardado local y no requieren una cuenta ni servicios pagos. La conexión opcional a Google Drive sigue dependiendo de completar la configuración OAuth pendiente de la integración previa.

**Exportar PDF** conserva fondos, tinta, texto e imágenes. Las grabaciones y tarjetas se consultan dentro de Nala.

Nala 0.5 abre los cuadernos anteriores con sus datos existentes. Para usar objetos, audio de clase y tarjetas entre dispositivos, instalá 0.5 en ambos antes de editar esos apuntes: las versiones anteriores desconocen los campos nuevos y pueden omitirlos al guardar.
