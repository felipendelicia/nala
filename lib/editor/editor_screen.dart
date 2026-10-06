import 'package:flutter/material.dart';
import '../document/notebook.dart';
import '../ui/app_theme.dart';
import 'editor_controller.dart';
import 'paper_canvas.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.controller});
  final EditorController controller;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  bool allowPop = false, closing = false;
  Future<void> close() async {
    if (closing) return;
    closing = true;
    try {
      await widget.controller.flush();
      if (!mounted) return;
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tus últimos cambios todavía no se guardaron. Reintentá antes de salir.',
            ),
          ),
        );
    } finally {
      closing = false;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final page = controller.notebook.pages.first;
      return PopScope(
        canPop: allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) close();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Volver a mis apuntes',
              onPressed: close,
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(controller.notebook.title),
            actions: [
              IconButton(
                tooltip: 'Deshacer',
                onPressed: controller.canUndo ? controller.undo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Rehacer',
                onPressed: controller.canRedo ? controller.redo : null,
                icon: const Icon(Icons.redo),
              ),
              DropdownButton<PaperPattern>(
                value: page.background.pattern,
                items: PaperPattern.values
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(paperLabel(p.index)),
                      ),
                    )
                    .toList(),
                onChanged: (p) {
                  if (p != null)
                    controller.apply(
                      (book) => book.copyWith(
                        pages: [
                          page.copyWith(background: PageBackground.paper(p)),
                        ],
                      ),
                    );
                },
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Column(
            children: [
              if (controller.savingError != null)
                MaterialBanner(
                  content: const Text(
                    'No se pudo guardar. Tus cambios siguen en memoria.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: controller.retrySave,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  controller.saving
                      ? 'Guardando…'
                      : 'Guardado en este dispositivo',
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: FittedBox(
                      child: PaperCanvas(
                        page: page,
                        tool: EditorTool.pen,
                        onStroke: (stroke) => controller.apply(
                          (book) => book.copyWith(
                            pages: [
                              page.copyWith(strokes: [...page.strokes, stroke]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
