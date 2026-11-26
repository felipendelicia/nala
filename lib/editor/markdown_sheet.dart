import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../document/markdown_content.dart';
import '../document/notebook.dart';

const markdownSheetMargin = 48.0;
const markdownSheetFontSize = 15.0;
const markdownLineHeight = 1.45;
const markdownSheetWidth = 595.28;
const markdownSheetHeight = 841.89;
const _sheetLocale = Locale('es');
const _sheetTextStyle = TextStyle(
  inherit: false,
  fontFamily: 'NalaSans',
  color: Color(0xff202020),
  fontSize: markdownSheetFontSize,
  height: markdownLineHeight,
);

List<NotebookPage> updateMarkdownSheets(
  NotebookPage page,
  String markdown, {
  required String Function() newId,
}) {
  final sections = _paginateMarkdown(markdown);
  final preserveDimensions =
      page.height > markdownSheetHeight &&
      (page.comments.any((comment) => comment.y > markdownSheetHeight) ||
          page.strokes.any(
            (stroke) =>
                stroke.points.any((point) => point.y > markdownSheetHeight),
          ) ||
          page.objects.any(
            (object) => object.y + object.height > markdownSheetHeight,
          ));
  return [
    page.copyWith(
      height: preserveDimensions ? page.height : markdownSheetHeight,
      markdown: sections.first,
    ),
    for (final section in sections.skip(1))
      _blankSheet(newId()).copyWith(markdown: section),
  ];
}

NotebookPage _blankSheet(String id) => NotebookPage(
  id: id,
  width: markdownSheetWidth,
  height: markdownSheetHeight,
  background: const PageBackground.paper(PaperPattern.blank),
);

const _contentWidth = markdownSheetWidth - 2 * markdownSheetMargin;
const _pageCapacity = markdownSheetHeight - 2 * markdownSheetMargin - 2;

TextPainter _layoutSheetBlock(MarkdownBlock block, double width) => TextPainter(
  text: _blockSpan(block, _sheetTextStyle),
  textDirection: TextDirection.ltr,
  textScaler: TextScaler.noScaling,
  locale: _sheetLocale,
)..layout(maxWidth: width - math.min(block.indent, width / 4));

double _measureBlock(MarkdownBlock block) {
  if (block.divider) return block.gap + 1;
  final painter = _layoutSheetBlock(block, _contentWidth);
  final height = painter.height + block.gap;
  painter.dispose();
  return height;
}

void paintMarkdownSheet(Canvas canvas, String markdown, Size size) {
  final width = size.width - 2 * markdownSheetMargin;
  final height = size.height - 2 * markdownSheetMargin;
  if (width <= 0 || height <= 0) return;
  final rows = <({double indent, double height, TextPainter? painter})>[];
  var contentHeight = 0.0;
  try {
    for (final block in parseMarkdown(markdown)) {
      final painter = block.divider ? null : _layoutSheetBlock(block, width);
      final rowHeight = (painter?.height ?? 1) + block.gap;
      rows.add((
        indent: math.min(block.indent, width / 4),
        height: rowHeight,
        painter: painter,
      ));
      contentHeight += rowHeight;
    }
    if (contentHeight == 0) return;
    final divider = Paint()..color = _sheetTextStyle.color!.withAlpha(46);
    canvas.save();
    try {
      canvas.translate(markdownSheetMargin, markdownSheetMargin);
      canvas.scale(math.min(1, height / contentHeight));
      var y = 0.0;
      for (final row in rows) {
        final painter = row.painter;
        if (painter == null) {
          canvas.drawRect(
            Rect.fromLTWH(row.indent, y, width - row.indent, 1),
            divider,
          );
        } else {
          painter.paint(canvas, Offset(row.indent, y));
        }
        y += row.height;
      }
    } finally {
      canvas.restore();
    }
  } finally {
    for (final row in rows) {
      row.painter?.dispose();
    }
  }
}

double _measureMarkdown(String markdown) => parseMarkdown(
  markdown,
).fold(0, (height, block) => height + _measureBlock(block));

List<String> _paginateMarkdown(String markdown) {
  if (markdown.trim().isEmpty) {
    throw const FormatException('El resumen está vacío.');
  }
  if (_measureMarkdown(markdown) <= _pageCapacity) return [markdown];
  final pages = <String>[];
  String contents = '';
  for (final section in _pageSections(markdown)) {
    final combined = contents.isEmpty ? section : '$contents\n\n$section';
    if (contents.isNotEmpty && _measureMarkdown(combined) > _pageCapacity) {
      pages.add(contents);
      contents = section;
    } else {
      contents = combined;
    }
  }
  if (contents.isNotEmpty) pages.add(contents);
  return pages;
}

Iterable<String> _pageSections(String markdown) sync* {
  String? heading;
  for (final source in markdownSections(markdown)) {
    final blocks = parseMarkdown(source);
    final sections =
        blocks.fold(0.0, (height, block) => height + _measureBlock(block)) <=
            _pageCapacity
        ? [source]
        : [for (final block in blocks) ..._splitBlock(block)];
    for (final section in sections) {
      if (heading != null) {
        final together = '$heading\n\n$section';
        if (_measureMarkdown(together) <= _pageCapacity) {
          yield together;
          heading = null;
          continue;
        }
        yield heading;
        heading = null;
      }
      final first = parseMarkdown(section).singleOrNull;
      if (first != null && first.heading > 0) {
        heading = section;
      } else {
        yield section;
      }
    }
  }
  if (heading != null) yield heading;
}

Iterable<String> _splitBlock(MarkdownBlock block) sync* {
  final source = markdownBlockSource(block);
  if (_measureMarkdown(source) <= _pageCapacity) {
    yield source;
    return;
  }

  final text = block.runs.map((run) => run.text).join();
  final offsets = <int>[0];
  for (final character in text.characters) {
    offsets.add(offsets.last + character.length);
  }
  final breaks = <int>[];
  for (var i = 1; i < offsets.length; i++) {
    final character = text.substring(offsets[i - 1], offsets[i]);
    if (block.code ? character == '\n' : character.trim().isEmpty) {
      breaks.add(i);
    }
  }
  var start = 0;
  while (start < offsets.length - 1) {
    String fragment(int end) =>
        markdownBlockSource(block, start: offsets[start], end: offsets[end]);
    var low = start + 1;
    var high = offsets.length - 1;
    var lastFit = low;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (_measureMarkdown(fragment(middle)) <= _pageCapacity) {
        lastFit = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    if (lastFit < offsets.length - 1) {
      final preferred = breaks.lastWhere(
        (boundary) => boundary > start && boundary <= lastFit,
        orElse: () => lastFit,
      );
      if (preferred - start >= (lastFit - start) ~/ 2) lastFit = preferred;
    }
    yield fragment(lastFit);
    start = lastFit;
  }
}

class MarkdownSheet extends StatelessWidget {
  const MarkdownSheet({super.key, required this.page});

  final NotebookPage page;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(markdownSheetMargin),
    child: LayoutBuilder(
      builder: (_, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: constraints.maxWidth,
          child: MarkdownContent._sheet(page.markdown!),
        ),
      ),
    ),
  );
}

class MarkdownContent extends StatefulWidget {
  const MarkdownContent({
    super.key,
    required this.markdown,
    this.onLink,
    this.style,
    this.textScaler,
  }) : _layoutAsSheet = false;

  const MarkdownContent._sheet(this.markdown)
    : _layoutAsSheet = true,
      onLink = null,
      style = _sheetTextStyle,
      textScaler = TextScaler.noScaling;

  final String markdown;
  final ValueChanged<String>? onLink;
  final TextStyle? style;
  final TextScaler? textScaler;
  final bool _layoutAsSheet;

  @override
  State<MarkdownContent> createState() => _MarkdownContentState();
}

class _MarkdownContentState extends State<MarkdownContent> {
  late List<MarkdownBlock> _blocks = parseMarkdown(widget.markdown);

  @override
  void didUpdateWidget(MarkdownContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) {
      _blocks = parseMarkdown(widget.markdown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style =
        widget.style ??
        DefaultTextStyle.of(context).style.copyWith(height: markdownLineHeight);
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final block in _blocks)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: math.min(block.indent, constraints.maxWidth / 4),
                bottom: block.gap,
              ),
              child: block.divider
                  ? ColoredBox(
                      color: style.color != null
                          ? style.color!.withAlpha(46)
                          : colors.outlineVariant,
                      child: const SizedBox(height: 1),
                    )
                  : widget._layoutAsSheet
                  ? RichText(
                      text: _blockSpan(block, style),
                      textDirection: TextDirection.ltr,
                      textScaler: TextScaler.noScaling,
                      locale: _sheetLocale,
                    )
                  : widget.onLink == null ||
                        !block.runs.any((run) => run.link != null)
                  ? Text.rich(
                      _blockSpan(block, style),
                      textScaler: widget.textScaler,
                    )
                  : _LinkedMarkdownBlock(
                      block: block,
                      style: style,
                      textScaler: widget.textScaler,
                      onLink: widget.onLink!,
                    ),
            ),
        ],
      ),
    );
  }
}

TextSpan _blockSpan(
  MarkdownBlock block,
  TextStyle style, {
  Map<String, TapGestureRecognizer>? links,
}) => TextSpan(
  style: style.copyWith(
    fontSize: block.sizeFor(style.fontSize ?? 14),
    fontWeight: block.heading > 0 ? FontWeight.bold : null,
  ),
  children: [
    for (final run in block.runs)
      TextSpan(
        text: run.text,
        recognizer: links?[run.link],
        style: TextStyle(
          fontWeight: run.emphasis.contains(MarkdownEmphasis.bold)
              ? FontWeight.bold
              : null,
          fontStyle: run.emphasis.contains(MarkdownEmphasis.italic)
              ? FontStyle.italic
              : null,
          fontFamily: run.emphasis.contains(MarkdownEmphasis.code)
              ? 'monospace'
              : null,
          decoration: TextDecoration.combine([
            if (run.emphasis.contains(MarkdownEmphasis.strike))
              TextDecoration.lineThrough,
            if (run.link != null) TextDecoration.underline,
          ]),
        ),
      ),
  ],
);

class _LinkedMarkdownBlock extends StatefulWidget {
  const _LinkedMarkdownBlock({
    required this.block,
    required this.style,
    required this.textScaler,
    required this.onLink,
  });

  final MarkdownBlock block;
  final TextStyle style;
  final TextScaler? textScaler;
  final ValueChanged<String> onLink;

  @override
  State<_LinkedMarkdownBlock> createState() => _LinkedMarkdownBlockState();
}

class _LinkedMarkdownBlockState extends State<_LinkedMarkdownBlock> {
  final _links = <String, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _updateLinks();
  }

  @override
  void didUpdateWidget(_LinkedMarkdownBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) _updateLinks();
  }

  void _updateLinks() {
    final destinations = widget.block.runs
        .map((run) => run.link)
        .nonNulls
        .toSet();
    _links.removeWhere((destination, recognizer) {
      if (destinations.contains(destination)) return false;
      recognizer.dispose();
      return true;
    });
    for (final destination in destinations) {
      _links.putIfAbsent(
        destination,
        () => TapGestureRecognizer()..onTap = () => widget.onLink(destination),
      );
    }
  }

  @override
  void dispose() {
    for (final recognizer in _links.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text.rich(
    _blockSpan(widget.block, widget.style, links: _links),
    textScaler: widget.textScaler,
  );
}
