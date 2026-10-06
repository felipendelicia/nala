# Estado de Nala — 2026-10-06

Nala se desarrolla para tomar apuntes universitarios con S Pen en Samsung Tab S10 y continuar en Linux. El nombre y el icono se basan en la perrita de Felipe.

## Editor incorporado al código 0.2.0

- Tinta activa incremental en su propia capa, sin reconstruir la interfaz por cada muestra del lápiz. Presión expresiva y suavizado ajustables; los trazos anteriores mantienen su aspecto.
- Modo lectura: lápiz, dedos y mouse permiten navegar; las acciones de edición quedan deshabilitadas.
- Ajuste a hoja y ancho, porcentajes de zoom, bloqueo de escala conservando desplazamiento.
- Comentarios anclados a la hoja, texto editable y grabaciones de voz con guardar, escuchar y descartar. Captura sólo por acción explícita; se detiene al suspender o cerrar.
- Carpetas y subcarpetas, rutas, renombrado y movimientos. Se rechazan ciclos y borrado de carpetas no vacías.
- PDF original preservado, importación de páginas rotadas/protegidas, hojas intercaladas y exportación con tinta vectorial, fondos a 200 dpi y anexo de comentarios.

El recorrido completo de PDF en Linux pasó, incluido continuar navegando durante la exportación y cancelar el selector. Se corrigió la segunda inicialización del motor PDF durante exportación. Las pruebas de comentarios, guardado/reapertura y lectura en la aplicación Linux también pasaron. La interfaz fue comprobada en tamaños de escritorio y tablet, incluido texto ampliado.

## Verificación física pendiente

Felipe confirmó que la primera versión funciona en la tablet. Esta mejora de presión/latencia, el micrófono y altavoz reales y el selector Android necesitan probarse allí con el nuevo APK. Las pruebas de escritorio no demuestran una sensación equivalente a Notewise.

## Etapa final

La sincronización automática con Drive está implementada después de las mejoras locales. Incluye reintentos, transferencia de PDF/voz, carpetas y preservación de versiones concurrentes. Conectar por primera vez adopta la biblioteca local y conserva el original; otras cuentas mantienen sus propias bases, recursos y colas. La autenticación Linux usa navegador/PKCE y llavero; Android usa Google Sign-In.

La versión pública todavía requiere registrar los clientes OAuth de Nala en Google Cloud y compilar con esos identificadores. La conexión real entre tablet y PC no se ha probado. Instrucciones en [Drive](drive-setup.md); hasta configurarlo los apuntes permanecen en el dispositivo.

## Publicación

Repositorio público: [felipendelicia/nala](https://github.com/felipendelicia/nala). La primera [v0.1.0](https://github.com/felipendelicia/nala/releases/tag/v0.1.0) corresponde al editor anterior a PDF y a estas mejoras. La siguiente versión descargable está en preparación. No se publican cuadernos personales, bases, caches, SDK, tokens ni claves de firma.
