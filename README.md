# Nala

Cuadernos y anotaciones sobre PDF para Samsung Tab S10 y Linux.

Versión de prueba en desarrollo. Permite crear cuadernos, guardarlos automáticamente en el dispositivo, organizar por materia y escribir con lápiz o mouse. Incluye hojas blancas, rayadas, cuadriculadas y punteadas, resaltador, borrador, selección para mover trazos, deshacer y agregar páginas.

El código actual incorpora importación de PDF, anotaciones sobre sus páginas, hojas de apuntes intercaladas y exportación a PDF. Se conservan los PDF originales y los trazos editables. Los PDF protegidos piden su contraseña, que se mantiene únicamente durante la sesión. La validación completa de este flujo y del selector de guardado en Android está en curso; ver [verificación](docs/verification.md).

El guardado es local: cada dispositivo conserva sus propios apuntes. La sincronización con Drive queda para la última etapa. La siguiente prioridad es mejorar la fluidez y la presión del lápiz, seguida por modo lectura, comentarios de texto y voz, controles de zoom y carpetas con subcarpetas. Ver [estado y prioridades](docs/status.md).

Las versiones de prueba disponibles se publican en [Releases](https://github.com/felipendelicia/nala/releases). La primera corresponde al editor local previo al trabajo de PDF; su APK fue probado en la tablet. Los archivos compilados se distribuyen allí y no se incluyen en el historial de código.

En Linux, descomprimí el paquete y ejecutá `Abrir-Nala.sh` manteniéndolo junto a `Nala-Linux/`. En Android, copiá `Nala.apk`, abrilo y permití la instalación desde la aplicación que lo abre. Es un APK de prueba firmado con una clave de desarrollo.

Herramientas usadas: Flutter 3.47.6, Dart 3.13.5.

Desde la raíz del repositorio, con Flutter instalado y disponible en PATH:

```sh
tool/flutter-safe pub get
tool/flutter-safe build linux --release --no-pub
tool/flutter-safe test --no-pub --concurrency=1
tool/flutter-safe test --no-pub integration_test/local_notebook_test.dart -d linux
tool/flutter-safe test --no-pub integration_test/pdf_round_trip_test.dart -d linux
tool/flutter-safe build apk --debug --no-pub --target-platform android-arm64
```

`tool/flutter-safe` ejecuta las tareas de a una dentro de un servicio con un límite total de 2300 MiB de RAM, 256 MiB de swap y dos CPU. Requiere Linux con una sesión systemd de usuario. Gradle además tiene un límite de heap de 1536 MiB, un solo worker y no deja un daemon persistente. La compilación de Linux usa Ninja con un solo trabajo. Estos límites se añadieron para una PC de 7.5 GiB de RAM. No ejecutar tareas de Flutter por fuera del script al mismo tiempo que se genera el APK.

La compilación Linux debe preceder a las pruebas de PDF: les proporciona la biblioteca nativa PDFium real. Requisitos de las plataformas y detalles del entorno en [compilación](docs/build-notes.md).

El icono está basado en la perrita de Felipe; ver [branding](docs/branding.md).

El [diseño inicial](docs/superpowers/specs/2026-10-06-apuntes-design.md) y el [plan inicial](docs/superpowers/plans/2026-10-06-apuntes-implementation.md) se conservan como documentos históricos. El estado actual se detalla en `docs/status.md`.
