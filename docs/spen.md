# Lápiz y S Pen

En el editor, abrí **Ajustes del lápiz** (icono de ajustes al lado del grosor). La ventana **Lápiz y S Pen** guarda la respuesta a la presión, el suavizado, la herramienta del botón y su comportamiento. Estas preferencias pertenecen al dispositivo y se conservan al cerrar/reabrir la aplicación.

- **Mantener apretado:** usa la herramienta elegida y al soltar recupera la anterior. Por defecto es la goma.
- **Pulsar para alternar:** cada pulsación cambia entre la herramienta del botón y la que estabas usando.
- Herramientas: goma, resaltador, lápiz, selección o desactivado.
- Usá el botón con la punta cerca de la pantalla o apoyada. No requiere Bluetooth. Los comandos a distancia/Air Actions no forman parte de esta integración.
- Presión 100% y suavizado 0% son los valores iniciales para seguir la punta sin retraso añadido por filtros. Aumentá el suavizado si preferís corregir pequeñas vibraciones del trazo.

Cambiar de herramienta con el botón durante un trazo confirma su tramo anterior antes de continuar. Lectura y ventanas abiertas impiden cambios del botón; cancelar, perder foco o salir del editor restaura la herramienta temporal. La palma continúa sin mover la hoja mientras escribís.

## Renderizado y verificación

La tinta activa usa máscaras por mosaicos dentro de la zona visible, a resolución de pantalla. Los trazos cortos van directamente al lienzo. En trazos largos sólo se rasterizan los mosaicos tocados desde el cuadro anterior, conservando su contorno completo para evitar que el antialias engrose los bordes. Se aplica la transparencia una sola vez al componer la máscara, para conservar el resaltador al cruzarse. La caché se libera al confirmar/cancelar. La nota y el PDF conservan los puntos originales y los contornos vectoriales; no se guardan puntos predichos ni una imagen de la tinta.

La goma descarta candidatos por límites geométricos en caché y no revisa trazos ya borrados durante el gesto. Mover un trazo crea una nueva geometría y nuevos límites.

El puente Android informa cambios del botón y estado al tocar, con posiciones en el flujo de entrada normal de Flutter. Se evita procesar el mismo botón desde dos colas, para que muestras anteriores no deshagan una pulsación reciente. La integración existente de Flutter ya pide entrada sin agrupar; no se duplicó esa solicitud.

Referencias primarias: [MotionEvent y botones de Android](https://developer.android.com/reference/android/view/MotionEvent), [entrada de baja latencia](https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/advanced-stylus-features), [botón de lápiz en Flutter](https://api.flutter.dev/flutter/gestures/kPrimaryStylusButton-constant.html), [FlutterView del motor utilizado](https://github.com/flutter/flutter/blob/692136cb6582dbfc5af3fb33c2515a069f2f66d0/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/FlutterView.java), [AndroidTouchProcessor del mismo motor](https://github.com/flutter/flutter/blob/692136cb6582dbfc5af3fb33c2515a069f2f66d0/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/AndroidTouchProcessor.java).

Las pruebas de escritorio usan entradas sintéticas de lápiz: verifican dibujo, presión, contacto, cancelación, lectura, foco, persistencia y cambios de herramienta. No miden el recorrido físico punta-pantalla. La sensación y la entrega del botón por Samsung deben probarse en la Tab S10. Notewise sigue siendo la referencia de experiencia, sin afirmar equivalencia medida.

Medición de esta PC (GTK Linux, motor en modo debug): después de 8000 muestras, 48 cuadros con 8 muestras nuevas por cuadro, salida de 600×600 píxeles, orden alternado y lectura de píxeles. Mediana: **6.846 ms** incremental frente a **10.373 ms** dibujando todo el contorno (aproximadamente 34% menos); percentil 95: **14.455 ms** frente a **19.555 ms**. Esto compara el trabajo de rasterizado y lectura de una imagen en este equipo; no equivale a latencia del S Pen, tiempos de cuadros en la tablet ni una comparación con Notewise. El ensayo se reproduce en `integration_test/spen_fluency_test.dart` y genera `.dart_tool/spen-raster-benchmark.json`.
