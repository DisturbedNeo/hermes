import 'package:flutter/material.dart';
import 'package:hermes/core/models/hermes_theme_data.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/hermes_theme_builder.dart';

class SolarpunkTheme {
  static HermesThemeData build() {
    final lightTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: const Color(0xFF3CC276),
        secondary: const Color(0xFFFDC741),
        tertiary: const Color(0xFF64B0B0),
        surface: const Color(0xFFFAFAFA),
      ),
      isDark: false,
    ).build();

    final darkTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: const Color(0xFF324F33),
        secondary: const Color(0xFF94860E),
        tertiary: const Color(0xFF13645C), 

        surface: const Color(0xFF0D1711),
      ),
      isDark: true,
    ).build();

    return HermesThemeData(
      name: 'Solarpunk',
      id: 'solarpunk',
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      description: 'A solarpunk blend of green life and bright tech — organic hues grounded by solar warmth and aqua light.',
      category: 'Nature-Tech',
    );
  }
}
