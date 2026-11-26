<img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" alt="" width="64" height="64">

# Nala

Cuadernos digitales para tomar apuntes a mano, anotar archivos PDF y estudiar en la Samsung Galaxy Tab S10 y en Linux. Nala guarda los cambios en el dispositivo mientras escribís. Si usás ambos equipos, podés sincronizar la biblioteca con tu propio servidor.

## Descargar e instalar

La versión de prueba actual es la **0.7.13**. [Notas de la versión](https://github.com/felipendelicia/nala/releases/tag/v0.7.13) · [Todas las versiones](https://github.com/felipendelicia/nala/releases)

| Plataforma | Descarga | Instalación |
| --- | --- | --- |
| Android ARM64 · Tab S10 | [Nala.apk](https://github.com/felipendelicia/nala/releases/download/v0.7.13/Nala.apk) | Abrí el APK y seguí los pasos del instalador de Android. Si el sistema lo pide, habilitá la instalación desde la app con la que abriste el archivo. |
| Linux x64 | [Nala-Linux-x64.tar.gz](https://github.com/felipendelicia/nala/releases/download/v0.7.13/Nala-Linux-x64.tar.gz) | Descomprimí el paquete y ejecutá `Abrir-Nala.sh`. Dejá el lanzador junto a la carpeta `Nala-Linux/`. |

### Actualizar desde Nala

Si ya tenés el actualizador, abrí **Ajustes → Buscar actualizaciones** y tocá **Instalar** cuando aparezca una versión nueva. En la tablet, confirmá en el instalador de Android. En Linux, cerrá Nala y volvé a abrirla con el lanzador. La versión instalada figura debajo de **Buscar actualizaciones**.

## Qué podés hacer

- **Escribir y organizar apuntes.** Usá el S Pen con presión, resaltador y borrador, o editá con el ratón en la PC. Organizá tus cuadernos en carpetas desplegables y retomá los últimos que abriste desde **Recientes**.
- **Ganar espacio para escribir.** Activá **Pantalla completa** desde Ajustes o desde el menú del cuaderno para ocultar las barras del sistema. En Linux, usá **F11** para entrar y salir.
- **Anotar y compartir PDF.** Importá un PDF, escribí sobre él e intercalá hojas de apuntes. La exportación convierte cada hoja en una imagen y mantiene su tamaño y orientación. El PDF original y las anotaciones editables se conservan en Nala.
- **Preparar material de estudio.** Combiná plantillas, texto, imágenes, fórmulas LaTeX y hojas Markdown. Agregá comentarios, grabá clases con audio vinculado a la tinta y repasá con tarjetas de repetición espaciada.
- **Usar la biblioteca en dos equipos.** El guardado local funciona sin conexión. Podés configurar la sincronización en **Ajustes → Servidor privado** y crear o restaurar una copia desde **Backup de la biblioteca**.

## Guías

- [Edición, herramientas de estudio y ChatGPT](docs/study-tools.md)
- [Elementos reutilizables, enlaces entre hojas y copias de seguridad](docs/notebook-workflow.md)
- [Configurar el S Pen](docs/spen.md)
- [Conectar la tablet y la PC a un servidor privado](docs/server-setup.md)
- [Consultar apuntes en Codex con el conector MCP local](docs/mcp.md)

## Compilar y probar

El proyecto usa Flutter y Dart. Se verificó con Flutter 3.47.6 y Dart 3.13.5. Desde Linux, con Flutter en el `PATH` y una sesión systemd de usuario, ejecutá estos comandos desde la raíz del repositorio.

```sh
tool/flutter-safe pub get
tool/flutter-safe build linux --release
tool/flutter-safe test --no-pub --concurrency=1
tool/flutter-safe build apk --release --target-platform android-arm64
```

La compilación de Linux aporta la biblioteca nativa PDFium que usan las pruebas de PDF. [Requisitos de compilación](docs/build-notes.md) · [Pruebas del servidor](docs/server-setup.md#pruebas-de-desarrollo) · [Cómo preparar una release](docs/releases/updates.md)
