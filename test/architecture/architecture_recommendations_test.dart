import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architectural target tests for the post-migration Hermes design.
///
/// These tests are intentionally expected to fail while the current migration
/// is incomplete. They are source-level guardrails for boundaries that are
/// difficult to express with ordinary runtime tests. The tests should be
/// removed or narrowed only when the corresponding architectural decision has
/// been implemented and replaced by stronger compile-time checks where
/// possible.

Future<Map<String, String>> _readProductionSources() async {
  final sources = <String, String>{};
  await for (final entity in Directory('lib').list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    sources[path] = await entity.readAsString();
  }
  return sources;
}

Iterable<MapEntry<String, String>> _under(
  Map<String, String> sources,
  String directory,
) => sources.entries.where(
  (entry) => entry.key == directory || entry.key.startsWith('$directory/'),
);

String _source(Map<String, String> sources, String path) {
  final value = sources[path];
  if (value == null) throw StateError('Expected production file $path');
  return value;
}

void _expectNoViolations(String label, Iterable<String> violations) {
  final values = violations.toList(growable: false);
  expect(values, isEmpty, reason: '$label:\n${values.join('\n')}');
}

void main() {
  late Map<String, String> sources;

  setUpAll(() async {
    sources = await _readProductionSources();
  });

  test('application and infrastructure seams are statically typed', () {
    const files = [
      'lib/features/chat/application/chat_controller.dart',
      'lib/features/chat/application/chat_workspace_controller.dart',
      'lib/features/chat/runtime/chat_workspace_controller.dart',
      'lib/features/task/application/task_application/task_controller.dart',
      'lib/features/task/application/task_application/task_ports.dart',
      'lib/features/task/runtime/task_controller.dart',
      'lib/features/task/runtime/task_context.dart',
      'lib/features/task/runtime/task_persistence_store.dart',
      'lib/features/task/runtime/task_tool_execution_service.dart',
      'lib/features/project/application/project_application/project_application.dart',
      'lib/features/project/application/project_application/project_ports.dart',
      'lib/features/project/runtime/project_context.dart',
      'lib/features/project/runtime/project_aggregate_store.dart',
      'lib/features/project/runtime/project_planning_workspace_reader.dart',
      'lib/features/project/infrastructure/project_aggregate_repository.dart',
      'lib/features/project/infrastructure/project_snapshot_migrator.dart',
      'lib/features/project/infrastructure/project_transaction_coordinator.dart',
      'lib/shared_kernel/tool_contracts.dart',
      'lib/features/project/application/project_application/project_execution_port.dart',
    ];
    final dynamicDeclaration = RegExp(
      r'^\s*(?:required\s+)?dynamic\??\s+(?:get\s+)?[A-Za-z_]\w*',
      multiLine: true,
    );
    final violations = <String>[];

    for (final path in files) {
      for (final match in dynamicDeclaration.allMatches(
        _source(sources, path),
      )) {
        violations.add('$path:${match.start}: dynamic dependency declaration');
      }
    }

    _expectNoViolations('typed application seams', violations);
  });

  test(
    'runtime entrypoints are composed from collaborators, not Dart parts',
    () {
      const entrypoints = [
        'lib/features/chat/runtime/chat_controller.dart',
        'lib/features/task/runtime/task_controller.dart',
        'lib/features/project/runtime/project_application.dart',
      ];
      final partDeclaration = RegExp(r'^\s*part(?:\s+of)?\s+', multiLine: true);
      final violations = <String>[];

      for (final path in entrypoints) {
        if (partDeclaration.hasMatch(_source(sources, path))) {
          violations.add(
            '$path: runtime entrypoint still uses part composition',
          );
        }
      }

      _expectNoViolations('runtime collaborator composition', violations);
    },
  );

  test('feature domains own feature entities instead of shared_kernel', () {
    final violations = <String>[];
    final sharedKernel = _under(
      sources,
      'lib/shared_kernel',
    ).map((entry) => entry.value).join('\n');

    if (RegExp(r'\bclass\s+ProjectDocument\b').hasMatch(sharedKernel)) {
      violations.add('shared_kernel still owns ProjectDocument');
    }
    if (RegExp(r'\bclass\s+Task\b').hasMatch(sharedKernel)) {
      violations.add('shared_kernel still owns Task');
    }

    final projectDomain = _under(
      sources,
      'lib/features/project/domain',
    ).map((entry) => entry.value).join('\n');
    if (!RegExp(r'\bclass\s+ProjectAggregate\b').hasMatch(projectDomain)) {
      violations.add(
        'features/project/domain does not define ProjectAggregate',
      );
    }

    final taskDomain = _under(
      sources,
      'lib/features/task/domain',
    ).map((entry) => entry.value).join('\n');
    if (!RegExp(r'\bclass\s+TaskAggregate\b').hasMatch(taskDomain)) {
      violations.add('features/task/domain does not define TaskAggregate');
    }

    final modelDomain = _under(
      sources,
      'lib/features/model/domain',
    ).map((entry) => entry.value).join('\n');
    if (!RegExp(
      r'\b(?:abstract\s+interface\s+)?class\s+ModelProvider\b',
    ).hasMatch(modelDomain)) {
      violations.add('features/model/domain does not own ModelProvider');
    }

    _expectNoViolations('feature domain ownership', violations);
  });

  test(
    'application APIs do not expose persistence or platform escape hatches',
    () {
      final violations = <String>[];
      final applicationPaths = sources.keys.where(
        (path) =>
            path.startsWith('lib/features/') && path.contains('/application/'),
      );
      final publicRuntimeEntrypoints = [
        'lib/features/task/runtime/task_controller.dart',
        'lib/features/project/runtime/project_application.dart',
      ];
      final escapeHatch = RegExp(
        r'^\s*(?:dynamic|[A-Za-z_]\w*(?:<[^>]+>)?)\s+get\s+'
        r'(?:repository|workspaceSandbox|toolService)\b',
        multiLine: true,
      );

      for (final path in [...applicationPaths, ...publicRuntimeEntrypoints]) {
        if (escapeHatch.hasMatch(_source(sources, path))) {
          violations.add(
            '$path: exposes a repository or platform service getter',
          );
        }
      }

      for (final path in [
        'lib/features/task/application/task_application/task_ports.dart',
        'lib/shared_kernel/tool_contracts.dart',
      ]) {
        final source = _source(sources, path);
        if (source.contains('dynamic get repository') ||
            source.contains('dynamic get workspaceSandbox')) {
          violations.add('$path: port exposes a dynamic infrastructure handle');
        }
      }

      _expectNoViolations('application boundary encapsulation', violations);
    },
  );

  test('task materialization is explicit rather than globally registered', () {
    const forbidden = [
      'registerProjectTaskDefinitionFactory',
      '_taskDefinitionFactory',
      'dynamic toTaskDefinition',
    ];
    final violations = <String>[];

    for (final path in [
      'lib/shared_kernel/project_task_models.dart',
      'lib/shared_kernel/task_plan_materializer.dart',
    ]) {
      final source = _source(sources, path);
      for (final symbol in forbidden) {
        if (source.contains(symbol)) {
          violations.add('$path: contains hidden materialization seam $symbol');
        }
      }
    }

    _expectNoViolations('explicit task materialization', violations);
  });

  test('model-server ownership belongs to the model feature', () {
    final violations = <String>[];
    for (final entry in _under(sources, 'lib/features/chat')) {
      if (entry.value.contains('LlamaServerManager') ||
          entry.value.contains('features/chat/runtime/model/')) {
        violations.add('${entry.key}: chat feature owns model-server details');
      }
    }

    final modelSources = _under(
      sources,
      'lib/features/model',
    ).map((entry) => entry.value).join('\n');
    if (!modelSources.contains('class LlamaServerManager')) {
      violations.add('features/model does not own LlamaServerManager');
    }

    _expectNoViolations('model feature ownership', violations);
  });

  test(
    'chat state transitions are reducer-only in the real runtime context',
    () {
      const path = 'lib/features/chat/runtime/chat_application_context.dart';
      final source = _source(sources, path);
      final violations = <String>[];

      if (RegExp(r'_state\s*=\s*_state\.copyWith').hasMatch(source)) {
        violations.add('$path: writes state directly with copyWith');
      }
      if (RegExp(r'^\s*set\s+[A-Za-z_]\w*', multiLine: true).hasMatch(source)) {
        violations.add('$path: exposes mutable state setters');
      }

      _expectNoViolations('chat reducer ownership', violations);
    },
  );

  test('lifecycle startup and listener cleanup are wired', () {
    final violations = <String>[];
    final main = _source(sources, 'lib/main.dart');
    final workspaceController = _source(
      sources,
      'lib/features/chat/runtime/chat_workspace_controller.dart',
    );

    if (!main.contains('.start()')) {
      violations.add('main.dart does not start AppDependencies lifecycle');
    }
    if (workspaceController.contains(
          'addListener(_handleServerAvailabilityChanged)',
        ) &&
        !workspaceController.contains(
          'removeListener(_handleServerAvailabilityChanged)',
        )) {
      violations.add(
        'chat workspace registers server listener without removing it',
      );
    }

    _expectNoViolations('lifecycle integration', violations);
  });

  test('architecture documentation names the active ports', () {
    final violations = <String>[];
    for (final path in ['README.md', 'docs/architecture.md']) {
      final source = File(path).readAsStringSync();
      for (final retiredPort in [
        'TaskApplicationPort',
        'ProjectApplicationPort',
      ]) {
        if (source.contains(retiredPort)) {
          violations.add('$path: references retired port $retiredPort');
        }
      }
    }

    _expectNoViolations('architecture documentation', violations);
  });
}
