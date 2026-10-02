import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/model/application/diagnostics_visibility.dart';
import 'package:hermes/features/model/application/model_load_configuration.dart';
import 'package:hermes/core/contracts/execution_settings.dart';

abstract interface class PreferencesNotificationsPort {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}

abstract interface class AppearanceSettingsPort {
  Future<bool> isDarkMode();
  Future<String?> getThemeId();
  Future<void> setDarkMode(bool value);
  Future<void> setThemeId(String themeId);
}

abstract interface class ModelDirectorySettingsPort {
  Future<String?> getModelsDirectory();
  Future<String?> getLlamaCppDirectory();
  Future<bool> setLlamaCppDirectory(String path);
  Future<bool> setModelsDirectory(String directory);
}

abstract interface class ModelPreferencesPort {
  Future<ModelLoadConfiguration?> getModelLoadConfiguration(String modelAlias);
  Future<bool> setModelLoadConfiguration(
    String modelAlias,
    ModelLoadConfiguration configuration,
  );
  Future<bool> removeModelLoadConfiguration(String modelAlias);
}

abstract interface class DiagnosticsSettingsPort {
  Future<bool> setDiagnosticsVisibility(DiagnosticsVisibility value);
  Future<DiagnosticsVisibility> getDiagnosticsVisibility();
}

abstract interface class CompactionSettingsPort {
  Future<CompactionSettings> getCompactionSettings();
  Future<void> setCompactionSettings(CompactionSettings settings);
}

abstract interface class ExecutionSettingsPort {
  Future<TaskSystemSettings> getTaskSystemSettings();
  Future<void> setTaskSystemSettings(TaskSystemSettings settings);
}

abstract interface class PersistenceSettingsPort {
  Future<String> getFullDatabasePath();
}

abstract interface class ChatRuntimePreferencesPort
    implements
        PreferencesNotificationsPort,
        CompactionSettingsPort,
        ExecutionSettingsPort {}

abstract interface class SettingsPreferencesPort
    implements
        ModelDirectorySettingsPort,
        CompactionSettingsPort,
        ExecutionSettingsPort,
        DiagnosticsSettingsPort {}

abstract interface class ModelPickerPreferencesPort
    implements ModelDirectorySettingsPort, ModelPreferencesPort {}

abstract interface class DiagnosticsBarPreferencesPort
    implements PreferencesNotificationsPort, DiagnosticsSettingsPort {}

abstract interface class ChatPresentationPreferencesPort
    implements
        SettingsPreferencesPort,
        ModelPickerPreferencesPort,
        DiagnosticsBarPreferencesPort {}

/// Combined adapter retained for composition and compatibility. Feature
/// services should depend on the smallest focused port or bundle above.
abstract interface class PreferencesPort
    implements
        PreferencesNotificationsPort,
        AppearanceSettingsPort,
        ModelDirectorySettingsPort,
        ModelPreferencesPort,
        DiagnosticsSettingsPort,
        CompactionSettingsPort,
        ExecutionSettingsPort,
        PersistenceSettingsPort,
        ChatRuntimePreferencesPort,
        SettingsPreferencesPort,
        ModelPickerPreferencesPort,
        DiagnosticsBarPreferencesPort,
        ChatPresentationPreferencesPort {}
