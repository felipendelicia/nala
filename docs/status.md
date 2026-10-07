# Estado de Nala — 2026-10-06

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

## Verificación física pendiente

Felipe confirmó que la primera versión funciona en la tablet. Esta mejora de presión/latencia, el micrófono y altavoz reales y el selector Android necesitan probarse allí con el nuevo APK. Las pruebas de escritorio no demuestran una sensación equivalente a Notewise.

## Etapa final

La sincronización automática con Drive está implementada después de las mejoras locales. Incluye reintentos, transferencia de PDF/voz, carpetas y preservación de versiones concurrentes. Conectar por primera vez adopta la biblioteca local y conserva el original; otras cuentas mantienen sus propias bases, recursos y colas. La autenticación Linux usa navegador/PKCE y llavero; Android usa Google Sign-In.

La versión pública todavía requiere registrar los clientes OAuth de Nala en Google Cloud y compilar con esos identificadores. La conexión real entre tablet y PC no se ha probado. Instrucciones en [Drive](drive-setup.md); hasta configurarlo los apuntes permanecen en el dispositivo.

## Publicación

Repositorio público: [felipendelicia/nala](https://github.com/felipendelicia/nala). La [v0.4.0](https://github.com/felipendelicia/nala/releases/tag/v0.4.0) distribuye el APK Android ARM64 y la aplicación Linux x64 con sumas SHA-256. El acceso Nala del menú de esta PC abre la versión nueva. La primera [v0.1.0](https://github.com/felipendelicia/nala/releases/tag/v0.1.0) corresponde al editor anterior a PDF y a estas mejoras. No se publican cuadernos personales, bases, caches, SDK, tokens ni claves de firma.
