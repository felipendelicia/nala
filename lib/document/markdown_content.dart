import 'package:markdown/markdown.dart' as md;

enum MarkdownEmphasis { bold, italic, code, strike }

class MarkdownRun {
  const MarkdownRun(this.text, {this.emphasis = const {}, this.link});

  final String text;
  final Set<MarkdownEmphasis> emphasis;
  final String? link;
}

class MarkdownBlock {
  const MarkdownBlock({
    this.runs = const [],
    this.indent = 0,
    this.heading = 0,
    this.code = false,
    this.divider = false,
    this.marker,
    this.codeLanguage,
  });

  final List<MarkdownRun> runs;
  final double indent;
  final int heading;
  final bool code, divider;
  final String? marker, codeLanguage;

  double sizeFor(double base) =>
      base *
      switch (heading) {
        1 => 1.75,
        2 => 1.4,
        3 => 1.18,
        _ => code ? .92 : 1,
      };

  double get gap => heading > 0 ? 11 : 8;
}

/// A shared representation of Markdown for the canvas, chat and PDF export.
/// All content is text. Parsing never opens links or loads remote images.
List<MarkdownBlock> parseMarkdown(String markdown) => _blocks(
  md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parse(markdown),
).toList();

Iterable<MarkdownBlock> _blocks(
  Iterable<md.Node> nodes, {
  double indent = 0,
  String? prefix,
}) sync* {
  for (final node in nodes) {
    if (node is! md.Element) {
      yield MarkdownBlock(
        indent: indent,
        runs: [MarkdownRun(node.textContent)],
      );
      continue;
    }
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'ul':
      case 'ol':
        var index = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        for (final child in children.whereType<md.Element>()) {
          yield* _blocks(
            _wrapListParagraphs(child.children ?? const []),
            indent: indent + 14,
            prefix: node.tag == 'ul' ? '•  ' : '${index++}.  ',
          );
        }
      case 'blockquote':
        yield* _blocks(children, indent: indent + 14, prefix: '›  ');
      case 'pre':
        final className = children
            .whereType<md.Element>()
            .firstOrNull
            ?.attributes['class'];
        yield MarkdownBlock(
          indent: indent + 8,
          code: true,
          codeLanguage: className?.startsWith('language-') == true
              ? className!.substring('language-'.length)
              : null,
          runs: [
            MarkdownRun(
              node.textContent.trimRight(),
              emphasis: const {MarkdownEmphasis.code},
            ),
          ],
        );
      case 'table':
        for (final section in children.whereType<md.Element>()) {
          for (final row in (section.children ?? []).whereType<md.Element>()) {
            final cells = (row.children ?? []).whereType<md.Element>().toList();
            yield MarkdownBlock(
              indent: indent,
              runs: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0) const MarkdownRun('  |  '),
                  ..._runs(
                    cells[i].children ?? const [],
                    emphasis: section.tag == 'thead'
                        ? const {MarkdownEmphasis.bold}
                        : const {},
                  ),
                ],
              ],
            );
          }
        }
      case 'hr':
        yield MarkdownBlock(indent: indent, divider: true);
      default:
        final heading = node.tag.length == 2 && node.tag.startsWith('h')
            ? int.tryParse(node.tag.substring(1)) ?? 0
            : 0;
        yield MarkdownBlock(
          indent: indent,
          heading: heading,
          marker: switch (prefix?.trim()) {
            '•' => '-',
            '›' => '>',
            final other => other,
          },
          runs: [if (prefix != null) MarkdownRun(prefix), ..._runs(children)],
        );
        prefix = null;
    }
  }
}

/// Source sections at blank-line boundaries outside fenced code. Existing
/// Markdown stays untouched when the section fits a page by itself.
Iterable<String> markdownSections(String markdown) sync* {
  final fencePattern = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
  final section = <String>[];
  String? fence;
  for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
    if (fence == null && line.trim().isEmpty) {
      if (section.isNotEmpty) {
        yield section.join('\n');
        section.clear();
      }
      continue;
    }
    section.add(line);
    final match = fencePattern.firstMatch(line);
    if (match == null) continue;
    final token = match[1]!;
    if (fence == null) {
      fence = token;
    } else if (token.startsWith(fence) && match[2]!.trim().isEmpty) {
      fence = null;
    }
  }
  if (section.isNotEmpty) yield section.join('\n');
}

/// Rebuilds a renderable Markdown fragment when a block must cross a page
/// boundary. Inline emphasis and code fences are balanced on each sheet.
String markdownBlockSource(MarkdownBlock block, {int start = 0, int? end}) {
  if (block.divider) return '---';
  if (block.code) {
    final text = block.runs.single.text.substring(start, end);
    final fence = _backticksFor(text, minimum: 3);
    return '$fence${block.codeLanguage ?? ''}\n$text\n$fence';
  }
  final hasMarker = start == 0 && block.marker != null;
  var offset = 0;
  final source = StringBuffer();
  final fragment = StringBuffer();
  MarkdownRun? format;
  for (final run in block.runs) {
    final next = offset + run.text.length;
    final first = start > offset ? start - offset : 0;
    final last = end != null && end < next ? end - offset : run.text.length;
    if (last > first && (!hasMarker || offset > 0)) {
      if (format != null && !_sameFormatting(format, run)) {
        source.write(_runSource(format, fragment.toString()));
        fragment.clear();
      }
      format = run;
      fragment.write(run.text.substring(first, last));
    }
    offset = next;
    if (end != null && offset >= end) break;
  }
  if (format != null) source.write(_runSource(format, fragment.toString()));
  final text = source.toString().trim();
  final title = block.heading > 0 ? '${'#' * block.heading} ' : '';
  final marker = hasMarker ? '${block.marker} ' : '';
  return '$marker$title$text';
}

bool _sameFormatting(MarkdownRun first, MarkdownRun second) =>
    first.link == second.link &&
    first.emphasis.length == second.emphasis.length &&
    first.emphasis.containsAll(second.emphasis);

String _runSource(MarkdownRun run, String text) {
  final middle = text.trim();
  if (middle.isEmpty) return text;
  final start = text.length - text.trimLeft().length;
  final end = start + middle.length;
  final code = run.emphasis.contains(MarkdownEmphasis.code);
  final fence = code ? _backticksFor(middle) : null;
  // Separate code delimiters from backticks in the preserved literal.
  final codePadding = code && (middle.startsWith('`') || middle.endsWith('`'))
      ? ' '
      : '';
  var content = code
      ? '$fence$codePadding$middle$codePadding$fence'
      : middle.replaceAllMapped(
          RegExp(r'([\\`*_{}\[\]()#+.!<>|~&-])'),
          (match) => '\\${match[0]}',
        );
  if (run.emphasis.contains(MarkdownEmphasis.italic)) content = '*$content*';
  if (run.emphasis.contains(MarkdownEmphasis.bold)) content = '**$content**';
  if (run.emphasis.contains(MarkdownEmphasis.strike)) content = '~~$content~~';
  final link = run.link;
  if (link != null) {
    final destination = link.replaceAll('>', '%3E').replaceAll('<', '%3C');
    content = '[$content](<$destination>)';
  }
  return '${text.substring(0, start)}$content${text.substring(end)}';
}

String _backticksFor(String text, {int minimum = 1}) {
  var length = minimum;
  for (final match in RegExp(r'`+').allMatches(text)) {
    if (match.end - match.start >= length) length = match.end - match.start + 1;
  }
  return '`' * length;
}

Iterable<md.Node> _wrapListParagraphs(List<md.Node> nodes) sync* {
  var inline = <md.Node>[];
  for (final node in nodes) {
    if (node is md.Element &&
        const {
          'p',
          'ul',
          'ol',
          'blockquote',
          'pre',
          'table',
          'hr',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
        }.contains(node.tag)) {
      if (inline.isNotEmpty) yield md.Element('p', inline);
      inline = [];
      yield node;
    } else {
      inline.add(node);
    }
  }
  if (inline.isNotEmpty) yield md.Element('p', inline);
}

Iterable<MarkdownRun> _runs(
  Iterable<md.Node> nodes, {
  Set<MarkdownEmphasis> emphasis = const {},
  String? link,
}) sync* {
  for (final node in nodes) {
    if (node is! md.Element) {
      yield MarkdownRun(node.textContent, emphasis: emphasis, link: link);
      continue;
    }
    switch (node.tag) {
      case 'br':
        yield const MarkdownRun('\n');
      case 'img':
        final label = node.attributes['alt'];
        if (label != null) yield MarkdownRun(label, emphasis: emphasis);
      case 'input':
        yield MarkdownRun(node.attributes.containsKey('checked') ? '✓ ' : '□ ');
      default:
        final added = switch (node.tag) {
          'strong' => MarkdownEmphasis.bold,
          'em' => MarkdownEmphasis.italic,
          'code' => MarkdownEmphasis.code,
          'del' => MarkdownEmphasis.strike,
          _ => null,
        };
        yield* _runs(
          node.children ?? const [],
          emphasis: added == null ? emphasis : {...emphasis, added},
          link: node.tag == 'a' ? node.attributes['href'] : link,
        );
    }
  }
}
