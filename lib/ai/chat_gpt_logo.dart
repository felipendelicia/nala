import 'package:flutter/material.dart';

class ChatGptLogo extends StatelessWidget {
  const ChatGptLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    Theme.of(context).brightness == Brightness.dark
        ? 'assets/chatgpt-blossom-dark.png'
        : 'assets/chatgpt-blossom.png',
    width: size,
    height: size,
    excludeFromSemantics: true,
  );
}
