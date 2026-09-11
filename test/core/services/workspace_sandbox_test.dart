import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('WorkspaceSandbox', () {
    late Directory root;
    late Directory outside;
    late WorkspaceSandbox sandbox;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
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

    test('does not restore legacy host terminal approval', () async {
      final service = WorkspaceService(sandbox: sandbox);
      addTearDown(service.dispose);

      final restored = await service.restore(
        rootPath: root.path,
        displayName: 'workspace',
        lastOpenedAt: DateTime(2024),
        commandExecutionApproved: true,
      );

      expect(restored.commandExecutionApproved, isFalse);
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

      final result = await ToolService(workspaceSandbox: sandbox).execute(
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

    test('bounds reads, writes, and patched results by UTF-8 bytes', () async {
      final oversized = List.filled(
        WorkspaceSandbox.maxWriteBytes + 1,
        'x',
      ).join();
      final existing = File('${root.path}/existing.txt');
      await existing.writeAsString('keep me');

      await expectLater(
        sandbox.writeFile(root.path, 'too-large.txt', oversized),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.code,
            'code',
            'workspace_file_too_large',
          ),
        ),
      );
      await expectLater(
        sandbox.patchFile(root.path, 'existing.txt', 'keep me', oversized),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.code,
            'code',
            'workspace_file_too_large',
          ),
        ),
      );
      await File('${root.path}/oversized-read.txt').writeAsString(oversized);
      await expectLater(
        sandbox.readFile(root.path, 'oversized-read.txt'),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.code,
            'code',
            'workspace_file_too_large',
          ),
        ),
      );

      expect(await existing.readAsString(), 'keep me');
      expect(await File('${root.path}/too-large.txt').exists(), isFalse);
    });

    test('atomic writes preserve permissions and leave no temp file', () async {
      if (!Platform.isLinux) return;
      final target = File('${root.path}/script.sh');
      await target.writeAsString('#!/bin/sh\necho old\n');
      expect((await Process.run('chmod', ['755', target.path])).exitCode, 0);

      await sandbox.writeFile(root.path, 'script.sh', '#!/bin/sh\necho new\n');

      expect(await target.readAsString(), '#!/bin/sh\necho new\n');
      expect((await target.stat()).mode & 0x1ff, 0x1ed);
      expect(
        await target.parent
            .list()
            .where(
              (entry) =>
                  entry.path.contains('.script.sh.hermes-') &&
                  entry.path.endsWith('.tmp'),
            )
            .isEmpty,
        isTrue,
      );
    });

    test('filesystem inspection honors cancellation', () async {
      await File('${root.path}/notes.txt').writeAsString('needle');
      final token = CancellationToken();
      await token.cancel();

      await expectLater(
        sandbox.listDirectory(root.path, '.', cancellationToken: token),
        throwsA(isA<OperationCancelledException>()),
      );
      await expectLater(
        sandbox.readFile(root.path, 'notes.txt', cancellationToken: token),
        throwsA(isA<OperationCancelledException>()),
      );
      await expectLater(
        sandbox.searchFiles(root.path, 'needle', cancellationToken: token),
        throwsA(isA<OperationCancelledException>()),
      );
    });

    test('artifact previews stop at the requested character limit', () async {
      await File(
        '${root.path}/artifact.txt',
      ).writeAsString(List.filled(100, 'abcd').join());

      final preview = await sandbox.readFilePreview(
        root.path,
        'artifact.txt',
        maxChars: 25,
      );

      expect(preview, '${List.filled(6, 'abcd').join()}a...');
      expect(preview.length, 28);
    });

    test('directory listings reject more than the configured limit', () async {
      for (var i = 0; i <= WorkspaceSandbox.maxDirectoryEntries; i++) {
        File('${root.path}/entry_$i').createSync();
      }

      await expectLater(
        sandbox.listDirectory(root.path, '.'),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.code,
            'code',
            'workspace_listing_too_large',
          ),
        ),
      );
    });

    test('searches reject more than the configured file limit', () async {
      for (var i = 0; i <= WorkspaceSandbox.maxSearchFiles; i++) {
        File('${root.path}/file_$i').createSync();
      }

      await expectLater(
        sandbox.searchFiles(root.path, 'not-present'),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.code,
            'code',
            'workspace_search_too_broad',
          ),
        ),
      );
    });

    test('runCommand blocks dangerous executables before spawning', () async {
      final file = File('${root.path}/generated.txt')
        ..writeAsStringSync('important');

      await expectLater(
        sandbox.runCommand(
          root.path,
          executable: 'rm',
          arguments: ['generated.txt'],
        ),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.message,
            'message',
            contains('File deletion commands'),
          ),
        ),
      );

      expect(await file.exists(), isTrue);
    });

    test('runCommand runs a single shell command line', () async {
      final result = await sandbox.runCommand(
        root.path,
        command: 'printf hello > generated.txt && cat generated.txt',
      );

      expect(result['exit_code'], 0);
      expect(result['stdout'], 'hello');
      expect(await File('${root.path}/generated.txt').readAsString(), 'hello');
    });

    test(
      'runCommand blocks dangerous commands inside shell wrappers',
      () async {
        final file = File('${root.path}/generated.txt')
          ..writeAsStringSync('important');

        await expectLater(
          sandbox.runCommand(
            root.path,
            executable: 'bash',
            arguments: ['-lc', 'echo ok && rm generated.txt'],
          ),
          throwsA(
            isA<WorkspaceSandboxException>().having(
              (error) => error.message,
              'message',
              contains('File deletion commands'),
            ),
          ),
        );

        expect(await file.exists(), isTrue);
      },
    );

    test('runCommand blocks dangerous command substitution', () async {
      final file = File('${root.path}/generated.txt')
        ..writeAsStringSync('important');

      await expectLater(
        sandbox.runCommand(root.path, command: 'echo \$(rm generated.txt)'),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.message,
            'message',
            contains('command substitution'),
          ),
        ),
      );

      expect(await file.exists(), isTrue);
    });

    test('runCommand blocks generated and wrapped deletion commands', () async {
      final file = File('${root.path}/generated.txt')
        ..writeAsStringSync('important');

      for (final command in const [
        'printf "generated.txt\\n" | xargs rm',
        'timeout 5 nice -n 2 rm generated.txt',
        'python -c "print(1)"',
        'python3 -c "print(1)"',
        'node -e "console.log(1)"',
        'node --eval "console.log(1)"',
        'node -p "1 + 1"',
        'node --print "1 + 1"',
        'perl -e "print 1"',
        'ruby -e "puts 1"',
        'lua -e "print(1)"',
        'php -r "echo 1;"',
      ]) {
        await expectLater(
          sandbox.runCommand(root.path, command: command),
          throwsA(isA<WorkspaceSandboxException>()),
        );
      }

      expect(await file.exists(), isTrue);
    });

    test('runCommand kills the process group on timeout', () async {
      final timedSandbox = WorkspaceSandbox(
        commandTimeout: const Duration(milliseconds: 250),
        commandTerminationGrace: const Duration(milliseconds: 100),
      );

      await expectLater(
        timedSandbox.runCommand(
          root.path,
          command:
              'sleep 30 & child=\$!; echo \$child > child.pid; wait \$child',
        ),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.code,
            'code',
            'command_timeout',
          ),
        ),
      );

      final pid = int.parse(
        (await File('${root.path}/child.pid').readAsString()).trim(),
      );
      expect(await _processExists(pid), isFalse);
    });

    test('runCommand escalates when the process group ignores TERM', () async {
      final timedSandbox = WorkspaceSandbox(
        commandTimeout: const Duration(milliseconds: 250),
        commandTerminationGrace: const Duration(milliseconds: 100),
      );

      await expectLater(
        timedSandbox.runCommand(
          root.path,
          command:
              'trap \'\' TERM; echo \$\$ > stubborn.pid; while true; do sleep 1; done',
        ),
        throwsA(
          isA<WorkspaceSandboxException>().having(
            (error) => error.code,
            'code',
            'command_timeout',
          ),
        ),
      );

      final pid = int.parse(
        (await File('${root.path}/stubborn.pid').readAsString()).trim(),
      );
      expect(await _processExists(pid), isFalse);
    });

    test('runCommand kills the process group when cancelled', () async {
      final token = CancellationToken();
      final running = sandbox.runCommand(
        root.path,
        command: 'sleep 30 & child=\$!; echo \$child > child.pid; wait \$child',
        cancellationToken: token,
      );
      final pidFile = File('${root.path}/child.pid');
      for (var i = 0; i < 50 && !await pidFile.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      await token.cancel();
      await expectLater(running, throwsA(isA<OperationCancelledException>()));
      final pid = int.parse((await pidFile.readAsString()).trim());
      expect(await _processExists(pid), isFalse);
    });

    test(
      'runCommand does not wait for a child after the parent exits on cancellation',
      () async {
        final cancellableSandbox = WorkspaceSandbox(
          commandTimeout: const Duration(seconds: 5),
          commandTerminationGrace: const Duration(milliseconds: 100),
        );
        final token = CancellationToken();
        final running = cancellableSandbox.runCommand(
          root.path,
          command:
              'trap \'exit 0\' TERM; (trap \'\' TERM; sleep 30) & child=\$!; echo \$child > child.pid; wait \$child',
          cancellationToken: token,
        );
        final pidFile = File('${root.path}/child.pid');
        for (var i = 0; i < 50 && !await pidFile.exists(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        await token.cancel();
        await expectLater(
          running,
          throwsA(isA<OperationCancelledException>()),
        ).timeout(const Duration(seconds: 2));
        final pid = int.parse((await pidFile.readAsString()).trim());
        expect(await _processExists(pid), isFalse);
      },
    );

    test('runCommand drains and bounds large output', () async {
      final result = await sandbox.runCommand(
        root.path,
        command: 'yes x | head -c 200000',
      );

      expect(result['exit_code'], 0);
      expect(result['stdout'], endsWith('... output truncated ...'));
      expect((result['stdout'] as String).length, lessThan(70000));
    });
  });

  group('ToolService workspace tools', () {
    test('does not expose workspace tools by default', () {
      final tools = ToolService(
        workspaceSandbox: WorkspaceSandbox(),
      ).getToolDefinitions();

      expect(tools.map((tool) => tool.id), isNot(contains('read_file')));
    });

    test('exposes workspace tools when requested', () {
      final tools = ToolService(
        workspaceSandbox: WorkspaceSandbox(),
      ).getToolDefinitions(includeWorkspaceTools: true);

      expect(tools.map((tool) => tool.id), contains('read_file'));
      expect(tools.map((tool) => tool.id), contains('run_command'));
      final runCommand = tools.singleWhere((tool) => tool.id == 'run_command');
      final properties = runCommand.schema['properties'] as Map;
      expect(properties.keys, contains('args'));
    });

    test('rejects workspace tool execution without context', () async {
      final result = await ToolService(
        workspaceSandbox: WorkspaceSandbox(),
      ).execute(toolId: 'read_file', argumentsJson: '{"path":"README.md"}');

      expect(result, contains('active workspace'));
    });

    test('gates terminal execution on workspace approval', () async {
      final root = await Directory.systemTemp.createTemp('hermes_workspace_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final service = ToolService(workspaceSandbox: WorkspaceSandbox());
      final result = await service.execute(
        toolId: 'run_command',
        argumentsJson: '{"command":"pwd"}',
        context: WorkspaceToolContext(
          workspace: WorkspaceAttachment.fromPath(root.path),
        ),
      );

      expect(result, contains('Host terminal access is disabled'));
    });

    test('reports blocked terminal commands as tool errors', () async {
      final root = await Directory.systemTemp.createTemp('hermes_workspace_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File('${root.path}/generated.txt').writeAsString('important');

      final service = ToolService(workspaceSandbox: WorkspaceSandbox());
      final result = await service.execute(
        toolId: 'run_command',
        argumentsJson: '{"command":"rm generated.txt"}',
        context: WorkspaceToolContext(
          workspace: WorkspaceAttachment.fromPath(
            root.path,
            commandExecutionApproved: true,
          ),
        ),
      );

      expect(result, contains('"error"'));
      expect(result, contains('File deletion commands'));
      expect(await File('${root.path}/generated.txt').exists(), isTrue);
    });

    test('runs declared command arguments with shell quoting', () async {
      final root = await Directory.systemTemp.createTemp('hermes_workspace_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final service = ToolService(workspaceSandbox: WorkspaceSandbox());
      final result = await service.execute(
        toolId: 'run_command',
        argumentsJson: '{"command":"printf","args":["%s","hello world"]}',
        context: WorkspaceToolContext(
          workspace: WorkspaceAttachment.fromPath(
            root.path,
            commandExecutionApproved: true,
          ),
        ),
      );

      expect(result, contains('"stdout":"hello world"'));
    });
  });
}

Future<bool> _processExists(int pid) async {
  final result = await Process.run('kill', ['-0', '$pid']);
  return result.exitCode == 0;
}
