# Herramientas

SDK verificado: Flutter 3.47.6 estable, Dart 3.13.5. Android SDK 36, Java 21. Clang, ninja y libsecret instalados por Felipe.

El wrapper `../flutterw` usa el SDK y caches del workspace. Las pruebas Flutter requieren acceso a localhost. Después de resolver dependencias con `../flutterw pub get`, usar `--no-pub` en las pruebas y builds para evitar consultas innecesarias de red.

Primera comprobación: ocho tests de codec y lápiz pasando; build Linux debug correcto y aplicación ejecutándose con VM Service el 6 de octubre de 2026. La comprobación física del S Pen queda pendiente de instalar el APK en la tablet.
