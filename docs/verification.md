# Nala 0.1.0 — versión de prueba, 2026-10-06

Se generaron y comprobaron estos archivos en la PC de Felipe:

- `dist/Nala.apk`: compilación Android debug, nombre Nala, mínimo Android 7 (API 24), target API 36 y firma APK v2 válida. El archivo entregado conserva el SHA-256 de la salida de Flutter. Todavía no se instaló ni se probó en la Samsung Tab S10.
- `dist/Nala-Linux/`: compilación Linux x64 release completa, con sus bibliotecas y recursos.
- `dist/Abrir-Nala.sh`: abre la versión de escritorio. Entrada **Nala** instalada en el menú de aplicaciones y validada con `desktop-file-validate`.

Pasaron las 28 pruebas unitarias y la prueba de integración en Linux que crea un cuaderno, cierra el repositorio y vuelve a abrirlo conservando su título. La versión release se abrió en una ventana de 1280 × 720 y abrió su base SQLite real; el proceso seguía activo al terminar la verificación.

Las compilaciones y pruebas se ejecutaron de a una en servicios de systemd con un límite total de 2300 MiB de RAM, 256 MiB de swap y dos CPU. Android terminó en unos 39 segundos, con un pico registrado de 1.7 GiB y sin usar swap. Linux release terminó en unos 38 segundos. No se registraron nuevos eventos de falta de memoria en el kernel durante estas comprobaciones. `tool/flutter-safe` conserva estos límites para las siguientes tareas e impide dos ejecuciones simultáneas del mismo proyecto.

Esta entrega permite probar cuadernos con guardado local y el editor. Importar/exportar PDF, sincronizar con Drive y validar el lápiz físico en la tablet siguen pendientes. No representa la finalización del plan de implementación completo.
