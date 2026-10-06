# Nala

Cuadernos y anotaciones sobre PDF para Samsung Tab S10 y Linux.

Versión de prueba en desarrollo. Ya permite crear cuadernos, guardarlos en el dispositivo, organizar por materia y escribir con lápiz o mouse. Incluye hojas blancas, rayadas, cuadriculadas y punteadas, resaltador, borrador, selección para mover trazos, deshacer y agregar páginas.

La importación y exportación de PDF y la sincronización con Drive todavía están pendientes. El guardado actual es local: cada dispositivo conserva sus propios apuntes.

Para probar en esta PC, buscá **Nala** en el menú de aplicaciones o abrí `dist/Abrir-Nala.sh`. Para la tablet, copiá `dist/Nala.apk`, abrilo y permití la instalación desde la aplicación que lo abre. Es un APK de prueba firmado con la clave de desarrollo; no es una publicación en una tienda.

Herramientas usadas: Flutter 3.47.6, Dart 3.13.5.

Desde esta carpeta:

```sh
tool/flutter-safe pub get
tool/flutter-safe test --no-pub --concurrency=1
tool/flutter-safe build apk --debug --no-pub --target-platform android-arm64
tool/flutter-safe build linux --release --no-pub
```

En esta PC de 7.5 GiB de RAM, `tool/flutter-safe` ejecuta las tareas de a una dentro de un servicio con un límite total de 2300 MiB de RAM, 256 MiB de swap y dos CPU. Requiere Linux con una sesión systemd de usuario. Gradle además tiene un límite de heap de 1536 MiB, un solo worker y no deja un daemon persistente. La compilación de Linux usa Ninja con un solo trabajo. No abrir una app de depuración ni ejecutar tareas de Flutter por fuera de este script al mismo tiempo que se genera el APK.

El icono está basado en la perrita de Felipe; ver [branding](docs/branding.md).
