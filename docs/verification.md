# Nala 0.1.0 — versión de prueba, 2026-10-06

Se generaron y comprobaron estos archivos en la PC de Felipe:

- `dist/Nala.apk`: compilación Android debug, nombre Nala, mínimo Android 7 (API 24), target API 36 y firma APK v2 válida. El archivo entregado conserva el SHA-256 de la salida de Flutter. Felipe confirmó posteriormente que esta versión funciona bien en la Samsung Tab S10.
- `dist/Nala-Linux/`: compilación Linux x64 release completa, con sus bibliotecas y recursos.
- `dist/Abrir-Nala.sh`: abre la versión de escritorio. Entrada **Nala** instalada en el menú de aplicaciones y validada con `desktop-file-validate`.

Pasaron las 28 pruebas unitarias y la prueba de integración en Linux que crea un cuaderno, cierra el repositorio y vuelve a abrirlo conservando su título. La versión release se abrió en una ventana de 1280 × 720 y abrió su base SQLite real; el proceso seguía activo al terminar la verificación.

Las compilaciones y pruebas se ejecutaron de a una en servicios de systemd con un límite total de 2300 MiB de RAM, 256 MiB de swap y dos CPU. Android terminó en unos 39 segundos, con un pico registrado de 1.7 GiB y sin usar swap. Linux release terminó en unos 38 segundos. No se registraron nuevos eventos de falta de memoria en el kernel durante estas comprobaciones. `tool/flutter-safe` conserva estos límites para las siguientes tareas e impide dos ejecuciones simultáneas del mismo proyecto.

Esta entrega permite probar cuadernos con guardado local y el editor. Importar/exportar PDF, sincronizar con Drive y validar el lápiz físico en la tablet siguen pendientes. No representa la finalización del plan de implementación completo.

## Publicación en GitHub y checkpoint de PDF

El repositorio público `felipendelicia/nala` conserva el historial de código. La versión de prueba [v0.1.0](https://github.com/felipendelicia/nala/releases/tag/v0.1.0) distribuye el APK y el paquete Linux del commit `c440928527417d2fbad1a8b6d4ff4e4d58c6313d`; se verificó que los archivos entregados coinciden con las salidas de esa compilación. Estos binarios todavía no incluyen PDF.

El código de PDF se publica como trabajo en curso junto con sus fixtures y pruebas. La suite de 36 pruebas unitarias pasó en Linux. El análisis estático no encontró problemas. El test nativo `integration_test/pdf_round_trip_test.dart` todavía no completó la verificación: la ejecución más reciente terminó con código 79, los casos fueron reportados como “did not complete” y Flutter mostró un `PathNotFoundException` durante la finalización del listener temporal. La causa está pendiente de investigación; no se afirma que el flujo completo de PDF esté validado. El selector Android de guardado también queda pendiente de una prueba física.

Los hashes de los binarios publicados son:

```text
c9c6c1e0baccda067c9e85feff9d752c8417daeb4a5d33ad79ea2ce0608fba8d  Nala.apk
65ddaaaccf74ed1bb1f8a76793c8c237236efcd1434b24d4bbc8c1422fa97d10  Nala-Linux-x64.tar.gz
```
