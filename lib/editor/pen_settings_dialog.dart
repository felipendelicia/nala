import 'package:flutter/material.dart';

import 'pen_preferences.dart';

class PenSettingsDialog extends StatefulWidget {
  const PenSettingsDialog({super.key, required this.settings});
  final PenSettings settings;
  @override
  State<PenSettingsDialog> createState() => _PenSettingsDialogState();
}

class _PenSettingsDialogState extends State<PenSettingsDialog> {
  late double pressure = widget.settings.pressure;
  late double stabilization = widget.settings.stabilization;
  late PenButtonTool buttonTool = widget.settings.buttonTool;
  late PenButtonMode buttonMode = widget.settings.buttonMode;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Lápiz y S Pen'),
    content: SizedBox(
      width: 340,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Respuesta a la presión'),
            Slider(
              value: pressure,
              min: 0,
              max: 1,
              divisions: 10,
              label: '${(pressure * 100).round()}%',
              onChanged: (v) => setState(() => pressure = v),
            ),
            const Text('Más presión, más variación de grosor.'),
            const SizedBox(height: 24),
            const Text('Suavizado'),
            Slider(
              value: stabilization,
              min: 0,
              max: .4,
              divisions: 10,
              label: '${(stabilization * 100).round()}%',
              onChanged: (v) => setState(() => stabilization = v),
            ),
            const Text('0% sigue la punta sin retraso de suavizado.'),
            const SizedBox(height: 24),
            DropdownButtonFormField<PenButtonTool>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Botón del S Pen'),
              initialValue: buttonTool,
              items: const [
                DropdownMenuItem(
                  value: PenButtonTool.eraser,
                  child: Text('Goma'),
                ),
                DropdownMenuItem(
                  value: PenButtonTool.highlighter,
                  child: Text('Resaltador'),
                ),
                DropdownMenuItem(
                  value: PenButtonTool.pen,
                  child: Text('Lápiz'),
                ),
                DropdownMenuItem(
                  value: PenButtonTool.selection,
                  child: Text('Selección'),
                ),
                DropdownMenuItem(
                  value: PenButtonTool.none,
                  child: Text('Desactivado'),
                ),
              ],
              onChanged: (value) => setState(() => buttonTool = value!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PenButtonMode>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Cómo usar el botón',
              ),
              initialValue: buttonMode,
              items: const [
                DropdownMenuItem(
                  value: PenButtonMode.hold,
                  child: Text('Mantener apretado'),
                ),
                DropdownMenuItem(
                  value: PenButtonMode.toggle,
                  child: Text('Pulsar para alternar'),
                ),
              ],
              onChanged: buttonTool == PenButtonTool.none
                  ? null
                  : (value) => setState(() => buttonMode = value!),
            ),
            const SizedBox(height: 12),
            const Text(
              'Usalo con el lápiz cerca de la pantalla o escribiendo.',
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
        onPressed: () => Navigator.pop(
          context,
          PenSettings(
            pressure: pressure,
            stabilization: stabilization,
            buttonTool: buttonTool,
            buttonMode: buttonMode,
          ),
        ),
        child: const Text('Aplicar'),
      ),
    ],
  );
}
