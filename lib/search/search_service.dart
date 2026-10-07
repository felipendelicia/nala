import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../document/asset_store.dart';
import '../document/notebook.dart';
import '../document/page_object.dart';
import '../pdf/pdf_service.dart';

enum SearchHitKind { title, subject, comment, text, pdf, recognized }

class SearchHit {
  const SearchHit({
    required this.notebookId,
    required this.pageIndex,
    required this.snippet,
    required this.kind,
  });
  final String notebookId, snippet;
  final int pageIndex;
  final SearchHitKind kind;
}

class SearchFailure {
  const SearchFailure({required this.notebookId, required this.pageIndex});
  final String notebookId;
  final int pageIndex;
}

class SearchResult {
  SearchResult({
    required List<SearchHit> hits,
    required List<SearchFailure> failures,
    this.cancelled = false,
  }) : hits = List.unmodifiable(hits),
       failures = List.unmodifiable(failures);
  final List<SearchHit> hits;
  final List<SearchFailure> failures;
  final bool cancelled;
}

class SearchCancellation {
  final pdf = PdfRenderCancellation();
  bool get isCancelled => pdf.isCancelled;
  void cancel() => pdf.cancel();
}

String normalizeSearch(String value) {
  const accents = 'áàâäãåéèêëíìîïóòôöõúùûüñç';
  const plain = 'aaaaaaeeeeiiiiooooouuuunc';
  final result = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    if (rune >= 0x0300 && rune <= 0x036f) continue;
    final char = String.fromCharCode(rune),
        index = accents.indexOf(String.fromCharCode(rune));
    result.write(index < 0 ? char : plain[index]);
  }
  return result.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Hash only the inputs to recognition, never the recognized result itself.
/// This cache identity travels in the notebook and is shared across platforms.
Future<String> pageRecognitionFingerprint(NotebookPage page) =>
    compute(_fingerprint, {
      'width': page.width,
      'height': page.height,
      'background': page.background.toJson(),
      'strokes': page.strokes.map((s) => s.toJson()).toList(),
      'objects': page.objects.map((o) => o.toJson()).toList(),
    });
String _fingerprint(Map<String, Object> value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

class SearchService {
  SearchService({required this.pdf, required this.assets});
  final PdfService pdf;
  final AssetStore assets;
  final _pdfCache = <(String, int), String>{};
  int _characters = 0;
  void _cache((String, int) key, String text) {
    if (text.length > 200000) return;
    final old = _pdfCache.remove(key);
    _characters -= old?.length ?? 0;
    _pdfCache[key] = text;
    _characters += text.length;
    while (_pdfCache.length > 128 || _characters > 1000000) {
      _characters -= _pdfCache.remove(_pdfCache.keys.first)!.length;
    }
  }

  Future<String> _original(
    NotebookPage page,
    SearchCancellation cancellation,
  ) async {
    final key = (page.background.assetId!, page.background.pageNumber!);
    final cached = _pdfCache.remove(key);
    if (cached != null) {
      _pdfCache[key] = cached;
      return cached;
    }
    final text = await pdf.extractText(
      key.$1,
      key.$2,
      cancellation: cancellation.pdf,
    );
    _cache(key, text);
    return text;
  }

  Future<SearchResult> search(
    List<Notebook> notebooks,
    String query, {
    SearchCancellation? cancellation,
    void Function(int completed, int total)? onProgress,
  }) async {
    final token = cancellation ?? SearchCancellation(),
        needle = normalizeSearch(query);
    final hits = <SearchHit>[], failures = <SearchFailure>[];
    if (needle.isEmpty) return SearchResult(hits: hits, failures: failures);
    final total = notebooks.fold<int>(0, (sum, n) => sum + n.pages.length);
    var completed = 0;
    void add(
      String text,
      Notebook notebook,
      int pageIndex,
      SearchHitKind kind,
    ) {
      final folded = normalizeSearch(text), index = folded.indexOf(needle);
      if (index < 0) return;
      final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final start = (index - 45).clamp(0, compact.length),
          end = (index + needle.length + 90).clamp(start, compact.length);
      hits.add(
        SearchHit(
          notebookId: notebook.id,
          pageIndex: pageIndex,
          kind: kind,
          snippet:
              '${start > 0 ? '…' : ''}${compact.substring(start, end)}${end < compact.length ? '…' : ''}',
        ),
      );
    }

    for (final notebook in notebooks) {
      if (token.isCancelled) break;
      add(notebook.title, notebook, 0, SearchHitKind.title);
      add(notebook.subject, notebook, 0, SearchHitKind.subject);
      for (var index = 0; index < notebook.pages.length; index++) {
        if (token.isCancelled) break;
        final page = notebook.pages[index];
        for (final comment in page.comments) {
          add(comment.text, notebook, index, SearchHitKind.comment);
        }
        for (final object in page.objects) {
          if (object.kind == PageObjectKind.text) {
            add(object.text, notebook, index, SearchHitKind.text);
          }
        }
        if (page.recognizedText.isNotEmpty &&
            page.recognitionFingerprint != null &&
            page.recognitionFingerprint ==
                await pageRecognitionFingerprint(page)) {
          add(page.recognizedText, notebook, index, SearchHitKind.recognized);
        }
        if (page.background.pageNumber != null) {
          try {
            add(
              await _original(page, token),
              notebook,
              index,
              SearchHitKind.pdf,
            );
          } on PdfRenderCancelled {
            token.cancel();
          } catch (_) {
            failures.add(
              SearchFailure(notebookId: notebook.id, pageIndex: index),
            );
          }
        }
        completed++;
        if (!token.isCancelled) onProgress?.call(completed, total);
        // Yield between pages so typing/cancel remain responsive on large notes.
        await Future<void>.delayed(Duration.zero);
      }
    }
    return SearchResult(
      hits: hits,
      failures: failures,
      cancelled: token.isCancelled,
    );
  }
}
