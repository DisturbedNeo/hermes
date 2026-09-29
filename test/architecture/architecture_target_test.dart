import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Target architecture gates for the next Hermes migration step.
///
/// These checks intentionally describe architectural ownership rather than
/// implementation style. They may fail while the migration is in progress;
/// each failure should become green as the corresponding boundary is moved
/// into the implementation.

Future<Map<String, String>> _readProductionSources() async {
  final sources = <String, String>{};
  await for (final entity in Directory('lib').list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.mapper.dart') ||
        entity.path.endsWith('mappers.init.dart')) {
      continue;
    }
    final path = entity.path.replaceAll('\\', '/');
    sources[path] = await entity.readAsString();
  }
  return sources;
}

String _source(Map<String, String> sources, String path) {
  final source = sources[path];
  if (source == null) throw StateError('Expected production file $path');
  return source;
}

Iterable<String> _under(Map<String, String> sources, String directory) =>
    sources.entries
        .where(
          (entry) =>
              entry.key == directory || entry.key.startsWith('$directory/'),
        )
        .map((entry) => entry.value);

void _expectNoViolations(String label, Iterable<String> violations) {
  final values = violations.toList(growable: false);
  expect(values, isEmpty, reason: '$label:\n${values.join('\n')}');
}

void main() {
  late Map<String, String> sources;

  setUpAll(() async {
    sources = await _readProductionSources();
  });

  test(
    'production imports use package URIs so dependency checks see all edges',
    () {
      final relativeImport = RegExp(
        r'''^\s*(?:import|export)\s+['"]\.\.?/''',
        multiLine: true,
      );
      final violations = <String>[];

      for (final entry in sources.entries) {
        if (relativeImport.hasMatch(entry.value)) {
          violations.add('${entry.key}: contains a relative import or export');
        }
      }

      _expectNoViolations('production import URI hygiene', violations);
    },
  );

  test('feature domains own canonical aggregates and model contracts', () {
    final sharedKernel = _under(sources, 'lib/shared_kernel').join('\n');
    final violations = <String>[];

    const forbiddenSharedDeclarations = [
      'class ProjectAggregate',
      'typedef ProjectDocument',
      'class TaskAggregate',
      'typedef Task',
      'abstract interface class ModelProvider',
    ];
    for (final declaration in forbiddenSharedDeclarations) {
      if (sharedKernel.contains(declaration)) {
        violations.add('shared_kernel still owns $declaration');
      }
    }

    final projectDomain = _under(
      sources,
      'lib/features/project/domain',
    ).join('\n');
    if (!projectDomain.contains('class ProjectAggregate')) {
      violations.add(
        'features/project/domain does not define ProjectAggregate',
      );
    }

    final taskDomain = _under(sources, 'lib/features/task/domain').join('\n');
    if (!taskDomain.contains('class TaskAggregate')) {
      violations.add('features/task/domain does not define TaskAggregate');
    }

    final modelDomain = _under(sources, 'lib/features/model/domain').join('\n');
    if (!modelDomain.contains('class ModelProvider')) {
      violations.add('features/model/domain does not define ModelProvider');
    }

    _expectNoViolations('feature entity ownership', violations);
  });

  test('runtime engines are composed from collaborators rather than parts', () {
    const runtimeEngines = [
      'lib/features/chat/runtime/chat_runtime_engine.dart',
      'lib/features/task/runtime/task_runtime_engine.dart',
      'lib/features/project/runtime/project_runtime_engine.dart',
    ];
    final partDeclaration = RegExp(r'^\s*part\s+', multiLine: true);
    final violations = <String>[];

    for (final path in runtimeEngines) {
      if (partDeclaration.hasMatch(_source(sources, path))) {
        violations.add(
          '$path: runtime engine still uses Dart part composition',
        );
      }
    }

    _expectNoViolations('runtime collaborator composition', violations);
  });

  test(
    'application ports do not expose repositories or platform capabilities',
    () {
      const publicSeams = {
        'lib/features/task/application/task_application/task_ports.dart',
        'lib/features/project/runtime/project_runtime_engine.dart',
        'lib/shared_kernel/tool_contracts.dart',
      };
      final escapeHatch = RegExp(
        r'^\s*[A-Za-z_]\w*(?:<[^\n>]+>)?\s+get\s+'
        r'(?:persistence|repository|tools|materializer|workspaceSandbox|toolService)\b',
        multiLine: true,
      );
      final violations = <String>[];

      for (final path in publicSeams) {
        for (final match in escapeHatch.allMatches(_source(sources, path))) {
          violations.add(
            '$path:${match.start}: public infrastructure escape hatch',
          );
        }
      }

      _expectNoViolations('application boundary encapsulation', violations);
    },
  );

  test('application seams do not use dynamic dependency declarations', () {
    final dynamicDependency = RegExp(
      r'\brequired\s+dynamic\s+\w+|'
      r'\bfinal\s+dynamic\s+\w+|'
      r'\bas\s+dynamic\b',
    );
    final violations = <String>[];

    for (final entry in sources.entries) {
      final isFeatureBoundary =
          entry.key.startsWith('lib/features/') &&
          !entry.key.contains('/presentation/');
      final isSharedKernel = entry.key.startsWith('lib/shared_kernel/');
      if (!isFeatureBoundary && !isSharedKernel) {
        continue;
      }
      for (final match in dynamicDependency.allMatches(entry.value)) {
        violations.add('${entry.key}:${match.start}: dynamic dependency seam');
      }
    }

    _expectNoViolations('typed dependency seams', violations);
  });

  test('runtime composition requires explicit persistence collaborators', () {
    const runtimeContexts = {
      'lib/features/task/runtime/task_context.dart': ['InMemoryTaskRepository'],
      'lib/features/project/runtime/project_context.dart': [
        'InMemoryProjectRepository',
        'InMemoryProjectAggregateRepository',
      ],
    };
    final violations = <String>[];

    for (final entry in runtimeContexts.entries) {
      final source = _source(sources, entry.key);
      for (final fallback in entry.value) {
        if (source.contains(fallback)) {
          violations.add('${entry.key}: silently creates $fallback');
        }
      }
    }

    _expectNoViolations('explicit runtime persistence composition', violations);
  });

  test('model server lifetime is owned by application lifecycle', () {
    final appDependencies = _source(sources, 'lib/app_dependencies.dart');
    final chatWorkspace = _source(
      sources,
      'lib/features/chat/runtime/chat_workspace_controller.dart',
    );
    final violations = <String>[];
    final modelRegistration = RegExp(
      r"lifecycleCoordinator\.register\([\s\S]{0,240}"
      r"name: 'model'[\s\S]{0,240}dispose: modelManager\.dispose",
    );

    if (!modelRegistration.hasMatch(appDependencies)) {
      violations.add(
        'app_dependencies.dart does not register modelManager with lifecycle',
      );
    }
    if (chatWorkspace.contains('await serverManager.dispose()')) {
      violations.add('chat workspace disposes the model server directly');
    }

    _expectNoViolations('model lifecycle ownership', violations);
  });
}
