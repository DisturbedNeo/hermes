import 'dart:io';

import 'package:hermes/features/persistence/infrastructure/atomic_json_snapshot_store.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/persistence/application/project_snapshot_store_port.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';

/// Converts pre-aggregate project snapshots to the canonical project/task
/// layout. The operation is deliberately isolated from normal repository
/// reads so migration policy cannot leak into aggregate behavior.
class ProjectSnapshotMigrator {
  ProjectSnapshotMigrator({
    required ProjectSnapshotStorePort projectRepository,
    required TaskPersistencePort taskRepository,
    AtomicJsonSnapshotStore snapshots = const AtomicJsonSnapshotStore(),
  }) : _projects = projectRepository,
       _tasks = taskRepository,
       _snapshots = snapshots;

  final ProjectSnapshotStorePort _projects;
  final TaskPersistencePort _tasks;
  final AtomicJsonSnapshotStore _snapshots;

  Future<void> migrateLegacyEmbeddedTasks(
    String workspaceRoot,
    String projectId,
  ) async {
    final file = File(_projects.projectSnapshotPath(workspaceRoot, projectId));
    late final SnapshotEnvelope envelope;
    try {
      final raw = await _snapshots.readMapWithoutRepair(file);
      if (raw == null) return;
      envelope = SnapshotEnvelope.decode(raw.map);
    } on FormatException {
      return;
    } on SnapshotCorruptionException {
      return;
    }

    final embedded = envelope.document['tasks'];
    if (embedded is! List || embedded.isEmpty) return;

    final document = Map<String, dynamic>.from(envelope.document);
    final existingIds = <String>{
      for (final value
          in document['taskIds'] is List
              ? document['taskIds'] as List
              : const [])
        if (value is String && value.trim().isNotEmpty) value,
    };
    final migratedTasks = <Task>[];
    for (final value in embedded) {
      if (value is! Map) continue;
      try {
        final task = ModelJson.decode<Task>(Map<String, dynamic>.from(value));
        if (task.id.trim().isEmpty) continue;
        existingIds.add(task.id);
        final current = await _tasks.revisionOfUnlocked(workspaceRoot, task.id);
        if (current == null) {
          migratedTasks.add(
            task.copyWith(persistenceRevision: 0, projectId: projectId),
          );
        }
      } catch (_) {
        // Malformed legacy entries are reported by normal aggregate reads.
      }
    }
    for (final task in migratedTasks) {
      await _tasks.saveSnapshotUnlocked(
        workspaceRoot,
        task,
        expectedRevision: 0,
        currentRevision: null,
      );
    }
    document
      ..remove('tasks')
      ..['taskIds'] = existingIds.toList(growable: false);
    await _snapshots.writeMap(
      file,
      SnapshotEnvelope.encode(document, envelope.revision),
    );
  }
}
