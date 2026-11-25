# Servidor privado de Nala

## Objetivo

Felipe quiere abrir los mismos apuntes en la Tab S10 y en Linux. Su servidor alojará la biblioteca central y tendrá un solo propietario. Nala guardará cada edición en el dispositivo y la enviará al servidor cuando pueda conectarse. Esto permite tomar apuntes en clase y recuperar la biblioteca en otro equipo.

## Enfoque y alojamiento

Felipe eligió usar un servidor que ya tiene. El diseño propone un servicio HTTP desplegable como contenedor OCI, con una URL HTTPS y almacenamiento persistente. Si el servidor ya tiene un proxy HTTPS, éste podrá publicar el servicio en una URL propia. El entorno concreto y el acceso para instalarlo se verifican antes del despliegue. El desarrollo y las pruebas de integración pueden ejecutarse en local.

`SyncEngine` ya usa `RemoteStore` para consultar y guardar revisiones, carpetas y archivos. El nuevo adaptador conectará el motor al servidor de Nala y la configuración **Servidor de Nala** reemplazará el acceso a Drive. El usuario ingresa la URL y una credencial revocable por dispositivo. El administrador del servidor genera las credenciales. El cliente comprueba el certificado HTTPS y guarda la credencial en el almacén seguro del sistema. Si ese almacén no está disponible, ofrece conectar por la sesión actual. La interfaz mostrará si hay cambios pendientes, si la biblioteca está sincronizada o si hace falta reconectar.

## Biblioteca y sincronización

- El servidor guarda carpetas, revisiones y sus archivos asociados. Esto incluye tinta, texto, enlaces, tarjetas, fórmulas, fondos PDF, imágenes originales y editadas, notas de voz y grabaciones. Las plantillas y los elementos que ya se insertaron viajan con el cuaderno. Las colecciones reutilizables, favoritos y ajustes del dispositivo se pueden trasladar con el backup completo de Nala.
- Una instancia del servicio usa SQLite y un directorio de archivos en un volumen persistente. Los clientes suben primero los archivos que referencia cada revisión. El servidor verifica el hash antes de hacer visible el archivo y acepta la revisión cuando todos sus recursos están disponibles. Repetir una operación confirmada con el mismo contenido produce el mismo resultado. Un identificador existente con contenido distinto genera un error.
- Los clientes conservan la cola de cambios en disco. La sincronización normal se activa al abrir o volver a la aplicación y al editar con la aplicación activa. La descarga inicial obtiene la biblioteca del servidor, incluidos los recursos que permiten abrirla offline. Las consultas y transferencias se pueden reanudar. El protocolo permite paginar revisiones y descargar cambios desde un cursor confirmado. Los archivos grandes se transfieren por bloques, incluidos los audios de clase.
- Cuando tablet y PC editan el mismo cuaderno sin conexión, se conservan ambas versiones. El cliente aplica un avance remoto al editor sólo cuando ha guardado sus cambios y el usuario ha soltado el lápiz. La sincronización incluye las marcas de borrado de carpetas. El cliente confirma el destino antes de enviar datos por primera vez o a un servidor cuya identidad cambió.

## Migración y recuperación

La primera conexión ofrece subir la biblioteca abierta que está disponible en el dispositivo. Si los dos equipos tienen apuntes distintos, ambos pueden aportar sus bibliotecas al mismo servidor. Se conservan identificadores, enlaces, revisiones retenidas y conflictos. Las operaciones repetidas y las revisiones que ya coinciden se reconocen por su identificador y contenido. Cada equipo conserva su biblioteca durante el proceso. La migración se confirma cuando el servidor reconoce los registros y archivos enviados.

Las bibliotecas de instalaciones anteriores que usaron Drive se pueden elegir a partir de sus copias locales. La sincronización anterior se detiene antes de migrar. Los apuntes que sólo existan en Drive deben descargarse a la biblioteca de origen con la versión anterior. Si el usuario cancela la primera carga, puede seguir editando offline. Un cambio de destino también suspende la transferencia hasta que el usuario elija explícitamente migrar su biblioteca al servidor nuevo. Cada cursor y estado de transferencia pertenece al servidor que lo emitió.

El servidor debe poder producir una copia recuperable y coherente de la base y sus archivos. La puesta en marcha contempla una copia periódica fuera de su volumen y una prueba de restauración en una instancia limpia. Una restauración invalida los cursores previos. Los dispositivos conservan su biblioteca offline y ofrecen incorporar explícitamente las revisiones locales a la instancia recuperada.

## Criterios de aceptación

1. Migrar una biblioteca de prueba con varios cuadernos, enlaces, PDF, imágenes y grabaciones. Conectar un cliente con una base limpia y comprobar que abre los cuadernos y sus recursos.
2. Editar sin red, cerrar y reabrir el cliente, recuperar la conexión y comprobar que los pendientes llegan al otro cliente. Simular dos ediciones del mismo cuaderno y comprobar que ambas versiones se conservan.
3. Interrumpir la subida de un archivo grande y reanudarla. Repetir la migración y comprobar que conserva los identificadores, el número de revisiones y los enlaces.
4. Verificar que una credencial revocada pierde acceso y que el backup del servidor se restaura en otra instancia. Ejecutar primero las pruebas con datos sintéticos y comprobar Android y Linux contra el servidor del usuario antes de dar la instalación por terminada.
