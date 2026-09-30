import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The single authoritative architecture gate for the production package.
///
/// This suite deliberately scans the repository rather than a hand-picked set
/// of files. A missing source root, unclassified file, unresolved internal
/// directive, stale path, dependency cycle, or forbidden edge is a failure.
/// Keep target-specific checks below tied to real production paths; do not
/// replace them with compatibility paths or source fragments that can pass
/// when the implementation has moved.

const _topLevelDirectories = {'app', 'features', 'platform', 'shared_kernel'};
const _rootFiles = {'app_dependencies.dart', 'main.dart'};
const _featureLayers = {
  'application',
  'domain',
  'infrastructure',
  'presentation',
  'runtime',
};
const _featureContractPaths = {
  'features/project/project_aggregate_repository_port.dart',
  'features/project/project_repository_port.dart',
};
const _requiredDirectories = [
  'lib/app',
  'lib/features',
  'lib/platform',
  'lib/shared_kernel',
];

class _Directive {
  const _Directive({required this.kind, required this.uri, required this.line});

  final String kind;
  final String uri;
  final int line;
}

class _SourceFile {
  const _SourceFile({
    required this.path,
    required this.source,
    required this.imports,
    required this.parts,
    required this.partOfs,
  });

  final String path;
  final String source;
  final List<_Directive> imports;
  final List<_Directive> parts;
  final List<_Directive> partOfs;

  _Location? get location => _locate(path);
}

class _Location {
  const _Location({required this.layer, this.feature});

  final String layer;
  final String? feature;
}

class _ArchitectureSnapshot {
  const _ArchitectureSnapshot(this.files);

  final List<_SourceFile> files;

  Map<String, _SourceFile> get byPath => {
    for (final file in files) file.path: file,
  };
}

List<_Directive> _parseDirectives(String source, String kind, RegExp pattern) {
  final directives = <_Directive>[];
  for (final match in pattern.allMatches(source)) {
    final body = match.group(1) ?? '';
    final uris = RegExp(r'''['"]([^'"]+)['"]''')
        .allMatches(body)
        .map((uriMatch) => uriMatch.group(1)!)
        .toList(growable: false);
    final line = _lineNumber(source, match.start);
    if (uris.isEmpty) {
      directives.add(_Directive(kind: kind, uri: '', line: line));
      continue;
    }
    for (final uri in uris) {
      directives.add(_Directive(kind: kind, uri: uri, line: line));
    }
  }
  return directives;
}

int _lineNumber(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

String _normalisePath(String path) => path.replaceAll('\\', '/');

String _resolveRelativePath(String sourcePath, String uri) {
  if (uri.isEmpty || uri.startsWith('/')) return '';
  final segments = _normalisePath(sourcePath).split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isEmpty) return '';
      segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

String? _internalTarget(String sourcePath, String uri) {
  if (uri.startsWith('package:hermes/')) {
    return 'lib/${uri.substring('package:hermes/'.length)}';
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  return _resolveRelativePath(sourcePath, uri);
}

Future<_ArchitectureSnapshot> _readProductionSources() async {
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    throw StateError('Architecture scan requires a lib/ directory.');
  }

  final files = <_SourceFile>[];
  await for (final entity in lib.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = _normalisePath(entity.path);
    if (!path.startsWith('lib/')) {
      throw StateError('Production file escaped lib/: $path');
    }
    final source = await entity.readAsString();
    files.add(
      _SourceFile(
        path: path,
        source: source,
        imports: _parseDirectives(
          source,
          'import/export',
          RegExp(r'^\s*(?:import|export)\s+([\s\S]*?);', multiLine: true),
        ),
        parts: _parseDirectives(
          source,
          'part',
          RegExp(r'^\s*part\s+(?!of\b)([\s\S]*?);', multiLine: true),
        ),
        partOfs: _parseDirectives(
          source,
          'part of',
          RegExp(r'^\s*part\s+of\s+([\s\S]*?);', multiLine: true),
        ),
      ),
    );
  }

  if (files.isEmpty) {
    throw StateError('Architecture scan found no Dart production sources.');
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return _ArchitectureSnapshot(files);
}

_Location? _locate(String path) {
  if (!path.startsWith('lib/')) return null;
  final relative = path.substring('lib/'.length);
  if (_rootFiles.contains(relative)) {
    return const _Location(layer: 'composition');
  }

  final segments = relative.split('/');
  if (segments.isEmpty || !_topLevelDirectories.contains(segments.first)) {
    return null;
  }
  if (segments.first == 'app') {
    return const _Location(layer: 'composition');
  }
  if (segments.first == 'shared_kernel') {
    return const _Location(layer: 'shared_kernel');
  }
  if (segments.first == 'platform') {
    return const _Location(layer: 'platform');
  }
  if (segments.first != 'features' || segments.length < 3) return null;
  final feature = segments[1];
  final layer = segments[2];
  if (_featureLayers.contains(layer)) {
    return _Location(layer: layer, feature: feature);
  }
  if (_featureContractPaths.contains(relative)) {
    return _Location(layer: 'feature_contract', feature: feature);
  }
  return null;
}

bool _isPortPath(String path) {
  final name = path.split('/').last;
  return name.endsWith('_port.dart') || name.endsWith('_ports.dart');
}

bool _isCrossFeatureContract(
  _Location source,
  _Location target,
  String targetFilePath,
) {
  if (source.feature == null || target.feature == null) return false;
  if (source.feature == target.feature) return false;
  return target.layer == 'domain' ||
      target.layer == 'feature_contract' ||
      (target.layer == 'application' && _isPortPath(targetFilePath));
}

bool _allowsEdge(_SourceFile sourceFile, _SourceFile targetFile) {
  final source = sourceFile.location;
  final target = targetFile.location;
  if (source == null || target == null) return false;
  if (source.layer == 'composition') return true;
  if (target.layer == 'composition') return false;

  if (_isCrossFeatureContract(source, target, targetFile.path)) return true;
  if (source.feature != null &&
      target.feature != null &&
      source.feature != target.feature) {
    return false;
  }

  if (source.layer == 'shared_kernel') {
    return target.layer == 'shared_kernel';
  }
  if (source.layer == 'platform') {
    return target.layer == 'platform' || target.layer == 'shared_kernel';
  }
  if (source.layer == 'feature_contract') {
    return target.layer == 'feature_contract' ||
        target.layer == 'domain' ||
        target.layer == 'shared_kernel';
  }
  if (source.layer == 'domain') {
    return target.layer == 'domain' || target.layer == 'shared_kernel';
  }
  if (source.layer == 'application') {
    return {
      'application',
      'domain',
      'runtime',
      'feature_contract',
      'shared_kernel',
    }.contains(target.layer);
  }
  if (source.layer == 'runtime') {
    return {
      'application',
      'domain',
      'runtime',
      'feature_contract',
      'shared_kernel',
    }.contains(target.layer);
  }
  if (source.layer == 'infrastructure') {
    return {
      'application',
      'domain',
      'infrastructure',
      'feature_contract',
      'shared_kernel',
    }.contains(target.layer);
  }
  if (source.layer == 'presentation') {
    return {
      'application',
      'domain',
      'presentation',
      'shared_kernel',
    }.contains(target.layer);
  }
  return false;
}

Map<String, Set<String>> _importGraph(_ArchitectureSnapshot snapshot) {
  final graph = <String, Set<String>>{
    for (final file in snapshot.files) file.path: <String>{},
  };
  final files = snapshot.byPath;
  for (final file in snapshot.files) {
    for (final directive in file.imports) {
      final target = _internalTarget(file.path, directive.uri);
      if (target != null && files.containsKey(target)) {
        graph[file.path]!.add(target);
      }
    }
  }
  return graph;
}

List<String> _cycles(Map<String, Set<String>> graph) {
  final active = <String>{};
  final visited = <String>{};
  final stack = <String>[];
  final found = <String>{};

  void visit(String node) {
    if (active.contains(node)) {
      final start = stack.indexOf(node);
      if (start >= 0) {
        final cycle = [...stack.sublist(start), node];
        final canonical = cycle.sublist(0, cycle.length - 1)..sort();
        found.add('${canonical.join(' -> ')} -> ${canonical.first}');
      }
      return;
    }
    if (!visited.add(node)) return;
    active.add(node);
    stack.add(node);
    for (final target in graph[node] ?? const <String>{}) {
      visit(target);
    }
    stack.removeLast();
    active.remove(node);
  }

  for (final node in graph.keys) {
    visit(node);
  }
  return found.toList()..sort();
}

String _lineRef(String path, int line) => '$path:$line';

_SourceFile _requiredSource(_ArchitectureSnapshot snapshot, String path) {
  final source = snapshot.byPath[path];
  if (source == null) {
    throw StateError('Required production path is missing: $path');
  }
  return source;
}

void _expectNoViolations(String label, Iterable<String> violations) {
  final values = violations.toList(growable: false);
  expect(values, isEmpty, reason: '$label:\n${values.join('\n')}');
}

bool _hasClass(String source, String name) =>
    RegExp(r'\bclass\s+' + RegExp.escape(name) + r'\b').hasMatch(source);

bool _hasAbstractClass(String source, String name) => RegExp(
  r'\babstract\s+(?:interface\s+)?class\s+' + RegExp.escape(name) + r'\b',
).hasMatch(source);

void main() {
  late _ArchitectureSnapshot snapshot;

  setUpAll(() async {
    snapshot = await _readProductionSources();
  });

  group('authoritative production architecture', () {
    test('inventory and every internal directive resolve to real files', () {
      final violations = <String>[];
      final files = snapshot.byPath;

      for (final directory in _requiredDirectories) {
        if (!Directory(directory).existsSync()) {
          violations.add(
            '$directory: required architecture directory is missing',
          );
        }
      }

      final duplicatePaths = snapshot.files
          .map((file) => file.path)
          .where(
            (path) =>
                snapshot.files.where((file) => file.path == path).length > 1,
          );
      for (final path in duplicatePaths.toSet()) {
        violations.add('$path: source path was indexed more than once');
      }

      for (final file in snapshot.files) {
        if (file.location == null) {
          violations.add(
            '${file.path}: production file is outside the classified module layout',
          );
        }
        for (final directive in [
          ...file.imports,
          ...file.parts,
          ...file.partOfs,
        ]) {
          if (directive.uri.isEmpty) {
            violations.add(
              '${_lineRef(file.path, directive.line)}: ${directive.kind} has no URI',
            );
            continue;
          }
          final target = _internalTarget(file.path, directive.uri);
          if (target != null && !files.containsKey(target)) {
            violations.add(
              '${_lineRef(file.path, directive.line)}: ${directive.kind} targets missing $target',
            );
          }
        }

        for (final directive in file.parts) {
          final targetPath = _internalTarget(file.path, directive.uri);
          final target = targetPath == null ? null : files[targetPath];
          if (target == null) continue;
          final declaresParent = target.partOfs.any(
            (partOf) => _internalTarget(target.path, partOf.uri) == file.path,
          );
          if (!declaresParent) {
            violations.add(
              '${_lineRef(file.path, directive.line)}: part target $targetPath '
              'does not declare part of ${file.path}',
            );
          }
        }

        for (final directive in file.partOfs) {
          final parentPath = _internalTarget(file.path, directive.uri);
          final parent = parentPath == null ? null : files[parentPath];
          if (parent == null) continue;
          final declaresPart = parent.parts.any(
            (part) => _internalTarget(parent.path, part.uri) == file.path,
          );
          if (!declaresPart) {
            violations.add(
              '${_lineRef(file.path, directive.line)}: part-of parent $parentPath '
              'does not declare ${file.path} as a part',
            );
          }
        }
      }

      _expectNoViolations(
        'production inventory/directive resolution',
        violations,
      );
    });

    test('resolved package and relative imports obey the layer graph', () {
      final violations = <String>[];
      final files = snapshot.byPath;

      for (final file in snapshot.files) {
        final source = file.location;
        if (source == null) {
          violations.add(
            '${file.path}: cannot classify source layer for dependency checking',
          );
          continue;
        }
        for (final directive in file.imports) {
          final targetPath = _internalTarget(file.path, directive.uri);
          if (targetPath == null) continue;
          final target = files[targetPath];
          if (target == null) {
            violations.add(
              '${_lineRef(file.path, directive.line)}: dependency target $targetPath is not indexed',
            );
            continue;
          }
          if (!_allowsEdge(file, target)) {
            violations.add(
              '${_lineRef(file.path, directive.line)}: ${source.layer} -> '
              '${target.location?.layer} ${target.path}',
            );
          }
        }
      }

      _expectNoViolations('layer dependency graph', violations);
    });

    test('the internal import graph is acyclic', () {
      final violations = _cycles(_importGraph(snapshot));
      _expectNoViolations('internal import cycles', violations);
    });

    test('runtime composition does not hide implementation in Dart parts', () {
      final violations = <String>[];
      for (final file in snapshot.files) {
        if (file.location?.layer != 'runtime') continue;
        if (file.parts.isNotEmpty || file.partOfs.isNotEmpty) {
          violations.add(
            '${file.path}: runtime collaborator is still composed with part/part of',
          );
        }
      }
      _expectNoViolations('runtime collaborator composition', violations);
    });

    test('the real application boundaries and runtime entrypoints exist', () {
      final requiredClasses = {
        'lib/features/chat/application/chat_controller.dart': 'ChatController',
        'lib/features/chat/application/chat_workspace_controller.dart':
            'ChatWorkspaceController',
        'lib/features/task/application/task_application/task_controller.dart':
            'TaskController',
        'lib/features/project/application/project_application/project_application.dart':
            'ProjectApplication',
        'lib/features/chat/runtime/chat_runtime_engine.dart':
            'ChatRuntimeController',
        'lib/features/task/runtime/task_runtime_engine.dart':
            'TaskRuntimeController',
        'lib/features/project/runtime/project_runtime_engine.dart':
            'ProjectRuntimeApplication',
      };
      final violations = <String>[];
      for (final entry in requiredClasses.entries) {
        final source = _requiredSource(snapshot, entry.key);
        if (!_hasClass(source.source, entry.value)) {
          violations.add('${entry.key}: missing ${entry.value}');
        }
      }
      _expectNoViolations('application/runtime entrypoints', violations);
    });

    test('application ports expose the declared narrow contracts', () {
      final taskPorts = _requiredSource(
        snapshot,
        'lib/features/task/application/task_application/task_ports.dart',
      ).source;
      final projectPorts = _requiredSource(
        snapshot,
        'lib/features/project/application/project_application/project_ports.dart',
      ).source;
      final violations = <String>[];

      for (final port in [
        'TaskQueryPort',
        'TaskPlanningPort',
        'TaskExecutionPort',
        'TaskRecoveryPort',
      ]) {
        if (!_hasAbstractClass(taskPorts, port)) {
          violations.add('task_ports.dart: missing $port');
        }
      }
      for (final port in [
        'ProjectQueryPort',
        'ProjectCommandPort',
        'ProjectExecutionPort',
      ]) {
        if (!_hasAbstractClass(projectPorts, port)) {
          violations.add('project_ports.dart: missing $port');
        }
      }
      _expectNoViolations('application port contracts', violations);
    });

    test(
      'application/runtime boundary declarations do not use dynamic seams',
      () {
        final violations = <String>[];
        final dynamicDependency = RegExp(
          r'\brequired\s+dynamic\b|'
          r'\b(?:final|var)\s+dynamic\b|'
          r'\bdynamic\s+get\b|'
          r'\b(?:Future|Stream)\s*<\s*dynamic\b|'
          r'\btypedef\s+[^;=]+dynamic\b',
        );
        for (final file in snapshot.files) {
          final location = file.location;
          if (location == null ||
              (location.layer != 'application' &&
                  location.layer != 'runtime')) {
            continue;
          }
          for (final match in dynamicDependency.allMatches(file.source)) {
            violations.add(
              '${_lineRef(file.path, _lineNumber(file.source, match.start))}: dynamic dependency seam',
            );
          }
        }
        _expectNoViolations('typed application/runtime seams', violations);
      },
    );

    test('chat state transitions are owned by the real reducer boundary', () {
      final context = _requiredSource(
        snapshot,
        'lib/features/chat/runtime/chat_runtime_collaborators.dart',
      );
      final reducer = _requiredSource(
        snapshot,
        'lib/features/chat/domain/chat_state.dart',
      );
      final violations = <String>[];

      if (!reducer.source.contains('class ChatStateReducer')) {
        violations.add('chat_state.dart: missing ChatStateReducer');
      }
      if (!RegExp(r'\bChatState\s+reduce\s*\(').hasMatch(reducer.source)) {
        violations.add(
          'chat_state.dart: reducer does not expose reduce(state, event)',
        );
      }
      if (RegExp(r'\b_state\s*\.\s*copyWith\s*\(').hasMatch(context.source)) {
        violations.add(
          'chat_runtime_collaborators.dart: constructs state with copyWith outside the reducer',
        );
      }
      if (RegExp(r'\bvoid\s+set[A-Z]\w*\s*\(').hasMatch(context.source)) {
        violations.add(
          'chat_runtime_collaborators.dart: exposes state mutation setters',
        );
      }
      _expectNoViolations('chat reducer ownership', violations);
    });

    test('runtime contexts require explicit collaborators', () {
      final taskContext = _requiredSource(
        snapshot,
        'lib/features/task/runtime/task_runtime_collaborators.dart',
      );
      final projectContext = _requiredSource(
        snapshot,
        'lib/features/project/runtime/project_runtime_collaborators.dart',
      );
      final violations = <String>[];
      for (final entry in {
        taskContext.path: ['TaskPlanningService()', 'TaskPersistenceStore('],
        projectContext.path: [
          'ProjectModelCalls(',
          'ProjectAggregateHydrator(',
          'ProjectCommandService(',
        ],
      }.entries) {
        for (final fallback in entry.value) {
          if (snapshot.byPath[entry.key]!.source.contains(fallback)) {
            violations.add('${entry.key}: silently constructs $fallback');
          }
        }
      }
      _expectNoViolations(
        'explicit runtime collaborator composition',
        violations,
      );
    });

    test('model lifecycle is owned by the composition root', () {
      final appDependencies = _requiredSource(
        snapshot,
        'lib/app_dependencies.dart',
      ).source;
      final chatWorkspace = _requiredSource(
        snapshot,
        'lib/features/chat/runtime/chat_workspace_controller.dart',
      ).source;
      final violations = <String>[];
      if (!RegExp(
        r"lifecycleCoordinator\.register\([\s\S]{0,300}"
        r"name:\s*'model'[\s\S]{0,300}dispose:\s*modelManager\.dispose",
      ).hasMatch(appDependencies)) {
        violations.add(
          'app_dependencies.dart: model manager is not lifecycle-owned',
        );
      }
      if (chatWorkspace.contains('await serverManager.dispose()')) {
        violations.add(
          'chat_workspace_controller.dart: disposes the model server directly',
        );
      }
      _expectNoViolations('model lifecycle ownership', violations);
    });

    test('persistence adapters implement real application ports', () {
      final expectedImplementations = {
        'lib/platform/workspace_service.dart': 'WorkspacePresentationPort',
        'lib/shared_kernel/workspace_persistence_coordinator.dart':
            'PersistencePort',
        'lib/features/model/infrastructure/chat_client.dart': 'ModelProvider',
        'lib/features/task/infrastructure/task_repository.dart':
            'TaskPersistencePort',
        'lib/features/project/infrastructure/project_repository.dart':
            'ProjectRepositoryPort',
        'lib/features/project/infrastructure/project_aggregate_repository.dart':
            'ProjectAggregateRepositoryPort',
        'lib/features/chat/infrastructure/chat_library_repository.dart':
            'ChatLibraryPort',
        'lib/features/chat/infrastructure/system_prompt_library_repository.dart':
            'PromptLibraryPort',
        'lib/features/settings/infrastructure/preferences_service.dart':
            'PreferencesPort',
      };
      final violations = <String>[];
      for (final entry in expectedImplementations.entries) {
        final source = _requiredSource(snapshot, entry.key).source;
        if (!RegExp(
          r'\bimplements\b[\s\S]{0,180}\b' + RegExp.escape(entry.value) + r'\b',
        ).hasMatch(source)) {
          violations.add('${entry.key}: does not implement ${entry.value}');
        }
      }
      _expectNoViolations('typed adapter implementations', violations);
    });
  });
}
