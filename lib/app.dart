import 'package:flutter/material.dart';
import 'document/notebook.dart';
import 'editor/editor_screen.dart';

class NalaApp extends StatelessWidget {
  const NalaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'Nala', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff24584b)),
      scaffoldBackgroundColor: const Color(0xfff5f3ed)),
    home: EditorScreen(notebook: Notebook.blank(id: 'first', pageId: 'first-page',
      title: 'Mi cuaderno', pattern: PaperPattern.grid, now: DateTime.now())));
}
