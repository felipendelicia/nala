import 'package:flutter/material.dart';
import '../document/notebook.dart';
import 'paper_canvas.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.notebook});
  final Notebook notebook;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}
class _EditorScreenState extends State<EditorScreen> {
  late Notebook book = widget.notebook;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(book.title), actions: [DropdownButton<PaperPattern>(
      value: book.pages.first.background.pattern,
      items: PaperPattern.values.map((p) => DropdownMenuItem(value: p, child: Text(
        ['Blanca', 'Rayada', 'Cuadriculada', 'Punteada'][p.index]))).toList(),
      onChanged: (p) { if (p != null) setState(() => book = book.copyWith(pages: [book.pages.first.copyWith(background: PageBackground.paper(p))])); })]),
    body: Padding(padding: const EdgeInsets.all(24), child: Center(child: FittedBox(
      child: PaperCanvas(page: book.pages.first, tool: EditorTool.pen,
        onStroke: (stroke) => setState(() => book = book.copyWith(pages: [book.pages.first.copyWith(
          strokes: [...book.pages.first.strokes, stroke])])))))),
  );
}
