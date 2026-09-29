import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Completion gates for the architecture migration.
///
/// The older architecture tests verify individual seams. These tests verify
/// that the transitional architecture itself no longer exists. They are
/// intentionally repository-wide: a migration is not complete while one
/// production import, compatibility export, or legacy module remains.

class _SourceFile {
  const _SourceFile(this.path, this.source, this.imports);

  final String path;
  final String source;
  final Set<String> imports;
}

const _allowedTopLevelDirectories = {
  'app',
  'features',
  'platform',
  'shared_kernel',
};
const _allowedRootFiles = {'app_dependencies.dart', 'main.dart'};
const _featureLayers = {
  'application',
  'domain',
  'infrastructure',
  'presentation',
  'runtime',
};
const _featureRootContractFiles = {
  'project_aggregate_repository_port.dart',
  'project_application_port.dart',
  'project_repository_port.dart',
  'project_runtime_contracts.dart',
  'task_runtime_contracts.dart',
};

Future<List<_SourceFile>> _readProductionSources() async {
  final result = <_SourceFile>[];
  await for (final entity in Directory('lib').list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = await entity.readAsString();
    final imports = <String>{};
    for (final match in RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    ).allMatches(source)) {
      final uri = match.group(1);
      if (uri != null && uri.startsWith('package:hermes/')) {
        imports.add(uri);
      }
    }
    result.add(_SourceFile(entity.path.replaceAll('\\', '/'), source, imports));
  }
  return result;
}

String _relativePath(String path) =>
    path.startsWith('lib/') ? path.substring('lib/'.length) : path;

List<String> _segments(String path) => _relativePath(path).split('/');

String? _featureOf(String path) {
  final segments = _segments(path);
  return segments.length >= 2 && segments.first == 'features'
      ? segments[1]
      : null;
}

String? _layerOf(String path) {
  final segments = _segments(path);
  if (segments.length >= 3 &&
      segments.first == 'features' &&
      _featureLayers.contains(segments[2])) {
    return segments[2];
  }
  if (segments.first == 'shared_kernel') return 'shared_kernel';
  if (segments.first == 'platform') return 'platform';
  if (segments.first == 'app' || _allowedRootFiles.contains(segments.first)) {
    return 'composition';
  }
  if (segments.length == 3 &&
      segments.first == 'features' &&
      _featureRootContractFiles.contains(segments.last)) {
    return 'feature_contract';
  }
  return null;
}

String? _targetPath(String uri) {
  if (!uri.startsWith('package:hermes/')) return null;
  return uri.substring('package:hermes/'.length);
}

bool _isCompositionPath(String path) => _layerOf(path) == 'composition';

bool _isPortFile(String path) {
  final fileName = _segments(path).last;
  return fileName.endsWith('_port.dart') || fileName.endsWith('_ports.dart');
}

void _expectNoViolations(String label, Iterable<String> violations) {
  final values = violations.toList(growable: false);
  expect(values, isEmpty, reason: '$label:\n${values.join('\n')}');
}

void main() {
  late List<_SourceFile> files;
  late Map<String, _SourceFile> filesByRelativePath;

  setUpAll(() async {
    files = await _readProductionSources();
    filesByRelativePath = {
      for (final file in files) _relativePath(file.path): file,
    };
  });

  test(
    'the architecture migration has no legacy module or compatibility surface',
    () {
      final violations = <String>[];

      for (final file in files) {
        final relative = _relativePath(file.path);
        final segments = relative.split('/');

        if (segments.first == 'core' || segments.first == 'ui') {
          violations.add('$relative: legacy top-level module remains');
        }
        if (file.imports.any(
          (uri) =>
              uri.startsWith('package:hermes/core/') ||
              uri.startsWith('package:hermes/ui/'),
        )) {
          violations.add('$relative: imports a legacy package path');
        }
        if (file.source.contains('package:hermes/ui/')) {
          violations.add('$relative: references the removed global UI package');
        }
      }

      _expectNoViolations('legacy module surface', violations);
    },
  );

  test('every production file belongs to the target module layout', () {
    final violations = <String>[];

    for (final file in files) {
      final relative = _relativePath(file.path);
      final segments = relative.split('/');
      if (_allowedRootFiles.contains(relative)) continue;
      if (segments.isEmpty ||
          !_allowedTopLevelDirectories.contains(segments.first)) {
        violations.add('$relative: outside the target top-level module layout');
        continue;
      }

      if (segments.first == 'features') {
        if (segments.length < 3) {
          violations.add('$relative: feature file is not under a layer');
        } else if (segments.length == 3 &&
            !_featureRootContractFiles.contains(segments.last)) {
          violations.add('$relative: unclassified feature-root file remains');
        } else if (segments.length >= 3 &&
            !_featureLayers.contains(segments[2]) &&
            !_featureRootContractFiles.contains(segments.last)) {
          violations.add('$relative: uses an unrecognised feature layer');
        }
      }
    }

    _expectNoViolations('target module layout', violations);
  });

  test('the package import graph obeys the layer direction', () {
    final violations = <String>[];

    for (final file in files) {
      final sourcePath = _relativePath(file.path);
      final sourceLayer = _layerOf(sourcePath);
      final sourceFeature = _featureOf(sourcePath);
      if (sourceLayer == null) {
        violations.add('$sourcePath: cannot classify source layer');
        continue;
      }

      for (final uri in file.imports) {
        final targetPath = _targetPath(uri);
        if (targetPath == null) continue;
        final targetLayer = _layerOf(targetPath);
        final targetFeature = _featureOf(targetPath);
        if (targetLayer == null) {
          violations.add('$sourcePath: imports unclassified target $uri');
          continue;
        }
        if (sourceLayer == 'composition') continue;

        final sameFeature =
            sourceFeature != null && sourceFeature == targetFeature;
        final allowed = switch (sourceLayer) {
          'shared_kernel' => targetLayer == 'shared_kernel',
          'platform' =>
            targetLayer == 'shared_kernel' || targetLayer == 'platform',
          'domain' =>
            targetLayer == 'shared_kernel' ||
                (sameFeature && targetLayer == 'domain'),
          'feature_contract' =>
            targetLayer == 'shared_kernel' ||
                (sameFeature &&
                    (targetLayer == 'domain' ||
                        targetLayer == 'feature_contract')),
          'presentation' =>
            targetLayer == 'shared_kernel' ||
                (sameFeature &&
                    {
                      'presentation',
                      'application',
                      'domain',
                    }.contains(targetLayer)),
          'application' =>
            targetLayer == 'shared_kernel' ||
                (sameFeature &&
                    {
                      'application',
                      'domain',
                      'runtime',
                      'feature_contract',
                    }.contains(targetLayer)),
          'runtime' =>
            targetLayer == 'shared_kernel' ||
                (sameFeature &&
                    {
                      'application',
                      'domain',
                      'runtime',
                      'feature_contract',
                    }.contains(targetLayer)) ||
                (targetLayer == 'application' && _isPortFile(targetPath)),
          'infrastructure' =>
            targetLayer == 'shared_kernel' ||
                (sameFeature &&
                    {
                      'application',
                      'domain',
                      'infrastructure',
                      'feature_contract',
                    }.contains(targetLayer)),
          _ => false,
        };

        if (!allowed) {
          violations.add('$sourcePath -> $uri');
        }
      }
    }

    _expectNoViolations('layer dependency violations', violations);
  });

  test(
    'application boundaries contain real narrow ports, not transitional aliases',
    () {
      final violations = <String>[];
      final forbiddenPortSymbols = {
        'TaskApplicationPort',
        'ProjectApplicationPort',
        'TaskRepositoryPort',
        'ProjectRepositoryPort',
        'ProjectAggregateRepositoryPort',
      };
      final entrypoints = {
        'features/chat/application/chat_controller.dart': 'ChatController',
        'features/chat/application/chat_workspace_controller.dart':
            'ChatWorkspaceController',
        'features/task/application/task_application/task_controller.dart':
            'TaskController',
        'features/project/application/project_application/project_application.dart':
            'ProjectApplication',
      };

      for (final file in files.where((file) {
        final path = _relativePath(file.path);
        return path.startsWith('features/') &&
            path.contains('/application/') &&
            _isPortFile(path);
      })) {
        if (RegExp(r'^\s*export\s+', multiLine: true).hasMatch(file.source)) {
          violations.add(
            '${_relativePath(file.path)}: compatibility export remains',
          );
        }
        for (final symbol in forbiddenPortSymbols) {
          if (file.source.contains(symbol)) {
            violations.add('${_relativePath(file.path)}: exposes $symbol');
          }
        }
      }

      for (final entry in entrypoints.entries) {
        final file = filesByRelativePath[entry.key];
        if (file == null) {
          violations.add(
            '${entry.key}: public application entrypoint is missing',
          );
          continue;
        }
        if (RegExp(r'^\s*typedef\s+', multiLine: true).hasMatch(file.source)) {
          violations.add(
            '${entry.key}: public entrypoint is only a typedef alias',
          );
        }
        if (!RegExp(
          r'\bclass\s+' + RegExp.escape(entry.value) + r'\b',
        ).hasMatch(file.source)) {
          violations.add(
            '${entry.key}: missing concrete ${entry.value} facade',
          );
        }
      }

      _expectNoViolations('application boundary violations', violations);
    },
  );

  test('concrete cross-feature wiring exists only in the composition root', () {
    final violations = <String>[];

    for (final file in files) {
      final sourcePath = _relativePath(file.path);
      if (_isCompositionPath(sourcePath)) continue;
      final sourceFeature = _featureOf(sourcePath);
      if (sourceFeature == null) continue;

      for (final uri in file.imports) {
        final targetPath = _targetPath(uri);
        final targetFeature = targetPath == null
            ? null
            : _featureOf(targetPath);
        if (targetFeature == null || targetFeature == sourceFeature) continue;

        final targetLayer = _layerOf(targetPath!);
        final isNarrowPort =
            targetLayer == 'application' && _isPortFile(targetPath);
        if (!isNarrowPort) {
          violations.add(
            '$sourcePath imports cross-feature implementation $uri',
          );
        }
      }
    }

    _expectNoViolations('cross-feature implementation wiring', violations);
  });
}
