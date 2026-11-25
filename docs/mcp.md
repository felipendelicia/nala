# Conector MCP local de Nala

El conector comparte todos los cuadernos visibles de la biblioteca activa de Nala en Linux, incluso los que están en carpetas. Consulta la copia local cada vez que se usa una herramienta. Los apuntes de la tablet aparecen cuando llegan a esa copia por la sincronización habitual.

## Instalar en Codex

Usá Python 3.11 o posterior, `uv` y el CLI de Codex. Instalá `poppler-utils` en Linux si usás cuadernos con PDF y querés consultar su texto y sus imágenes de página. Ejecutá estos comandos desde la raíz de este repositorio.

```sh
uv --directory mcp sync --locked
codex mcp add nala -- "$(command -v uv)" --directory "$(pwd -P)/mcp" run --locked --offline python -m nala_mcp
codex mcp get nala
```

Codex lanza el conector por entrada y salida estándar y lo registra para sus sesiones locales en esta PC. Abrí un chat local nuevo y usá `/mcp` para comprobar que aparece `nala`. Si el escritorio todavía muestra los servidores anteriores, usá la opción de reiniciar de la configuración MCP. [Guía de MCP de Codex](https://learn.chatgpt.com/docs/extend/mcp?surface=app#connect-codex-to-an-mcp-server)

Para usar otra carpeta de datos, agregá `--data-root /ruta/a/los/datos` después de `nala_mcp` en el comando registrado. La ruta habitual en Linux es `~/.local/share/com.felipe.apuntes`, o su equivalente bajo `XDG_DATA_HOME`.

## Consultar apuntes

Podés pedirle a Codex «Mostrame qué cuadernos tengo en Nala» o «Buscá lo que anoté sobre derivadas y citame el cuaderno y la página».

| Herramienta | Qué devuelve |
| --- | --- |
| `list_notebooks` | Título, materia, carpeta y cantidad de páginas de los cuadernos. |
| `list_pages` | Páginas en el orden de Nala, con sus identificadores y una marca de escritura manuscrita. |
| `search` | Fragmentos que coinciden con una búsqueda, con cuaderno y página. |
| `fetch` | Texto disponible de una página, con su cita. |
| `view_page` | Imagen de una página para leer tinta manuscrita, gráficos o diagramas. |

Los resultados paginados incluyen `next_offset`. Las referencias incluyen `revision_id` para identificar la versión visible exacta cuando hay un conflicto o la numeración de páginas cambia. Si la versión ya salió de la biblioteca activa, volvé a listar o buscar la página.

La búsqueda incluye títulos, materias, carpetas, texto insertado, comentarios, texto original de PDF y transcripciones guardadas que coincidan con la página actual. Para un manuscrito sin transcripción, Codex puede abrir las páginas como imágenes. Los PDF protegidos por contraseña pueden quedar disponibles solo a través de sus anotaciones.

## Datos y mantenimiento

Las cinco herramientas son de solo lectura. El conector usa SQLite en modo de solo lectura y muestra las versiones visibles, con el mismo criterio de borrado que Nala. El proceso consulta lo que ya está guardado en tu PC y el modelo recibe los fragmentos o las imágenes que solicita.

Codex ejecuta el código de `mcp/nala_mcp/` directamente desde este repositorio. Después de actualizarlo, volvé a cargar el conector en Codex. Si cambió `mcp/uv.lock`, ejecutá primero `uv --directory mcp sync --locked`. Para quitar el acceso, ejecutá `codex mcp remove nala`.

```sh
uv --directory mcp run --locked --offline python -m unittest discover -v
```

Las pruebas usan bibliotecas temporales. Incluyen visibilidad de cambios guardados, borrados y conflictos, además de una sesión MCP real por entrada y salida estándar.
