import 'package:flutter/material.dart';

const nalaGreen = Color(0xff24584b);
const nalaBackground = Color(0xfff5f3ed);
const nalaInk = Color(0xff202020);
ThemeData nalaTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: nalaGreen,
    surface: nalaBackground,
  ),
  scaffoldBackgroundColor: nalaBackground,
  appBarTheme: const AppBarTheme(
    backgroundColor: nalaBackground,
    foregroundColor: nalaInk,
    elevation: 0,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
    filled: true,
    fillColor: Colors.white,
  ),
  visualDensity: VisualDensity.standard,
);
String paperLabel(int index) =>
    ['Blanca', 'Rayada', 'Cuadriculada', 'Punteada'][index];
