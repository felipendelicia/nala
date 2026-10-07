# Nala: editor continuo y nueva identidad visual

Felipe quiere bloquear el movimiento horizontal además del zoom, un resaltador más ancho por defecto, una mejora visual sustancial, compartir directamente el PDF de trabajo, recorrer las hojas bajando y mover apuntes entre carpetas. La latencia de escritura tiene prioridad sobre todas las decisiones visuales. Se conserva la autorización de trabajo autónomo y publicación: no se repiten los pasos de aprobación rutinarios.

## Comportamiento

Las hojas forman una tira vertical, con 32 puntos de separación y alineación centrada en el ancho máximo del documento. La rueda desplaza; Ctrl+rueda hace zoom. El dedo desplaza y dos dedos acercan. Se mantienen botones/índice para saltar. Un salto mueve la cámara a la página conservando la escala; ajustar hoja/ancho sigue siendo explícito. Cada página conserva sus dimensiones, tinta y comentarios propios. Dibujar en una separación no crea tinta y un trazo pertenece a la hoja donde empezó. El índice activo sigue la hoja bajo el centro de la vista cuando se navega.

El bloqueo horizontal ignora el componente X de desplazamiento y evita traslación X al pellizcar. El vertical permanece libre. El bloqueo de zoom es independiente. Los botones de ajuste son acciones explícitas; no se recentra por una muestra de lápiz o por un cambio de índice.

La geometría de la tira se calcula al cambiar el documento. Se buscan por altura las hojas visibles y sólo esas montan PaperCanvas/PDF. Los fondos vecinos mantienen la caché limitada existente. Las muestras de tinta no reconstruyen la interfaz ni las hojas. La primera muestra y todas las siguientes se notifican inmediatamente, sin temporizador ni animaciones. Los controles que alteran coordenadas cancelan un gesto incompleto.

Lápiz y resaltador tienen color y grosor independientes: lápiz inicial 2.5 pt grafito, resaltador inicial 14 pt amarillo. Cambiar una herramienta y volver recupera sus ajustes. El resaltador conserva presión uniforme.

Compartir PDF crea una instantánea de lo guardado sin abrir un selector de destino. Android abre ACTION_SEND con PDF, content URI de FileProvider y permiso temporal de lectura. Linux ofrece copiar el archivo PDF al portapapeles de archivos o abrir un correo con el adjunto; no envía mensajes automáticamente. Exportar sigue disponible para guardar una copia. Los archivos compartidos son temporales privados, nombres saneados, sesiones únicas, limpieza de sesiones anteriores a 24 horas. Cancelar/deshabilitar/doble toque no produce dos entregas; errores dejan las notas intactas. Mientras se prepara la instantánea se puede seguir escribiendo.

Cada tarjeta de apunte muestra Opciones de apunte con Renombrar y Mover a…. El selector existente ofrece raíces/subcarpetas y se verifica persistencia. No se agregan arrastres ambiguos de biblioteca.

## Dirección visual

Paleta: bosque #183E35, verde Nala #24584B, verde claro #DCECE5, papel #FFFFFF, fondo frío #F1F5F6, tinta #20343B. Manrope (Google Fonts/OFL, incluida offline) para interfaz; DejaVu permanece para exportaciones Unicode. Tipografía de títulos 28–32 px, texto 14–16 px y controles mínimos 44 px.

Biblioteca: navegación lateral bosque, marca con la perrita, título de carpeta y recuento, búsqueda separada, acciones claras y miniaturas grandes con aspecto de papel. Las opciones de cada apunte son visibles. Editor: cabecera blanca con título/lectura/compartir; herramientas agrupadas en un estuche con muestras de color y ancho; superficie gris fría, hojas blancas con sombra discreta y separación/número; pie compacto con estado, navegación y bloqueos. No hay animaciones durante escritura ni fondos decorativos costosos. En ventanas pequeñas las herramientas se desplazan horizontalmente y las acciones secundarias se agrupan; no desbordan con texto ampliado.

## Validación y límites

Pruebas de cámara/bloqueos, scroll y escritura en la segunda página, tamaños mixtos, separación sin tinta, miles de páginas con widgets visibles limitados, parámetros independientes, compartir con PDF real y canales nativos simulados, fallos de compartir y movimiento persistente entre carpetas. Inspección de capturas Linux/tablet simulada, suite completa y pruebas nativas. Builds Android/Linux secuenciales con tool/flutter-safe.

La sensación física y latencia del S Pen requieren la Tab S10. No se afirma equivalencia física con Notewise. Drive no cambia su configuración externa.

Referencias de implementación: [FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider), [Manrope/OFL](https://github.com/google/fonts/tree/main/ofl/manrope). Linux no tiene un panel general de compartir equivalente al de Android; se presentan destinos disponibles con nombres explícitos.

## Ampliaciones del usuario

Se agrega tema claro/oscuro/sistema con preferencia persistente. Se oscurecen biblioteca, barras, controles y superficie del editor; las hojas mantienen los colores del documento/PDF. El logo definitivo es la silueta blanca sobre negro que el usuario aprobó explícitamente (adjunto e66b4419), incorporada tal cual. Se regeneran iconos de Android y el icono Linux.
