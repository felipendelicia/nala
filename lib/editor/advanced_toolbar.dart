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
  Widget _content(
    BuildContext context, {
    required String label,
    required Widget icon,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: .38);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: IconTheme(
              data: IconThemeData(color: color, size: 24),
              child: icon,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }

  Widget _action(
    BuildContext context, {
    required String label,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool selected = false,
  }) => SizedBox(
    width: 96,
    child: Tooltip(
      message: tooltip,
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.all(4),
            backgroundColor: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _content(
            context,
            label: label,
            icon: Icon(icon),
            enabled: onPressed != null,
          ),
        ),
      ),
    ),
  );

  Widget _menu<T>(
    BuildContext context, {
    required String label,
    required String tooltip,
    required Widget icon,
    required ValueChanged<T> onSelected,
    required PopupMenuItemBuilder<T> itemBuilder,
    bool selected = false,
  }) => SizedBox(
    width: 96,
    child: Semantics(
      selected: selected,
      child: PopupMenuButton<T>(
        onOpened: onOpenMenu,
        onCanceled: onOpenMenu,
        tooltip: tooltip,
        onSelected: onSelected,
        itemBuilder: itemBuilder,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: _content(context, label: label, icon: icon),
          ),
        ),
      ),
    ),
  );

  Widget _group(List<Widget> children) =>
      Wrap(spacing: 12, runSpacing: 12, children: children);

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!reading) ...[
          _group([
            _menu<String>(
              context,
              label: 'Formas',
              tooltip: 'Formas',
              icon: Icon(
                shape == null ? Icons.category_outlined : Icons.category,
              ),
              selected: shape != null,
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
                const PopupMenuItem(value: 'ellipse', child: Text('Elipse')),
              ],
            ),
            _action(
              context,
              label: 'Regla',
              tooltip: 'Regla',
              icon: Icons.straighten,
              selected: ruler,
              onPressed: onRuler,
            ),
            if (ruler)
              _menu<double>(
                context,
                label: 'Ángulo',
                tooltip: 'Ángulo de la regla',
                icon: Text(
                  '${rulerAngle.toInt()}°',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onSelected: onAngle,
                itemBuilder: (_) => [
                  for (final a in [0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0])
                    PopupMenuItem(value: a, child: Text('${a.toInt()}°')),
                ],
              ),
            _action(
              context,
              label: 'Texto',
              tooltip: 'Insertar texto',
              icon: Icons.text_fields,
              onPressed: onText,
            ),
            _action(
              context,
              label: 'Imagen',
              tooltip: 'Insertar imagen',
              icon: Icons.image_outlined,
              onPressed: onImage,
            ),
            _menu<String>(
              context,
              label: 'Lápices',
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
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              onRemoveFavorite!(f.id);
                            },
                            icon: const Icon(Icons.close, size: 18),
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
            _action(
              context,
              label: 'Plantillas',
              tooltip: 'Plantillas y portadas',
              icon: Icons.style_outlined,
              onPressed: onTemplates,
            ),
          ]),
          const SizedBox(height: 12),
          _group([
            if (hasSelection) ...[
              _action(
                context,
                label: 'Copiar',
                tooltip: 'Copiar selección',
                icon: Icons.copy,
                onPressed: onCopy,
              ),
              _action(
                context,
                label: 'Cortar',
                tooltip: 'Cortar selección',
                icon: Icons.content_cut,
                onPressed: onCut,
              ),
              _action(
                context,
                label: 'Duplicar',
                tooltip: 'Duplicar selección',
                icon: Icons.copy_all,
                onPressed: onDuplicate,
              ),
              _menu<double>(
                context,
                label: 'Tamaño',
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
              _action(
                context,
                label: 'Girar',
                tooltip: 'Girar selección',
                icon: Icons.rotate_right,
                onPressed: onRotate,
              ),
              _action(
                context,
                label: 'Editar texto',
                tooltip: 'Editar texto seleccionado',
                icon: Icons.edit_note,
                onPressed: onEditText,
              ),
            ],
            _action(
              context,
              label: 'Pegar',
              tooltip: 'Pegar selección',
              icon: Icons.content_paste,
              onPressed: canPaste ? onPaste : null,
            ),
          ]),
          const SizedBox(height: 12),
        ],
        _group([
          _action(
            context,
            label: 'Buscar',
            tooltip: 'Buscar en apunte',
            icon: Icons.search,
            onPressed: onSearch,
          ),
          _action(
            context,
            label: 'Audio',
            tooltip: 'Audio de clase',
            icon: Icons.mic_none,
            onPressed: onAudio,
          ),
          _action(
            context,
            label: 'Tarjetas',
            tooltip: 'Tarjetas de estudio',
            icon: Icons.school_outlined,
            onPressed: onStudy,
          ),
        ]),
      ],
    ),
  );
}
