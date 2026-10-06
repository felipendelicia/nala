# Estado de Nala — 2026-10-06

Nala se desarrolla para tomar apuntes universitarios con S Pen en Samsung Tab S10 y continuar en Linux. El nombre y el icono fueron elegidos a partir de la perrita de Felipe.

## Disponible en la primera versión de prueba

- Cuadernos con guardado local automático y recuperación al reabrir.
- Hojas blancas, rayadas, cuadriculadas y punteadas.
- Lápiz con presión, resaltador, borrador y selección para mover o eliminar trazos.
- Deshacer, rehacer, agregar hojas y navegación con dedos o mouse.
- Biblioteca con búsqueda y organización por materia.
- Versiones para Android y Linux. Felipe confirmó que la versión inicial funciona en la tablet.

## Trabajo de PDF incorporado al código

Importación del archivo original, fondos de página con caché limitada, páginas rotadas o protegidas, hojas de apuntes intercaladas y exportación con tinta vectorial sobre fondos a 200 dpi. La preparación de imágenes y la exportación usan workers. El guardado en Android usa el selector nativo de documentos.

Las pruebas unitarias de este trabajo pasaron; la comprobación completa del flujo en Linux y el selector físico en Android siguen en verificación. La primera versión descargable todavía corresponde al editor anterior a estos cambios.

## Orden de las próximas mejoras

1. Fluidez de escritura: reducir el trabajo por muestra del lápiz y mejorar la respuesta a la presión. Referencia de experiencia solicitada: Notewise.
2. Modo lectura, ajuste de hoja y ancho, porcentajes de zoom y bloqueo del zoom.
3. Comentarios de texto y grabaciones de voz. Se prevén marcadores vinculados a la hoja y una lista de comentarios.
4. Carpetas y subcarpetas con jerarquías de apuntes.
5. Sincronización automática con Google Drive, después de mejorar los flujos locales.

Estas mejoras son requisitos pendientes, no funciones ya entregadas. La sensación y la latencia real del lápiz requieren validación en la Tab S10; las pruebas de escritorio no las demuestran.

## Publicación

Repositorio público: [felipendelicia/nala](https://github.com/felipendelicia/nala). Incluye código, recursos, pruebas, documentación y el historial de desarrollo. Los compilados se distribuyen como versiones de prueba en Releases. Los cuadernos personales, bases locales, caches, SDK, tokens y claves de firma quedan fuera del repositorio.
