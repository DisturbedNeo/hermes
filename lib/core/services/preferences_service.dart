import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  static const String _dataLocationKey = 'data_location_path';
  static const String _darkModeKey = 'is_dark_mode';
  static const String _themeIdKey = 'theme_id';
  static const String _worldOverviewTabPrefKey = 'last_tab_index_';

  Future<String> getDataDirectoryPath() async {
    final savedPath = (await _prefs).getString(_dataLocationKey);

    if (savedPath != null) {
      final dir = Directory(savedPath);
      if (await dir.exists()) {
        return savedPath;
      }
    }

    return await getDefaultDataLocation();
  }

  Future<bool> setDataDirectoryPath(String directoryPath) async {
    final currentPath = await getFullDatabasePath();
    final File currentDbFile = File(currentPath);
    final String newPath = path.join(directoryPath, getDatabaseFileName());
    final File newDbFile = File(newPath);

    bool dataMoved = false;

    if (await currentDbFile.exists() && !await newDbFile.exists()) {
      try {
        await Directory(directoryPath).create(recursive: true);
        await currentDbFile.copy(newPath);
        dataMoved = true;
      } catch (e) {
        return false;
      }
    }

    if (!(await (await _prefs).setString(_dataLocationKey, directoryPath))) {
      if (dataMoved) {
        await newDbFile.delete();
      }
      return false;
    }

    if (dataMoved && await currentDbFile.exists()) {
      try {
        await currentDbFile.delete();
      } catch (e) {
        // No-op
      }
    }

    return true;
  }

  Future<String> getDefaultDataLocation() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    return documentsDirectory.path;
  }

  String getDatabaseFileName() => 'codex.db';

  Future<String> getFullDatabasePath() async {
    final directory = await getDataDirectoryPath();
    return path.join(directory, getDatabaseFileName());
  }

  Future<bool> isDarkMode() async => (await _prefs).getBool(_darkModeKey) ?? false;

  Future<bool> setDarkMode(bool isDarkMode) async =>
      (await _prefs).setBool(_darkModeKey, isDarkMode);

  Future<String?> getThemeId() async => (await _prefs).getString(_themeIdKey);

  Future<bool> setThemeId(String themeId) async =>
      (await _prefs).setString(_themeIdKey, themeId);

  Future<int> getTabIndex(String worldId) async {
    final prefs = await _prefs;
    return prefs.getInt('$_worldOverviewTabPrefKey$worldId') ?? 0;
  }

  Future<bool> setTabIndex(String worldId, int index) async {
    final prefs = await _prefs;
    return prefs.setInt('$_worldOverviewTabPrefKey$worldId', index);
  }

  void dispose() {}
}
