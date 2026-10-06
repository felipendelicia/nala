# Conectar Nala con Google Drive

La versión pública incluye el motor y la pantalla de sincronización, pero no tiene clientes OAuth configurados. El editor y el guardado local funcionan sin Google. Para habilitar Drive hay que registrar Nala en un proyecto de Google Cloud y compilar con los identificadores de ese proyecto.

## Registro

1. Crear un proyecto en Google Cloud y habilitar Google Drive API.
2. Configurar la pantalla de consentimiento de Google Auth Platform. Si permanece en modo de prueba, agregar las cuentas que van a usar Nala como usuarios de prueba.
3. En ese mismo proyecto, crear un cliente OAuth Android para el paquete `com.felipe.apuntes` y la huella SHA-1 del certificado que firma el APK.
4. Crear también un cliente OAuth de aplicación web. Su identificador se pasa a Google Sign-In Android como `GOOGLE_WEB_CLIENT_ID`; el secreto web no se usa ni se distribuye.
5. Crear un cliente OAuth de aplicación de escritorio para Linux. Pasar su identificador y, si Google lo proporciona, su secreto de cliente de escritorio. Linux abre el navegador del sistema, usa PKCE y recibe el callback en una dirección de loopback con puerto aleatorio.

Todos los clientes deben pertenecer al mismo proyecto para compartir la identidad de la app en Drive. El permiso solicitado es `drive.file`, junto con identificación básica de la cuenta; los archivos propios de Nala se marcan con `appProperties.application=nala-v1`. Las carpetas dentro de la biblioteca se guardan como metadatos de Nala, dentro de una carpeta Drive llamada Nala.

La huella del APK de prueba actual es:

```text
08:CA:83:E6:DC:41:02:14:76:E3:81:14:59:6E:00:B9:4B:35:2D:6D
```

Una compilación con otra clave necesita registrar su propia huella; la clave de desarrollo no está en este repositorio.

## Compilación

Crear `config.local.json` en la raíz del proyecto, con las claves siguientes y los valores reales obtenidos de Google:

```json
{
  "GOOGLE_WEB_CLIENT_ID": "",
  "GOOGLE_DESKTOP_CLIENT_ID": "",
  "GOOGLE_DESKTOP_CLIENT_SECRET": ""
}
```

Este archivo está excluido de Git. No pegar tokens ni contraseñas de la cuenta ahí. Las credenciales de usuario Linux se guardan en el llavero del sistema; si no está disponible, la sesión funciona sólo en memoria y pide conectar otra vez al reiniciar. Android usa Google Sign-In del dispositivo.

```sh
tool/flutter-safe build apk --release --target-platform android-arm64 --dart-define-from-file=config.local.json
tool/flutter-safe build linux --release --dart-define-from-file=config.local.json
```

Los identificadores de cliente y el secreto de cliente instalado forman parte del binario: una app instalada no puede proteger un secreto de servidor. Nunca distribuir un secreto de cliente web ni una cuenta de servicio.

## Comprobación con dos dispositivos

Conectar la misma cuenta desde la tablet y la PC. Crear una carpeta, escribir en un apunte y agregar un PDF y un comentario de voz. Esperar “Sincronizado con Drive” y comprobar la reapertura en el otro dispositivo. Desconectar la red, editar el mismo apunte en ambos y volver a conectarlos: las dos ramas deben aparecer como versiones en la biblioteca. Comprobar también desconexión, revocación del permiso y cambio de cuenta.

La sincronización comienza al conectar y al volver a la app. Agrupa guardados durante dos segundos, consulta cambios cada treinta segundos mientras está activa y reintenta fallos respetando la espera del servidor. Desconectar conserva la biblioteca y sus pendientes. La primera cuenta adopta los apuntes locales dejando el original; otras cuentas tienen bibliotecas separadas. Un avance remoto se aplica en el editor después de guardar y soltar el lápiz. Si hay ramas concurrentes, conserva la edición actual y muestra ambas versiones al volver a la biblioteca.

Las pruebas automáticas usan dos SQLite reales y archivos de recursos reales; simulan únicamente Google y el sistema de credenciales. Cubren conflictos, recursos, carpetas, paginación, respuestas perdidas, reanudación, revocación y cambios de cuenta. La prueba real entre tablet y PC sigue pendiente porque todavía no hay un proyecto OAuth configurado.

Referencias oficiales: [OAuth de aplicaciones instaladas](https://developers.google.com/identity/protocols/oauth2/native-app), [subidas reanudables de Drive](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [propiedades privadas de archivos](https://developers.google.com/workspace/drive/api/guides/properties).
