import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// These tests describe the target architecture rather than the current
/// transitional layout. They are deliberately strict: a passing suite should
/// mean that concrete adapters, compatibility shims, broad ports, and
/// monolithic orchestration have actually been removed.

class _SourceFile {
  const _SourceFile(this.path, this.source);

  final String path;
  final String source;
}

Future<List<_SourceFile>> _readSources(String root) async {
  final files = <_SourceFile>[];
  await for (final entity in Directory(root).list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.mapper.dart') ||
        entity.path.endsWith('mappers.init.dart')) {
      continue;
    }
    files.add(_SourceFile(entity.path, await entity.readAsString()));
  }
  return files;
}

String? _packageDirective(String line) {
  final match = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  ).firstMatch(line);
  final uri = match?.group(1);
  return uri?.startsWith('package:hermes/') == true ? uri : null;
}

Map<String, Set<String>> _packageEdges(Iterable<_SourceFile> files) {
  return {
    for (final file in files)
      file.path: {
        for (final line in file.source.split('\n')) ?_packageDirective(line),
      },
  };
}

void _expectNoViolations(String label, Iterable<String> violations) {
  final values = violations.toList(growable: false);
  expect(values, isEmpty, reason: '$label:\n${values.join('\n')}');
}

Iterable<_SourceFile> _under(Iterable<_SourceFile> files, String root) =>
    files.where((file) => file.path.startsWith(root));

bool _hasAbstractClass(String source, String name) => RegExp(
  r'abstract\s+(?:interface\s+)?class\s+' + RegExp.escape(name) + r'\b',
).hasMatch(source);

void main() {
  late List<_SourceFile> files;
  late Map<String, Set<String>> edges;

  setUpAll(() async {
    files = await _readSources('lib');
    edges = _packageEdges(files);
  });

  test('the shared kernel is dependency-free and directionally inward', () {
    final forbidden = <String>[
      'package:hermes/core/',
      'package:hermes/features/',
      'package:flutter/',
      'package:http/',
      'package:path_provider/',
      'package:shared_preferences/',
      'package:sqflite',
      'package:provider/',
      'dart:io',
    ];
    final violations = <String>[];

    for (final file in _under(files, 'lib/shared_kernel/')) {
      for (final line in file.source.split('\n')) {
        for (final edge in forbidden) {
          if (line.contains(edge)) {
            violations.add('${file.path}: imports $edge');
          }
        }
      }
    }

    _expectNoViolations('shared kernel dependency violations', violations);
  });

  test(
    'domains do not depend on core, platform, or other application layers',
    () {
      final domainRoots = [
        'lib/features/chat/domain/',
        'lib/features/model/domain/',
        'lib/features/project/domain/',
        'lib/features/task/domain/',
        'lib/features/workspace/domain/',
      ];
      final forbidden = <String>[
        'package:hermes/core/',
        'package:hermes/features/chat/application/',
        'package:hermes/features/model/infrastructure/',
        'package:hermes/features/project/application/',
        'package:hermes/features/project/infrastructure/',
        'package:hermes/features/task/application/',
        'package:hermes/features/task/infrastructure/',
        'package:hermes/features/workspace/application/',
        'package:flutter/',
        'package:http/',
        'package:sqflite',
      ];
      final violations = <String>[];

      for (final root in domainRoots) {
        for (final file in _under(files, root)) {
          for (final line in file.source.split('\n')) {
            for (final edge in forbidden) {
              if (line.contains(edge)) {
                violations.add('${file.path}: imports $edge');
              }
            }
          }
        }
      }

      _expectNoViolations('domain dependency violations', violations);
    },
  );

  test('feature application code depends on ports, not concrete adapters', () {
    final forbidden = <String>[
      'package:flutter/',
      'package:http/',
      'package:path_provider/',
      'package:shared_preferences/',
      'package:sqflite',
      'package:hermes/core/services/',
      'package:hermes/core/tools/',
      'package:hermes/core/models/',
      'package:hermes/features/chat/infrastructure/',
      'package:hermes/features/model/infrastructure/',
      'package:hermes/features/project/infrastructure/',
      'package:hermes/features/settings/infrastructure/',
      'package:hermes/features/task/infrastructure/',
    ];
    final violations = <String>[];

    for (final file in files.where(
      (file) =>
          file.path.startsWith('lib/features/') &&
          file.path.contains('/application/'),
    )) {
      for (final line in file.source.split('\n')) {
        for (final edge in forbidden) {
          if (line.contains(edge)) {
            violations.add('${file.path}: imports $edge');
          }
        }
      }
    }

    _expectNoViolations('application adapter leakage', violations);
  });

  test('presentation code depends on feature facades and view state only', () {
    final forbidden = <String>[
      'package:hermes/core/services/',
      'package:hermes/core/tools/',
      'package:hermes/features/chat/infrastructure/',
      'package:hermes/features/model/infrastructure/',
      'package:hermes/features/project/infrastructure/',
      'package:hermes/features/settings/infrastructure/',
      'package:hermes/features/task/infrastructure/',
      'package:hermes/features/workspace/application/',
    ];
    final violations = <String>[];

    for (final file in _under(files, 'lib/ui/')) {
      for (final line in file.source.split('\n')) {
        for (final edge in forbidden) {
          if (line.contains(edge)) {
            violations.add('${file.path}: imports $edge');
          }
        }
      }
    }

    _expectNoViolations('presentation adapter leakage', violations);
  });

  test(
    'presentation code is owned by features rather than a global UI bucket',
    () {
      final violations = <String>[];
      final legacyUiFiles = files
          .where((file) => file.path.startsWith('lib/ui/'))
          .toList(growable: false);
      if (legacyUiFiles.isNotEmpty) {
        violations.add(
          'lib/ui still contains ${legacyUiFiles.length} Dart files; move '
          'presentation into feature presentation packages',
        );
      }
      for (final file in files) {
        if (file.source.contains('package:hermes/ui/')) {
          violations.add('${file.path}: imports the removed global UI package');
        }
      }
      _expectNoViolations('feature-local presentation', violations);
    },
  );

  test('core cannot remain a cross-feature dependency hub', () {
    final violations = <String>[];
    for (final file in _under(files, 'lib/core/')) {
      for (final uri in edges[file.path] ?? const <String>{}) {
        if (uri.startsWith('package:hermes/features/')) {
          violations.add('${file.path}: imports $uri');
        }
      }
    }
    _expectNoViolations('core-to-feature dependency violations', violations);
  });

  test('compatibility re-exports have been removed', () {
    final compatibilityPaths = {
      'lib/core/services/preferences_service.dart',
      'lib/core/services/chat_library_repository.dart',
      'lib/core/services/system_prompt_library_repository.dart',
      'lib/features/task/application/task_application/task_repository.dart',
      'lib/features/task/application/task_application/task_model_output.dart',
      'lib/features/project/application/project_application/project_repository.dart',
      'lib/features/project/application/project_application/project_aggregate_repository.dart',
    };
    final violations = <String>[];
    for (final file in files.where(
      (file) => compatibilityPaths.contains(file.path),
    )) {
      for (final line in file.source.split('\n')) {
        if (!line.trimLeft().startsWith('export ')) continue;
        violations.add('${file.path}: $line');
      }
    }
    _expectNoViolations('feature compatibility exports', violations);
  });

  test('chat, task, and project use narrow application ports', () {
    final applicationSource = files
        .where(
          (file) =>
              file.path.startsWith('lib/features/') &&
              file.path.contains('/application/'),
        )
        .map((file) => file.source)
        .join('\n');
    final requiredPorts = [
      'TaskQueryPort',
      'TaskPlanningPort',
      'TaskExecutionPort',
      'TaskRecoveryPort',
      'ProjectQueryPort',
      'ProjectCommandPort',
      'ProjectExecutionPort',
    ];
    final missing = <String>[];

    for (final port in requiredPorts) {
      if (!_hasAbstractClass(applicationSource, port)) {
        missing.add('application layer: missing $port');
      }
    }

    final broadPortViolations = <String>[];
    for (final file in files.where(
      (file) => file.path.contains('/application/'),
    )) {
      for (final symbol in [
        'TaskApplicationPort',
        'ProjectApplicationPort',
        'TaskRepositoryPort',
        'ProjectRepositoryPort',
        'ToolService',
        'ProjectDocument',
      ]) {
        if (file.source.contains('abstract interface class $symbol')) {
          broadPortViolations.add('${file.path}: still declares $symbol');
        }
      }
    }

    _expectNoViolations('narrow-port declarations', [
      ...missing,
      ...broadPortViolations,
    ]);
  });

  test('application ports do not expose persistence documents or adapters', () {
    final portSource = files
        .where(
          (file) =>
              file.path.startsWith('lib/features/') &&
              file.path.contains('/application/') &&
              file.path.contains('port'),
        )
        .map((file) => file.source)
        .join('\n');
    final forbidden = [
      'TaskRepositoryPort',
      'ProjectRepositoryPort',
      'ProjectAggregateRepositoryPort',
      'ToolService',
      'ProjectDocument',
      'ProjectState',
    ];
    final violations = <String>[];

    for (final symbol in forbidden) {
      if (portSource.contains(symbol)) {
        violations.add('application port source: contains $symbol');
      }
    }

    _expectNoViolations('port abstraction leaks', violations);
  });

  test('controller entrypoints are composed from collaborators, not parts', () {
    final entrypoints = [
      'lib/features/chat/application/chat_controller.dart',
      'lib/features/task/application/task_application/task_controller.dart',
      'lib/features/project/application/project_application/project_application.dart',
    ];
    final violations = <String>[];

    for (final path in entrypoints) {
      final source = File(path).readAsStringSync();
      if (RegExp(r'^\s*part(?:\s+of)?\s+', multiLine: true).hasMatch(source)) {
        violations.add('$path: still uses Dart part composition');
      }
      for (final symbol in [
        '_delegate',
        '_ChatApplicationContext',
        '_TaskApplicationContext',
        '_ProjectApplicationContext',
      ]) {
        if (source.contains(symbol)) {
          violations.add('$path: still owns $symbol');
        }
      }
    }

    for (final file in files.where(
      (file) =>
          file.path.contains('/features/') &&
          file.path.contains('/application/'),
    )) {
      if (RegExp(r'^\s*part\s+of\s+', multiLine: true).hasMatch(file.source)) {
        violations.add('${file.path}: part-of implementation remains');
      }
    }

    _expectNoViolations('collaborator composition', violations);
  });

  test('chat state transitions are centralized in the reducer', () {
    final context = File(
      'lib/features/chat/application/chat_application_context.dart',
    ).readAsStringSync();
    final reducer = File(
      'lib/features/chat/domain/chat_state.dart',
    ).readAsStringSync();
    final violations = <String>[];

    if (RegExp(r'_state\s*=\s*_state\.copyWith').hasMatch(context)) {
      violations.add('chat_application_context.dart writes state directly');
    }
    if (RegExp(r'^\s*set\s+[A-Za-z_]', multiLine: true).hasMatch(context)) {
      violations.add('chat_application_context.dart exposes state setters');
    }
    if (!reducer.contains('class ChatStateReducer')) {
      violations.add('chat_state.dart is missing ChatStateReducer');
    }
    if (!RegExp(r'ChatState\s+reduce\s*\(').hasMatch(reducer)) {
      violations.add('ChatStateReducer must expose reduce(ChatState, event)');
    }

    _expectNoViolations('chat state ownership', violations);
  });

  test('project state is an aggregate boundary, not a compatibility alias', () {
    final domain = files
        .where((file) => file.path.startsWith('lib/features/project/domain/'))
        .map((file) => file.source)
        .join('\n');
    final allProjectApplication = files
        .where(
          (file) => file.path.startsWith('lib/features/project/application/'),
        )
        .map((file) => file.source)
        .join('\n');
    final violations = <String>[];

    if (domain.contains('typedef ProjectDocument = ProjectState')) {
      violations.add('ProjectDocument is still an alias for ProjectState');
    }
    if (!_hasAbstractClass(domain, 'ProjectAggregate') &&
        !RegExp(r'\bclass\s+ProjectAggregate\b').hasMatch(domain)) {
      violations.add('project domain is missing ProjectAggregate');
    }
    for (final type in [
      'ProjectPlanState',
      'ProjectExecutionState',
      'ProjectEvidenceState',
      'ProjectControlState',
    ]) {
      if (!RegExp(r'\bclass\s+' + type + r'\b').hasMatch(domain)) {
        violations.add('project domain is missing $type');
      }
    }
    for (final symbol in ['ProjectDocument', 'ProjectState']) {
      if (allProjectApplication.contains(symbol)) {
        violations.add('project application still exposes $symbol');
      }
    }

    _expectNoViolations('project aggregate boundary', violations);
  });

  test(
    'task execution uses an aggregate boundary rather than the persistence DTO',
    () {
      final taskDomain = files
          .where((file) => file.path.startsWith('lib/features/task/domain/'))
          .map((file) => file.source)
          .join('\n');
      final taskApplication = files
          .where(
            (file) => file.path.startsWith('lib/features/task/application/'),
          )
          .map((file) => file.source)
          .join('\n');
      final violations = <String>[];

      if (!RegExp(r'\bclass\s+TaskAggregate\b').hasMatch(taskDomain)) {
        violations.add('task domain is missing TaskAggregate');
      }
      if (RegExp(
        r'\bTask(?:\?|<|>|\s+snapshot|\s+task|\s+current)',
      ).hasMatch(taskApplication)) {
        violations.add(
          'task application still passes persistence Task documents directly',
        );
      }

      _expectNoViolations('task aggregate boundary', violations);
    },
  );

  test(
    'aggregate persistence is split from migration and transaction recovery',
    () {
      final aggregatePath =
          'lib/features/project/infrastructure/project_aggregate_repository.dart';
      final source = File(aggregatePath).readAsStringSync();
      final violations = <String>[];

      for (final method in [
        '_normalizeLegacyEmbeddedTasksUnlocked',
        '_commitUnlocked',
        '_recoverInterruptedTransactionsUnlocked',
      ]) {
        if (source.contains(method)) {
          violations.add('$aggregatePath still owns $method');
        }
      }
      if (source.split('\n').length > 500) {
        violations.add(
          '$aggregatePath exceeds the 500-line responsibility limit',
        );
      }
      for (final entry in {
        'lib/features/project/infrastructure/project_snapshot_migrator.dart':
            'class ProjectSnapshotMigrator',
        'lib/features/project/infrastructure/project_transaction_coordinator.dart':
            'class ProjectTransactionCoordinator',
      }.entries) {
        if (!File(entry.key).existsSync()) {
          violations.add('${entry.key} is missing');
        } else if (!File(entry.key).readAsStringSync().contains(entry.value)) {
          violations.add('${entry.key} is missing ${entry.value}');
        }
      }

      _expectNoViolations('aggregate persistence responsibilities', violations);
    },
  );

  test('tools use typed requests and results behind a registry port', () {
    final allSource = files.map((file) => file.source).join('\n');
    final toolInterface = files
        .where(
          (file) =>
              RegExp(r'\b(?:abstract\s+)?class\s+Tool\b').hasMatch(file.source),
        )
        .map((file) => file.source)
        .join('\n');
    final violations = <String>[];

    if (!_hasAbstractClass(allSource, 'ToolRegistryPort')) {
      violations.add('missing ToolRegistryPort');
    }
    if (!toolInterface.contains('Future<ToolResult>') ||
        !toolInterface.contains('ToolRequest')) {
      violations.add('Tool must expose typed ToolRequest/ToolResult execution');
    }
    if (RegExp(
      r'Future<String>\s+process\s*\(\s*String\s+input',
    ).hasMatch(allSource)) {
      violations.add('legacy string-based Tool.process remains');
    }

    _expectNoViolations('typed tool boundary', violations);
  });

  test('model runtime ownership is separated from chat application code', () {
    final violations = <String>[];
    for (final file in files.where(
      (file) =>
          file.path.startsWith('lib/features/') &&
          file.path.contains('/application/'),
    )) {
      for (final symbol in [
        'LlamaServerManager',
        'ChatClient',
        'package:http/',
      ]) {
        if (file.source.contains(symbol)) {
          violations.add(
            '${file.path}: contains concrete model adapter $symbol',
          );
        }
      }
    }
    if (!_hasAbstractClass(
      files.map((file) => file.source).join('\n'),
      'ModelRuntimePort',
    )) {
      violations.add('missing ModelRuntimePort');
    }

    _expectNoViolations('model runtime boundary', violations);
  });

  test(
    'application lifecycle has one coordinator and one exit coordinator',
    () {
      final dependencies = File('lib/app_dependencies.dart').readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();
      final violations = <String>[];

      if (!dependencies.contains('ApplicationLifecycleCoordinator')) {
        violations.add(
          'AppDependencies does not use ApplicationLifecycleCoordinator',
        );
      }
      if (dependencies.contains('ApplicationLifecycleState _lifecycleState')) {
        violations.add('AppDependencies duplicates lifecycle state ownership');
      }
      if (!File('lib/app/application_exit_coordinator.dart').existsSync()) {
        violations.add('missing lib/app/application_exit_coordinator.dart');
      } else if (!File(
        'lib/app/application_exit_coordinator.dart',
      ).readAsStringSync().contains('class ApplicationExitCoordinator')) {
        violations.add('missing ApplicationExitCoordinator');
      }
      if (!main.contains('ApplicationExitCoordinator')) {
        violations.add('main.dart does not use ApplicationExitCoordinator');
      }
      if (main.contains('didRequestAppExit')) {
        violations.add('main.dart still owns exit orchestration');
      }

      _expectNoViolations('lifecycle ownership', violations);
    },
  );

  test('the package import graph contains no cycles', () {
    final violations = <String>[];
    final packageToPath = <String, String>{};
    for (final file in files) {
      final relative = file.path.startsWith('lib/')
          ? file.path.substring('lib/'.length)
          : file.path;
      packageToPath['package:hermes/$relative'] = file.path;
    }

    final visiting = <String>{};
    final visited = <String>{};
    final stack = <String>[];

    void visit(String filePath) {
      if (filePath.isEmpty || visited.contains(filePath)) return;
      if (!visiting.add(filePath)) {
        final start = stack.indexOf(filePath);
        final cycle = [...stack.skip(start < 0 ? 0 : start), filePath];
        violations.add('cycle: ${cycle.join(' -> ')}');
        return;
      }

      stack.add(filePath);
      for (final uri in edges[filePath] ?? const <String>{}) {
        final target = packageToPath[uri];
        if (target != null) visit(target);
      }
      stack.removeLast();
      visiting.remove(filePath);
      visited.add(filePath);
    }

    for (final file in files) {
      visit(file.path);
    }
    _expectNoViolations('package import cycles', violations);
  });
}
