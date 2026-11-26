# Servidor privado de Nala

Nala sincroniza cuadernos, carpetas y adjuntos entre la Tab S10 y Linux. Cada equipo guarda en una base local y envía los cambios al volver a conectarse. La primera carga requiere que confirmes el destino. Si dos equipos modifican el mismo cuaderno sin recibir el cambio del otro, la biblioteca muestra ambas versiones.

## Preparar el servicio

Desde `server/` en el repositorio o `Nala-Servidor/` en el paquete, construí e iniciá el servicio con Docker Compose. El volumen del servicio contiene la base SQLite, los archivos y el registro de credenciales.

```sh
docker compose up -d --build
docker compose ps
```

En el proxy HTTPS de tu servidor, dirigí la URL elegida a `127.0.0.1:8080`. Podés cambiar el puerto publicado con `NALA_HOST_PORT`. Los clientes necesitan llegar a esa URL desde sus redes habituales y confiar en su certificado. Preservá las rutas `/v1`, los encabezados de autenticación y los métodos `GET`, `HEAD`, `PUT` y `PATCH`. Configurá un límite por solicitud de al menos 64 MiB para las revisiones. Los adjuntos se suben por bloques de 4 MiB. Usá la URL HTTPS definitiva en Nala para evitar redirecciones.

## Conectar la Tab S10 y Linux

Creá una credencial por equipo. Cada comando devuelve una credencial distinta. Copiala directamente al dispositivo correspondiente.

```sh
docker compose exec nala nala-server token-create tablet
docker compose exec nala nala-server token-create pc
```

1. En la biblioteca, abrí **Ajustes → Servidor privado**. Escribí la URL `https://` y la credencial del equipo y tocá **Verificar conexión**.
2. Revisá el destino. Si el equipo ya tiene apuntes, elegí **Migrar y conectar** para incorporarlos. En una instalación nueva, elegí **Conectar** para descargar la biblioteca existente.
3. Repetí en el otro equipo con su propia credencial. Dejá Nala abierta durante la primera sincronización. El estado muestra los cambios pendientes y avisa al completar el envío.
4. Creá un cuaderno de prueba en un equipo y esperá a que aparezca editable en el otro. Probá una edición sin internet y volvé a abrir Nala con conexión para enviarla.

Cada dispositivo conserva su biblioteca local durante la migración. Subir una revisión que ya está presente conserva su identificador y evita duplicarla. Si tenés apuntes en ambos equipos, podés incorporar los dos catálogos. Para trasladar colecciones de plantillas, elementos reutilizables o preferencias, usá **Backup de la biblioteca**.

Si perdés un dispositivo, revocá su credencial desde el servidor. El otro equipo conserva su acceso.

```sh
docker compose exec nala nala-server token-revoke tablet
```

## Copias y recuperación

Hacé copias periódicas fuera del volumen del servicio. El destino debe ser privado, ya que el archivo incluye la biblioteca y el registro de acceso. Reemplazá `/ruta/absoluta/copias` por el directorio de copias del servidor y dale acceso de escritura al usuario `10001:10001` del contenedor.

```sh
docker compose run --rm --no-deps -v /ruta/absoluta/copias:/backups nala backup /backups/nala.tar.gz
```

Para probar una restauración, usá un proyecto de Compose separado con un volumen vacío y montá las copias en modo lectura. Para iniciar ese proyecto como segunda instancia, elegí un puerto distinto con `NALA_HOST_PORT`.

```sh
docker compose -p nala-recuperacion run --rm --no-deps -v /ruta/absoluta/copias:/backups:ro nala restore /backups/nala.tar.gz
NALA_HOST_PORT=8081 docker compose -p nala-recuperacion up -d
```

Al restaurar, el servidor emite una identidad nueva e invalida las credenciales de la copia. Generá una credencial nueva por dispositivo, verificá el destino y confirmá la incorporación de los apuntes locales cuando Nala lo pida.

## Pruebas de desarrollo

Desde la raíz del repositorio, ejecutá las pruebas del servidor y el recorrido de dos clientes Flutter. El recorrido utiliza dos bases SQLite temporales y el servicio HTTP en `127.0.0.1`.

```sh
python3 -m unittest discover -s server -v
tool/flutter-safe test --no-pub --concurrency=1 test/sync/server_round_trip_test.dart
```
