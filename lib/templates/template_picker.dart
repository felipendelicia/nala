import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../editor/paper_background.dart';
import 'template_store.dart';

Future<PageTemplate?> showTemplatePicker(
  BuildContext context, {
  required TemplateStore store,
}) => showDialog<PageTemplate>(
  context: context,
  builder: (_) => _TemplatePicker(store: store),
);

class _TemplatePicker extends StatefulWidget {
  const _TemplatePicker({required this.store});
  final TemplateStore store;
  @override
  State<_TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<_TemplatePicker> {
  List<PageTemplate>? templates;
  bool importing = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.store.load();
      if (mounted) {
        setState(() {
          templates = loaded;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo leer tu biblioteca de plantillas.');
      }
    }
  }

  Future<void> _import(bool pdf) async {
    setState(() {
      importing = true;
      error = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          pdf
              ? const XTypeGroup(
                  label: 'PDF',
                  extensions: ['pdf'],
                  mimeTypes: ['application/pdf'],
                )
              : const XTypeGroup(
                  label: 'Imágenes',
                  extensions: ['png', 'jpg', 'jpeg'],
                  mimeTypes: ['image/png', 'image/jpeg'],
                ),
        ],
      );
      if (file == null || !mounted) return;
      final name = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final bytes = await file.readAsBytes();
      if (pdf) {
        await widget.store.importPdf(bytes, name: name);
      } else {
        await widget.store.importImage(bytes, name: name);
      }
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo importar. Usá un PDF sin contraseña o una imagen PNG/JPEG válida de hasta 50 MB.',
        );
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _remove(PageTemplate template) async {
    try {
      await widget.store.remove(template.id);
      await _load();
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo eliminar esa plantilla.');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Plantillas y portadas'),
    content: SizedBox(
      width: 700,
      height: MediaQuery.sizeOf(context).height * .62,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: importing ? null : () => _import(true),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Importar PDF'),
              ),
              OutlinedButton.icon(
                onPressed: importing ? null : () => _import(false),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Importar imagen'),
              ),
            ],
          ),
          if (importing)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: templates == null
                ? Center(
                    child: error == null
                        ? const CircularProgressIndicator()
                        : TextButton(
                            onPressed: _load,
                            child: const Text('Reintentar'),
                          ),
                  )
                : LayoutBuilder(
                    builder: (context, size) => GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (size.maxWidth / 150).floor().clamp(
                          1,
                          5,
                        ),
                        childAspectRatio: .66,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: templates!.length,
                      itemBuilder: (context, index) {
                        final template = templates![index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: importing
                                ? null
                                : () => Navigator.pop(context, template),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: TemplatePreview(
                                      template: template,
                                      store: widget.store,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 10,
                                    right: 6,
                                    bottom: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          template.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (!template.builtIn)
                                        IconButton(
                                          tooltip: 'Eliminar plantilla',
                                          onPressed: importing
                                              ? null
                                              : () => _remove(template),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: importing ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
    ],
  );
}

class TemplatePreview extends StatefulWidget {
  const TemplatePreview({
    super.key,
    required this.template,
    required this.store,
  });
  final PageTemplate template;
  final TemplateStore store;
  @override
  State<TemplatePreview> createState() => _TemplatePreviewState();
}

class _TemplatePreviewState extends State<TemplatePreview> {
  Future<Uint8List>? preview;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TemplatePreview old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id) _load();
  }

  void _load() {
    final id = widget.template.coverAssetId;
    preview = id == null ? null : widget.store.assets.read(id);
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: widget.template.width / widget.template.height,
    child: preview == null
        ? FittedBox(
            child: SizedBox(
              width: widget.template.width,
              height: widget.template.height,
              child: CustomPaint(
                painter: PaperBackgroundPainter(
                  widget.template.background.pattern!,
                ),
              ),
            ),
          )
        : FutureBuilder<Uint8List>(
            future: preview,
            builder: (context, state) => state.hasData
                ? Image.memory(state.data!, fit: BoxFit.fill)
                : ColoredBox(
                    color: Colors.white,
                    child: Center(
                      child: Icon(
                        state.hasError
                            ? Icons.broken_image_outlined
                            : Icons.image_outlined,
                        color: Colors.grey,
                      ),
                    ),
                  ),
          ),
  );
}
