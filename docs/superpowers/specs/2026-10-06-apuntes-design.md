# App de apuntes para la universidad

Estado: diseño aprobado por Felipe el 6 de octubre de 2026 para preparar el plan de implementación. Este documento define el producto; todavía no se implementó la aplicación.

## Objetivo

Tomar apuntes con el S Pen en una Samsung Tab S10 y continuar trabajando con los mismos documentos en una PC con Linux. La referencia funcional es Xournal++.

Felipe pidió:

- Elegir el tipo de hoja.
- Crear cuadernos vacíos.
- Anotar sobre PDFs.
- Usar los documentos desde ambos dispositivos.
- Sincronización automática tipo Drive.

Esta propuesta interpreta el último punto como sincronización mediante la cuenta de Google Drive de Felipe. Propone edición en ambos dispositivos y funcionamiento sin internet.

## Enfoque recomendado

Una aplicación Flutter con versiones para Android y Linux, con el editor, el formato de documento y la sincronización compartidos. El tratamiento del lápiz, los archivos, la autenticación y las credenciales se adapta a cada plataforma.

La alternativa considerada es una aplicación web instalable. Simplifica la distribución, pero requiere comprobar en la tablet la escritura, los gestos, el almacenamiento local y el comportamiento al trabajar sin conexión. Se recomienda empezar con las aplicaciones para Android y Linux y validar pronto el S Pen en la tablet real.

## Experiencia principal

### Biblioteca

La pantalla inicial muestra cuadernos y documentos PDF, sus nombres, miniaturas, fecha de edición y estado de sincronización. Permite organizar por materia, buscar por título, crear un cuaderno e importar un PDF desde el selector de archivos del dispositivo.

La app puede empezar a usarse localmente antes de conectar Google Drive. Al conectar la misma cuenta en ambos dispositivos, aparecen los mismos documentos.

### Editor

La hoja ocupa la mayor parte de la pantalla. Una barra compacta reúne lápiz, resaltador, borrador, selección, color, grosor, deshacer y rehacer. Un panel plegable muestra las páginas. Los controles se adaptan al uso táctil en la tablet y al teclado y mouse en la PC.

El S Pen escribe; los dedos desplazan y amplían la hoja. En la PC se puede dibujar con mouse o un lápiz compatible. La selección permite mover y eliminar trazos. Los atajos de teclado cubren deshacer, rehacer y las herramientas principales.

Los cambios se guardan automáticamente en el dispositivo. El estado distingue guardado local, cambios pendientes, sincronización en curso y documento sincronizado.

### Hojas y PDFs

Un cuaderno nuevo empieza con una página y permite agregar más. Las páginas de cuaderno ofrecen fondo blanco, rayado, cuadriculado o punteado. El patrón se elige por página, con una opción para aplicarlo a todo el cuaderno, y cambiarlo conserva los trazos existentes.

El PDF se importa como parte del documento y mantiene sus páginas como fondo. Las anotaciones se guardan por separado del contenido original. Se pueden añadir páginas de apuntes entre páginas del PDF y elegir su patrón.

La exportación a PDF incluye los fondos y las anotaciones. El documento editable se conserva en la aplicación para continuar trabajando.

## Datos y guardado

Cada documento tiene un identificador estable, título, materia y páginas ordenadas. Cada página tiene tamaño, patrón o referencia a una página de PDF, y trazos con identificadores estables.

Los trazos guardan puntos en coordenadas de la hoja, presión, herramienta, color y grosor. El desplazamiento y el zoom no modifican esas coordenadas. Los PDFs originales se conservan como recursos del documento.

El guardado local usa transacciones para confirmar una edición y su pendiente de sincronización juntas. La recuperación al volver a abrir la app debe incluir las ediciones ya confirmadas aunque la sincronización haya fallado. La actividad de red y la preparación de documentos no bloquean la escritura.

## Sincronización con Google Drive

La app crea una carpeta propia visible en Drive. Solicita el alcance `drive.file` para trabajar con los archivos creados por la aplicación. Los cuadernos conservan su estructura editable y sus recursos; una exportación PDF es un resultado adicional.

La sincronización se intenta después de guardar, al abrir o retomar la app y al recuperar la conexión mientras la app está activa. Los pendientes sobreviven al cierre. La primera versión garantiza este comportamiento con la aplicación activa; sincronizar con la aplicación cerrada requiere trabajo específico según el sistema operativo.

Para evitar sobrescribir silenciosamente una edición concurrente, las revisiones sincronizadas son archivos inmutables con un identificador único y la revisión de la que parten. Los PDFs originales se suben como recursos separados reutilizables. La app consulta las revisiones disponibles antes de continuar un documento.

Si tablet y PC editan desde la misma revisión antes de recibir los cambios de la otra, ambas revisiones se conservan. La biblioteca muestra las dos versiones identificadas por dispositivo y fecha para que Felipe pueda revisarlas. La detección debe ser idempotente: volver a sincronizar no crea copias nuevas del mismo conflicto.

Los fallos de red conservan los cambios locales y se reintentan con espera progresiva. Si la autorización vence, la app conserva los pendientes y permite reconectar la cuenta.

## Componentes

- **Biblioteca y editor:** presentan los documentos y reciben acciones del usuario.
- **Modelo de documento:** define páginas, trazos, recursos y revisiones; compartido entre plataformas.
- **Motor de escritura:** transforma la entrada a coordenadas de página y dibuja los trazos y las herramientas.
- **Adaptador PDF:** dibuja los fondos importados y produce la exportación con las anotaciones.
- **Repositorio local:** confirma cambios, recupera documentos y conserva la cola de sincronización.
- **Sincronización Drive:** autentica, consulta y transfiere revisiones y recursos, y detecta conflictos.
- **Adaptadores de plataforma:** manejan entrada del lápiz, selectores de archivos y almacenamiento seguro de credenciales.

## Configuración y verificación

La conexión real con Drive requiere configurar un proyecto de Google Cloud, habilitar Drive API y registrar las credenciales OAuth correspondientes a Android y a la aplicación de escritorio. Las credenciales del conector de Drive de esta conversación no configuran la nueva aplicación. Los tokens se guardan en el almacenamiento seguro del dispositivo.

El proyecto se considerará listo para su primera entrega cuando:

1. Se pueda crear un cuaderno, cambiar el patrón de una página y conservar sus trazos tras cerrar y abrir.
2. Se pueda importar un PDF, escribir sobre una página, añadir una hoja de apuntes y exportar el resultado.
3. Dibujar, seleccionar y borrar funcione con distintos niveles de zoom sin desplazar las anotaciones respecto del fondo.
4. En la Tab S10 real se pueda escribir apoyando la mano, con presión y gestos de navegación utilizables. Esta prueba requiere el dispositivo; un emulador no confirma la experiencia del S Pen.
5. Con la misma cuenta, un cambio guardado en la tablet aparezca editable en Linux y viceversa.
6. Las ediciones sin internet se recuperen y sincronicen después; dos ediciones concurrentes conserven ambas versiones sin duplicarlas en cada reintento.

La validación incluye pruebas del modelo y del guardado, pruebas de sincronización con dos clientes, revisión de la interfaz en ambos tamaños y una prueba real con Google Drive después de conectar la cuenta.

## Fuentes

- [Xournal++](https://xournalpp.github.io/).
- [Plataformas soportadas por Flutter](https://docs.flutter.dev/reference/supported-platforms).
- [Presión en eventos de entrada de Flutter](https://api.flutter.dev/flutter/gestures/PointerEvent/pressure.html).
- [Entrada con lápiz en Android](https://developer.android.com/develop/ui/compose/touch-input/stylus-input/advanced-stylus-features).
- [Permisos de Google Drive API](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).
- [Carga de archivos en Google Drive](https://developers.google.com/workspace/drive/api/guides/manage-uploads).
- [OAuth para aplicaciones de escritorio](https://developers.google.com/identity/protocols/oauth2/native-app).
