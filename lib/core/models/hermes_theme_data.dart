import 'package:flutter/material.dart';

class HermesThemeData {
  final String name;
  final String id;
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final String? category;
  final String? description;
  final double version;

  const HermesThemeData({
    required this.name,
    required this.id,
    required this.lightTheme,
    required this.darkTheme,
    this.category,
    this.description,
    this.version = 1.0,
  });

  HermesThemeData copyWith({
    String? name,
    String? id,
    ThemeData? lightTheme,
    ThemeData? darkTheme,
    String? category,
    String? description,
    double? version,
  }) => HermesThemeData(
    name: name ?? this.name,
    id: id ?? this.id,
    lightTheme: lightTheme ?? this.lightTheme,
    darkTheme: darkTheme ?? this.darkTheme,
    category: category ?? this.category,
    description: description ?? this.description,
    version: version ?? this.version,
  );

  ThemeData themeForMode(bool isDarkMode) =>
      isDarkMode ? darkTheme : lightTheme;
}
