import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<List<File>> _dartFiles(String root) async {
  final files = <File>[];
  await for (final entity in Directory(root).list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
  }
  return files;
}

Future<Map<String, Set<String>>> _importsByFile(String root) async {
  final result = <String, Set<String>>{};
  for (final file in await _dartFiles(root)) {
    final imports = <String>{};
    for (final line in (await file.readAsLines())) {
      final match = RegExp(
        r'''^import ['"](package:hermes/[^'"]+)''',
      ).firstMatch(line);
      if (match != null) imports.add(match.group(1)!);
    }
    result[file.path] = imports;
  }
  return result;
}

void main() {
  test('obsolete orchestration architecture is absent', () async {
    final files = await _dartFiles('lib');
    final source = [
      for (final file in files) await file.readAsString(),
    ].join('\n');

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

  test('dependency matrix rejects forbidden feature edges', () async {
    final imports = await _importsByFile('lib');
    final forbidden = <String, List<String>>{
      'lib/core': [
        'package:hermes/features/chat/application/',
        'package:hermes/features/task/application/',
        'package:hermes/features/model/infrastructure/',
      ],
      'lib/features/chat/application': [
        'package:hermes/features/task/application/task_application/task_controller.dart',
        'package:hermes/features/project/application/project_application/project_application.dart',
      ],
      'lib/features/task/application': [
        'package:hermes/features/project/application/',
        'package:hermes/features/task/infrastructure/',
      ],
      'lib/features/project/application': [
        'package:hermes/features/project/infrastructure/',
      ],
      'lib/features/project/domain': [
        'package:hermes/features/task/domain/',
        'package:hermes/features/task/application/',
      ],
      'lib/features/task/domain': [
        'package:hermes/features/project/domain/',
        'package:hermes/features/project/application/',
      ],
      'lib/shared_kernel': ['package:hermes/features/'],
    };

    for (final entry in forbidden.entries) {
      for (final fileEntry in imports.entries) {
        if (!fileEntry.key.startsWith(entry.key)) continue;
        for (final edge in entry.value) {
          expect(
            fileEntry.value.where((value) => value.startsWith(edge)),
            isEmpty,
            reason: '${fileEntry.key} imports forbidden edge $edge',
          );
        }
      }
    }
  });

  test('chat orchestration is defined against application ports', () async {
    final controller = await File(
      'lib/features/chat/runtime/chat_controller.dart',
    ).readAsString();
    final workspaceController = await File(
      'lib/features/chat/runtime/chat_workspace_controller.dart',
    ).readAsString();
    expect(controller, contains('TaskApplicationPort'));
    expect(controller, contains('ProjectApplicationPort'));
    expect(workspaceController, contains('TaskApplicationPort'));
    expect(workspaceController, contains('ProjectApplicationPort'));
  });

  test(
    'application entrypoints stay below the orchestration line budget',
    () async {
      const maxLines = 500;
      final entrypoints = [
        'lib/features/chat/application/chat_controller.dart',
        'lib/features/task/application/task_application/task_controller.dart',
        'lib/features/project/application/project_application/project_application.dart',
      ];
      final violations = <String>[];

      for (final path in entrypoints) {
        final lines = await File(path).readAsLines();
        if (lines.length > maxLines) {
          violations.add(
            '$path contains ${lines.length} lines; expected at most $maxLines',
          );
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test(
    'application entrypoints contain no monolithic runtime or coordinator',
    () async {
      const applicationRoots = [
        'lib/features/chat/application',
        'lib/features/task/application',
        'lib/features/project/application',
      ];
      const forbiddenDeclarations = [
        'class _ChatControllerRuntime',
        'class _TaskApplicationCoordinator',
        'abstract class ProjectApplicationRuntime',
        'class _ProjectApplicationCoordinator',
      ];
      final violations = <String>[];

      for (final root in applicationRoots) {
        for (final file in await _dartFiles(root)) {
          final source = await file.readAsString();
          for (final declaration in forbiddenDeclarations) {
            if (source.contains(declaration)) {
              violations.add('${file.path} still contains $declaration');
            }
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test(
    'application entrypoints delegate to explicit runtime collaborators',
    () async {
      // The migration intentionally supersedes the former part-based
      // application entrypoints: public application files now expose the
      // runtime collaborators through focused aliases.
      final entrypoints = [
        'lib/features/chat/application/chat_controller.dart',
        'lib/features/task/application/task_application/task_controller.dart',
        'lib/features/project/application/project_application/project_application.dart',
      ];
      for (final entrypoint in entrypoints) {
        final source = await File(entrypoint).readAsString();
        expect(source, isNot(contains('part ')), reason: entrypoint);
        expect(source, contains('runtime/'), reason: entrypoint);
      }

      final ownership = <String, List<String>>{
        'lib/features/chat/runtime/chat_work_operations.dart': [
          'generateOrContinue',
          'runProject',
        ],
        'lib/features/task/runtime/task_planning_operations.dart': [
          'createTask',
          'createProjectTask',
        ],
        'lib/features/task/runtime/task_execution_operations.dart': [
          'runNextStep',
          '_executeStep',
        ],
        'lib/features/project/runtime/project_execution_operations.dart': [
          '_runProjectCore',
          '_executeProjectTask',
          'createProject',
        ],
        'lib/features/project/runtime/project_planning_recovery_operations.dart':
            ['_recoverProjectCore'],
      };
      for (final entry in ownership.entries) {
        final source = await File(entry.key).readAsString();
        for (final operation in entry.value) {
          expect(source, contains(operation), reason: entry.key);
        }
      }
    },
  );

  test(
    'application implementation files stay below the monolith threshold',
    () async {
      const maxLines = 2100;
      const applicationRoots = [
        'lib/features/chat/application',
        'lib/features/task/application',
        'lib/features/project/application',
      ];
      final violations = <String>[];

      for (final root in applicationRoots) {
        for (final file in await _dartFiles(root)) {
          final lines = await file.readAsLines();
          if (lines.length > maxLines) {
            violations.add(
              '${file.path} contains ${lines.length} lines; expected at most $maxLines',
            );
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test(
    'application entrypoints expose their public application contracts',
    () async {
      final contracts = <String, String>{
        'lib/features/chat/application/chat_controller.dart':
            'typedef ChatController = ChatRuntimeController',
        'lib/features/task/application/task_application/task_controller.dart':
            'typedef TaskController = TaskRuntimeController',
        'lib/features/project/application/project_application/project_application.dart':
            'typedef ProjectApplication = ProjectRuntimeApplication',
      };

      for (final entry in contracts.entries) {
        final source = await File(entry.key).readAsString();
        expect(
          source,
          contains(entry.value),
          reason: '${entry.key} no longer exposes ${entry.value}',
        );
      }
    },
  );

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
    final task = await File(
      'lib/features/task/infrastructure/task_repository.dart',
    ).readAsString();
    final project = await File(
      'lib/features/project/infrastructure/project_repository.dart',
    ).readAsString();
    final aggregate = await File(
      'lib/features/project/infrastructure/project_aggregate_repository.dart',
    ).readAsString();
    final chatLibrary = await File(
      'lib/features/chat/infrastructure/chat_library_repository.dart',
    ).readAsString();
    final promptLibrary = await File(
      'lib/features/chat/infrastructure/system_prompt_library_repository.dart',
    ).readAsString();
    final preferences = await File(
      'lib/features/settings/infrastructure/preferences_service.dart',
    ).readAsString();

    expect(workspace, contains('implements WorkspacePort'));
    expect(persistence, contains('implements PersistencePort'));
    expect(model, contains('implements ModelProvider'));
    expect(task, contains('implements TaskRepositoryPort'));
    expect(project, contains('implements ProjectRepositoryPort'));
    expect(aggregate, contains('implements ProjectAggregateRepositoryPort'));
    expect(chatLibrary, contains('implements ChatLibraryPort'));
    expect(promptLibrary, contains('implements PromptLibraryPort'));
    expect(preferences, contains('implements PreferencesPort'));
  });

  test(
    'presentation depends on controllers and immutable state, not project services',
    () async {
      final files = await _dartFiles('lib/features/chat/presentation');
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
    },
  );

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
      expect(
        source,
        contains(type),
        reason: '$type is not composed explicitly',
      );
    }
  });
}
