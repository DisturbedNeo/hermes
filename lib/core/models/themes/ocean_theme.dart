import 'package:flutter/material.dart';
import 'package:hermes/core/models/hermes_theme_data.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/hermes_theme_builder.dart';

class OceanTheme {
  static HermesThemeData build() {
    final lightTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: Colors.blue.shade700,
        secondary: Colors.amber,
        background: Colors.blue.shade50,
        surface: Colors.white,
      ),
      isDark: false,
    ).build();
    
    final darkTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: Colors.blue.shade300,
        secondary: Colors.amber,
        background: const Color(0xFF102027),
        surface: const Color(0xFF263238),
      ),
      isDark: true,
    ).build();
    
    return HermesThemeData(
      name: 'Ocean',
      id: 'ocean',
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      description: 'A calming blue theme',
      category: 'Cool',
    );
  }
}
