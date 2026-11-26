# Actualizaciones de Nala

Instalá una vez el primer paquete que incluye **Ajustes → Buscar actualizaciones**. En Android abrí el APK sobre la instalación existente. En Linux descomprimí el paquete y abrí `Abrir-Nala.sh`. Después podés buscar nuevas versiones desde Ajustes. Android abre el instalador del sistema y puede pedirte que autorices a Nala a instalar aplicaciones. Linux prepara los archivos al tocar **Instalar** y los activa la próxima vez que abras el lanzador.

## Preparar una versión para GitHub

1. Subí el número de versión y de compilación en `pubspec.yaml`. Conservá el identificador y el certificado del APK anterior para que Android acepte la actualización sobre la instalación existente.
2. Compilá y empaquetá los binarios.

   ```sh
   tool/flutter-safe build linux --release
   tool/flutter-safe build apk --release --target-platform android-arm64
   mkdir -p dist
   tool/package-linux build/linux/x64/release/bundle dist/Nala-Linux-x64.tar.gz
   cp build/app/outputs/flutter-apk/app-release.apk dist/Nala.apk
   ```

3. En [GitHub Releases](https://github.com/felipendelicia/nala/releases), adjuntá `Nala.apk` y `Nala-Linux-x64.tar.gz` a la publicación del commit compilado. Usá el tag `vX.Y.Z` con la misma versión de los paquetes. Las publicaciones preliminares también se ofrecen cuando se publican con ese formato.

Nala busca un paquete para su plataforma en las publicaciones del repositorio y verifica su tamaño y SHA-256 con los datos de GitHub antes de usarlo. En Linux el lanzador mantiene los archivos de la versión en el directorio de instalación. Los cuadernos se guardan en el directorio de datos de la aplicación.
