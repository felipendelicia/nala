import 'package:flutter/material.dart';

typedef TextObjectDraft = ({String text, double fontSize});

class TextObjectDialog extends StatefulWidget {
  const TextObjectDialog({super.key, this.text = '', this.fontSize = 16});
  final String text;
  final double fontSize;
  @override
  State<TextObjectDialog> createState() => _TextObjectDialogState();
}

class _TextObjectDialogState extends State<TextObjectDialog> {
  late final text = TextEditingController(text: widget.text);
  late double size = widget.fontSize;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.text.isEmpty ? 'Insertar texto' : 'Editar texto'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: text,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Texto'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Tamaño'),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<double>(
                    isExpanded: true,
                    value: size,
                    items:
                        ({12.0, 16.0, 20.0, 24.0, 32.0, 40.0, size}.toList()
                              ..sort())
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text('${v.toInt()} pt'),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => size = v!),
                  ),
                ),
              ],
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
        onPressed: text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (
                text: text.text.trim(),
                fontSize: size,
              )),
        child: Text(widget.text.isEmpty ? 'Insertar' : 'Guardar'),
      ),
    ],
  );
}
