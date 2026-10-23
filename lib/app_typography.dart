import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Offline text styling helpers that preserve the app's existing typography
/// parameters while using Flutter's platform-default sans-serif font.
///
/// Keep this API limited to the styles this app uses. If Inter is bundled in
/// the future, its font family can be selected here without changing screens.
class AppTypography {
  static TextStyle textStyle({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    ui.Paint? foreground,
    ui.Paint? background,
    List<ui.Shadow>? shadows,
    List<ui.FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    return (textStyle ?? const TextStyle()).copyWith(
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  static TextTheme textTheme([TextTheme? textTheme]) {
    final base = textTheme ?? ThemeData.light().textTheme;
    return TextTheme(
      displayLarge: textStyle(textStyle: base.displayLarge),
      displayMedium: textStyle(textStyle: base.displayMedium),
      displaySmall: textStyle(textStyle: base.displaySmall),
      headlineLarge: textStyle(textStyle: base.headlineLarge),
      headlineMedium: textStyle(textStyle: base.headlineMedium),
      headlineSmall: textStyle(textStyle: base.headlineSmall),
      titleLarge: textStyle(textStyle: base.titleLarge),
      titleMedium: textStyle(textStyle: base.titleMedium),
      titleSmall: textStyle(textStyle: base.titleSmall),
      bodyLarge: textStyle(textStyle: base.bodyLarge),
      bodyMedium: textStyle(textStyle: base.bodyMedium),
      bodySmall: textStyle(textStyle: base.bodySmall),
      labelLarge: textStyle(textStyle: base.labelLarge),
      labelMedium: textStyle(textStyle: base.labelMedium),
      labelSmall: textStyle(textStyle: base.labelSmall),
    );
  }
}
