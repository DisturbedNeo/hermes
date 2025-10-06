import 'package:flutter/material.dart';
import 'package:hermes/core/models/hermes_theme_data.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/hermes_theme_builder.dart';

class SolarpunkTheme {
  static HermesThemeData build() {
    final lightTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: const Color(0xFF2E8B57),   // Verdant green
        secondary: const Color(0xFFFBC02D), // Solar gold
        tertiary: const Color(0xFF5BA4A4),  // Seafoam teal
        background: const Color(0xFFFAFDF9),
        surface: const Color(0xFFF0F8F4),
      ),
      isDark: false,
    ).build();

    final darkTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: const Color(0xFF81C784),   // Leaf glow
        secondary: const Color(0xFFFFEE58), // Solar yellow
        tertiary: const Color(0xFF4FD1C5),  // Aqua-green pulse
        background: const Color(0xFF0D1F14),
        surface: const Color(0xFF1B2E22),
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
