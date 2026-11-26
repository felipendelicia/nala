import 'package:flutter/material.dart';
import '../document/notebook.dart';
import '../ui/app_theme.dart';

typedef NotebookDraft = ({String title, PaperPattern pattern});

class NotebookDialog extends StatefulWidget {
  const NotebookDialog({super.key});
  @override
  State<NotebookDialog> createState() => _NotebookDialogState();
}

class _NotebookDialogState extends State<NotebookDialog> {
  final title = TextEditingController();
  var pattern = PaperPattern.grid;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuevo cuaderno'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre del cuaderno',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PaperPattern>(
              initialValue: pattern,
              decoration: const InputDecoration(labelText: 'Tipo de hoja'),
              items: PaperPattern.values
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(paperLabel(p.index)),
                    ),
                  )
                  .toList(),
              onChanged: (p) {
                if (p != null) setState(() => pattern = p);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (title: title.text, pattern: pattern)),
        child: const Text('Crear'),
      ),
    ],
  );
}
