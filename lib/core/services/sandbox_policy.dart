/// Sandbox policy: configuration constants, data classes, and validation rules.
///
/// This module encapsulates all policy decisions for the workspace sandbox:
/// size limits, path traversal rules, hidden-entry filtering, and output caps.
/// It has no file system I/O dependencies — it is pure policy.

library;

import 'dart:convert';

import 'package:path/path.dart' as path;

// ---------------------------------------------------------------------------
// Policy Constants
// ---------------------------------------------------------------------------

/// Maximum bytes allowed when reading a single file.
const int kMaxReadBytes = 1024 * 1024;

/// Maximum number of search match results to return.
const int kMaxSearchResults = 100;

/// Maximum encoded JSON size for search result payloads.
const int kMaxSearchOutputBytes = 64 * 1024;

/// Maximum bytes for command stdout/stderr output.
const int kMaxCommandOutputBytes = 64 * 1024;

/// Timeout applied to user-approved host command execution.
const Duration kCommandTimeout = Duration(seconds: 30);

// ---------------------------------------------------------------------------
// Data Classes
// ---------------------------------------------------------------------------

/// Resolved workspace path with root, absolute, and relative representations.
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

/// Exception thrown when a sandbox operation violates policy.
class WorkspaceSandboxException implements Exception {
  final String message;
  final String code;

  const WorkspaceSandboxException(
    this.message, {
    this.code = 'workspace_validation',
  });

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Policy Validation Helpers
// ---------------------------------------------------------------------------

/// Returns true if the given [basename] is a hidden dot entry name.
bool _isDotEntry(String basename) =>
    basename.isNotEmpty &&
    basename != '.' &&
    basename != '..' &&
    basename.startsWith('.');

/// Returns true if any component of [relativePath] is a hidden dot entry.
bool pathContainsDotEntry(String relativePath) {
  final normalised = path.normalize(relativePath);
  if (normalised == '.') return false;
  return path.split(normalised).any(_isDotEntry);
}

/// Asserts that [candidate] lies within the [root] directory.
///
/// Throws [WorkspaceSandboxException] if the candidate path escapes the root.
void assertInside(String root, String candidate) {
  final relative = path.relative(candidate, from: root);
  if (relative == '.' ||
      (!relative.startsWith('..') && !path.isAbsolute(relative))) {
    return;
  }
  throw WorkspaceSandboxException('Path escapes the workspace.');
}

/// Throws [WorkspaceSandboxException] if serializing [results] would exceed
/// the search output byte limit.
void throwIfSearchOutputTooLarge(List<Map<String, dynamic>> results) {
  final encodedBytes = utf8.encode(jsonEncode({'matches': results})).length;
  if (encodedBytes <= kMaxSearchOutputBytes) return;
  throw WorkspaceSandboxException(
    'Search results are too large to return safely '
    '($encodedBytes bytes, limit $kMaxSearchOutputBytes bytes). '
    'Narrow your query or specify a more targeted path to continue.',
  );
}

/// Caps [value] to [kMaxCommandOutputBytes] UTF-8 bytes, appending a truncation
/// marker when the content exceeds the limit.
String capOutput(String value) {
  final bytes = utf8.encode(value);
  if (bytes.length <= kMaxCommandOutputBytes) return value;
  return '${utf8.decode(bytes.take(kMaxCommandOutputBytes).toList(), allowMalformed: true)}\n... output truncated ...';
}
