# Estado de Nala — 2026-10-07

Nala se desarrolla para tomar apuntes universitarios con S Pen en Samsung Tab S10 y continuar en Linux. El nombre y el icono se basan en la perrita de Felipe.

## Editor 0.3.0

- Páginas continuas al bajar, con índice opcional, hojas de tamaños mixtos y tinta local a cada página. Sólo las hojas visibles montan canvas; una prueba cubre mil páginas.
- Tinta activa incremental en su propia capa, sin reconstruir la interfaz por muestra. Presión expresiva y suavizado ajustables; el trazo terminado reutiliza su geometría y los trazos antiguos conservan su aspecto.
- Bloqueos independientes de movimiento horizontal y zoom. Se puede seguir bajando o saltar de hoja con ambos bloqueados.
- Lápiz grafito de 2.5 pt y resaltador amarillo de 14 pt; grosores y colores independientes durante la sesión.
- Diseño nuevo de biblioteca/editor, Manrope y el logo minimalista elegido por Felipe. Interfaz en blanco, negro y grises; Claro, Oscuro o Seguir sistema con preferencia guardada; las hojas y PDF conservan sus colores.
- Compartir PDF directo desde el editor: selector Android; archivo al portapapeles o adjunto de correo Linux. Exportar una copia sigue disponible.
- Mover/renombrar apuntes desde su menú, carpetas y subcarpetas persistidas en SQLite.
- Lectura, comentarios de texto/voz y PDF protegido/rotado con hojas intercaladas. El PDF exportado conserva tinta vectorial y fondos a 200 dpi; comentarios en anexo y audio disponible en Nala.

La verificación actual y los límites se detallan en [verificación](verification.md). Las pruebas nativas se ejecutan una por proceso Flutter, manteniendo los límites de recursos.

## S Pen y botón 0.4.0

Presión inmediata y suavizado inicial 0%; caché de tinta activa por mosaicos con bordes estables y geometría vectorial conservada. Ajustes guardados de presión/suavizado y herramienta del botón: goma, resaltador, lápiz, selección o desactivado. Mantener y alternar disponibles; goma por defecto. Cambios de herramienta durante contacto, cancelaciones y ventanas protegidos por pruebas reales de editor. Guía y medida de rasterizado en [S Pen](spen.md).

## Herramientas y estudio 0.5.0

Formas/regla, selección con copiar/cortar/duplicar/pegar/escala/giro/color, imágenes y texto, favoritos persistidos, pestañas/vista dividida, plantillas propias y portadas, búsqueda, audio temporal y tarjetas con repetición espaciada. Los nuevos datos conservan la compatibilidad con los cuadernos anteriores y sus medios se incluyen en guardado/sync/exportación. Los apuntes manuscritos se reconocen localmente en Android después de descargar explícitamente el modelo español; Linux requiere Tesseract con español para OCR de impresos y puede buscar el texto reconocido guardado en Android. Ver [guía de uso](study-tools.md) y [revisión](study-tools-review.md).

La entrega local actual es **0.6.0+7**, lista en `dist/`: APK ARM64 y paquete Linux x64; el menú Nala abre la versión nueva. Pasaron **270** pruebas, análisis sin incidencias y tres recorridos nativos Linux. El paquete final descomprimido abrió con SQLite temporal válido. La entrega 0.5.1 completa queda respaldada junto a las anteriores; la última release pública sigue siendo 0.4. Detalles en [verificación](verification.md).

## Encabezado compacto 0.5.1

Dos filas de 56 píxeles al editar y sólo una al leer. Las pestañas de 48 aparecen con varios apuntes. Más herramientas abre los controles adicionales en un panel con etiquetas; elegir una acción lo cierra sin cambiar las coordenadas de la hoja. Opciones del cuaderno permite abrir otro apunte, dividir y exportar. Se verificaron texto ampliado, temas claro/oscuro, pantalla pequeña y división horizontal/vertical.

## Herramientas para apuntes 0.6.0

Elementos reutilizables con búsqueda/renombrado e inserciones independientes; enlaces a páginas de otros apuntes que conservan los editores abiertos; recorte, opacidad, original recuperable y bloqueo de imágenes/objetos; fórmulas LaTeX con vista previa local y representación en PDF; barra ordenable con accesos elegibles y ubicación superior/lateral. El backup completo `.nala.zip` incluye la biblioteca, recursos y ajustes locales; comprueba el archivo antes de restaurar copias y remapea los enlaces internos. Guía en [herramientas para apuntes](notebook-workflow.md) y hallazgos corregidos en [revisión](notebook-workflow-review.md).

## Verificación física pendiente

Felipe confirmó que la primera versión funciona en la tablet. La presión/latencia, el micrófono y altavoz reales, el selector Android y la descarga/calidad del modelo manuscrito necesitan probarse allí con el nuevo APK. Las pruebas de escritorio no demuestran una sensación equivalente a Notewise.

## Etapa final

La sincronización automática con Drive está implementada después de las mejoras locales. Incluye reintentos, transferencia de PDF/voz, carpetas y preservación de versiones concurrentes. Conectar por primera vez adopta la biblioteca local y conserva el original; otras cuentas mantienen sus propias bases, recursos y colas. La autenticación Linux usa navegador/PKCE y llavero; Android usa Google Sign-In.

La versión pública todavía requiere registrar los clientes OAuth de Nala en Google Cloud y compilar con esos identificadores. La conexión real entre tablet y PC no se ha probado. Instrucciones en [Drive](drive-setup.md); hasta configurarlo los apuntes permanecen en el dispositivo.

## Publicación

Repositorio público: [felipendelicia/nala](https://github.com/felipendelicia/nala). La [v0.4.0](https://github.com/felipendelicia/nala/releases/tag/v0.4.0) distribuye el APK Android ARM64 y la aplicación Linux x64 con sumas SHA-256. El acceso Nala del menú de esta PC abre la versión nueva. La primera [v0.1.0](https://github.com/felipendelicia/nala/releases/tag/v0.1.0) corresponde al editor anterior a PDF y a estas mejoras. No se publican cuadernos personales, bases, caches, SDK, tokens ni claves de firma.
