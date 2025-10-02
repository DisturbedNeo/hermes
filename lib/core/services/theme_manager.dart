import 'package:flutter/material.dart';
import 'package:hermes/core/models/hermes_theme_data.dart';
import 'package:hermes/core/models/themes/forest_theme.dart';
import 'package:hermes/core/models/themes/luxury_theme.dart';
import 'package:hermes/core/models/themes/ocean_theme.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';

class ThemeManager with ChangeNotifier {
  bool _isDarkMode = false;
  late HermesThemeData _currentTheme;

  final PreferencesService _preferencesService = serviceProvider.get<PreferencesService>();

  static List<HermesThemeData> allThemes = [
    LuxuryTheme.build(),
    OceanTheme.build(),
    ForestTheme.build(),
  ];

  final Duration _themeSwitchDuration = const Duration(milliseconds: 300);

  ThemeManager() {
    _loadThemePreferences();
  }

  bool get isDarkMode => _isDarkMode;
  String get currentThemeId => _currentTheme.id;
  HermesThemeData get currentThemeData => _currentTheme;
  Duration get animationDuration => _themeSwitchDuration;

  Future<void> _loadThemePreferences() async {
    _isDarkMode = await _preferencesService.isDarkMode();

    final savedThemeId = await _preferencesService.getThemeId();
    if (savedThemeId != null) {
      _currentTheme = allThemes.firstWhere((theme) => theme.id == savedThemeId);
    } else {
      _currentTheme = allThemes.first;
    }

    notifyListeners();
  }

  Future<void> toggleTheme({bool? forceDarkMode}) async {
    final newDarkMode = forceDarkMode ?? !_isDarkMode;

    if (_isDarkMode != newDarkMode) {
      _isDarkMode = newDarkMode;
      await _preferencesService.setDarkMode(_isDarkMode);
      notifyListeners();
    }
  }

  Future<void> setTheme(String themeId) async {
    if (currentThemeId == themeId) return;

    _currentTheme = allThemes.firstWhere((theme) => theme.id == themeId);
    await _preferencesService.setThemeId(themeId);
    notifyListeners();
  }

  ThemeData get currentTheme =>
      _isDarkMode ? _currentTheme.darkTheme : _currentTheme.lightTheme;

  List<String> get themeCategories {
    final categories = <String>[];
    for (final theme in allThemes) {
      if (theme.category != null && !categories.contains(theme.category)) {
        categories.add(theme.category!);
      }
    }
    return categories;
  }
}
