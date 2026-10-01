import 'package:hermes/features/chat/application/contracts/compaction_settings.dart';
import 'package:hermes/features/model/application/diagnostics_visibility.dart';
import 'package:hermes/features/model/application/model_load_configuration.dart';
import 'package:hermes/features/task/application/contracts/task_system_settings.dart';

/// Minimal settings contract needed by application services.
///
/// Platform preferences, path providers, and migration details remain owned
/// by the concrete infrastructure service. Application code only sees the
/// values and notifications it actually consumes.
abstract interface class PreferencesPort {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);

  Future<CompactionSettings> getCompactionSettings();
  Future<void> setCompactionSettings(CompactionSettings settings);
  Future<TaskSystemSettings> getTaskSystemSettings();
  Future<void> setTaskSystemSettings(TaskSystemSettings settings);

  Future<bool> isDarkMode();
  Future<String?> getThemeId();
  Future<void> setDarkMode(bool value);
  Future<void> setThemeId(String themeId);
  Future<String?> getModelsDirectory();
  Future<String?> getLlamaCppDirectory();
  Future<bool> setLlamaCppDirectory(String path);
  Future<bool> setModelsDirectory(String directory);
  Future<bool> setDiagnosticsVisibility(DiagnosticsVisibility value);
  Future<DiagnosticsVisibility> getDiagnosticsVisibility();
  Future<String> getFullDatabasePath();
  Future<ModelLoadConfiguration?> getModelLoadConfiguration(String modelAlias);
  Future<bool> setModelLoadConfiguration(
    String modelAlias,
    ModelLoadConfiguration configuration,
  );
  Future<bool> removeModelLoadConfiguration(String modelAlias);
}
