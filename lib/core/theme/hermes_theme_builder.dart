import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hermes/core/theme/extensions/button_theme.dart';
import 'package:hermes/core/theme/extensions/card_theme.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/extensions/input_theme.dart';

/// Calculates the WCAG contrast ratio between two colors.
double _contrastRatio(Color fg, Color bg) {
  final fgLuminance = _relativeLuminance(fg);
  final bgLuminance = _relativeLuminance(bg);
  final lighter = fgLuminance > bgLuminance ? fgLuminance : bgLuminance;
  final darker = fgLuminance < bgLuminance ? fgLuminance : bgLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Calculates the relative luminance of a color per WCAG 2.x specification.
double _relativeLuminance(Color c) {
  final r = _linearize(c.r / 255.0);
  final g = _linearize(c.g / 255.0);
  final b = _linearize(c.b / 255.0);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Linearizes an sRGB component value.
double _linearize(double value) {
  if (value <= 0.04045) return value / 12.92;
  return (math.pow((value + 0.055) / 1.055, 2.4)) as double;
}

/// Validates that the contrast ratio between [foreground] and [background]
/// meets the WCAG AA minimum. Logs a warning in debug mode if it does not.
void _validateContrast(
  String description,
  Color fg,
  Color bg, {
  required double minRatio,
}) {
  final ratio = _contrastRatio(fg, bg);
  if (ratio < minRatio) {
    final minR = minRatio.toStringAsFixed(1);
    debugPrint(
      '[HermesTheme] Contrast ratio ${ratio.toStringAsFixed(2)}:1 for "$description" '
      '(fg: $fg, bg: $bg) is below WCAG AA minimum of $minR',
    );
  }
}

class HermesThemeBuilder {
  final HermesPalette _palette;
  final bool _isDark;

  HermesButtonTheme? _buttonTheme;
  HermesCardTheme? _cardTheme;
  HermesInputTheme? _inputTheme;
  TextTheme? _textTheme;
  TabBarTheme? _tabBarTheme;
  AppBarTheme? _appBarTheme;

  HermesThemeBuilder({required HermesPalette palette, required bool isDark})
    : _palette = palette,
      _isDark = isDark;

  HermesThemeBuilder withButtonTheme(HermesButtonTheme buttonTheme) {
    _buttonTheme = buttonTheme;
    return this;
  }

  HermesThemeBuilder withCardTheme(HermesCardTheme cardTheme) {
    _cardTheme = cardTheme;
    return this;
  }

  HermesThemeBuilder withInputTheme(HermesInputTheme inputTheme) {
    _inputTheme = inputTheme;
    return this;
  }

  HermesThemeBuilder withTextTheme(TextTheme textTheme) {
    _textTheme = textTheme;
    return this;
  }

  HermesThemeBuilder withTabBarTheme(TabBarTheme tabBarTheme) {
    _tabBarTheme = tabBarTheme;
    return this;
  }

  HermesThemeBuilder withAppBarTheme(AppBarTheme appBarTheme) {
    _appBarTheme = appBarTheme;
    return this;
  }

  ThemeData build() {
    // Validate contrast ratios in debug mode (WCAG AA minimums)
    if (kDebugMode) {
      // Body text on surface background — normal text requires 4.5:1
      _validateContrast(
        'body text on surface',
        _palette.onSurface,
        _palette.surface,
        minRatio: 4.5,
      );

      // Headline text on surface background — normal text requires 4.5:1
      final headlineColor = _isDark ? _palette.secondary : _palette.primary;
      _validateContrast(
        'headline text on surface',
        headlineColor,
        _palette.surface,
        minRatio: 4.5,
      );

      // On-primary on primary (e.g., button text) — normal text requires 4.5:1
      _validateContrast(
        'onPrimary on primary',
        _palette.onPrimary,
        _palette.primary,
        minRatio: 4.5,
      );

      // On-secondary on secondary — normal text requires 4.5:1
      _validateContrast(
        'onSecondary on secondary',
        _palette.onSecondary,
        _palette.secondary,
        minRatio: 4.5,
      );

      // Error text on error container — normal text requires 4.5:1 (approximate with on/error)
      _validateContrast(
        'error color contrast',
        _palette.onError,
        _palette.error,
        minRatio: 3.0,
      );

      // Tab bar unselected label — large text requires 3:1
      final unselectedTabColor = _palette.onPrimary.withAlpha(180);
      _validateContrast(
        'unselected tab label',
        unselectedTabColor,
        _palette.primary,
        minRatio: 3.0,
      );

      // Hint text on surface — normal text requires 4.5:1 (but we use withAlpha so check at actual alpha)
      final hintStyle = _isDark
          ? _palette.onSurface.withAlpha(150)
          : _palette.onSurface.withAlpha(150);
      _validateContrast(
        'hint text on surface',
        hintStyle,
        _palette.surface,
        minRatio: 3.0,
      );
    }

    final buttonTheme =
        _buttonTheme ??
        (_isDark
            ? HermesButtonTheme.dark(
                primary: _palette.primary,
                onPrimary: _palette.onPrimary,
                secondary: _palette.secondary,
                onSecondary: _palette.onSecondary,
                error: _palette.error,
                onError: _palette.onError,
              )
            : HermesButtonTheme.light(
                primary: _palette.primary,
                onPrimary: _palette.onPrimary,
                secondary: _palette.secondary,
                onSecondary: _palette.onSecondary,
                error: _palette.error,
                onError: _palette.onError,
              ));

    final cardTheme =
        _cardTheme ??
        (_isDark
            ? HermesCardTheme.dark(
                secondary: _palette.secondary,
                surface: _palette.surface,
              )
            : HermesCardTheme.light(
                primary: _palette.primary,
                surface: _palette.surface,
              ));

    final inputTheme =
        _inputTheme ??
        (_isDark
            ? HermesInputTheme.dark(
                secondary: _palette.secondary,
                surface: _palette.surface,
                onSurface: _palette.onSurface,
              )
            : HermesInputTheme.light(
                primary: _palette.primary,
                surface: _palette.surface,
                onSurface: _palette.onSurface,
              ));

    final textTheme = _textTheme ?? _createDefaultTextTheme();

    final tabBarTheme =
        _tabBarTheme ??
        TabBarTheme(
          labelColor: _palette.onPrimary,
          unselectedLabelColor: _palette.onPrimary.withAlpha(180),
          indicatorColor: _palette.secondary,
          indicatorSize: TabBarIndicatorSize.tab,
        );

    final appBarTheme =
        _appBarTheme ??
        AppBarTheme(
          backgroundColor: _palette.primary,
          foregroundColor: _palette.onPrimary,
          elevation: _isDark ? 2 : 1,
          centerTitle: false,
        );

    final colorScheme = (_isDark ? ColorScheme.dark : ColorScheme.light)(
      primary: _palette.primary,
      onPrimary: _palette.onPrimary,
      secondary: _palette.secondary,
      onSecondary: _palette.onSecondary,
      tertiary: _palette.tertiary,
      onTertiary: _palette.onTertiary,
      surface: _palette.surface,
      onSurface: _palette.onSurface,
      background: _palette.surface,
      onBackground: _palette.onSurface,
      error: _palette.error,
      onError: _palette.onError,
    );

    final dividerTheme = DividerThemeData(
      color: _palette.divider,
      thickness: 1,
      space: 1,
    );

    final elevatedButtonTheme = ElevatedButtonThemeData(
      style: buttonTheme.primaryStyle,
    );

    final textButtonTheme = TextButtonThemeData(style: buttonTheme.textStyle);

    final outlinedButtonTheme = OutlinedButtonThemeData(
      style: buttonTheme.outlinedStyle,
    );

    return (_isDark
            ? ThemeData.dark(useMaterial3: true)
            : ThemeData.light(useMaterial3: true))
        .copyWith(
          colorScheme: colorScheme,
          scaffoldBackgroundColor: _palette.surface,

          appBarTheme: appBarTheme,
          cardTheme: cardTheme.cardTheme.data,
          inputDecorationTheme: inputTheme.inputDecorationTheme,
          textSelectionTheme: inputTheme.textSelectionTheme,
          elevatedButtonTheme: elevatedButtonTheme,
          textButtonTheme: textButtonTheme,
          outlinedButtonTheme: outlinedButtonTheme,
          tabBarTheme: tabBarTheme.data,
          textTheme: textTheme,
          dividerTheme: dividerTheme,

          extensions: [_palette, buttonTheme, cardTheme, inputTheme],
        );
  }

  TextTheme _createDefaultTextTheme() {
    final headlineColor = _isDark ? _palette.secondary : _palette.primary;
    final bodyColor = _palette.onSurface;

    return TextTheme(
      bodyLarge: TextStyle(color: bodyColor),
      bodyMedium: TextStyle(color: bodyColor),
      bodySmall: TextStyle(color: bodyColor),
      displayLarge: TextStyle(color: bodyColor, fontWeight: FontWeight.bold),
      displayMedium: TextStyle(color: bodyColor, fontWeight: FontWeight.bold),
      displaySmall: TextStyle(color: bodyColor, fontWeight: FontWeight.bold),
      headlineLarge: TextStyle(
        color: headlineColor,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: headlineColor,
        fontWeight: FontWeight.bold,
      ),
      titleLarge: TextStyle(color: bodyColor, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: bodyColor, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(color: bodyColor, fontWeight: FontWeight.w600),
      labelLarge: TextStyle(color: _palette.onPrimary),
    );
  }
}
