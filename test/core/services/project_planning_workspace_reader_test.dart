import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/project_system/project_planning_workspace_reader.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  test('reads an allowed document in bounded windows until complete', () async {
    final root = await Directory.systemTemp.createTemp('hermes_planning_read_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final design = List.generate(
      8,
      (index) => 'Design line ${index + 1}',
    ).join('\n');
    await File('${root.path}/Design.md').writeAsString(design);

    final reader = ProjectPlanningWorkspaceReader(
      workspace: WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      ),
      sandbox: WorkspaceSandbox(),
      allowedPaths: const ['Design.md'],
      maxTotalBytes: 200,
      maxWindowBytes: 100,
      maxWindowLines: 3,
    );

    final first = await reader.read(requestedPath: 'Design.md');
    expect(first['ok'], isTrue);
    expect(first['start_line'], 1);
    expect(first['end_line'], 3);
    expect(first['has_more'], isTrue);
    expect(first['next_start_line'], 4);

    final second = await reader.read(
      requestedPath: 'Design.md',
      startLine: first['next_start_line'] as int,
    );
    expect(second['ok'], isTrue);
    expect(second['start_line'], 4);
    expect(second['end_line'], 6);
    expect(second['next_start_line'], 7);

    final third = await reader.read(
      requestedPath: 'Design.md',
      startLine: second['next_start_line'] as int,
    );
    expect(third['ok'], isTrue);
    expect(third['has_more'], isFalse);
    expect(third['end_line'], 8);
    expect(
      [
        first,
        second,
        third,
      ].map((item) => item['content'] as String).join('\n'),
      design,
    );
  });

  test('enforces the discovery allowlist and total context budget', () async {
    final root = await Directory.systemTemp.createTemp('hermes_planning_read_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File('${root.path}/Design.md').writeAsString('one\ntwo\nthree');
    await File('${root.path}/secret.md').writeAsString('not discoverable');

    final reader = ProjectPlanningWorkspaceReader(
      workspace: WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      ),
      sandbox: WorkspaceSandbox(),
      allowedPaths: const ['Design.md'],
      maxTotalBytes: 3,
      maxWindowBytes: 3,
    );

    final outside = await reader.read(requestedPath: 'secret.md');
    expect(outside['ok'], isFalse);
    expect(outside['code'], 'workspace_path_not_in_discovery');

    final first = await reader.read(requestedPath: 'Design.md');
    expect(first['ok'], isTrue);
    expect(first['bytes'], 3);
    expect(first['has_more'], isTrue);

    final exhausted = await reader.read(
      requestedPath: 'Design.md',
      startLine: first['next_start_line'] as int,
    );
    expect(exhausted['ok'], isFalse);
    expect(exhausted['code'], 'planning_context_budget_exhausted');
  });
}
