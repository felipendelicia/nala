# Nala: escritura y organización

Felipe autoriza implementar de forma autónoma las mejoras del editor. El objetivo es tomar apuntes universitarios en Tab S10 y Linux con escritura fluida, presión perceptible, lectura cómoda y organización jerárquica. La sincronización queda después de las funciones locales.

## Escritura

Cada muestra del lápiz amplía una geometría incremental y repinta únicamente la capa de tinta activa. No reconstruye la barra, el fondo PDF ni la lista de trazos guardados. La confirmación copia los puntos una sola vez. El trazo visible y el exportado comparten la misma fórmula de ancho y contorno. Los trazos antiguos conservan su curva de presión; los nuevos usan una curva expresiva ajustable. Mouse y resaltador usan ancho constante. Un suavizado causal ligero reduce ruido sin esperar muestras futuras; la punta conserva el último punto al terminar. Cancelar, salir o cambiar de herramienta descarta un trazo incompleto.

La validación automática comprueba la independencia de la capa activa y la conservación de presión y puntos. La fluidez física y la latencia de la Tab S10 requieren prueba del dispositivo; no se promete una cifra de fps a partir de pruebas debug.

## Lectura y vista

Modo lectura desactiva dibujo, borrado, selección, cambios de hoja y atajos de edición. Mantiene navegación, zoom, consulta de comentarios y exportación. Lápiz o mouse arrastran la página al leer. Ajustar hoja, ajustar ancho y porcentajes 50/75/100/125/150/200 se refieren a la escala de la hoja en el lienzo. Bloquear zoom conserva la escala frente a gestos, rueda y cambios de página; permite desplazar. Cambios de controles y avisos no recentran la hoja durante un trazo.

## Carpetas

Carpetas con identificadores estables y padre opcional se guardan en SQLite. La biblioteca muestra rutas, subcarpetas y apuntes del directorio actual. Crear, renombrar y mover apuntes o carpetas conserva los datos. Se rechazan ciclos, destinos inexistentes y borrado de carpetas no vacías. Los cuadernos antiguos quedan en la raíz. La búsqueda continúa disponible. Los cambios de ubicación de un cuaderno son revisiones del documento.

## Comentarios

Cada comentario pertenece a una página y tiene posición, texto y una grabación opcional. Marcadores en la hoja y una lista permiten consultar, editar y eliminar. La grabación empieza sólo al pulsar el botón de micrófono, muestra duración y controles de guardar/cancelar. Se detiene al cerrar la pantalla o suspender la app; nunca se graba en segundo plano. Android solicita permiso de micrófono y usa AudioRecord/MediaPlayer. Linux usa pw-record/pw-play ya instalados, con fallback arecord/aplay. No se instalan herramientas con sudo. Los archivos temporales se eliminan al cancelar y el audio confirmado se guarda por hash en el almacén local. Reproducción y grabación son mutuamente excluyentes. Lectura permite escuchar, sin editar.

## PDF y entrega

Resolver la prueba de flujo nativo pendiente: importar, dibujar, insertar hoja, exportar y reabrir. Los originales se conservan, las contraseñas quedan en memoria y la exportación prepara fondos a 200 dpi con tinta vectorial. Las compilaciones y pruebas se ejecutan de a una mediante tool/flutter-safe. Generar APK release de prueba y Linux release, incrementar versión, publicar código y binarios en el repositorio autorizado. Una revisión independiente final comprueba pérdida de datos, entradas canceladas, grabación y cambios de vista.

## Última etapa: Drive

Después de verificar los flujos locales se ejecutan las tareas de motor de sincronización y OAuth del plan inicial. Recursos de PDF y audio se incluyen por hash; las carpetas también deben viajar con sus documentos. La conexión real requiere credenciales OAuth del proyecto de Google Cloud. No se inventan credenciales ni se incluyen tokens en GitHub. Si faltan, se prepara la conexión configurable y se informa el requisito externo con el resto de la app funcionando.
