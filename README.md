# Nala

Cuadernos y anotaciones sobre PDF para Samsung Tab S10 y Linux.

Versión de prueba en desarrollo. Permite crear cuadernos, guardarlos automáticamente en el dispositivo y organizarlos en carpetas y subcarpetas. Incluye hojas blancas, rayadas, cuadriculadas y punteadas, resaltador, borrador, selección, deshacer y agregar páginas. La tinta activa se pinta en una capa independiente y los nuevos trazos tienen presión expresiva y suavizado ajustables.

El código actual incorpora importación de PDF, anotaciones sobre sus páginas, hojas de apuntes intercaladas y exportación a PDF. Se conservan los PDF originales y los trazos editables. Los PDF protegidos piden su contraseña, que se mantiene únicamente durante la sesión. El flujo de importación, anotación, hojas intercaladas y exportación se verificó en la aplicación Linux. El selector Android aún requiere una comprobación física; ver [verificación](docs/verification.md).

El editor muestra las páginas una debajo de otra: podés seguir bajando sin abrir el índice. Incluye modo lectura, ajuste a hoja y ancho, porcentajes de zoom y bloqueos independientes del zoom y del movimiento horizontal. El resaltador empieza más ancho que el lápiz y cada herramienta conserva su grosor y color durante la sesión. Compartir PDF prepara una instantánea del apunte y abre directamente el selector de Android; Linux permite copiar el archivo o adjuntarlo a un correo, sin guardarlo antes manualmente.

La biblioteca y el editor usan un diseño nuevo con Manrope y el logo minimalista elegido por Felipe. La interfaz usa blanco, negro y grises. Desde Apariencia podés elegir Claro, Oscuro o Seguir sistema; la preferencia se conserva al reiniciar. El papel y los PDF mantienen sus colores originales. Los apuntes se pueden mover entre carpetas desde su menú de opciones.

Se pueden anclar comentarios de texto y notas de voz a la hoja. El audio comienza únicamente al pulsar Grabar, se puede escuchar o descartar y se detiene al pasar la app al fondo. Android usa su micrófono y Linux necesita PipeWire (pw-record/pw-play) o ALSA (arecord/aplay); los recursos se guardan como WAV mono de 16 kHz. Los comentarios permanecen editables en Nala. El PDF exportado incluye marcadores numerados y un anexo con el texto; las notas de voz se identifican con su duración y se escuchan desde Nala.

La sincronización automática con Drive está incorporada al código: carpetas, revisiones, PDF y voz, con reintentos y bibliotecas separadas por cuenta. La versión pública conserva el guardado local porque todavía necesita registrar los clientes OAuth en Google Cloud. Ver [configuración de Drive](docs/drive-setup.md) y [estado](docs/status.md).

La [versión de prueba 0.3.0](https://github.com/felipendelicia/nala/releases/tag/v0.3.0) incluye estas mejoras. Descargas: [APK para la Tab S10 (Android ARM64)](https://github.com/felipendelicia/nala/releases/download/v0.3.0/Nala.apk), [Linux x64](https://github.com/felipendelicia/nala/releases/download/v0.3.0/Nala-Linux-x64.tar.gz) y [sumas de comprobación](https://github.com/felipendelicia/nala/releases/download/v0.3.0/SHA256SUMS). La primera versión corresponde al editor previo al trabajo de PDF; su APK fue probado en la tablet. Los archivos compilados se distribuyen en Releases y no se incluyen en el historial de código.

En Linux, descomprimí el paquete y ejecutá `Abrir-Nala.sh` manteniéndolo junto a `Nala-Linux/`. En Android, copiá `Nala.apk`, abrilo y permití la instalación desde la aplicación que lo abre. Es un APK de prueba firmado con una clave de desarrollo.

Herramientas usadas: Flutter 3.47.6, Dart 3.13.5.

Desde la raíz del repositorio, con Flutter instalado y disponible en PATH:

```sh
tool/flutter-safe pub get
tool/flutter-safe build linux --release
tool/flutter-safe test --no-pub --concurrency=1
tool/flutter-safe test --no-pub integration_test/local_notebook_test.dart -d linux
tool/flutter-safe test --no-pub integration_test/pdf_round_trip_test.dart -d linux
tool/flutter-safe test --no-pub integration_test/appearance_share_test.dart -d linux
tool/flutter-safe build apk --release --target-platform android-arm64
```

`tool/flutter-safe` ejecuta las tareas de a una dentro de un servicio con un límite total de 2300 MiB de RAM, 256 MiB de swap y dos CPU. Requiere Linux con una sesión systemd de usuario. Gradle además tiene un límite de heap de 512 MiB, un solo worker y no deja un daemon persistente. La compilación de Linux usa Ninja con un solo trabajo. Estos límites se añadieron para una PC de 7.5 GiB de RAM. No ejecutar tareas de Flutter por fuera del script al mismo tiempo que se genera el APK.

La compilación Linux debe preceder a las pruebas de PDF: les proporciona la biblioteca nativa PDFium real. Requisitos de las plataformas y detalles del entorno en [compilación](docs/build-notes.md).

El icono está basado en la perrita de Felipe; ver [branding](docs/branding.md).

El [diseño inicial](docs/superpowers/specs/2026-10-06-apuntes-design.md) y el [plan inicial](docs/superpowers/plans/2026-10-06-apuntes-implementation.md) se conservan como documentos históricos. El estado actual se detalla en [estado](docs/status.md) y las decisiones de esta entrega en [decisiones](docs/decisions.md).
