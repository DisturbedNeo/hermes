import 'package:flutter/material.dart';

class HermesInputTheme extends ThemeExtension<HermesInputTheme> {
  final InputDecorationTheme inputDecorationTheme;
  final TextSelectionThemeData textSelectionTheme;

  const HermesInputTheme({
    required this.inputDecorationTheme,
    required this.textSelectionTheme,
  });

  factory HermesInputTheme.light({
    required Color primary,
    required Color surface,
    required Color onSurface,
  }) => HermesInputTheme(
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: TextStyle(color: onSurface.withAlpha(150)),
      labelStyle: TextStyle(color: primary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: primary,
      selectionColor: primary.withValues(alpha: 0.3),
      selectionHandleColor: primary,
    ),
  );

  factory HermesInputTheme.dark({
    required Color secondary,
    required Color surface,
    required Color onSurface,
  }) => HermesInputTheme(
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface.withAlpha(240),
      hintStyle: TextStyle(color: onSurface.withAlpha(150)),
      labelStyle: TextStyle(color: secondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: surface.withAlpha(100)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: secondary.withAlpha(200), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: secondary,
      selectionColor: secondary.withValues(alpha: 0.3),
      selectionHandleColor: secondary,
    ),
  );

  @override
  ThemeExtension<HermesInputTheme> copyWith({
    InputDecorationTheme? inputDecorationTheme,
    TextSelectionThemeData? textSelectionTheme,
  }) => HermesInputTheme(
    inputDecorationTheme: inputDecorationTheme ?? this.inputDecorationTheme,
    textSelectionTheme: textSelectionTheme ?? this.textSelectionTheme,
  );

  @override
  ThemeExtension<HermesInputTheme> lerp(
    covariant ThemeExtension<HermesInputTheme>? other,
    double t,
  ) {
    if (other is! HermesInputTheme) {
      return this;
    }

    return HermesInputTheme(
      inputDecorationTheme: _lerpInputDecorationTheme(
        inputDecorationTheme,
        other.inputDecorationTheme,
        t,
      ),
      textSelectionTheme: _lerpTextSelectionTheme(
        textSelectionTheme,
        other.textSelectionTheme,
        t,
      ),
    );
  }

  static InputDecorationTheme _lerpInputDecorationTheme(
    InputDecorationTheme a,
    InputDecorationTheme b,
    double t,
  ) => InputDecorationTheme(
    filled: t < 0.5 ? a.filled : b.filled,
    fillColor: Color.lerp(a.fillColor, b.fillColor, t),
    hintStyle: TextStyle.lerp(a.hintStyle, b.hintStyle, t),
    labelStyle: TextStyle.lerp(a.labelStyle, b.labelStyle, t),
    border: t < 0.5 ? a.border : b.border,
    focusedBorder: t < 0.5 ? a.focusedBorder : b.focusedBorder,
    errorBorder: t < 0.5 ? a.errorBorder : b.errorBorder,
    focusedErrorBorder: t < 0.5 ? a.focusedErrorBorder : b.focusedErrorBorder,
  );

  static TextSelectionThemeData _lerpTextSelectionTheme(
    TextSelectionThemeData a,
    TextSelectionThemeData b,
    double t,
  ) => TextSelectionThemeData(
    cursorColor: Color.lerp(a.cursorColor, b.cursorColor, t),
    selectionColor: Color.lerp(a.selectionColor, b.selectionColor, t),
    selectionHandleColor: Color.lerp(
      a.selectionHandleColor,
      b.selectionHandleColor,
      t,
    ),
  );
}

extension CodexInputThemeExtension on ThemeData {
  HermesInputTheme? get codexInput => extension<HermesInputTheme>();
}
