import 'dart:convert';

import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:hermes/features/task/application/yaml_validation_port.dart';
import 'package:path/path.dart' as path;

class TaskGateFileValidationService {
  TaskGateFileValidationService({
    required WorkspaceVerificationPort sandbox,
    required YamlValidationPort yamlValidator,
  }) : _sandbox = sandbox,
       _yamlValidator = yamlValidator;

  final WorkspaceVerificationPort _sandbox;
  final YamlValidationPort _yamlValidator;

  Future<TaskGateResult> artifactExists(
    WorkspaceAttachment workspace,
    TaskGate gate,
    List<TaskArtifact> artifacts,
    DateTime now,
  ) async {
    final paths = _gatePaths(gate, artifacts);
    if (paths.isEmpty) {
      return _result(
        gate,
        TaskGateStatus.pending,
        'No artifact paths were available to verify.',
        now,
      );
    }
    final missing = <String>[];
    for (final item in paths) {
      final inspected = await _sandbox.inspectPath(workspace.rootPath, item);
      if (!inspected.exists) missing.add(inspected.path);
    }
    if (missing.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'Required artifacts are missing: ${missing.join(', ')}.',
        now,
        {'paths': paths, 'missing': missing},
      );
    }
    return _result(gate, _passStatus(gate), 'Required artifacts exist.', now, {
      'paths': paths,
    });
  }

  Future<TaskGateResult> artifactNonempty(
    WorkspaceAttachment workspace,
    TaskGate gate,
    List<TaskArtifact> artifacts,
    DateTime now,
  ) async {
    final paths = _gatePaths(gate, artifacts);
    if (paths.isEmpty) {
      return _result(
        gate,
        TaskGateStatus.pending,
        'No artifact paths were available to verify.',
        now,
      );
    }
    final empty = <String>[];
    final entityTypes = <String, String>{};
    for (final item in paths) {
      final inspected = await _sandbox.inspectPath(workspace.rootPath, item);
      entityTypes[inspected.path] = _workspaceEntryTypeName(inspected.kind);
      switch (inspected.kind) {
        case WorkspaceEntryKind.directory:
          // A directory is an existence boundary. File length is not a
          // meaningful non-empty check for directories, and the persisted
          // artifact kind is descriptive model input rather than authority.
          continue;
        case WorkspaceEntryKind.file:
          if (inspected.size > 0) continue;
          empty.add(inspected.path);
          continue;
        case WorkspaceEntryKind.link:
        case null:
          empty.add(inspected.path);
      }
    }
    if (empty.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'Required artifacts are empty or missing: ${empty.join(', ')}.',
        now,
        {'paths': paths, 'empty': empty, 'entityTypes': entityTypes},
      );
    }
    return _result(
      gate,
      _passStatus(gate),
      'Required artifacts are non-empty.',
      now,
      {'paths': paths, 'entityTypes': entityTypes},
    );
  }

  Future<TaskGateResult> contentContains(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final content = await _readGateFile(workspace, gate, cancellationToken);
    final required = jsonStringList(
      gate.params['mustContain'] ?? gate.params['contains'],
    );
    final missing = required
        .where((item) => !content.contains(item))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'File is missing required content: ${missing.join(', ')}.',
        now,
        {'missing': missing},
      );
    }
    return _result(
      gate,
      _passStatus(gate),
      'File contains required content.',
      now,
    );
  }

  Future<TaskGateResult> contentNotContains(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final content = await _readGateFile(workspace, gate, cancellationToken);
    final forbidden = jsonStringList(
      gate.params['mustNotContain'] ??
          gate.params['notContain'] ??
          gate.params['forbidden'],
    );
    final found = forbidden
        .where((item) => content.contains(item))
        .toList(growable: false);
    if (found.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'File contains forbidden content: ${found.join(', ')}.',
        now,
        {'found': found},
      );
    }
    return _result(
      gate,
      _passStatus(gate),
      'Forbidden content was not found.',
      now,
    );
  }

  Future<TaskGateResult> jsonValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final content = await _readGateFile(workspace, gate, cancellationToken);
    jsonDecode(content);
    return _result(gate, _passStatus(gate), 'JSON is valid.', now);
  }

  Future<TaskGateResult> yamlValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final content = await _readGateFile(workspace, gate, cancellationToken);
    _yamlValidator.validate(content);
    return _result(gate, _passStatus(gate), 'YAML is valid.', now);
  }

  Future<TaskGateResult> xmlValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final content = (await _readGateFile(
      workspace,
      gate,
      cancellationToken,
    )).trim();
    if (!_looksLikeWellFormedXml(content)) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'XML is not well formed.',
        now,
      );
    }
    return _result(gate, _passStatus(gate), 'XML appears well formed.', now);
  }

  Future<TaskGateResult> markdownLinksValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final filePath = _gatePath(gate);
    final content = await _readGateFile(workspace, gate, cancellationToken);
    final missing = <String>[];
    final linkPattern = RegExp(r'\[[^\]]+\]\(([^)]+)\)');
    for (final match in linkPattern.allMatches(content)) {
      cancellationToken?.throwIfCancelled();
      final rawTarget = match.group(1)?.trim() ?? '';
      if (rawTarget.isEmpty ||
          rawTarget.startsWith('#') ||
          rawTarget.startsWith('http://') ||
          rawTarget.startsWith('https://') ||
          rawTarget.startsWith('mailto:')) {
        continue;
      }
      final target = rawTarget.split('#').first;
      final relative = path.normalize(
        path.join(path.dirname(filePath), target),
      );
      final inspected = await _sandbox.inspectPath(
        workspace.rootPath,
        relative,
      );
      if (!inspected.exists) {
        missing.add(rawTarget);
      }
    }
    if (missing.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'Markdown has missing local links: ${missing.join(', ')}.',
        now,
        {'missingLinks': missing},
      );
    }
    return _result(
      gate,
      _passStatus(gate),
      'Markdown local links are valid.',
      now,
    );
  }

  Future<TaskGateResult> schemaMatches(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final content = await _readGateFile(workspace, gate, cancellationToken);
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'Schema expects a JSON object.',
        now,
      );
    }
    final requiredKeys = jsonStringList(gate.params['requiredKeys']);
    final missing = requiredKeys
        .where((key) => !decoded.containsKey(key))
        .toList(growable: false);
    final typeErrors = <String>[];
    final types = jsonMap(gate.params['types']);
    for (final entry in types.entries) {
      if (!decoded.containsKey(entry.key)) continue;
      final expected = entry.value.toString();
      if (!_matchesType(decoded[entry.key], expected)) {
        typeErrors.add('${entry.key}: expected $expected');
      }
    }
    if (missing.isNotEmpty || typeErrors.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'JSON schema requirements were not met.',
        now,
        {'missing': missing, 'typeErrors': typeErrors},
      );
    }
    return _result(
      gate,
      _passStatus(gate),
      'JSON schema requirements passed.',
      now,
    );
  }

  Future<TaskGateResult> workspaceCleanEnough(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final git = await _sandbox.inspectPath(workspace.rootPath, '.git');
    if (!git.exists) {
      return _result(
        gate,
        TaskGateStatus.pending,
        'Workspace is not a git repository.',
        now,
      );
    }
    if (!workspace.commandExecutionApproved) {
      return _result(
        gate,
        TaskGateStatus.pending,
        'Terminal execution is required to check workspace cleanliness.',
        now,
      );
    }
    final result = await _sandbox.runCommand(
      workspace.rootPath,
      command: 'git',
      arguments: const ['status', '--porcelain'],
      cancellationToken: cancellationToken,
    );
    final exitCode = result.exitCode ?? -1;
    if (exitCode != 0) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'git status failed with exit code $exitCode.',
        now,
        {
          'command': result.command,
          'working_directory': result.workingDirectory,
          'exit_code': result.exitCode,
          'stdout': result.stdout,
          'stderr': result.stderr,
        },
      );
    }
    final stdout = result.stdout;
    if (stdout.trim().isNotEmpty && gate.required) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'Workspace has uncommitted changes.',
        now,
        {'status': stdout},
      );
    }
    return _result(
      gate,
      gate.required ? TaskGateStatus.passed : TaskGateStatus.advisory,
      stdout.trim().isEmpty
          ? 'Workspace is clean.'
          : 'Workspace has changes; advisory gate recorded them.',
      now,
      stdout.trim().isEmpty ? const {} : {'status': stdout},
    );
  }

  List<String> _gatePaths(TaskGate gate, List<TaskArtifact> artifacts) {
    final paths = jsonStringList(gate.params['paths']);
    if (paths.isNotEmpty) return paths;
    final single = jsonString(gate.params['path']);
    if (single.isNotEmpty) return [single];
    return artifacts.map((artifact) => artifact.path).toList();
  }

  String _gatePath(TaskGate gate) {
    final single = jsonString(gate.params['path']);
    if (single.isNotEmpty) return single;
    final paths = jsonStringList(gate.params['paths']);
    if (paths.isNotEmpty) return paths.first;
    throw StateError('Gate ${gate.id} requires a path.');
  }

  Future<String> _readGateFile(
    WorkspaceAttachment workspace,
    TaskGate gate,
    CancellationToken? cancellationToken,
  ) async {
    final result = await _sandbox.readFile(
      workspace.rootPath,
      _gatePath(gate),
      cancellationToken: cancellationToken,
    );
    return result.content;
  }

  String _workspaceEntryTypeName(WorkspaceEntryKind? kind) => switch (kind) {
    WorkspaceEntryKind.file => 'file',
    WorkspaceEntryKind.directory => 'directory',
    WorkspaceEntryKind.link => 'link',
    null => 'not_found',
  };

  bool _matchesType(Object? value, String expected) {
    return switch (expected) {
      'string' => value is String,
      'number' => value is num,
      'int' || 'integer' => value is int,
      'boolean' || 'bool' => value is bool,
      'array' || 'list' => value is List,
      'object' || 'map' => value is Map,
      'null' => value == null,
      _ => true,
    };
  }

  bool _looksLikeWellFormedXml(String content) {
    if (!content.startsWith('<') || !content.endsWith('>')) return false;
    final stack = <String>[];
    final tagPattern = RegExp(r'<\s*(/)?\s*([A-Za-z_][\w:.-]*)([^>]*)>');
    for (final match in tagPattern.allMatches(content)) {
      final full = match.group(0) ?? '';
      if (full.startsWith('<?') || full.startsWith('<!--')) continue;
      final closing = match.group(1) == '/';
      final name = match.group(2) ?? '';
      final suffix = match.group(3) ?? '';
      if (full.startsWith('<!') || suffix.trim().endsWith('/')) continue;
      if (closing) {
        if (stack.isEmpty || stack.removeLast() != name) return false;
      } else {
        stack.add(name);
      }
    }
    return stack.isEmpty;
  }

  TaskGateStatus _passStatus(TaskGate gate) =>
      gate.required ? TaskGateStatus.passed : TaskGateStatus.advisory;

  TaskGateResult _result(
    TaskGate gate,
    TaskGateStatus status,
    String summary,
    DateTime evaluatedAt, [
    Map<String, dynamic> details = const {},
    TaskGateFailureDisposition? failureDisposition,
  ]) {
    return TaskGateResult(
      gateId: gate.id,
      status: status,
      summary: summary,
      details: {
        'required': gate.required,
        'scope': gate.scope,
        if (gate.description?.trim().isNotEmpty == true)
          'description': gate.description,
        ...details,
      },
      failureDisposition:
          failureDisposition ??
          (status == TaskGateStatus.failed
              ? TaskGateFailureDisposition.repairable
              : null),
      evaluatedAt: evaluatedAt,
    );
  }
}
