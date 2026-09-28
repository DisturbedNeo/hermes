import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';

/// Minimal settings contract needed by application services.
///
/// Platform preferences, path providers, and migration details remain owned
/// by the concrete infrastructure service. Application code only sees the
/// values and notifications it actually consumes.
abstract interface class PreferencesPort {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);

  Future<CompactionSettings> getCompactionSettings();
  Future<TaskSystemSettings> getTaskSystemSettings();
}
