import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';

/// Infrastructure-facing extension for task snapshot storage.
///
/// Task repositories implement this capability; task execution receives only
/// [TaskPersistencePort], which contains aggregate operations and history
/// writes rather than filesystem layout details.
abstract interface class TaskSnapshotStorePort implements TaskPersistencePort {
  static const String tasksRoot = '.agent/tasks';
  static const String documentFileName = 'task.json';
  static const String runsDirectoryName = 'runs';

  String taskRelativePath(String taskId, String fileName);
}
