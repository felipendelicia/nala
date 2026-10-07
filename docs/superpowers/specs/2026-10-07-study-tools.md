# Nala 0.5 — herramientas y estudio

Felipe pidió incorporar autónomamente las nueve mejoras propuestas: formas/regla, selección completa, imágenes/texto, lápices favoritos, pestañas/vista dividida, plantillas/portadas, búsqueda, audio ligado a trazos y tarjetas con repetición espaciada. Esta instrucción autoriza resolver diseño, ejecución y verificaciones sin nuevas aprobaciones intermedias.

## Comportamiento

- Formas: línea, rectángulo y elipse editables como tinta vectorial; mantener la punta reconoce formas; regla con ángulo y guía para rectas.
- Selección: conserva mover/borrar y suma copiar, cortar, duplicar, pegar entre cuadernos, escala y color. Incluye objetos de texto e imagen.
- Objetos: cuadros de texto editables e imágenes PNG/JPEG con posición y tamaño. Persisten, se sincronizan como recursos por hash y salen en PDF.
- Favoritos: configuraciones de herramienta/color/grosor guardadas por dispositivo y accesibles desde la barra.
- Espacio de trabajo: documentos en pestañas; vista de dos documentos con navegación independiente y un solo propietario de entrada/audio por panel activo.
- Plantillas: hojas Cornell, agenda semanal, fondos PDF/imagen y portadas; biblioteca persistida de plantillas propias.
- Búsqueda: títulos, materias, comentarios, texto insertado y texto original de PDF. Reconocimiento manuscrito español en Android con ML Kit, procesamiento local después de descargar su modelo; Linux ofrece OCR local cuando hay un motor disponible. La interfaz indica disponibilidad y permite editar el texto reconocido. Nunca inventa resultados.
- Audio de clase: inicio explícito, trazos con grabación y posición temporal, detener/guardar al abandonar la sesión, tocar la tinta en lectura para escuchar desde ese momento. Reproducción desde una posición sin modificar el recurso original.
- Estudio: preguntas/respuestas persistidas dentro del cuaderno, creación desde texto/selección, mostrar respuesta y valorar Otra vez/Difícil/Bien/Fácil para programar próxima revisión.

## Compatibilidad y límites

Cuadernos previos siguen abriendo: campos nuevos opcionales y valores por defecto. Conservar originales PDF, tinta vectorial, comentarios, versiones y cola de sincronización. Los recursos nuevos se validan por hash antes de aceptar una revisión. No usar cuentas ni servicios pagos obligatorios. No grabar micrófono en verificaciones automáticas. Flutter siempre se ejecuta secuencialmente con tool/flutter-safe: 2300 MiB RAM, 256 MiB swap, dos CPU. Entregar Android ARM64 y Linux x64 con pruebas y documentación actualizadas; publicación externa no forma parte de este pedido.

## Arquitectura

Extender el documento con objetos de página, grabaciones y tarjetas. Separar transformaciones, geometría, favoritos, búsqueda y estudio en archivos específicos. Mantener EditorController como autoridad de guardado/revisión y usar su apply para toda edición. El espacio de trabajo se ocupa de pestañas y foco; cada editor conserva su cámara. La búsqueda trabaja sobre instantáneas y caches por contenido, sin reemplazar ediciones posteriores.
