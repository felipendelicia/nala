import 'package:flutter/material.dart';

Future<String?> askPdfPassword(
  BuildContext context, {
  bool incorrect = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PasswordDialog(incorrect: incorrect),
);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.incorrect});
  final bool incorrect;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('PDF protegido'),
    content: SizedBox(
      width: 360,
      child: TextField(
        controller: text,
        autofocus: true,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'Contraseña del PDF',
          errorText: widget.incorrect ? 'Contraseña incorrecta' : null,
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, text.text),
        child: const Text('Abrir'),
      ),
    ],
  );
}
