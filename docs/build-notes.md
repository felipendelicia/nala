# Herramientas

SDK verificado: Flutter 3.47.6 estable, Dart 3.13.5. Android SDK 36, Java 21. Clang, ninja y libsecret instalados por Felipe.

El repositorio se compila con un SDK de Flutter instalado por separado. `tool/flutter-safe` usa Flutter de PATH; en el workspace original puede encontrar un wrapper `../flutterw` con el SDK y los caches locales. Ese wrapper y el SDK no son parte del repositorio.

En Linux se necesitan CMake, Clang, Ninja, pkg-config, GTK 3 de desarrollo, libsecret de desarrollo y las herramientas estándar de C++. Android necesita Android SDK, sus licencias aceptadas y un JDK compatible con la configuración de Gradle. Las pruebas Flutter requieren acceso a localhost.

Resolver dependencias con `tool/flutter-safe pub get` y usar `--no-pub` en las siguientes pruebas. Antes de las pruebas de PDF, ejecutar `tool/flutter-safe build linux --release`: el harness usa `build/native_assets/linux/libpdfium.so` producido por la compilación, sin reemplazar el motor PDF por un mock.

Las compilaciones y pruebas se ejecutan de a una mediante `tool/flutter-safe`, que requiere una sesión systemd de usuario y limita el consumo de recursos del árbol completo de procesos. La compilación Android usa un worker y Linux usa un trabajo de Ninja.

Los archivos PDF de `test/support/pdf/` son fixtures sintéticos. La contraseña `nala-test` pertenece únicamente al archivo de prueba `protected.pdf`.

Primera comprobación: ocho tests de codec y lápiz pasando; build Linux debug correcto y aplicación ejecutándose con VM Service el 6 de octubre de 2026. La comprobación física del S Pen queda pendiente de instalar el APK en la tablet.

Para generar una versión release después de pruebas de integración, usá `tool/flutter-safe build apk --release --target-platform android-arm64` y `tool/flutter-safe build linux --release`, sin `--no-pub`. Flutter 3.47.6 regenera así los registros de plugins excluyendo dependencias de desarrollo; omitir esa fase puede dejar un registro Android de integration_test que no existe en release. No se modifica el archivo generado a mano.

Gradle usa heap de 768 MiB, metaspace de 384 MiB, code cache de 64 MiB, SerialGC y dos procesadores activos. Esto permite que la compilación Dart y el empaquetador compartan el límite global de 2300 MiB.
