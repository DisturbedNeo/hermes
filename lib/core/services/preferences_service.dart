import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/diagnostics_visibility.dart';
import 'package:hermes/core/helpers/preferences_keys.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService extends ChangeNotifier {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  Future<String> getDataDirectoryPath() async {
    final savedPath = (await _prefs).getString(PreferencesKeys.dataLocation);

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

    if (!(await (await _prefs).setString(
      PreferencesKeys.dataLocation,
      directoryPath,
    ))) {
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

  Future<String> getDefaultDataLocation() async =>
      (await getApplicationDocumentsDirectory()).path;
  Future<String> getFullDatabasePath() async =>
      path.join(await getDataDirectoryPath(), getDatabaseFileName());

  Future<bool> isDarkMode() async =>
      (await _prefs).getBool(PreferencesKeys.darkMode) ?? false;
  Future<bool> setDarkMode(bool isDarkMode) async =>
      (await _prefs).setBool(PreferencesKeys.darkMode, isDarkMode);

  Future<String?> getThemeId() async =>
      (await _prefs).getString(PreferencesKeys.themeId);
  Future<bool> setThemeId(String themeId) async =>
      (await _prefs).setString(PreferencesKeys.themeId, themeId);

  Future<int> getTabIndex(String worldId) async =>
      (await _prefs).getInt(
        '${PreferencesKeys.worldOverviewTabPrefix}$worldId',
      ) ??
      0;
  Future<bool> setTabIndex(String worldId, int index) async => (await _prefs)
      .setInt('${PreferencesKeys.worldOverviewTabPrefix}$worldId', index);

  Future<String?> getLlamaCppDirectory() async =>
      (await _prefs).getString(PreferencesKeys.llamaCppDirectory);
  Future<bool> setLlamaCppDirectory(String path) async =>
      (await _prefs).setString(PreferencesKeys.llamaCppDirectory, path);

  Future<String?> getModelsDirectory() async =>
      (await _prefs).getString(PreferencesKeys.modelsDirectory);
  Future<bool> setModelsDirectory(String directory) async =>
      (await _prefs).setString(PreferencesKeys.modelsDirectory, directory);

  Future<DiagnosticsVisibility> getDiagnosticsVisibility() async =>
      DiagnosticsVisibilityLabel.fromName(
        (await _prefs).getString(PreferencesKeys.diagnosticsVisibility),
      );

  Future<bool> setDiagnosticsVisibility(
    DiagnosticsVisibility visibility,
  ) async {
    final saved = await (await _prefs).setString(
      PreferencesKeys.diagnosticsVisibility,
      visibility.name,
    );

    if (saved) notifyListeners();
    return saved;
  }

  Future<CompactionSettings> getCompactionSettings() async {
    final prefs = await _prefs;
    return CompactionSettings(
      enabled: prefs.getBool(PreferencesKeys.contextCompactionEnabled) ?? true,
      triggerThreshold:
          prefs.getDouble(PreferencesKeys.contextCompactionTrigger) ?? 0.80,
      hardLimitThreshold:
          prefs.getDouble(PreferencesKeys.contextCompactionHardLimit) ?? 0.95,
      recentWindowUnits:
          prefs.getInt(PreferencesKeys.contextCompactionRecentWindow) ?? 6,
      allowEmergencyPayloadTruncation:
          prefs.getBool(PreferencesKeys.contextCompactionEmergencyTruncation) ??
          false,
    ).normalised();
  }

  Future<bool> setCompactionSettings(CompactionSettings settings) async {
    final prefs = await _prefs;
    final normalised = settings.normalised();
    final saved =
        await prefs.setBool(
          PreferencesKeys.contextCompactionEnabled,
          normalised.enabled,
        ) &&
        await prefs.setDouble(
          PreferencesKeys.contextCompactionTrigger,
          normalised.triggerThreshold,
        ) &&
        await prefs.setDouble(
          PreferencesKeys.contextCompactionHardLimit,
          normalised.hardLimitThreshold,
        ) &&
        await prefs.setInt(
          PreferencesKeys.contextCompactionRecentWindow,
          normalised.recentWindowUnits,
        ) &&
        await prefs.setBool(
          PreferencesKeys.contextCompactionEmergencyTruncation,
          normalised.allowEmergencyPayloadTruncation,
        );

    if (saved) notifyListeners();
    return saved;
  }

  Future<TaskSystemSettings> getTaskSystemSettings() async {
    final prefs = await _prefs;
    return TaskSystemSettings(
      enabled: prefs.getBool(PreferencesKeys.taskSystemEnabled) ?? true,
      requireApprovalBeforeExecution:
          prefs.getBool(
            PreferencesKeys.taskSystemRequireApprovalBeforeExecution,
          ) ??
          true,
      requireApprovalBeforeFileEdits:
          prefs.getBool(PreferencesKeys.taskSystemApprovalBeforeFileEdits) ??
          true,
      showTaskMessagesInChat:
          prefs.getBool(PreferencesKeys.taskSystemShowMessagesInChat) ?? true,
    ).normalised();
  }

  Future<bool> setTaskSystemSettings(TaskSystemSettings settings) async {
    final prefs = await _prefs;
    final normalised = settings.normalised();
    final saved =
        await prefs.setBool(
          PreferencesKeys.taskSystemEnabled,
          normalised.enabled,
        ) &&
        await prefs.setBool(
          PreferencesKeys.taskSystemRequireApprovalBeforeExecution,
          normalised.requireApprovalBeforeExecution,
        ) &&
        await prefs.setBool(
          PreferencesKeys.taskSystemApprovalBeforeFileEdits,
          normalised.requireApprovalBeforeFileEdits,
        ) &&
        await prefs.setBool(
          PreferencesKeys.taskSystemShowMessagesInChat,
          normalised.showTaskMessagesInChat,
        );

    if (saved) notifyListeners();
    return saved;
  }
}
