import 'package:flutter/material.dart';
import '../document/notebook.dart';
import 'paper_canvas.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_page_background.dart';

class PagePanel extends StatelessWidget {
  const PagePanel({
    super.key,
    required this.pages,
    required this.currentPage,
    required this.onPage,
    required this.onAdd,
    this.pdf,
  });
  final List<NotebookPage> pages;
  final int currentPage;
  final ValueChanged<int> onPage;
  final VoidCallback? onAdd;
  final PdfService? pdf;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${pages.length} ${pages.length == 1 ? 'hoja' : 'hojas'}',
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: pages.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Semantics(
                label: 'Hoja ${index + 1}',
                selected: index == currentPage,
                child: InkWell(
                  onTap: () => onPage(index),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: index == currentPage
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: index == currentPage ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 140,
                          child: FittedBox(
                            child: IgnorePointer(
                              child: PaperCanvas(
                                page: pages[index],
                                tool: EditorTool.pen,
                                onStroke: (_) {},
                                background:
                                    pdf == null ||
                                        pages[index].background.assetId == null
                                    ? null
                                    : PdfPageBackground(
                                        pdf: pdf!,
                                        page: pages[index],
                                        scale: .25,
                                        render: false,
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('${index + 1}'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (onAdd != null)
          IconButton(
            tooltip: 'Agregar hoja',
            onPressed: onAdd,
            icon: const Icon(Icons.note_add_outlined),
          ),
      ],
    ),
  );
}
