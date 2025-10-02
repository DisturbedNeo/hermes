import 'package:flutter/material.dart';
import 'package:hermes/core/models/hermes_theme_data.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/hermes_theme_builder.dart';

class ForestTheme {
  static HermesThemeData build() {
    final lightTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: const Color(0xFF2E7D32),
        secondary: const Color(0xFFFFD54F),
        background: const Color(0xFFE8F5E9),
        surface: Colors.white,
      ),
      isDark: false,
    ).build();
    
    final darkTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: const Color(0xFF81C784),
        secondary: const Color(0xFFFFD54F),
        background: const Color(0xFF1B2A21),
        surface: const Color(0xFF2D3833),
      ),
      isDark: true,
    ).build();
    
    return HermesThemeData(
      name: 'Forest',
      id: 'forest',
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      description: 'A refreshing forest theme',
      category: 'Nature',
    );
  }
}
