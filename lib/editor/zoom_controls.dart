import 'package:flutter/material.dart';

class ZoomControls extends StatelessWidget {
  const ZoomControls({
    super.key,
    required this.scale,
    required this.locked,
    required this.onScale,
    required this.onZoom,
    required this.onFit,
    required this.onFitWidth,
    required this.onLock,
  });
  final double scale;
  final bool locked;
  final ValueChanged<double> onScale, onZoom;
  final VoidCallback onFit, onFitWidth, onLock;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Alejar',
        onPressed: locked ? null : () => onZoom(.8),
        icon: const Icon(Icons.remove),
      ),
      PopupMenuButton<double>(
        tooltip: 'Porcentaje de zoom',
        enabled: !locked,
        onSelected: onScale,
        itemBuilder: (_) => [.5, .75, 1.0, 1.25, 1.5, 2.0]
            .map(
              (v) =>
                  PopupMenuItem(value: v, child: Text('${(v * 100).round()}%')),
            )
            .toList(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${(scale * 100).round()}%'),
        ),
      ),
      IconButton(
        tooltip: 'Acercar',
        onPressed: locked ? null : () => onZoom(1.25),
        icon: const Icon(Icons.add),
      ),
      IconButton(
        tooltip: 'Ajustar hoja',
        onPressed: locked ? null : onFit,
        icon: const Icon(Icons.fit_screen),
      ),
      IconButton(
        tooltip: 'Ajustar ancho',
        onPressed: locked ? null : onFitWidth,
        icon: const Icon(Icons.swap_horiz),
      ),
      IconButton(
        tooltip: locked ? 'Desbloquear zoom' : 'Bloquear zoom',
        isSelected: locked,
        onPressed: onLock,
        icon: Icon(locked ? Icons.lock_outline : Icons.lock_open),
      ),
    ],
  );
}
