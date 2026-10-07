# Nala: elementos, enlaces, imágenes, barra, backup y LaTeX

La autorización del usuario es implementar estas seis mejoras autónomamente. La entrega será Nala 0.6.0 para Android ARM64 y Linux x64. Conservamos el encabezado compacto, los apuntes existentes y la apariencia en grises.

## Objetos de página

`PageObjectKind.latex` conserva el código en `text` y una representación PNG transparente en `assetId`. Los objetos agregan `originalAssetId` (imagen sin recortar), `opacity` (0..1), `locked` y `link` (`PageLink` con `notebookId` y `pageId`). Los campos nuevos son opcionales; los documentos antiguos siguen abriendo. `copyWith` permite actualizar o quitar referencias. La imagen original y la representación entran en sincronización, exportación y backup.

La edición de imágenes permite recortar, restablecer el original, cambiar opacidad y bloquear. Los objetos bloqueados no cambian mediante selección, borrado o transformaciones. Hay una acción explícita para desbloquearlos. Los recortes producen un nuevo recurso sin sobrescribir el original.

Las fórmulas se escriben con LaTeX matemático, tienen vista previa y pueden editarse después. El código inválido muestra un error y no se guarda. Se renderizan sin servicios externos y aparecen en PDF, copias y elementos reutilizables.

## Elementos y enlaces

La biblioteca de elementos persiste grupos de trazos y objetos seleccionados, con nombre, búsqueda, renombrado y eliminación. Insertar genera IDs nuevos, conserva imágenes y fórmulas, libera bloqueos y elimina referencias a grabaciones del apunte original. Se adapta al tamaño de la hoja y se puede mover después.

Un enlace lleva a una página de cualquier apunte de la biblioteca. Puede crearse como texto o agregarse a un objeto. El selector permite elegir cuaderno y página. Abrirlo reutiliza la pestaña ya abierta y navega a la página incluso si esa pestaña existía; un destino ausente produce un mensaje recuperable.

## Barra

La barra permite elegir y ordenar accesos y colocarla arriba, a la izquierda o a la derecha. Los ajustes persisten por biblioteca y se comparten entre paneles. Más herramientas siempre queda accesible. La vista de lectura mantiene su altura actual.

## Backup

Un archivo `.nala.zip` contiene cuadernos y versiones en conflicto, carpetas, todos sus recursos (incluido audio), plantillas, elementos y preferencias locales. Un manifiesto versionado incluye tamaños y SHA-256. La exportación lee una instantánea coherente. La importación valida todo antes de modificar la biblioteca: rechaza rutas extrañas, duplicados, archivos faltantes, hashes incorrectos, referencias inválidas y archivos excesivos.

Restaurar crea una carpeta de recuperación y copias con IDs nuevos; conserva los apuntes existentes. Los enlaces internos se remapean a las copias. Los recursos se deduplican. El lote de documentos y carpetas se importa en una transacción SQLite. Los registros y preferencias se fusionan/recuperan sin perder los anteriores y se informa cualquier limitación concreta. Las credenciales y la identidad del dispositivo no se exportan. Los diálogos explican qué incluye el archivo y muestran una previsualización antes de restaurarlo.

## Restricciones de entrega

Todas las ejecuciones Flutter son seriales con `tool/flutter-safe`, manteniendo el límite de memoria existente. No se usan apuntes personales, micrófono real ni cuentas reales en pruebas. No se cambian la firma Android ni los límites de Gradle. Las pruebas cubren persistencia, PDF, navegación, restauración corrupta y flujo nativo. Se guardan los instaladores 0.5.1 antes de reemplazar `dist`.
