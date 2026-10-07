import 'dart:async';
import 'package:flutter/material.dart';
import '../document/asset_store.dart';
import '../document/notebook.dart';
import '../pdf/pdf_service.dart';
import 'recognition_service.dart';
import 'search_service.dart';

typedef SaveRecognizedText =
    Future<bool> Function(
      String notebookId,
      String pageId,
      String fingerprint,
      String text,
    );

class NotebookSearchDialog extends StatefulWidget {
  const NotebookSearchDialog({
    super.key,
    required this.notebooks,
    required this.pdf,
    required this.assets,
    this.onOpen,
    this.onRecognized,
  });
  final List<Notebook> notebooks;
  final PdfService pdf;
  final AssetStore assets;
  final ValueChanged<SearchHit>? onOpen;
  final SaveRecognizedText? onRecognized;
  @override
  State<NotebookSearchDialog> createState() => _NotebookSearchDialogState();
}

class _NotebookSearchDialogState extends State<NotebookSearchDialog> {
  late final service = SearchService(pdf: widget.pdf, assets: widget.assets);
  late final recognizer = nativePageRecognition(
    assets: widget.assets,
    pdf: widget.pdf,
  );
  late List<Notebook> notebooks = List.of(widget.notebooks);
  final query = TextEditingController();
  SearchResult? result;
  SearchCancellation? searchCancellation;
  RecognitionAvailability? availability;
  Timer? debounce;
  bool searching = false, recognizing = false, modelBusy = false;
  int completed = 0, total = 0, pageIndex = 0, recognitionGeneration = 0;
  late String? notebookId = notebooks.firstOrNull?.id;
  String? error, recognitionError;
  Notebook? get selectedNotebook =>
      notebooks.where((n) => n.id == notebookId).firstOrNull;
  NotebookPage? get selectedPage {
    final notebook = selectedNotebook;
    return notebook == null || notebook.pages.isEmpty
        ? null
        : notebook.pages[pageIndex.clamp(0, notebook.pages.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _status();
  }

  Future<void> _status() async {
    try {
      final status = await recognizer.status();
      if (mounted) setState(() => availability = status);
    } catch (_) {
      if (mounted) {
        setState(
          () => availability = const RecognitionAvailability(
            available: false,
            ready: false,
            message: 'No se pudo consultar el reconocimiento local.',
          ),
        );
      }
    }
  }

  void _changed(String _) {
    debounce?.cancel();
    searchCancellation?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    debounce?.cancel();
    searchCancellation?.cancel();
    final token = searchCancellation = SearchCancellation();
    setState(() {
      searching = query.text.trim().isNotEmpty;
      completed = 0;
      total = notebooks.fold<int>(0, (sum, n) => sum + n.pages.length);
      error = null;
    });
    try {
      final response = await service.search(
        List.of(notebooks),
        query.text,
        cancellation: token,
        onProgress: (done, count) {
          if (mounted && identical(token, searchCancellation)) {
            setState(() {
              completed = done;
              total = count;
            });
          }
        },
      );
      if (mounted &&
          identical(token, searchCancellation) &&
          !token.isCancelled) {
        setState(() {
          result = response;
          searching = false;
        });
      }
    } catch (_) {
      if (mounted && identical(token, searchCancellation)) {
        setState(() {
          searching = false;
          error = 'No se pudo completar la búsqueda.';
        });
      }
    }
  }

  void _cancelSearch() {
    debounce?.cancel();
    searchCancellation?.cancel();
    setState(() {
      searching = false;
      error = 'Búsqueda cancelada.';
    });
  }

  Future<void> _model(bool download) async {
    setState(() {
      modelBusy = true;
      recognitionError = null;
    });
    try {
      if (download) {
        await recognizer.downloadModel();
      } else {
        await recognizer.deleteModel();
      }
      await _status();
    } catch (_) {
      if (mounted) {
        setState(
          () => recognitionError = download
              ? 'No se pudo descargar el modelo. Revisá la conexión y el espacio.'
              : 'No se pudo eliminar el modelo.',
        );
      }
    } finally {
      if (mounted) setState(() => modelBusy = false);
    }
  }

  Future<void> _recognize() async {
    final page = selectedPage, book = selectedNotebook;
    if (page == null || book == null || recognizing) return;
    final generation = ++recognitionGeneration;
    setState(() {
      recognizing = true;
      recognitionError = null;
    });
    try {
      final fingerprint = await pageRecognitionFingerprint(page);
      final text = await recognizer.recognize(page);
      if (!mounted || generation != recognitionGeneration) return;
      setState(() => recognizing = false);
      if (text.trim().isEmpty) {
        setState(
          () => recognitionError =
              'No se reconoció texto. Podés ingresarlo o corregirlo manualmente.',
        );
      }
      await _editRecognized(book, page, text, fingerprint);
    } on RecognitionCancelled {
      /* A cancelled result never becomes cache text. */
    } catch (_) {
      if (mounted && generation == recognitionGeneration) {
        setState(
          () => recognitionError =
              'No se pudo reconocer la página. Podés editar el texto manualmente.',
        );
      }
    } finally {
      if (mounted && generation == recognitionGeneration) {
        setState(() => recognizing = false);
      }
    }
  }

  void _cancelRecognition() {
    recognitionGeneration++;
    recognizer.cancel();
    setState(() => recognizing = false);
  }

  Future<void> _edit() async {
    final page = selectedPage, book = selectedNotebook;
    if (page == null || book == null) return;
    final fingerprint = await pageRecognitionFingerprint(page);
    if (!mounted) return;
    final current = page.recognitionFingerprint == fingerprint
        ? page.recognizedText
        : '';
    await _editRecognized(book, page, current, fingerprint);
  }

  Future<void> _editRecognized(
    Notebook book,
    NotebookPage page,
    String text,
    String fingerprint,
  ) async {
    final edited = await showDialog<String>(
      context: context,
      builder: (_) => _RecognizedTextEditor(text: text),
    );
    if (edited == null || !mounted) return;
    final save = widget.onRecognized;
    if (save == null) {
      setState(
        () => recognitionError =
            'Abrí esta herramienta desde la biblioteca para guardar el texto en el apunte.',
      );
      return;
    }
    try {
      final accepted = await save(book.id, page.id, fingerprint, edited.trim());
      if (!mounted) return;
      if (!accepted) {
        setState(
          () => recognitionError =
              'La página cambió durante el reconocimiento. Volvé a reconocerla para conservar tus cambios.',
        );
        return;
      }
      setState(() {
        notebooks = [
          for (final n in notebooks)
            n.id != book.id
                ? n
                : n.copyWith(
                    pages: [
                      for (final p in n.pages)
                        p.id != page.id
                            ? p
                            : p.copyWith(
                                recognizedText: edited.trim(),
                                recognitionFingerprint: fingerprint,
                              ),
                    ],
                  ),
        ];
        recognitionError = null;
      });
      await _search();
    } catch (_) {
      if (mounted) {
        setState(
          () => recognitionError = 'No se pudo guardar el texto reconocido.',
        );
      }
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    searchCancellation?.cancel();
    recognizer.dispose();
    query.dispose();
    super.dispose();
  }

  String _kind(SearchHitKind kind) => switch (kind) {
    SearchHitKind.title => 'Título',
    SearchHitKind.subject => 'Materia',
    SearchHitKind.comment => 'Comentario',
    SearchHitKind.text => 'Texto',
    SearchHitKind.pdf => 'PDF original',
    SearchHitKind.recognized => 'Texto reconocido',
  };
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.notebooks.length == 1
          ? 'Buscar en el apunte'
          : 'Buscar en todos los apuntes',
    ),
    content: SizedBox(
      width: 780,
      height: MediaQuery.sizeOf(context).height * .68,
      child: Column(
        children: [
          TextField(
            controller: query,
            autofocus: true,
            onChanged: _changed,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(
              hintText: 'Título, materia, comentario o texto',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: total == 0 ? null : completed / total,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('$completed/$total'),
                  IconButton(
                    tooltip: 'Cancelar búsqueda',
                    onPressed: _cancelSearch,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!),
            ),
          if (result != null && result!.failures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Resultados parciales: no se pudo leer el texto original de ${result!.failures.length} páginas PDF. Los PDF protegidos deben desbloquearse en el editor.',
              ),
            ),
          Expanded(
            child: result == null
                ? const Center(
                    child: Text(
                      'Buscá en títulos, texto, comentarios y PDF originales.',
                    ),
                  )
                : result!.hits.isEmpty
                ? const Center(child: Text('No se encontraron coincidencias.'))
                : ListView.builder(
                    itemCount: result!.hits.length,
                    itemBuilder: (context, index) {
                      final hit = result!.hits[index],
                          book = notebooks
                              .where(
                                (n) => n.id == result!.hits[index].notebookId,
                              )
                              .firstOrNull;
                      return ListTile(
                        title: Text(
                          '${book?.title ?? 'Apunte'} · página ${hit.pageIndex + 1}',
                        ),
                        subtitle: Text('${_kind(hit.kind)} · ${hit.snippet}'),
                        leading: const Icon(Icons.find_in_page_outlined),
                        onTap: () {
                          Navigator.pop(context, hit);
                          widget.onOpen?.call(hit);
                        },
                      );
                    },
                  ),
          ),
          const Divider(),
          Flexible(
            child: SingleChildScrollView(
              child: ExpansionTile(
                title: const Text('Reconocer y corregir texto'),
                tilePadding: EdgeInsets.zero,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      availability?.message ??
                          'Consultando reconocimiento local…',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (availability?.canDownload == true &&
                          availability?.ready != true)
                        OutlinedButton.icon(
                          onPressed: modelBusy || recognizing
                              ? null
                              : () => _model(true),
                          icon: const Icon(Icons.download_outlined),
                          label: Text(
                            modelBusy
                                ? 'Descargando…'
                                : 'Descargar modelo español',
                          ),
                        ),
                      if (availability?.canDownload == true &&
                          availability?.ready == true)
                        TextButton(
                          onPressed: modelBusy || recognizing
                              ? null
                              : () => _model(false),
                          child: const Text('Eliminar modelo'),
                        ),
                    ],
                  ),
                  if (notebooks.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: notebookId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Apunte'),
                      items: [
                        for (final book in notebooks)
                          DropdownMenuItem(
                            value: book.id,
                            child: Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: recognizing
                          ? null
                          : (id) => setState(() {
                              notebookId = id;
                              pageIndex = 0;
                            }),
                    ),
                  if (selectedNotebook != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(notebookId),
                        initialValue: pageIndex,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Página'),
                        items: [
                          for (
                            var index = 0;
                            index < selectedNotebook!.pages.length;
                            index++
                          )
                            DropdownMenuItem(
                              value: index,
                              child: Text('Página ${index + 1}'),
                            ),
                        ],
                        onChanged: recognizing
                            ? null
                            : (index) => setState(() => pageIndex = index ?? 0),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            !recognizing &&
                                !modelBusy &&
                                availability?.ready == true &&
                                selectedPage != null
                            ? _recognize
                            : null,
                        icon: const Icon(Icons.draw_outlined),
                        label: const Text('Reconocer página'),
                      ),
                      OutlinedButton.icon(
                        onPressed: recognizing || selectedPage == null
                            ? null
                            : _edit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar texto reconocido'),
                      ),
                      if (recognizing)
                        TextButton(
                          onPressed: _cancelRecognition,
                          child: const Text('Cancelar reconocimiento'),
                        ),
                    ],
                  ),
                  if (recognizing || modelBusy)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                  if (recognitionError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        recognitionError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  );
}

class _RecognizedTextEditor extends StatefulWidget {
  const _RecognizedTextEditor({required this.text});
  final String text;
  @override
  State<_RecognizedTextEditor> createState() => _RecognizedTextEditorState();
}

class _RecognizedTextEditorState extends State<_RecognizedTextEditor> {
  late final text = TextEditingController(text: widget.text);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Revisar texto reconocido'),
    content: SizedBox(
      width: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Corregí el resultado antes de guardarlo. Se usa para buscar y viaja con el apunte.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(hintText: 'Texto de esta página'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, text.text),
        child: const Text('Guardar texto'),
      ),
    ],
  );
}
