import 'dart:convert';
import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

part 'workspace_discovery_profile.mapper.dart';

/// A deterministic, bounded view of a workspace supplied to planning calls.
@MappableClass(ignoreNull: true)
class WorkspaceDiscoveryProfile with WorkspaceDiscoveryProfileMappable {
  final String workspaceName;
  final List<String> treePaths;
  final List<WorkspaceFileExcerpt> highSignalFiles;
  final String? packageName;
  final Map<String, String> scripts;
  final List<String> dependencies;
  final List<String> languages;
  final List<String> frameworks;
  final bool treeTruncated;
  final bool contentTruncated;
  final int omittedPathCount;

  const WorkspaceDiscoveryProfile({
    required this.workspaceName,
    this.treePaths = const [],
    this.highSignalFiles = const [],
    this.packageName,
    this.scripts = const {},
    this.dependencies = const [],
    this.languages = const [],
    this.frameworks = const [],
    this.treeTruncated = false,
    this.contentTruncated = false,
    this.omittedPathCount = 0,
  });

  List<String> get rootEntries => treePaths
      .map(
        (item) =>
            item.endsWith('/') ? item.substring(0, item.length - 1) : item,
      )
      .where((item) => path.split(item).length == 1)
      .toList();
}

@MappableClass()
class WorkspaceFileExcerpt with WorkspaceFileExcerptMappable {
  final String path;
  final String content;
  final bool truncated;

  const WorkspaceFileExcerpt({
    required this.path,
    required this.content,
    this.truncated = false,
  });
}

/// Collects workspace facts without invoking a model or workspace tools.
class WorkspaceDiscoveryProfileService {
  const WorkspaceDiscoveryProfileService();

  static const int maxDepth = 4;
  static const int maxPaths = 400;
  static const int maxFiles = 12;
  static const int maxFileBytes = 12 * 1024;
  static const int maxTotalBytes = 64 * 1024;

  static const Set<String> _ignoredDirectories = {
    '.dart_tool',
    '.git',
    '.gradle',
    '.idea',
    '.next',
    '.pub-cache',
    '.terraform',
    '.venv',
    '.vscode',
    'build',
    'coverage',
    'dist',
    'generated',
    'node_modules',
    'Pods',
    'target',
    'vendor',
  };

  static const Set<String> _highSignalNames = {
    'AGENTS.md',
    'CMakeLists.txt',
    'CONTRIBUTING.md',
    'Cargo.toml',
    'Gemfile',
    'Makefile',
    'README',
    'README.md',
    'README.rst',
    'analysis_options.yaml',
    'build.gradle',
    'build.gradle.kts',
    'go.mod',
    'package.json',
    'pom.xml',
    'pubspec.yaml',
    'pyproject.toml',
    'requirements.txt',
    'settings.gradle',
    'settings.gradle.kts',
    'tsconfig.json',
  };

  static const Set<String> _entrypointNames = {
    'app.dart',
    'app.js',
    'app.py',
    'app.ts',
    'index.js',
    'index.ts',
    'main.dart',
    'main.go',
    'main.kt',
    'main.py',
    'main.rs',
  };

  Future<WorkspaceDiscoveryProfile> collect({
    required WorkspaceAttachment workspace,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final root = Directory(path.normalize(workspace.rootPath));
    if (!await root.exists()) {
      return WorkspaceDiscoveryProfile(workspaceName: workspace.displayName);
    }

    final treePaths = <String>[];
    final candidates = <String>[];
    var omittedPathCount = 0;
    var treeTruncated = false;

    Future<void> walk(Directory directory, int depth) async {
      if (treeTruncated || depth > maxDepth) return;
      List<FileSystemEntity> children;
      try {
        children = await directory.list(followLinks: false).toList();
      } on FileSystemException {
        omittedPathCount++;
        return;
      }
      children.sort((a, b) => a.path.compareTo(b.path));
      for (final entity in children) {
        cancellationToken?.throwIfCancelled();
        if (treePaths.length >= maxPaths) {
          treeTruncated = true;
          omittedPathCount++;
          return;
        }
        final relative = path.relative(entity.path, from: root.path);
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link) {
          omittedPathCount++;
          continue;
        }
        if (type == FileSystemEntityType.directory) {
          if (_ignoredDirectories.contains(path.basename(entity.path))) {
            omittedPathCount++;
            continue;
          }
          treePaths.add('$relative/');
          if (depth < maxDepth) {
            await walk(Directory(entity.path), depth + 1);
          }
          continue;
        }
        if (type != FileSystemEntityType.file) continue;
        treePaths.add(relative);
        if (_isHighSignal(relative)) candidates.add(relative);
      }
    }

    await walk(root, 1);
    candidates.sort((a, b) {
      final score = _signalScore(a).compareTo(_signalScore(b));
      return score != 0 ? score : a.compareTo(b);
    });

    final excerpts = <WorkspaceFileExcerpt>[];
    var remainingBytes = maxTotalBytes;
    var contentTruncated = false;
    for (final relative in candidates.take(maxFiles)) {
      cancellationToken?.throwIfCancelled();
      if (remainingBytes <= 0) {
        contentTruncated = true;
        break;
      }
      final excerpt = await _readExcerpt(
        rootPath: root.path,
        relativePath: relative,
        limit: remainingBytes < maxFileBytes ? remainingBytes : maxFileBytes,
      );
      if (excerpt == null) {
        omittedPathCount++;
        continue;
      }
      excerpts.add(excerpt);
      remainingBytes -= utf8.encode(excerpt.content).length;
      contentTruncated = contentTruncated || excerpt.truncated;
    }
    if (candidates.length > maxFiles) {
      contentTruncated = true;
      omittedPathCount += candidates.length - maxFiles;
    }

    final metadata = _parseMetadata(excerpts);
    return WorkspaceDiscoveryProfile(
      workspaceName: workspace.displayName,
      treePaths: treePaths,
      highSignalFiles: excerpts,
      packageName: metadata.packageName,
      scripts: metadata.scripts,
      dependencies: metadata.dependencies,
      languages: _detectLanguages(treePaths),
      frameworks: _detectFrameworks(metadata.dependencies),
      treeTruncated: treeTruncated,
      contentTruncated: contentTruncated,
      omittedPathCount: omittedPathCount,
    );
  }

  bool _isHighSignal(String relative) {
    final basename = path.basename(relative);
    return _highSignalNames.contains(basename) ||
        _entrypointNames.contains(basename) ||
        basename.startsWith('README') ||
        basename.startsWith('tsconfig.') ||
        basename.endsWith('.csproj');
  }

  int _signalScore(String relative) {
    final basename = path.basename(relative);
    final depth = path.split(relative).length;
    if (basename == 'AGENTS.md') return depth;
    if (basename.startsWith('README')) return 10 + depth;
    if (_highSignalNames.contains(basename)) return 20 + depth;
    return 40 + depth;
  }

  Future<WorkspaceFileExcerpt?> _readExcerpt({
    required String rootPath,
    required String relativePath,
    required int limit,
  }) async {
    RandomAccessFile? handle;
    try {
      final file = File(path.join(rootPath, relativePath));
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size > 1024 * 1024) {
        return null;
      }
      handle = await file.open();
      final bytes = await handle.read(limit + 1);
      if (bytes.contains(0)) return null;
      final truncated = bytes.length > limit;
      final selected = truncated ? bytes.sublist(0, limit) : bytes;
      return WorkspaceFileExcerpt(
        path: relativePath,
        content: utf8.decode(selected, allowMalformed: true),
        truncated: truncated,
      );
    } on FileSystemException {
      return null;
    } finally {
      await handle?.close();
    }
  }

  _WorkspacePackageMetadata _parseMetadata(
    List<WorkspaceFileExcerpt> excerpts,
  ) {
    String? packageName;
    final scripts = <String, String>{};
    final dependencies = <String>{};
    for (final excerpt in excerpts) {
      final basename = path.basename(excerpt.path);
      if (basename == 'package.json') {
        try {
          final json = jsonDecode(excerpt.content);
          if (json is Map) {
            packageName ??= json['name']?.toString();
            final rawScripts = json['scripts'];
            if (rawScripts is Map) {
              for (final entry in rawScripts.entries) {
                scripts[entry.key.toString()] = entry.value.toString();
              }
            }
            for (final key in const ['dependencies', 'devDependencies']) {
              final values = json[key];
              if (values is Map) {
                dependencies.addAll(values.keys.map((item) => item.toString()));
              }
            }
          }
        } on FormatException {
          // A truncated or malformed manifest remains useful as an excerpt.
        }
      } else if (basename == 'pubspec.yaml') {
        try {
          final yaml = loadYaml(excerpt.content);
          if (yaml is YamlMap) {
            packageName ??= yaml['name']?.toString();
            for (final key in const ['dependencies', 'dev_dependencies']) {
              final values = yaml[key];
              if (values is YamlMap) {
                dependencies.addAll(values.keys.map((item) => item.toString()));
              }
            }
          }
        } on YamlException {
          // A truncated or malformed manifest remains useful as an excerpt.
        }
      }
    }
    final sortedDependencies = dependencies.toList()..sort();
    return _WorkspacePackageMetadata(
      packageName: packageName,
      scripts: Map.fromEntries(
        scripts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
      dependencies: sortedDependencies,
    );
  }

  List<String> _detectLanguages(List<String> treePaths) {
    const extensions = {
      '.dart': 'Dart',
      '.go': 'Go',
      '.java': 'Java',
      '.js': 'JavaScript',
      '.kt': 'Kotlin',
      '.py': 'Python',
      '.rb': 'Ruby',
      '.rs': 'Rust',
      '.swift': 'Swift',
      '.ts': 'TypeScript',
    };
    final result = <String>{};
    for (final item in treePaths) {
      final language = extensions[path.extension(item)];
      if (language != null) result.add(language);
    }
    return result.toList()..sort();
  }

  List<String> _detectFrameworks(List<String> dependencies) {
    const known = {
      'flutter': 'Flutter',
      'react': 'React',
      'next': 'Next.js',
      'nextjs': 'Next.js',
      'vue': 'Vue',
      'angular': 'Angular',
      'django': 'Django',
      'flask': 'Flask',
      'fastapi': 'FastAPI',
    };
    final result = <String>{};
    for (final dependency in dependencies) {
      final framework = known[dependency.toLowerCase()];
      if (framework != null) result.add(framework);
    }
    return result.toList()..sort();
  }
}

class _WorkspacePackageMetadata {
  final String? packageName;
  final Map<String, String> scripts;
  final List<String> dependencies;

  const _WorkspacePackageMetadata({
    required this.packageName,
    required this.scripts,
    required this.dependencies,
  });
}
