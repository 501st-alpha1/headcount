import 'package:flutter/material.dart';

/// Light and dark themes for Headcount, both derived from the same seed
/// color so they feel like the same app in either mode rather than two
/// unrelated designs. Selection between them is automatic — see
/// HeadcountApp.themeMode in main.dart, which follows the OS-level light/
/// dark setting rather than exposing an in-app toggle.
const _seedColor = Colors.teal;

ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ),
  );
}

ThemeData buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
  );
}
