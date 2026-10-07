# Nala 0.6: más herramientas para los apuntes

## Elementos reutilizables

Seleccioná trazos, textos, imágenes o fórmulas con Selección. Abrí Más herramientas → Guardar elemento y escribí un nombre. Más herramientas → Elementos reutilizables abre tu biblioteca: podés buscar, renombrar, borrar o tocar un elemento para insertarlo. Cada inserción crea una copia independiente que se adapta a la hoja. Podés moverla, cambiar su tamaño o girarla con las herramientas de selección.

La biblioteca se guarda en el dispositivo y entra en el backup completo. Las imágenes y fórmulas mantienen sus recursos; las marcas de audio de un apunte quedan asociadas a ese apunte.

## Enlaces entre apuntes

Más herramientas → Enlace a otro apunte permite elegir un cuaderno y una página. Inserta un texto subrayado con el destino. Para agregar el enlace a una imagen, texto o fórmula existente, seleccioná ese objeto y elegí Enlazar selección. Abrir enlace navega a la página; Quitar enlace elimina esa asociación.

En modo lectura, tocá el objeto enlazado para abrir su destino. Arrastrar sobre él sigue desplazando la hoja. Si el apunte está abierto, Nala reutiliza su pestaña y conserva los cambios. Los enlaces se navegan dentro de Nala y se mantienen al restaurar un backup.

## Editar imágenes

Seleccioná una imagen y abrí Más herramientas → Editar imagen. Arrastrá sobre la vista previa para elegir el recorte; el control de opacidad permite usarla como referencia bajo la escritura. Guardar aplica el cambio. Después podés volver a recortar o usar Restablecer original. Los recursos originales se conservan y Deshacer permite volver al estado anterior.

Bloquear objetos fija los objetos seleccionados para que no se muevan ni borren con la selección. Desbloquear objetos libera los objetos de la hoja. Los trazos que dibujás encima siguen siendo editables.

## Fórmulas LaTeX

Más herramientas → Insertar fórmula LaTeX abre un editor con vista previa. Escribí código matemático como `\frac{a}{b}`, `\sqrt{x}`, `\sum_{i=1}^{n} i` o `\int_0^1 x^2\,dx`. Guardá cuando la vista previa muestre la fórmula deseada. Podés cambiar su tamaño con las herramientas de selección. El editor indica los errores de sintaxis antes de guardar.

Para cambiar una fórmula, seleccionála y abrí Editar fórmula. Se conserva su código y se genera una imagen transparente que aparece en la hoja, los elementos guardados, la sincronización y el PDF. La escritura y el renderizado funcionan localmente.

## Personalizar la barra

Más herramientas → Personalizar barra permite elegir los accesos visibles, arrastrarlos para ordenar y ubicar la barra arriba, a la izquierda o a la derecha. Guardar aplica los cambios a los paneles abiertos y conserva el ajuste para la próxima sesión. Restablecer recupera la distribución inicial.

Más herramientas queda siempre accesible y contiene los controles que hayas ocultado. En modo lectura, la barra de edición se oculta para dejar más espacio a la hoja.

## Backup completo y restauración

En la biblioteca, abrí su menú y elegí Backup de la biblioteca. Guardar backup crea un archivo `.nala.zip` con cuadernos e historial retenido, versiones en conflicto, carpetas, imágenes originales y recortadas, grabaciones, fórmulas, plantillas, elementos, favoritos y ajustes locales. Guardalo fuera de la carpeta de Nala para conservar una copia independiente.

Abrir backup comprueba el archivo y muestra su contenido. Recuperar copias crea los apuntes dentro de una carpeta de recuperación y conserva los actuales. Los enlaces entre cuadernos del backup apuntarán a las copias recuperadas. Podés elegir Recuperar ajustes y favoritos; los ajustes anteriores quedan respaldados y la apariencia recuperada se aplica al volver a abrir la aplicación.

Si la suma de elementos o plantillas supera la capacidad de su biblioteca, los apuntes se recuperan y Nala conserva ese registro entrante aparte, indicando su ubicación. Esos elementos o plantillas excedentes no se agregan a la biblioteca activa.

Los archivos dañados, incompletos o con recursos que no coinciden con sus hashes se rechazan antes de cambiar la biblioteca. Límites de esta versión: 128 MB por archivo, 64 MB por recurso y 256 MB de contenido total. Las credenciales y la identidad del dispositivo quedan fuera del backup.

## Instalación

`dist/Nala.apk` actualiza la versión Android anterior. En Linux, descomprimí el paquete completo y abrí `Abrir-Nala.sh`, junto a `Nala-Linux/`. La entrega 0.5.1 se conserva en `dist/previous-v0.5.1/`. Actualizá ambos dispositivos a 0.6 antes de editar estos campos nuevos: versiones anteriores pueden omitirlos al guardar.

Las herramientas anteriores de escritura, búsqueda, grabación, estudio, plantillas, comentarios y PDF siguen disponibles. Sus instrucciones están en [la guía anterior](study-tools.md).
