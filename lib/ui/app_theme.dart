import 'package:flutter/material.dart';

const nalaAnnotation = Color(0xff202020);
const nalaSidebar = Color(0xff111111);
const nalaBackground = Colors.white;
const nalaInk = Color(0xff181818);

ThemeData nalaTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.black,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    brightness: brightness,
    primary: dark ? Colors.white : Colors.black,
    onPrimary: dark ? Colors.black : Colors.white,
    surface: dark ? const Color(0xff101010) : Colors.white,
    onSurface: dark ? Colors.white : nalaInk,
    error: dark ? Colors.white : Colors.black,
    onError: dark ? Colors.black : Colors.white,
    errorContainer: dark ? const Color(0xff303030) : const Color(0xffeeeeee),
    onErrorContainer: dark ? Colors.white : Colors.black,
    surfaceTint: Colors.transparent,
  );
  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: dark ? Colors.black : nalaBackground,
  );
  return theme.copyWith(
    textTheme: theme.textTheme.copyWith(
      headlineLarge: theme.textTheme.headlineLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
      ),
      headlineSmall: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
      ),
      titleLarge: theme.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      bodyMedium: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      labelLarge: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 72,
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: scheme.onSurface,
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .45),
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff202020) : const Color(0xfff2f2f2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    visualDensity: VisualDensity.standard,
  );
}

String paperLabel(int index) => [
  'Blanca',
  'Rayada',
  'Cuadriculada',
  'Punteada',
  'Cornell',
  'Agenda semanal',
][index];
