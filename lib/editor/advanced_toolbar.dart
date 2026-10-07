import 'package:flutter/material.dart';
import 'shape_tools.dart';
import 'pen_favorites.dart';

class AdvancedToolbar extends StatelessWidget {
  const AdvancedToolbar({
    super.key,
    required this.shape,
    required this.onShape,
    required this.ruler,
    required this.rulerAngle,
    required this.onRuler,
    required this.onAngle,
    required this.hasSelection,
    required this.canPaste,
    required this.onCopy,
    required this.onCut,
    required this.onDuplicate,
    required this.onPaste,
    required this.onScale,
    required this.onRotate,
    required this.onText,
    required this.onImage,
    required this.onEditText,
    required this.favorites,
    required this.onFavorite,
    required this.onSaveFavorite,
    required this.onRemoveFavorite,
    required this.onTemplates,
    required this.onSearch,
    required this.onAudio,
    required this.onStudy,
    required this.reading,
    required this.onOpenMenu,
  });
  final ShapeKind? shape;
  final ValueChanged<ShapeKind?> onShape;
  final bool ruler, hasSelection, canPaste, reading;
  final double rulerAngle;
  final VoidCallback onRuler,
      onCopy,
      onCut,
      onDuplicate,
      onPaste,
      onRotate,
      onText,
      onEditText,
      onStudy;
  final ValueChanged<double> onAngle, onScale;
  final VoidCallback? onImage, onSaveFavorite, onTemplates, onSearch, onAudio;
  final VoidCallback onOpenMenu;
  final List<PenFavorite> favorites;
  final ValueChanged<PenFavorite> onFavorite;
  final ValueChanged<String>? onRemoveFavorite;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (!reading) ...[
                PopupMenuButton<String>(
                  onOpened: onOpenMenu,
                  onCanceled: onOpenMenu,
                  tooltip: 'Formas',
                  icon: Icon(
                    shape == null ? Icons.category_outlined : Icons.category,
                  ),
                  onSelected: (value) => onShape(
                    value == 'free' ? null : ShapeKind.values.byName(value),
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'free',
                      child: Text('Trazo libre · mantener para formar'),
                    ),
                    const PopupMenuItem(value: 'line', child: Text('Línea')),
                    const PopupMenuItem(
                      value: 'rectangle',
                      child: Text('Rectángulo'),
                    ),
                    const PopupMenuItem(
                      value: 'ellipse',
                      child: Text('Elipse'),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Regla',
                  isSelected: ruler,
                  onPressed: onRuler,
                  icon: const Icon(Icons.straighten),
                ),
                if (ruler)
                  PopupMenuButton<double>(
                    onOpened: onOpenMenu,
                    onCanceled: onOpenMenu,
                    tooltip: 'Ángulo de la regla',
                    onSelected: onAngle,
                    itemBuilder: (_) => [
                      for (final a in [0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0])
                        PopupMenuItem(value: a, child: Text('${a.toInt()}°')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('${rulerAngle.toInt()}°'),
                    ),
                  ),
                IconButton(
                  tooltip: 'Insertar texto',
                  onPressed: onText,
                  icon: const Icon(Icons.text_fields),
                ),
                IconButton(
                  tooltip: 'Insertar imagen',
                  onPressed: onImage,
                  icon: const Icon(Icons.image_outlined),
                ),
                PopupMenuButton<String>(
                  onOpened: onOpenMenu,
                  onCanceled: onOpenMenu,
                  tooltip: 'Lápices favoritos',
                  icon: const Icon(Icons.star_outline),
                  onSelected: (id) {
                    if (id == 'save') {
                      onSaveFavorite?.call();
                      return;
                    }
                    onFavorite(favorites.firstWhere((f) => f.id == id));
                  },
                  itemBuilder: (_) => [
                    for (final f in favorites)
                      PopupMenuItem(
                        value: f.id,
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: Color(f.argb), size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${f.name} · ${f.width} pt')),
                            if (onRemoveFavorite != null)
                              IconButton(
                                tooltip: 'Quitar favorito',
                                onPressed: () {
                                  Navigator.pop(context);
                                  onRemoveFavorite!(f.id);
                                },
                                icon: const Icon(Icons.close, size: 16),
                              ),
                          ],
                        ),
                      ),
                    if (onSaveFavorite != null)
                      const PopupMenuItem(
                        value: 'save',
                        child: Text('Guardar lápiz actual…'),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: 'Plantillas y portadas',
                  onPressed: onTemplates,
                  icon: const Icon(Icons.style_outlined),
                ),
                if (hasSelection) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Copiar selección',
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy),
                  ),
                  IconButton(
                    tooltip: 'Cortar selección',
                    onPressed: onCut,
                    icon: const Icon(Icons.content_cut),
                  ),
                  IconButton(
                    tooltip: 'Duplicar selección',
                    onPressed: onDuplicate,
                    icon: const Icon(Icons.copy_all),
                  ),
                  PopupMenuButton<double>(
                    onOpened: onOpenMenu,
                    onCanceled: onOpenMenu,
                    tooltip: 'Tamaño de selección',
                    icon: const Icon(Icons.open_in_full),
                    onSelected: onScale,
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: .75,
                        child: Text('Reducir al 75%'),
                      ),
                      const PopupMenuItem(
                        value: 1.25,
                        child: Text('Ampliar al 125%'),
                      ),
                      const PopupMenuItem(
                        value: 2.0,
                        child: Text('Ampliar al 200%'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Girar selección',
                    onPressed: onRotate,
                    icon: const Icon(Icons.rotate_right),
                  ),
                  IconButton(
                    tooltip: 'Editar texto seleccionado',
                    onPressed: onEditText,
                    icon: const Icon(Icons.edit_note),
                  ),
                ],
                IconButton(
                  tooltip: 'Pegar selección',
                  onPressed: canPaste ? onPaste : null,
                  icon: const Icon(Icons.content_paste),
                ),
              ],
              IconButton(
                tooltip: 'Buscar en apunte',
                onPressed: onSearch,
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Audio de clase',
                onPressed: onAudio,
                icon: const Icon(Icons.mic_none),
              ),
              IconButton(
                tooltip: 'Tarjetas de estudio',
                onPressed: onStudy,
                icon: const Icon(Icons.school_outlined),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
