import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:uuid/uuid.dart';
import '../document/asset_store.dart';
import '../document/page_object.dart';

const _parserSettings = TexParserSettings(maxExpand: 100, strict: Strict.error);

SyntaxTree _parse(String source) {
  if (source.trim().isEmpty) {
    throw const FormatException('Escribí una fórmula.');
  }
  if (source.length > 4000) {
    throw const FormatException('La fórmula supera los 4000 caracteres.');
  }
  var depth = 0;
  for (var i = 0; i < source.length; i++) {
    if (source[i] == r'\' &&
        i + 1 < source.length &&
        (source[i + 1] == '{' ||
            source[i + 1] == '}' ||
            source[i + 1] == r'\')) {
      i++;
      continue;
    }
    if (source[i] == '{' && ++depth > 32) {
      throw const FormatException('La fórmula tiene demasiados niveles.');
    }
    if (source[i] == '}') depth--;
  }
  return SyntaxTree(greenRoot: TexParser(source, _parserSettings).parse());
}

/// Local math editor. Source remains editable; pages and exports use the
/// transparent PNG, avoiding dependence on a math engine when opening notes.
Future<PageObject?> showLatexEditor(
  BuildContext context, {
  required AssetStore assets,
  PageObject? object,
  String? id,
  Offset position = const Offset(40, 40),
  double maxWidth = 515,
  double maxHeight = 762,
  int argb = 0xff202020,
}) {
  if (!maxWidth.isFinite ||
      !maxHeight.isFinite ||
      maxWidth <= 0 ||
      maxHeight <= 0) {
    throw ArgumentError('La fórmula necesita espacio en la hoja.');
  }
  if (object != null &&
      (object.kind != PageObjectKind.latex || object.locked)) {
    return Future.value();
  }
  return showDialog<PageObject>(
    context: context,
    builder: (_) => _LatexEditor(
      assets: assets,
      object: object,
      id: id,
      position: position,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      argb: argb,
    ),
  );
}

class _LatexEditor extends StatefulWidget {
  const _LatexEditor({
    required this.assets,
    required this.object,
    required this.id,
    required this.position,
    required this.maxWidth,
    required this.maxHeight,
    required this.argb,
  });
  final AssetStore assets;
  final PageObject? object;
  final String? id;
  final Offset position;
  final double maxWidth, maxHeight;
  final int argb;
  @override
  State<_LatexEditor> createState() => _LatexEditorState();
}

class _LatexEditorState extends State<_LatexEditor> {
  late final TextEditingController source;
  final boundaryKey = GlobalKey();
  SyntaxTree? ast;
  String? error;
  bool busy = false;
  bool renderFailed = false;
  double get fontSize => widget.object?.fontSize ?? 24;
  int get argb => widget.object?.argb ?? widget.argb;

  @override
  void initState() {
    super.initState();
    source = TextEditingController(
      text: widget.object?.text ?? r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
    );
    parse();
    source.addListener(() => setState(parse));
  }

  void parse() {
    renderFailed = false;
    try {
      ast = _parse(source.text);
      error = null;
    } on Object catch (e) {
      ast = null;
      error = 'Fórmula inválida: $e';
    }
  }

  Widget renderError(Object e) {
    renderFailed = true;
    final current = source.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && current == source.text) {
        setState(() => error = 'Fórmula inválida: $e');
      }
    });
    return const Text('No se pudo representar la fórmula.');
  }

  Future<void> save() async {
    if (busy || ast == null || error != null || renderFailed) return;
    setState(() => busy = true);
    ui.Image? image;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final size = boundary.size;
      if (renderFailed ||
          !size.width.isFinite ||
          !size.height.isFinite ||
          size.isEmpty ||
          size.width > 2048 ||
          size.height > 2048 ||
          size.width * size.height > 1024 * 1024) {
        throw const FormatException(
          'La fórmula es demasiado grande. Dividila en varias fórmulas.',
        );
      }
      image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw const FormatException('No se pudo generar la fórmula.');
      }
      final assetId = await widget.assets.put(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
      if (!mounted) return;
      final scale = math.min(
        1.0,
        math.min(widget.maxWidth / size.width, widget.maxHeight / size.height),
      );
      final old = widget.object;
      final result = old == null
          ? PageObject(
              id: widget.id ?? const Uuid().v4(),
              kind: PageObjectKind.latex,
              x: widget.position.dx,
              y: widget.position.dy,
              width: size.width * scale,
              height: size.height * scale,
              text: source.text,
              assetId: assetId,
              argb: argb,
              fontSize: fontSize * scale,
            )
          : old.copyWith(
              text: source.text,
              assetId: assetId,
              width: size.width * scale,
              height: size.height * scale,
              fontSize: fontSize * scale,
            );
      Navigator.pop(context, result);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          error = 'No se pudo guardar la fórmula: $e';
          busy = false;
        });
      }
    } finally {
      image?.dispose();
    }
  }

  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.object == null ? 'Insertar fórmula' : 'Editar fórmula'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: source,
              enabled: !busy,
              minLines: 2,
              maxLines: 6,
              maxLength: 4000,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'LaTeX matemático',
                helperText: r'Ejemplo: \frac{1}{2}, x^2, \sqrt{x}',
              ),
            ),
            const SizedBox(height: 16),
            const Text('Vista previa'),
            const SizedBox(height: 8),
            if (ast != null)
              Container(
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(
                  minHeight: 80,
                  maxHeight: 240,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xfff3f3f3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Math(
                          ast: ast,
                          textScaleFactor: 1,
                          textStyle: TextStyle(
                            fontSize: fontSize,
                            color: Color(argb),
                          ),
                          onErrorFallback: renderError,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: busy || ast == null || error != null || renderFailed
            ? null
            : save,
        child: Text(widget.object == null ? 'Insertar' : 'Guardar'),
      ),
    ],
  );
}
