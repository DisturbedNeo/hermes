import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  static const String _dataLocationKey = 'data_location_path';
  static const String _darkModeKey = 'is_dark_mode';
  static const String _modelsDirectory = 'models_directory';
  static const String _llamaCppDirectory = 'llama_cpp_directory';
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
      } catch (_) {}
    }

    return true;
  }

  String getDatabaseFileName() => 'hermes.db';
  
  Future<String> getDefaultDataLocation() async => (await getApplicationDocumentsDirectory()).path;
  Future<String> getFullDatabasePath() async => path.join(await getDataDirectoryPath(), getDatabaseFileName());

  Future<bool> isDarkMode() async => (await _prefs).getBool(_darkModeKey) ?? false;
  Future<bool> setDarkMode(bool isDarkMode) async => (await _prefs).setBool(_darkModeKey, isDarkMode);

  Future<String?> getThemeId() async => (await _prefs).getString(_themeIdKey);
  Future<bool> setThemeId(String themeId) async => (await _prefs).setString(_themeIdKey, themeId);

  Future<int> getTabIndex(String worldId) async => (await _prefs).getInt('$_worldOverviewTabPrefKey$worldId') ?? 0;
  Future<bool> setTabIndex(String worldId, int index) async => (await _prefs).setInt('$_worldOverviewTabPrefKey$worldId', index);

  Future<String?> getLlamaCppDirectory() async => (await _prefs).getString(_llamaCppDirectory);
  Future<bool> setLlamaCppDirectory(String path) async => (await _prefs).setString(_llamaCppDirectory, path);

  Future<String?> getModelsDirectory() async => (await _prefs).getString(_modelsDirectory);
  Future<bool> setModelsDirectory(String directory) async => (await _prefs).setString(_modelsDirectory, directory);

  void dispose() {}
}
