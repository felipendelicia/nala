import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../document/deferred_notebook_page.dart';
import '../document/notebook.dart';
import '../editor/page_panel.dart';
import '../pdf/pdf_service.dart';

Future<Set<String>?> showStudyPagePicker(
  BuildContext context, {
  required List<NotebookPage> pages,
  required Set<String> selected,
  PdfService? pdf,
}) => showDialog<Set<String>>(
  context: context,
  builder: (_) => _StudyPagePicker(pages: pages, selected: selected, pdf: pdf),
);

class _StudyPagePicker extends StatefulWidget {
  const _StudyPagePicker({
    required this.pages,
    required this.selected,
    this.pdf,
  });

  final List<NotebookPage> pages;
  final Set<String> selected;
  final PdfService? pdf;

  @override
  State<_StudyPagePicker> createState() => _StudyPagePickerState();
}

class _StudyPagePickerState extends State<_StudyPagePicker> {
  static const _tileHeight = 156.0;
  static const _gap = 8.0;
  ScrollController? _scrollController;
  late final _selected = {
    for (final page in widget.pages)
      if (widget.selected.contains(page.id)) page.id,
  };
  late final _firstSelected = widget.pages.indexWhere(
    (page) => _selected.contains(page.id),
  );

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  Widget _grid(BuildContext _, BoxConstraints constraints) {
    final columns = (constraints.maxWidth / 124).floor().clamp(1, 4);
    return GridView.builder(
      controller: _scrollController ??= ScrollController(
        initialScrollOffset: _firstSelected < 0
            ? 0
            : (_firstSelected ~/ columns) * (_tileHeight + _gap),
      ),
      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: _tileHeight,
        crossAxisSpacing: _gap,
        mainAxisSpacing: _gap,
      ),
      itemCount: widget.pages.length,
      itemBuilder: (context, index) {
        final page = widget.pages[index];
        return _StudyPageTile(
          key: ValueKey(page.id),
          page: page,
          label: 'Hoja ${index + 1}',
          selected: _selected.contains(page.id),
          pdf: widget.pdf,
          onTap: () => _toggle(page.id),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Elegir páginas'),
    content: SizedBox(
      width: 520,
      height: 352,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              _selected.length == 1
                  ? '1 hoja seleccionada'
                  : '${_selected.length} hojas seleccionadas',
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: LayoutBuilder(builder: _grid)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, Set<String>.unmodifiable(_selected)),
        child: const Text('Usar selección'),
      ),
    ],
  );
}

class _StudyPageTile extends StatelessWidget {
  const _StudyPageTile({
    super.key,
    required this.page,
    required this.label,
    required this.selected,
    required this.onTap,
    this.pdf,
  });

  final NotebookPage page;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final PdfService? pdf;

  Widget _preview(NotebookPage source) => NotebookPagePreview(
    page: source,
    pdf: pdf,
    renderPdf: true,
    rasterScale: .25,
  );

  Widget _thumbnail() {
    final source = page;
    if (source is! DeferredNotebookPage || source.isReady) {
      return _preview(source);
    }
    return FutureBuilder<void>(
      future: source.prepare(),
      builder: (context, snapshot) => _preview(
        source.isReady
            ? source
            : NotebookPage(
                id: source.id,
                width: source.width,
                height: source.height,
                background: source.background,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onPrimaryContainer : colors.onSurface;
    return Semantics(
      label: label,
      checked: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(child: _thumbnail()),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: foreground),
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: foreground,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
