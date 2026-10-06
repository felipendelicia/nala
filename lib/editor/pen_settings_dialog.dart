import 'package:flutter/material.dart';

typedef PenSettings = ({double pressure, double stabilization});

class PenSettingsDialog extends StatefulWidget {
  const PenSettingsDialog({super.key, required this.settings});
  final PenSettings settings;
  @override
  State<PenSettingsDialog> createState() => _PenSettingsDialogState();
}

class _PenSettingsDialogState extends State<PenSettingsDialog> {
  late double pressure = widget.settings.pressure;
  late double stabilization = widget.settings.stabilization;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajustes del lápiz'),
    content: SizedBox(
      width: 340,
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
          const Text('Un valor bajo sigue más de cerca la punta del lápiz.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          pressure: pressure,
          stabilization: stabilization,
        )),
        child: const Text('Aplicar'),
      ),
    ],
  );
}
