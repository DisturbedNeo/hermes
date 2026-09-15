import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/sandbox_policy.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;

/// Read-only, budgeted workspace context for the initial project planner.
///
/// The planner can inspect a useful file in windows, but it cannot list the
/// workspace, follow links, run commands, or read paths that were not present
/// in the deterministic discovery tree.
class ProjectPlanningWorkspaceReader {
  ProjectPlanningWorkspaceReader({
    required WorkspaceAttachment workspace,
    required WorkspaceSandbox sandbox,
    required Iterable<String> allowedPaths,
    CancellationToken? cancellationToken,
    this.maxTotalBytes = defaultMaxTotalBytes,
    this.maxWindowBytes = defaultMaxWindowBytes,
    this.maxWindowLines = defaultMaxWindowLines,
  }) : _workspace = workspace,
       _sandbox = sandbox,
       _cancellationToken = cancellationToken,
       _allowedPaths = {
         for (final value in allowedPaths)
           if (value.trim().isNotEmpty && !value.endsWith('/'))
             _normalise(value): value,
       },
       _remainingBytes = maxTotalBytes;

  static const int defaultMaxTotalBytes = 80 * 1024;
  static const int defaultMaxWindowBytes = 12 * 1024;
  static const int defaultMaxWindowLines = 240;

  final WorkspaceAttachment _workspace;
  final WorkspaceSandbox _sandbox;
  final CancellationToken? _cancellationToken;
  final Map<String, String> _allowedPaths;
  final int maxTotalBytes;
  final int maxWindowBytes;
  final int maxWindowLines;
  int _remainingBytes;

  Future<Map<String, dynamic>> read({
    required String requestedPath,
    int startLine = 1,
    int? endLine,
  }) async {
    _cancellationToken?.throwIfCancelled();
    final normalised = _normalise(requestedPath);
    final allowedPath = _allowedPaths[normalised];
    if (allowedPath == null) {
      return _error(
        code: 'workspace_path_not_in_discovery',
        message:
            'Only existing files from the bounded workspace discovery tree can be read.',
      );
    }
    if (startLine < 1) {
      return _error(
        code: 'invalid_context_range',
        message: 'start_line must be at least 1.',
      );
    }
    final requestedEndLine = endLine ?? startLine + maxWindowLines - 1;
    if (requestedEndLine < startLine) {
      return _error(
        code: 'invalid_context_range',
        message: 'end_line must be greater than or equal to start_line.',
      );
    }
    if (requestedEndLine - startLine + 1 > maxWindowLines) {
      return _error(
        code: 'context_window_too_large',
        message:
            'A planning context read may contain at most $maxWindowLines lines.',
      );
    }
    if (_remainingBytes <= 0) return _budgetError();

    try {
      final resolved = await _sandbox.resolve(_workspace.rootPath, allowedPath);
      if (_normalise(resolved.relativePath) != normalised) {
        return _error(
          code: 'workspace_path_changed',
          message:
              'The requested discovery path is no longer the same regular file.',
        );
      }
      final file = await _sandbox.readFile(
        _workspace.rootPath,
        allowedPath,
        cancellationToken: _cancellationToken,
      );
      _cancellationToken?.throwIfCancelled();
      final content = file['content'] as String;
      if (content.contains('\u0000')) {
        return _error(
          code: 'workspace_binary_file',
          message: 'Planning context is limited to UTF-8 text files.',
        );
      }

      final lines = content.split('\n');
      if (startLine > lines.length) {
        return {
          'ok': true,
          'path': resolved.relativePath,
          'start_line': startLine,
          'end_line': startLine - 1,
          'total_lines': lines.length,
          'content': '',
          'bytes': 0,
          'has_more': false,
          'next_start_line': null,
          'budget_remaining': _remainingBytes,
        };
      }

      final targetEnd = requestedEndLine.clamp(startLine, lines.length).toInt();
      final selected = _selectLines(
        lines,
        startLine: startLine,
        endLine: targetEnd,
        maxBytes: _remainingBytes < maxWindowBytes
            ? _remainingBytes
            : maxWindowBytes,
      );
      if (selected.content.isEmpty && selected.endLine >= startLine) {
        return _error(
          code: 'context_line_too_large',
          message:
              'The requested range begins with a line larger than the remaining planning context budget. Request a narrower range after the line.',
        );
      }

      _remainingBytes -= selected.bytes;
      final hasMore = selected.endLine < lines.length;
      return {
        'ok': true,
        'path': resolved.relativePath,
        'start_line': startLine,
        'end_line': selected.endLine,
        'total_lines': lines.length,
        'content': selected.content,
        'bytes': selected.bytes,
        'has_more': hasMore,
        'next_start_line': hasMore ? selected.endLine + 1 : null,
        'budget_remaining': _remainingBytes,
      };
    } on WorkspaceSandboxException catch (error) {
      return _error(code: error.code, message: error.message);
    } on FileSystemException catch (error) {
      return _error(code: 'workspace_io_failure', message: error.message);
    } on FormatException {
      return _error(
        code: 'workspace_invalid_text',
        message: 'The requested file is not valid UTF-8 text.',
      );
    }
  }

  _SelectedLines _selectLines(
    List<String> lines, {
    required int startLine,
    required int endLine,
    required int maxBytes,
  }) {
    final selected = <String>[];
    var bytes = 0;
    for (var lineNumber = startLine; lineNumber <= endLine; lineNumber++) {
      final candidate = lines[lineNumber - 1];
      final separatorBytes = selected.isEmpty ? 0 : 1;
      final candidateBytes = utf8.encode(candidate).length + separatorBytes;
      if (bytes + candidateBytes > maxBytes) break;
      selected.add(candidate);
      bytes += candidateBytes;
    }
    return _SelectedLines(
      content: selected.join('\n'),
      endLine: selected.isEmpty
          ? startLine - 1
          : startLine + selected.length - 1,
      bytes: bytes,
    );
  }

  Map<String, dynamic> _budgetError() => _error(
    code: 'planning_context_budget_exhausted',
    message:
        'The planning context read budget is exhausted. Continue using the supplied profile without reading more files.',
  );

  Map<String, dynamic> _error({
    required String code,
    required String message,
  }) => {
    'ok': false,
    'code': code,
    'message': message,
    'budget_remaining': _remainingBytes,
  };

  static String _normalise(String value) => path
      .normalize(value.trim().replaceAll('\\', '/'))
      .replaceFirst(RegExp(r'^\./'), '')
      .toLowerCase();
}

class _SelectedLines {
  const _SelectedLines({
    required this.content,
    required this.endLine,
    required this.bytes,
  });

  final String content;
  final int endLine;
  final int bytes;
}
