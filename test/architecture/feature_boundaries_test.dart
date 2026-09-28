import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<List<File>> _dartFiles(String root) async {
  final files = <File>[];
  await for (final entity in Directory(root).list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
  }
  return files;
}

void main() {
  test('obsolete orchestration architecture is absent', () async {
    final files = await _dartFiles('lib');
    final source = [for (final file in files) await file.readAsString()].join('\n');

    for (final obsolete in [
      'ChatService',
      'TaskService',
      'ProjectWorkflowService',
      'ProjectOrchestrator',
      'ProjectWorkflowRuntime',
      'ProjectExecutionPhase',
      'ProjectPlanningPhase',
      'ProjectPersistencePhase',
      'ProjectCommandPhase',
    ]) {
      expect(source, isNot(contains(obsolete)), reason: '$obsolete remains');
    }
  });

  test('domain and ports stay independent from Flutter and adapters', () async {
    final domainFiles = <File>[
      ...await _dartFiles('lib/features/chat/domain'),
      ...await _dartFiles('lib/features/project/domain'),
      ...await _dartFiles('lib/features/task/domain'),
      ...await _dartFiles('lib/features/workspace/domain'),
      ...await _dartFiles('lib/features/model/domain'),
    ];

    for (final file in domainFiles) {
      final source = await file.readAsString();
      expect(source, isNot(contains("package:flutter/")), reason: file.path);
      expect(source, isNot(contains("package:http/")), reason: file.path);
      expect(source, isNot(contains('sqflite')), reason: file.path);
      expect(source, isNot(contains('/infrastructure/')), reason: file.path);
    }
  });

  test('infrastructure adapters implement typed ports', () async {
    final workspace = await File(
      'lib/core/services/workspace_service.dart',
    ).readAsString();
    final persistence = await File(
      'lib/core/services/workspace_persistence_coordinator.dart',
    ).readAsString();
    final model = await File(
      'lib/features/model/infrastructure/chat_client.dart',
    ).readAsString();

    expect(workspace, contains('implements WorkspacePort'));
    expect(persistence, contains('implements PersistencePort'));
    expect(model, contains('implements ModelProvider'));
  });

  test('presentation depends on controllers and immutable state, not project services', () async {
    final files = await _dartFiles('lib/ui');
    for (final file in files) {
      final source = await file.readAsString();
      expect(source, isNot(contains('ProjectCommandService')));
      expect(source, isNot(contains('TaskCommandService')));
    }

    final state = await File(
      'lib/features/chat/presentation/chat_view_state.dart',
    ).readAsString();
    final controller = await File(
      'lib/features/chat/application/chat_controller.dart',
    ).readAsString();
    expect(state, contains('class ChatViewState'));
    expect('$state\n$controller', contains('List.unmodifiable'));
  });

  test('composition root exposes the complete typed graph', () async {
    final source = await File('lib/app_dependencies.dart').readAsString();
    for (final type in [
      'TaskController',
      'ProjectApplication',
      'ChatWorkspaceController',
      'LlamaServerManager',
      'WorkspacePersistenceCoordinator',
      'WorkspaceService',
    ]) {
      expect(source, contains(type), reason: '$type is not composed explicitly');
    }
  });
}
