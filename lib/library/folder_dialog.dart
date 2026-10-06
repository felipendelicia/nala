import 'package:flutter/material.dart';
import 'library_controller.dart';

class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.title,
    required this.label,
    this.value = '',
  });
  final String title, label, value;
  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final text = TextEditingController(text: widget.value);
  void submit() {
    if (text.text.trim().isNotEmpty) Navigator.pop(context, text.text.trim());
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: text,
      autofocus: true,
      maxLength: 80,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: submit, child: const Text('Guardar')),
    ],
  );
}

class FolderDestination {
  const FolderDestination(this.id);
  final String? id;
}

class FolderPickerDialog extends StatelessWidget {
  const FolderPickerDialog({
    super.key,
    required this.library,
    this.movingFolderId,
  });
  final LibraryController library;
  final String? movingFolderId;
  @override
  Widget build(BuildContext context) {
    final folders =
        library.folders
            .where(
              (f) => !library.pathFor(f.id).any((p) => p.id == movingFolderId),
            )
            .toList()
          ..sort(
            (a, b) => library
                .pathFor(a.id)
                .map((f) => f.name)
                .join('/')
                .compareTo(library.pathFor(b.id).map((f) => f.name).join('/')),
          );
    return AlertDialog(
      title: const Text('Mover a…'),
      content: SizedBox(
        width: 420,
        height: 320,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Mis apuntes'),
              onTap: () =>
                  Navigator.pop(context, const FolderDestination(null)),
            ),
            for (final f in folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f.name),
                subtitle: Text(
                  library.pathFor(f.id).map((p) => p.name).join(' / '),
                ),
                onTap: () => Navigator.pop(context, FolderDestination(f.id)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
