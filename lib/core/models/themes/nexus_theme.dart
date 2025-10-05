import 'package:flutter/material.dart';
import 'package:hermes/core/models/hermes_theme_data.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/hermes_theme_builder.dart';

class NexusTheme {
  static HermesThemeData build() {
    // Light: crisp, clean, minimal
    final lightTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: const Color(0xFF2563EB),   // Cobalt blue — focus and clarity
        secondary: const Color(0xFF475569), // Slate gray — neutral depth
        tertiary: const Color(0xFF10B981),  // Teal — subtle, modern energy
        background: const Color(0xFFF8FAFC),
        surface: Colors.white,
      ),
      isDark: false,
    ).build();

    // Dark: glassy, tech-focused, low-glow
    final darkTheme = HermesThemeBuilder(
      palette: HermesPalette.custom(
        primary: const Color(0xFF60A5FA),   // Soft blue light
        secondary: const Color(0xFF94A3B8), // Steel gray tone
        tertiary: const Color(0xFF34D399),  // Cool mint accent — active states
        background: const Color(0xFF0F172A),
        surface: const Color(0xFF1E293B),
      ),
      isDark: true,
    ).build();

    return HermesThemeData(
      name: 'Nexus',
      id: 'nexus',
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      description: 'A modern, balanced theme blending cobalt blues, slate neutrals, and hints of teal energy.',
      category: 'Tech',
    );
  }
}
