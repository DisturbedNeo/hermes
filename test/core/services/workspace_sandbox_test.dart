import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  group('WorkspaceSandbox', () {
    late Directory root;
    late Directory outside;
    late WorkspaceSandbox sandbox;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_workspace_');
      outside = await Directory.systemTemp.createTemp('hermes_outside_');
      sandbox = WorkspaceSandbox();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await outside.exists()) await outside.delete(recursive: true);
    });

    test('allows nested paths inside the workspace', () async {
      await File('${root.path}/notes/chapter.txt').create(recursive: true);
      await File('${root.path}/notes/chapter.txt').writeAsString('draft');

      final resolved = await sandbox.resolve(root.path, 'notes/chapter.txt');

      expect(resolved.relativePath, 'notes/chapter.txt');
      expect(resolved.absolutePath, endsWith('notes/chapter.txt'));
    });

    test('rejects parent traversal outside the workspace', () async {
      await expectLater(
        sandbox.resolve(root.path, '../outside.txt', mustExist: false),
        throwsA(isA<WorkspaceSandboxException>()),
      );
    });

    test('rejects absolute paths outside the workspace', () async {
      final file = File('${outside.path}/secret.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('secret');

      await expectLater(
        sandbox.resolve(root.path, file.path),
        throwsA(isA<WorkspaceSandboxException>()),
      );
    });

    test('rejects symlinks that escape the workspace', () async {
      if (Platform.isWindows) return;

      final target = File('${outside.path}/secret.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('secret');
      await Link('${root.path}/secret_link').create(target.path);

      await expectLater(
        sandbox.readFile(root.path, 'secret_link'),
        throwsA(isA<WorkspaceSandboxException>()),
      );
    });

    test('rejects rename destinations outside the workspace', () async {
      await File('${root.path}/inside.txt').writeAsString('inside');

      await expectLater(
        sandbox.renamePath(root.path, 'inside.txt', '../outside.txt'),
        throwsA(isA<WorkspaceSandboxException>()),
      );
    });

    test('search skips binary files that cannot be decoded as UTF-8', () async {
      await File('${root.path}/notes.txt').writeAsString('needle');
      await File('${root.path}/binary.dat').writeAsBytes([0xff, 0xfe, 0xfd]);

      final results = await sandbox.searchFiles(root.path, 'needle');

      expect(results.map((item) => item['path']), contains('notes.txt'));
      expect(
        results.map((item) => item['path']),
        isNot(contains('binary.dat')),
      );
    });

    test('search skips hidden dot-folders from workspace root', () async {
      await File(
        '${root.path}/lib/main.dart',
      ).create(recursive: true).then((file) => file.writeAsString('needle'));
      await File(
        '${root.path}/.dart_tool/generated.dart',
      ).create(recursive: true).then((file) => file.writeAsString('needle'));
      await File(
        '${root.path}/.pub-cache/package.dart',
      ).create(recursive: true).then((file) => file.writeAsString('needle'));

      final results = await sandbox.searchFiles(root.path, 'needle');
      final paths = results.map((item) => item['path']);

      expect(paths, contains('lib/main.dart'));
      expect(paths, isNot(contains('.dart_tool/generated.dart')));
      expect(paths, isNot(contains('.pub-cache/package.dart')));
    });

    test('search treats slash path as workspace root', () async {
      await File(
        '${root.path}/lib/main.dart',
      ).create(recursive: true).then((file) => file.writeAsString('needle'));
      await File(
        '${root.path}/.dart_tool/generated.dart',
      ).create(recursive: true).then((file) => file.writeAsString('needle'));

      final results = await sandbox.searchFiles(
        root.path,
        'needle',
        relativePath: '/',
      );
      final paths = results.map((item) => item['path']);

      expect(paths, contains('lib/main.dart'));
      expect(paths, isNot(contains('.dart_tool/generated.dart')));
    });

    test(
      'search skips hidden dot-folders below non-dot explicit paths',
      () async {
        await File(
          '${root.path}/packages/app/lib/main.dart',
        ).create(recursive: true).then((file) => file.writeAsString('needle'));
        await File(
          '${root.path}/packages/app/.dart_tool/generated.dart',
        ).create(recursive: true).then((file) => file.writeAsString('needle'));

        final results = await sandbox.searchFiles(
          root.path,
          'needle',
          relativePath: 'packages/app',
        );
        final paths = results.map((item) => item['path']);

        expect(paths, contains('packages/app/lib/main.dart'));
        expect(
          paths,
          isNot(contains('packages/app/.dart_tool/generated.dart')),
        );
      },
    );

    test('search includes explicitly requested hidden dot-folders', () async {
      await File(
        '${root.path}/.dart_tool/generated.dart',
      ).create(recursive: true).then((file) => file.writeAsString('needle'));

      final results = await sandbox.searchFiles(
        root.path,
        'needle',
        relativePath: '.dart_tool',
      );

      expect(
        results.map((item) => item['path']),
        contains('.dart_tool/generated.dart'),
      );
    });

    test(
      'search includes explicitly requested nested hidden dot-folders',
      () async {
        await File(
          '${root.path}/packages/app/.cache/index.txt',
        ).create(recursive: true).then((file) => file.writeAsString('needle'));

        final results = await sandbox.searchFiles(
          root.path,
          'needle',
          relativePath: 'packages/app/.cache',
        );

        expect(
          results.map((item) => item['path']),
          contains('packages/app/.cache/index.txt'),
        );
      },
    );

    test('search reports oversized results as a tool error', () async {
      final longLine =
          '${List.filled(WorkspaceSandbox.maxSearchOutputBytes, 'x').join()} needle';
      await File('${root.path}/huge.txt').writeAsString(longLine);

      final result = await ToolService().execute(
        toolId: 'search_files',
        argumentsJson: '{"query":"needle"}',
        context: WorkspaceToolContext(
          workspace: WorkspaceAttachment.fromPath(root.path),
        ),
      );

      expect(result, contains('"error"'));
      expect(result, contains('Search results are too large'));
    });

    test('readFile reports directories as the wrong path type', () async {
      await Directory('${root.path}/lib').create();

      await expectLater(
        sandbox.readFile(root.path, 'lib'),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.message,
            'message',
            contains('Use list_directory'),
          ),
        ),
      );
    });
  });

  group('ToolService workspace tools', () {
    test('does not expose workspace tools by default', () {
      final tools = ToolService().getToolDefinitions();

      expect(tools.map((tool) => tool.id), isNot(contains('read_file')));
    });

    test('exposes workspace tools when requested', () {
      final tools = ToolService().getToolDefinitions(
        includeWorkspaceTools: true,
      );

      expect(tools.map((tool) => tool.id), contains('read_file'));
      expect(tools.map((tool) => tool.id), contains('run_command'));
    });

    test('rejects workspace tool execution without context', () async {
      final result = await ToolService().execute(
        toolId: 'read_file',
        argumentsJson: '{"path":"README.md"}',
      );

      expect(result, contains('active workspace'));
    });

    test('gates terminal execution on workspace approval', () async {
      final root = await Directory.systemTemp.createTemp('hermes_workspace_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final service = ToolService();
      final result = await service.execute(
        toolId: 'run_command',
        argumentsJson: '{"command":"pwd"}',
        context: WorkspaceToolContext(
          workspace: WorkspaceAttachment.fromPath(root.path),
        ),
      );

      expect(result, contains('Terminal commands are disabled'));
    });
  });
}
