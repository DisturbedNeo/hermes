import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:hermes/core/services/terminal_command_classifier.dart';

class WorkspaceSandbox {
  static const int maxReadBytes = 1024 * 1024;
  static const int maxSearchResults = 100;
  static const int maxSearchOutputBytes = 64 * 1024;
  static const int maxCommandOutputBytes = 64 * 1024;
  static const Duration commandTimeout = Duration(seconds: 30);

  Future<String> canonicalRoot(String rootPath) async {
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      throw WorkspaceSandboxException('Workspace folder does not exist.');
    }
    return dir.resolveSymbolicLinks();
  }

  Future<WorkspacePath> resolve(
    String rootPath,
    String relativePath, {
    bool mustExist = true,
    bool directory = false,
  }) async {
    if (relativePath.trim().isEmpty) relativePath = '.';
    if (path.isAbsolute(relativePath)) {
      throw WorkspaceSandboxException('Use workspace-relative paths only.');
    }

    final root = await canonicalRoot(rootPath);
    final requested = path.normalize(path.join(root, relativePath));
    final canonical = mustExist
        ? await _resolveExisting(requested)
        : await _resolveCreatable(requested);

    _assertInside(root, canonical);

    if (mustExist) {
      final type = await FileSystemEntity.type(canonical);
      if (type == FileSystemEntityType.notFound) {
        throw WorkspaceSandboxException('Path not found: $relativePath');
      }
      if (directory && type != FileSystemEntityType.directory) {
        throw WorkspaceSandboxException(
          'Path is not a directory: $relativePath',
        );
      }
    }

    return WorkspacePath(
      rootPath: root,
      absolutePath: canonical,
      relativePath: _relative(root, canonical),
    );
  }

  Future<List<Map<String, dynamic>>> listDirectory(
    String rootPath,
    String relativePath,
  ) async {
    final resolved = await resolve(rootPath, relativePath, directory: true);
    final entries = <Map<String, dynamic>>[];

    await for (final entity in Directory(resolved.absolutePath).list()) {
      final stat = await entity.stat();
      final type = stat.type == FileSystemEntityType.directory
          ? 'directory'
          : stat.type == FileSystemEntityType.link
          ? 'link'
          : 'file';
      entries.add({
        'path': _relative(resolved.rootPath, entity.path),
        'name': path.basename(entity.path),
        'type': type,
        'size': stat.size,
        'modified': stat.modified.toIso8601String(),
      });
    }

    entries.sort((a, b) {
      final typeCompare = (a['type'] as String).compareTo(b['type'] as String);
      if (typeCompare != 0) return typeCompare;
      return (a['name'] as String).compareTo(b['name'] as String);
    });
    return entries;
  }

  Future<Map<String, dynamic>> readFile(
    String rootPath,
    String relativePath,
  ) async {
    final resolved = await resolve(rootPath, relativePath);
    final type = await FileSystemEntity.type(resolved.absolutePath);
    if (type == FileSystemEntityType.directory) {
      throw WorkspaceSandboxException(
        'Path is a directory. Use list_directory for directories: ${resolved.relativePath}',
      );
    }
    final file = File(resolved.absolutePath);
    final length = await file.length();
    if (length > maxReadBytes) {
      throw WorkspaceSandboxException(
        'File is too large to read ($length bytes).',
      );
    }

    return {
      'path': resolved.relativePath,
      'content': await file.readAsString(),
      'bytes': length,
    };
  }

  Future<Map<String, dynamic>> writeFile(
    String rootPath,
    String relativePath,
    String content,
  ) async {
    final resolved = await resolve(rootPath, relativePath, mustExist: false);
    final file = File(resolved.absolutePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return {
      'path': resolved.relativePath,
      'bytes': utf8.encode(content).length,
    };
  }

  Future<Map<String, dynamic>> patchFile(
    String rootPath,
    String relativePath,
    String oldText,
    String newText, {
    bool replaceAll = false,
  }) async {
    final resolved = await resolve(rootPath, relativePath);
    final file = File(resolved.absolutePath);
    final current = await file.readAsString();
    if (!current.contains(oldText)) {
      throw WorkspaceSandboxException('Patch text was not found.');
    }
    final updated = replaceAll
        ? current.replaceAll(oldText, newText)
        : current.replaceFirst(oldText, newText);
    await file.writeAsString(updated);
    return {
      'path': resolved.relativePath,
      'replacements': replaceAll ? _countMatches(current, oldText) : 1,
    };
  }

  Future<Map<String, dynamic>> createDirectory(
    String rootPath,
    String relativePath,
  ) async {
    final resolved = await resolve(rootPath, relativePath, mustExist: false);
    await Directory(resolved.absolutePath).create(recursive: true);
    return {'path': resolved.relativePath};
  }

  Future<Map<String, dynamic>> renamePath(
    String rootPath,
    String from,
    String to,
  ) async {
    final source = await resolve(rootPath, from);
    final destination = await resolve(rootPath, to, mustExist: false);
    await Directory(
      path.dirname(destination.absolutePath),
    ).create(recursive: true);
    final type = await FileSystemEntity.type(source.absolutePath);
    if (type == FileSystemEntityType.directory) {
      await Directory(source.absolutePath).rename(destination.absolutePath);
    } else {
      await File(source.absolutePath).rename(destination.absolutePath);
    }
    return {'from': source.relativePath, 'to': destination.relativePath};
  }

  Future<Map<String, dynamic>> deletePath(
    String rootPath,
    String relativePath, {
    bool recursive = false,
  }) async {
    final resolved = await resolve(rootPath, relativePath);
    if (resolved.relativePath == '.') {
      throw WorkspaceSandboxException('Refusing to delete the workspace root.');
    }
    final type = await FileSystemEntity.type(resolved.absolutePath);
    if (type == FileSystemEntityType.directory) {
      await Directory(resolved.absolutePath).delete(recursive: recursive);
    } else {
      await File(resolved.absolutePath).delete();
    }
    return {'path': resolved.relativePath};
  }

  /// Returns true if the given [basename] is a hidden dot entry name.
  static bool _isDotEntry(String basename) =>
      basename.isNotEmpty &&
      basename != '.' &&
      basename != '..' &&
      basename.startsWith('.');

  static bool _pathContainsDotEntry(String relativePath) {
    final normalised = path.normalize(relativePath);
    if (normalised == '.') return false;
    return path.split(normalised).any(_isDotEntry);
  }

  Future<List<Map<String, dynamic>>> searchFiles(
    String rootPath,
    String query, {
    String relativePath = '.',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw WorkspaceSandboxException('Search query is required.');
    }

    final searchRootPath = relativePath.trim() == '/' ? '.' : relativePath;
    final root = await resolve(rootPath, searchRootPath, directory: true);

    // Only include hidden dot-folders when the requested search root itself is
    // inside one, e.g. ".agent" or "packages/.cache".
    final isExplicitDotSearch = _pathContainsDotEntry(root.relativePath);

    final results = <Map<String, dynamic>>[];
    final pendingDirectories = <Directory>[Directory(root.absolutePath)];

    while (pendingDirectories.isNotEmpty && results.length < maxSearchResults) {
      final directory = pendingDirectories.removeLast();
      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (results.length >= maxSearchResults) break;

          final basename = path.basename(entity.path);
          if (entity is Directory) {
            if (_isDotEntry(basename) && !isExplicitDotSearch) continue;
            pendingDirectories.add(entity);
            continue;
          }

          if (entity is! File) continue;
          if (await entity.length() > maxReadBytes) continue;

          final rel = _relative(root.rootPath, entity.path);
          try {
            final lines = await entity.readAsLines();
            for (var i = 0; i < lines.length; i++) {
              if (!lines[i].toLowerCase().contains(trimmed.toLowerCase())) {
                continue;
              }
              final result = {
                'path': rel,
                'line': i + 1,
                'preview': lines[i].trim(),
              };
              _throwIfSearchOutputTooLarge([...results, result]);
              results.add(result);
              if (results.length >= maxSearchResults) break;
            }
          } on FormatException {
            continue;
          } on FileSystemException {
            continue;
          }
        }
      } on FileSystemException {
        continue;
      }
    }

    // Graceful error when the search was too broad.
    if (results.length >= maxSearchResults) {
      throw WorkspaceSandboxException(
        'Search returned too many results ($maxSearchResults+ matches). '
        'Narrow your query or specify a more targeted path to continue.',
      );
    }

    return results;
  }

  void _throwIfSearchOutputTooLarge(List<Map<String, dynamic>> results) {
    final encodedBytes = utf8.encode(jsonEncode({'matches': results})).length;
    if (encodedBytes <= maxSearchOutputBytes) return;
    throw WorkspaceSandboxException(
      'Search results are too large to return safely '
      '($encodedBytes bytes, limit $maxSearchOutputBytes bytes). '
      'Narrow your query or specify a more targeted path to continue.',
    );
  }

  Future<Map<String, dynamic>> runCommand(
    String rootPath, {
    required String executable,
    required List<String> arguments,
    String workingDirectory = '.',
  }) async {
    if (executable.trim().isEmpty) {
      throw WorkspaceSandboxException('Command executable is required.');
    }
    if (path.isAbsolute(executable) || executable.contains(path.separator)) {
      throw WorkspaceSandboxException(
        'Use an executable name, not an absolute or relative executable path.',
      );
    }
    final blockedReason = TerminalCommandClassifier.blockedReason(
      executable: executable,
      arguments: arguments,
    );
    if (blockedReason != null) {
      throw WorkspaceSandboxException(blockedReason);
    }

    final cwd = await resolve(rootPath, workingDirectory, directory: true);
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: cwd.absolutePath,
    ).timeout(commandTimeout);

    return {
      'command': [executable, ...arguments].join(' '),
      'working_directory': cwd.relativePath,
      'exit_code': result.exitCode,
      'stdout': _capOutput(result.stdout.toString()),
      'stderr': _capOutput(result.stderr.toString()),
    };
  }

  Future<String> _resolveCreatable(String requested) async {
    final existing = await _nearestExistingParent(requested);
    final parent = await Directory(existing).resolveSymbolicLinks();
    final suffix = path.relative(requested, from: existing);
    return path.normalize(path.join(parent, suffix));
  }

  Future<String> _resolveExisting(String requested) async {
    final type = await FileSystemEntity.type(requested);
    return switch (type) {
      FileSystemEntityType.directory => Directory(
        requested,
      ).resolveSymbolicLinks(),
      FileSystemEntityType.file => File(requested).resolveSymbolicLinks(),
      FileSystemEntityType.link => Link(requested).resolveSymbolicLinks(),
      FileSystemEntityType.notFound => throw WorkspaceSandboxException(
        'Path not found.',
      ),
      _ => File(requested).resolveSymbolicLinks(),
    };
  }

  Future<String> _nearestExistingParent(String requested) async {
    var current = requested;
    while (true) {
      if (await Directory(current).exists() || await File(current).exists()) {
        return current;
      }
      final parent = path.dirname(current);
      if (parent == current) {
        throw WorkspaceSandboxException('No existing parent directory found.');
      }
      current = parent;
    }
  }

  void _assertInside(String root, String candidate) {
    final relative = path.relative(candidate, from: root);
    if (relative == '.' ||
        (!relative.startsWith('..') && !path.isAbsolute(relative))) {
      return;
    }
    throw WorkspaceSandboxException('Path escapes the workspace.');
  }

  String _relative(String root, String absolute) {
    final rel = path.relative(absolute, from: root);
    return rel == '' ? '.' : path.normalize(rel);
  }

  int _countMatches(String haystack, String needle) {
    if (needle.isEmpty) return 0;
    var count = 0;
    var index = 0;
    while (true) {
      index = haystack.indexOf(needle, index);
      if (index == -1) return count;
      count++;
      index += needle.length;
    }
  }

  String _capOutput(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxCommandOutputBytes) return value;
    return '${utf8.decode(bytes.take(maxCommandOutputBytes).toList(), allowMalformed: true)}\n... output truncated ...';
  }
}

class WorkspacePath {
  final String rootPath;
  final String absolutePath;
  final String relativePath;

  const WorkspacePath({
    required this.rootPath,
    required this.absolutePath,
    required this.relativePath,
  });
}

class WorkspaceSandboxException implements Exception {
  final String message;

  const WorkspaceSandboxException(this.message);

  @override
  String toString() => message;
}
