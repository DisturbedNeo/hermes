import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/project_system/project_discovery_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  test('collects bounded read-only planning evidence', () async {
    final root = await Directory.systemTemp.createTemp('hermes_discovery_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await Directory('${root.path}/.git').create();
    await File('${root.path}/README.md').writeAsString('# Example workspace');
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: discovery_example
dependencies:
  flutter:
    sdk: flutter
''');
    await Directory('${root.path}/lib/src').create(recursive: true);
    await File('${root.path}/lib/main.dart').writeAsString('void main() {}');
    await Directory('${root.path}/node_modules/pkg').create(recursive: true);
    await File(
      '${root.path}/node_modules/pkg/index.js',
    ).writeAsString('ignored');
    for (var index = 0; index < 90; index++) {
      await File('${root.path}/file_$index.txt').writeAsString('$index');
    }
    final workspace = WorkspaceAttachment(
      rootPath: root.path,
      displayName: 'Workspace',
      lastOpenedAt: DateTime(2026, 1, 1),
    );
    final sandbox = WorkspaceSandbox();
    final service = ProjectDiscoveryService(
      taskService: TaskService(
        toolService: ToolService(workspaceSandbox: sandbox),
        sandbox: sandbox,
      ),
    );
    final before = await root.list().map((item) => item.path).toSet();

    final snapshot = await service.collect(
      workspace: workspace,
      project: _project(),
    );
    final after = await root.list().map((item) => item.path).toSet();

    expect(snapshot.workspaceName, 'Workspace');
    expect(snapshot.gitAvailable, isTrue);
    expect(snapshot.rootEntries.length, lessThanOrEqualTo(80));
    expect(snapshot.workspaceProfile.treePaths.length, lessThanOrEqualTo(400));
    expect(snapshot.workspaceProfile.packageName, 'discovery_example');
    expect(snapshot.workspaceProfile.languages, contains('Dart'));
    expect(snapshot.workspaceProfile.frameworks, contains('Flutter'));
    expect(
      snapshot.workspaceProfile.highSignalFiles.map((item) => item.path),
      containsAll(['README.md', 'pubspec.yaml', 'lib/main.dart']),
    );
    expect(
      snapshot.workspaceProfile.treePaths,
      isNot(contains(contains('node_modules'))),
    );
    expect(snapshot.criterionSummaries.single, contains('criterion_001'));
    expect(snapshot.activeMemory.single, contains('Keep the API stable'));
    expect(before, after);
  });

  test(
    'reads a referenced 16 KiB design completely before ordinary files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hermes_design_discovery_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final design =
          'Chronicle .NET observability design\n${List.filled(16 * 1024, 'x').join()}';
      await File('${root.path}/Design.md').writeAsString(design);
      await File('${root.path}/README.md').writeAsString('# Generic readme');
      final workspace = WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Chronicle',
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      final sandbox = WorkspaceSandbox();
      final service = ProjectDiscoveryService(
        taskService: TaskService(
          toolService: ToolService(workspaceSandbox: sandbox),
          sandbox: sandbox,
        ),
      );

      final snapshot = await service.collect(
        workspace: workspace,
        goalContext: 'Implement the system specified in `Design.md`.',
      );

      expect(snapshot.workspaceProfile.highSignalFiles.first.path, 'Design.md');
      expect(snapshot.workspaceProfile.highSignalFiles.first.content, design);
      expect(
        snapshot.workspaceProfile.highSignalFiles.first.truncated,
        isFalse,
      );
      expect(snapshot.workspaceProfile.requiredContextIssues, isEmpty);
    },
  );

  test('prioritizes a nonstandard filename referenced by the goal', () async {
    final root = await Directory.systemTemp.createTemp(
      'hermes_priority_discovery_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(
      '${root.path}/product-blueprint.txt',
    ).writeAsString('authoritative');
    await File('${root.path}/README.md').writeAsString('ordinary');
    final workspace = WorkspaceAttachment(
      rootPath: root.path,
      displayName: 'Workspace',
      lastOpenedAt: DateTime(2026, 1, 1),
    );
    final sandbox = WorkspaceSandbox();
    final service = ProjectDiscoveryService(
      taskService: TaskService(
        toolService: ToolService(workspaceSandbox: sandbox),
        sandbox: sandbox,
      ),
    );

    final snapshot = await service.collect(
      workspace: workspace,
      goalContext: 'Follow "product-blueprint.txt" exactly.',
    );

    expect(
      snapshot.workspaceProfile.highSignalFiles
          .map((item) => item.path)
          .take(2),
      orderedEquals(['product-blueprint.txt', 'README.md']),
    );
  });

  test(
    'reports referenced context that cannot fit the discovery budget',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hermes_budget_discovery_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File(
        '${root.path}/ARCHITECTURE.MD',
      ).writeAsString(List.filled(65 * 1024, 'a').join());
      final workspace = WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      final sandbox = WorkspaceSandbox();
      final service = ProjectDiscoveryService(
        taskService: TaskService(
          toolService: ToolService(workspaceSandbox: sandbox),
          sandbox: sandbox,
        ),
      );

      final snapshot = await service.collect(
        workspace: workspace,
        goalContext: 'Implement `ARCHITECTURE.MD`.',
      );

      expect(
        snapshot.workspaceProfile.highSignalFiles.single.truncated,
        isTrue,
      );
      expect(
        snapshot.workspaceProfile.requiredContextIssues.single.code,
        'required_context_truncated',
      );
    },
  );
}

ProjectState _project() {
  final now = DateTime(2026, 1, 1);
  return ProjectState(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Deliver the project',
    refinedGoal: 'Deliver the project',
    criteria: [
      ProjectCriterion(
        id: 'criterion_001',
        statement: 'The project is verified.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    constraints: const [],
    memory: [
      ProjectMemoryEntry(
        id: 'memory_001',
        kind: ProjectMemoryKind.requirement,
        content: 'Keep the API stable.',
        sourceType: ProjectMemorySourceType.user,
        confidence: ProjectMemoryConfidence.confirmed,
        protected: true,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}
