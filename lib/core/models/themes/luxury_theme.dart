import 'package:flutter/material.dart';
import 'package:hermes/core/models/hermes_theme_data.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/hermes_colours.dart';
import 'package:hermes/core/theme/hermes_theme_builder.dart';

class LuxuryTheme {
  static HermesThemeData build() {
    final lightTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: HermesColours.burgundy,
        secondary: HermesColours.gold,
        background: HermesColours.cream,
        surface: Colors.white,
        onSurface: const Color(0xFF1F1F1F),
      ),
      isDark: false,
    ).build();
    
    final darkTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: HermesColours.burgundyLight,
        secondary: HermesColours.gold,
        background: HermesColours.darkBackground,
        surface: HermesColours.darkSurface,
        onSurface: HermesColours.cream,
      ),
      isDark: true,
    ).build();
    
    return HermesThemeData(
      name: 'Luxury',
      id: 'luxury',
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      description: 'A luxurious theme with burgundy and gold accents',
      category: 'Classic',
    );
  }
}
