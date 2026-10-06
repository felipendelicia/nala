import 'package:apuntes/document/notebook.dart';

InkStroke fixtureStroke({String id = 'stroke-1'}) => InkStroke(
  id: id, tool: InkTool.pen, argb: 0xff202020, width: 2,
  points: [InkPoint(x: 10, y: 20, pressure: .25), InkPoint(x: 30, y: 40, pressure: .75)],
);

Notebook fixtureNotebook({String id = 'doc-1'}) => Notebook(
  id: id, title: 'Álgebra', subject: 'Matemática',
  updatedAt: DateTime.utc(2026, 10, 6),
  pages: [NotebookPage(id: 'page-1', width: 595.28, height: 841.89,
    background: PageBackground.paper(PaperPattern.grid), strokes: [fixtureStroke()])],
);
