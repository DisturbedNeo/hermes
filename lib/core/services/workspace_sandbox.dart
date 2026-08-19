/// Workspace-confined file operations and host-command orchestration.
///
/// Policy configuration, rule definitions, and validation logic are isolated
/// in [sandbox_policy.dart]. This class has a single responsibility — perform
/// workspace-confined I/O. Host commands are delegated to [HostCommandRunner]
/// and are not sandboxed.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/host_command_runner.dart';
import 'package:hermes/core/services/terminal_command_parser.dart';
import 'sandbox_policy.dart';

// Re-export for backward compatibility with existing imports.
export 'sandbox_policy.dart' show WorkspacePath, WorkspaceSandboxException;

class WorkspaceSandbox {
  WorkspaceSandbox({
    Duration commandTimeout = kCommandTimeout,
    this.commandTerminationGrace = const Duration(seconds: 2),
    HostCommandRunner? hostCommandRunner,
  }) : _hostCommandRunner =
           hostCommandRunner ??
           HostCommandRunner(
             timeout: commandTimeout,
             terminationGrace: commandTerminationGrace,
           );

  final Duration commandTerminationGrace;
  final HostCommandRunner _hostCommandRunner;

  // Backward-compatible static accessors for constants previously defined here.
  // These delegate to the canonical definitions in sandbox_policy.dart.
  static const int maxReadBytes = kMaxReadBytes;
  static const int maxWriteBytes = kMaxWriteBytes;
  static const int maxDirectoryEntries = kMaxDirectoryEntries;
  static const int maxSearchFiles = kMaxSearchFiles;
  static const int maxSearchResults = kMaxSearchResults;
  static const int maxSearchOutputBytes = kMaxSearchOutputBytes;
  static const int maxCommandOutputBytes = kMaxCommandOutputBytes;
  static const Duration commandTimeout = kCommandTimeout;

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

    assertInside(root, canonical);

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
    String relativePath, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final resolved = await resolve(rootPath, relativePath, directory: true);
    final entries = <Map<String, dynamic>>[];

    await for (final entity in Directory(resolved.absolutePath).list()) {
      cancellationToken?.throwIfCancelled();
      if (entries.length >= kMaxDirectoryEntries) {
        throw WorkspaceSandboxException(
          'Directory contains more than $kMaxDirectoryEntries entries. '
          'Use a more targeted path to continue.',
          code: 'workspace_listing_too_large',
        );
      }
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
    String relativePath, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final resolved = await resolve(rootPath, relativePath);
    final type = await FileSystemEntity.type(resolved.absolutePath);
    if (type == FileSystemEntityType.directory) {
      throw WorkspaceSandboxException(
        'Path is a directory. Use list_directory for directories: ${resolved.relativePath}',
      );
    }
    final content = await _readUtf8File(
      File(resolved.absolutePath),
      maxBytes: kMaxReadBytes,
      cancellationToken: cancellationToken,
    );

    return {
      'path': resolved.relativePath,
      'content': content.text,
      'bytes': content.bytes,
    };
  }

  Future<String> readFilePreview(
    String rootPath,
    String relativePath, {
    required int maxChars,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final resolved = await resolve(rootPath, relativePath);
    final type = await FileSystemEntity.type(resolved.absolutePath);
    if (type == FileSystemEntityType.directory) {
      throw WorkspaceSandboxException(
        'Path is a directory: ${resolved.relativePath}',
      );
    }

    final buffer = StringBuffer();
    var length = 0;
    var truncated = false;
    final decoded = File(
      resolved.absolutePath,
    ).openRead().transform(utf8.decoder);
    await for (final chunk in decoded) {
      cancellationToken?.throwIfCancelled();
      final remaining = maxChars - length;
      if (chunk.length > remaining) {
        if (remaining > 0) buffer.write(chunk.substring(0, remaining));
        truncated = true;
        break;
      }
      buffer.write(chunk);
      length += chunk.length;
    }
    cancellationToken?.throwIfCancelled();
    return truncated ? '${buffer.toString()}...' : buffer.toString();
  }

  Future<Map<String, dynamic>> writeFile(
    String rootPath,
    String relativePath,
    String content, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final resolved = await resolve(rootPath, relativePath, mustExist: false);
    final bytes = utf8.encode(content);
    _throwIfWriteTooLarge(bytes.length);
    await _atomicWrite(
      File(resolved.absolutePath),
      bytes,
      cancellationToken: cancellationToken,
    );
    return {'path': resolved.relativePath, 'bytes': bytes.length};
  }

  Future<Map<String, dynamic>> patchFile(
    String rootPath,
    String relativePath,
    String oldText,
    String newText, {
    bool replaceAll = false,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final resolved = await resolve(rootPath, relativePath);
    final file = File(resolved.absolutePath);
    final current = (await _readUtf8File(
      file,
      maxBytes: kMaxReadBytes,
      cancellationToken: cancellationToken,
    )).text;
    if (!current.contains(oldText)) {
      throw WorkspaceSandboxException('Patch text was not found.');
    }
    final updated = replaceAll
        ? current.replaceAll(oldText, newText)
        : current.replaceFirst(oldText, newText);
    final bytes = utf8.encode(updated);
    _throwIfWriteTooLarge(bytes.length);
    await _atomicWrite(file, bytes, cancellationToken: cancellationToken);
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

  Future<List<Map<String, dynamic>>> searchFiles(
    String rootPath,
    String query, {
    String relativePath = '.',
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw WorkspaceSandboxException('Search query is required.');
    }

    final searchRootPath = relativePath.trim() == '/' ? '.' : relativePath;
    final root = await resolve(rootPath, searchRootPath, directory: true);

    // Only include hidden dot-folders when the requested search root itself is
    // inside one, e.g. ".agent" or "packages/.cache".
    final isExplicitDotSearch = pathContainsDotEntry(root.relativePath);

    final results = <Map<String, dynamic>>[];
    final pendingDirectories = <Directory>[Directory(root.absolutePath)];
    final lowerQuery = trimmed.toLowerCase();
    var scannedFiles = 0;

    while (pendingDirectories.isNotEmpty &&
        results.length < kMaxSearchResults) {
      final directory = pendingDirectories.removeLast();
      try {
        await for (final entity in directory.list(followLinks: false)) {
          cancellationToken?.throwIfCancelled();
          if (results.length >= kMaxSearchResults) break;

          final basename = path.basename(entity.path);
          if (entity is Directory) {
            if (_isDotEntry(basename) && !isExplicitDotSearch) continue;
            pendingDirectories.add(entity);
            continue;
          }

          if (entity is! File) continue;
          scannedFiles++;
          if (scannedFiles > kMaxSearchFiles) {
            throw WorkspaceSandboxException(
              'Search examined more than $kMaxSearchFiles files. '
              'Narrow the query or specify a more targeted path to continue.',
              code: 'workspace_search_too_broad',
            );
          }

          final rel = _relative(root.rootPath, entity.path);
          try {
            var lineNumber = 0;
            var fileBytes = 0;
            final byteStream = entity.openRead().transform(
              StreamTransformer<List<int>, List<int>>.fromHandlers(
                handleData: (chunk, sink) {
                  cancellationToken?.throwIfCancelled();
                  fileBytes += chunk.length;
                  if (fileBytes > kMaxReadBytes) {
                    sink.addError(
                      const WorkspaceSandboxException(
                        'File is too large to search safely.',
                        code: 'workspace_file_too_large',
                      ),
                    );
                    return;
                  }
                  sink.add(chunk);
                },
              ),
            );
            final lines = byteStream
                .transform(utf8.decoder)
                .transform(const LineSplitter());
            await for (final line in lines) {
              cancellationToken?.throwIfCancelled();
              lineNumber++;
              if (!line.toLowerCase().contains(lowerQuery)) {
                continue;
              }
              final result = {
                'path': rel,
                'line': lineNumber,
                'preview': line.trim(),
              };
              throwIfSearchOutputTooLarge([...results, result]);
              results.add(result);
              if (results.length >= kMaxSearchResults) break;
            }
          } on FormatException {
            continue;
          } on WorkspaceSandboxException catch (error) {
            if (error.code != 'workspace_file_too_large') rethrow;
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
    if (results.length >= kMaxSearchResults) {
      throw WorkspaceSandboxException(
        'Search returned too many results ($kMaxSearchResults+ matches). '
        'Narrow your query or specify a more targeted path to continue.',
      );
    }

    return results;
  }

  Future<Map<String, dynamic>> runCommand(
    String rootPath, {
    String? command,
    String? executable,
    List<String> arguments = const [],
    String workingDirectory = '.',
    CancellationToken? cancellationToken,
  }) async {
    final commandLine = _commandLine(
      command: command,
      executable: executable,
      arguments: arguments,
    );
    final cwd = await resolve(rootPath, workingDirectory, directory: true);
    return _hostCommandRunner.run(
      commandLine: commandLine,
      workingDirectory: cwd.absolutePath,
      relativeWorkingDirectory: cwd.relativePath,
      cancellationToken: cancellationToken,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers (operational mechanics, not policy)
  // ---------------------------------------------------------------------------

  Future<_Utf8FileContent> _readUtf8File(
    File file, {
    required int maxBytes,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final bytes = BytesBuilder();
    var byteCount = 0;
    await for (final chunk in file.openRead()) {
      cancellationToken?.throwIfCancelled();
      byteCount += chunk.length;
      if (byteCount > maxBytes) {
        throw WorkspaceSandboxException(
          'File is too large to read (limit $maxBytes bytes).',
          code: 'workspace_file_too_large',
        );
      }
      bytes.add(chunk);
    }
    cancellationToken?.throwIfCancelled();
    return _Utf8FileContent(utf8.decode(bytes.takeBytes()), byteCount);
  }

  void _throwIfWriteTooLarge(int bytes) {
    if (bytes <= kMaxWriteBytes) return;
    throw WorkspaceSandboxException(
      'File is too large to write ($bytes bytes, limit $kMaxWriteBytes bytes).',
      code: 'workspace_file_too_large',
    );
  }

  Future<void> _atomicWrite(
    File destination,
    List<int> bytes, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    await destination.parent.create(recursive: true);
    final temp = await _createTemporarySibling(destination);
    var committed = false;
    try {
      if (await destination.exists()) {
        final originalMode = (await destination.stat()).mode;
        await destination.copy(temp.path);
        await _applyPosixMode(temp, originalMode);
      }
      cancellationToken?.throwIfCancelled();
      await temp.writeAsBytes(bytes, flush: true);
      cancellationToken?.throwIfCancelled();
      await temp.rename(destination.path);
      committed = true;
    } finally {
      if (!committed && await temp.exists()) {
        await temp.delete();
      }
    }
  }

  Future<void> _applyPosixMode(File file, int mode) async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final permissions = (mode & 0xfff).toRadixString(8);
    final result = await Process.run('chmod', [permissions, file.path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Unable to preserve file permissions during atomic replacement.',
        file.path,
      );
    }
  }

  Future<File> _createTemporarySibling(File destination) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final temp = File(
        path.join(
          destination.parent.path,
          '.${path.basename(destination.path)}.hermes-$pid-'
          '${DateTime.now().microsecondsSinceEpoch}-$attempt.tmp',
        ),
      );
      try {
        return await temp.create(exclusive: true);
      } on FileSystemException {
        continue;
      }
    }
    throw FileSystemException(
      'Unable to create a temporary file for atomic replacement.',
      destination.path,
    );
  }

  String _commandLine({
    required String? command,
    required String? executable,
    required List<String> arguments,
  }) {
    final trimmed = command?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    final legacyExecutable = executable?.trim();
    if (legacyExecutable == null || legacyExecutable.isEmpty) return '';
    return TerminalCommandParser.commandTextFromParts(
      legacyExecutable,
      arguments,
    );
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

  // Re-use the policy helper for dot-entry detection in search.
  static bool _isDotEntry(String basename) =>
      basename.isNotEmpty &&
      basename != '.' &&
      basename != '..' &&
      basename.startsWith('.');
}

class _Utf8FileContent {
  const _Utf8FileContent(this.text, this.bytes);

  final String text;
  final int bytes;
}
