import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' show PdfPasswordException;
import '../document/notebook.dart';
import 'pdf_service.dart';

class PdfPageBackground extends StatefulWidget {
  const PdfPageBackground({
    super.key,
    required this.pdf,
    required this.page,
    required this.scale,
    this.render = true,
    this.onError,
    this.onRendered,
  });
  final PdfService pdf;
  final NotebookPage page;
  final double scale;
  final bool render;
  final ValueChanged<Object>? onError;
  final VoidCallback? onRendered;
  @override
  State<PdfPageBackground> createState() => _PdfPageBackgroundState();
}

class _PdfPageBackgroundState extends State<PdfPageBackground> {
  Uint8List? png;
  Object? error;
  PdfRenderCancellation? cancellation;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PdfPageBackground old) {
    super.didUpdateWidget(old);
    final changedPage =
        old.page.background.assetId != widget.page.background.assetId ||
        old.page.background.pageNumber != widget.page.background.pageNumber;
    if (changedPage) png = null;
    if (changedPage ||
        old.render != widget.render ||
        PdfService.scaleStep(old.scale) != PdfService.scaleStep(widget.scale)) {
      _load();
    }
  }

  Future<void> _load() async {
    cancellation?.cancel();
    if (!widget.render) return;
    final token = cancellation = PdfRenderCancellation();
    try {
      final bytes = await widget.pdf.renderBackground(
        widget.page.background.assetId!,
        widget.page.background.pageNumber!,
        scale: widget.scale,
        cancellation: token,
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        png = bytes;
        error = null;
      });
      widget.onRendered?.call();
    } on PdfRenderCancelled {
      /* The next page/scale owns the result. */
    } catch (e) {
      if (!mounted || token.isCancelled) return;
      setState(() => error = e);
      widget.onError?.call(e);
    }
  }

  @override
  void dispose() {
    cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.render
        ? png
        : widget.pdf.cache.latestFor(
            widget.page.background.assetId!,
            widget.page.background.pageNumber!,
          );
    return ColoredBox(
      color: Colors.white,
      child: bytes != null
          ? Image.memory(
              bytes,
              width: widget.page.width,
              height: widget.page.height,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.render && error == null)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: Color(0xff73786f),
                      size: 32,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    error is PdfPasswordException
                        ? 'PDF protegido'
                        : error != null
                        ? 'No se pudo mostrar el PDF'
                        : widget.render
                        ? 'Preparando PDF…'
                        : 'PDF · ${widget.page.background.pageNumber}',
                  ),
                ],
              ),
            ),
    );
  }
}
