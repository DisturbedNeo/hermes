import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/terminal_command_classifier.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

const Set<String> kTaskGateCatalog = {
  'artifact_exists',
  'artifact_nonempty',
  'command_passes',
  'no_tool_errors',
  'no_failed_commands',
  'content_contains',
  'content_not_contains',
  'json_valid',
  'yaml_valid',
  'xml_valid',
  'markdown_links_valid',
  'schema_matches',
  'workspace_clean_enough',
  'human_approval',
  'model_review',
};

class TaskGateEvaluation {
  final List<TaskGateResult> results;

  const TaskGateEvaluation({required this.results});

  bool get hasRequiredFailure => results.any((result) {
    return result.status == TaskGateStatus.failed &&
        result.details['required'] == true;
  });

  bool get hasRequiredPending => results.any((result) {
    return result.status == TaskGateStatus.pending &&
        result.details['required'] == true;
  });

  bool get hasHumanApprovalPending => results.any((result) {
    return result.gateId == 'human_approval' &&
        result.status == TaskGateStatus.pending &&
        result.details['required'] == true;
  });

  String get blockingSummary {
    final blockers = results.where((result) {
      final required = result.details['required'] == true;
      return required &&
          (result.status == TaskGateStatus.failed ||
              result.status == TaskGateStatus.pending);
    }).toList();
    if (blockers.isEmpty) return 'All required gates passed.';
    return blockers.map((result) => result.summary).join('\n');
  }
}

class TaskGateEvaluator {
  TaskGateEvaluator({WorkspaceSandbox? sandbox})
    : _sandbox = sandbox ?? WorkspaceSandbox();

  final WorkspaceSandbox _sandbox;

  Future<TaskGateEvaluation> evaluate({
    required WorkspaceAttachment workspace,
    required TaskDocument task,
    required TaskStep step,
    required List<TaskGate> gates,
    required List<TaskToolCallRecord> toolCalls,
    required List<TaskArtifact> artifacts,
    ChatClient? client,
    String baseSystemPrompt = '',
  }) async {
    final results = <TaskGateResult>[];
    for (final gate in gates) {
      results.add(
        await _evaluateGate(
          workspace: workspace,
          task: task,
          step: step,
          gate: gate,
          toolCalls: toolCalls,
          artifacts: artifacts,
          client: client,
          baseSystemPrompt: baseSystemPrompt,
        ),
      );
    }
    return TaskGateEvaluation(results: results);
  }

  Future<TaskGateResult> _evaluateGate({
    required WorkspaceAttachment workspace,
    required TaskDocument task,
    required TaskStep step,
    required TaskGate gate,
    required List<TaskToolCallRecord> toolCalls,
    required List<TaskArtifact> artifacts,
    required ChatClient? client,
    required String baseSystemPrompt,
  }) async {
    final now = DateTime.now();
    if (!kTaskGateCatalog.contains(gate.id)) {
      return _result(
        gate,
        TaskGateStatus.advisory,
        'Unknown gate "${gate.id}" was ignored.',
        now,
        {'unknown': true},
      );
    }

    try {
      return switch (gate.id) {
        'artifact_exists' => await _artifactExists(
          workspace,
          gate,
          artifacts,
          now,
        ),
        'artifact_nonempty' => await _artifactNonempty(
          workspace,
          gate,
          artifacts,
          now,
        ),
        'command_passes' => _commandPasses(gate, toolCalls, now),
        'no_tool_errors' => _noToolErrors(gate, toolCalls, now),
        'no_failed_commands' => _noFailedCommands(gate, toolCalls, now),
        'content_contains' => await _contentContains(workspace, gate, now),
        'content_not_contains' => await _contentNotContains(
          workspace,
          gate,
          now,
        ),
        'json_valid' => await _jsonValid(workspace, gate, now),
        'yaml_valid' => await _yamlValid(workspace, gate, now),
        'xml_valid' => await _xmlValid(workspace, gate, now),
        'markdown_links_valid' => await _markdownLinksValid(
          workspace,
          gate,
          now,
        ),
        'schema_matches' => await _schemaMatches(workspace, gate, now),
        'workspace_clean_enough' => await _workspaceCleanEnough(
          workspace,
          gate,
          now,
        ),
        'human_approval' => _result(
          gate,
          TaskGateStatus.pending,
          'Human approval is required before this step can complete.',
          now,
        ),
        'model_review' => await _modelReview(
          task,
          step,
          gate,
          client,
          baseSystemPrompt,
          now,
        ),
        _ => _result(
          gate,
          TaskGateStatus.advisory,
          'Unknown gate "${gate.id}" was ignored.',
          now,
        ),
      };
    } catch (e) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'Gate ${gate.id} failed: $e',
        now,
      );
    }
  }

  Future<TaskGateResult> _artifactExists(
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
      final resolved = await _sandbox.resolve(
        workspace.rootPath,
        item,
        mustExist: false,
      );
      if (await FileSystemEntity.type(resolved.absolutePath) ==
          FileSystemEntityType.notFound) {
        missing.add(resolved.relativePath);
      }
    }
    if (missing.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'Required artifacts are missing: ${missing.join(', ')}.',
        now,
        {'missing': missing},
      );
    }
    return _result(gate, _passStatus(gate), 'Required artifacts exist.', now);
  }

  Future<TaskGateResult> _artifactNonempty(
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
    for (final item in paths) {
      final resolved = await _sandbox.resolve(
        workspace.rootPath,
        item,
        mustExist: false,
      );
      final file = File(resolved.absolutePath);
      if (!await file.exists() || await file.length() == 0) {
        empty.add(resolved.relativePath);
      }
    }
    if (empty.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'Required artifacts are empty or missing: ${empty.join(', ')}.',
        now,
        {'empty': empty},
      );
    }
    return _result(
      gate,
      _passStatus(gate),
      'Required artifacts are non-empty.',
      now,
    );
  }

  TaskGateResult _commandPasses(
    TaskGate gate,
    List<TaskToolCallRecord> toolCalls,
    DateTime now,
  ) {
    final command = jsonString(gate.params['command']);
    final args = jsonStringList(gate.params['args']);
    final commandText = _commandTextFromParts(command, args);
    final workingDirectory = jsonString(
      gate.params['working_directory'] ?? gate.params['workingDirectory'],
      fallback: '.',
    );
    if (commandText.isEmpty) {
      return _result(
        gate,
        TaskGateStatus.pending,
        'command_passes gate is missing a command.',
        now,
      );
    }

    final lastMutation = _lastMutationIndex(toolCalls);
    for (var i = lastMutation + 1; i < toolCalls.length; i++) {
      final call = toolCalls[i];
      if (call.toolName != 'run_command') continue;
      final callArgs = jsonMap(call.arguments);
      if (_commandTextFromParts(
            jsonString(callArgs['command']),
            jsonStringList(callArgs['args']),
          ) !=
          commandText) {
        continue;
      }
      final cwd = jsonString(
        callArgs['working_directory'] ?? callArgs['workingDirectory'],
        fallback: '.',
      );
      if (path.normalize(cwd) != path.normalize(workingDirectory)) continue;
      final result = _resultSummaryMap(call);
      final exitCode = jsonInt(result['exit_code'], fallback: -1);
      if (exitCode == 0) {
        return _result(
          gate,
          _passStatus(gate),
          'Verification command passed: $commandText.',
          now,
          {'command': commandText, 'workingDirectory': cwd},
        );
      }
      return _result(
        gate,
        TaskGateStatus.failed,
        'Verification command failed with exit code $exitCode: $commandText.',
        now,
        {'command': commandText, 'exitCode': exitCode},
      );
    }
    return _result(
      gate,
      TaskGateStatus.pending,
      'Required verification command has not run after the last workspace mutation: $commandText.',
      now,
      {'command': commandText, 'workingDirectory': workingDirectory},
    );
  }

  TaskGateResult _noToolErrors(
    TaskGate gate,
    List<TaskToolCallRecord> toolCalls,
    DateTime now,
  ) {
    final unresolved = <Map<String, String>>[];
    final recoverable = <Map<String, String>>[];

    for (final call in toolCalls) {
      if (call.toolName == 'finish_task_step') continue;
      final error = call.error?.trim();
      if (error == null || error.isEmpty) continue;

      final category = _recoverableToolErrorCategory(call, error);
      final entry = <String, String>{'toolName': call.toolName, 'error': error};
      if (category != null) entry['category'] = category;
      if (category == null) {
        unresolved.add(entry);
      } else {
        recoverable.add(entry);
      }
    }

    if (unresolved.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'Unresolved tool errors must be fixed before completion.',
        now,
        {
          'errors': unresolved,
          if (recoverable.isNotEmpty) 'recoverableErrors': recoverable,
        },
      );
    }

    return _result(
      gate,
      _passStatus(gate),
      recoverable.isEmpty
          ? 'No unresolved tool errors.'
          : 'No unresolved tool errors. ${recoverable.length} recoverable tool guard issue(s) were recorded.',
      now,
      recoverable.isEmpty ? const {} : {'recoverableErrors': recoverable},
    );
  }

  String? _recoverableToolErrorCategory(TaskToolCallRecord call, String error) {
    final normalised = error.toLowerCase();
    final result = _resultSummaryMap(call);
    final reason = jsonNullableString(result['reason'])?.toLowerCase() ?? '';

    if (_containsAny(normalised, const [
      'blocked by terminal policy',
      'shell command substitution is blocked',
      'find -delete is blocked',
      'git clean is blocked',
      'git reset --hard is blocked',
      'terminal command is not whitelisted',
      'terminal commands are disabled',
      'tool is not available for this task step',
      'read-only steps may only',
      'read-only steps cannot',
      'task steps may only create artifacts',
      'use workspace-relative paths only',
      'path escapes the workspace',
      'refusing to delete the workspace root',
    ])) {
      return 'guard_denial';
    }

    if (_containsAny(normalised, const [
      'path not found',
      'path is not a directory',
      'path is a directory',
      'file is too large to read',
      'patch text was not found',
      'search returned too many results',
      'search results are too large',
      'no existing parent directory found',
    ])) {
      return 'workspace_validation';
    }

    if (_containsAny(normalised, const [
      'arguments must be a json object',
      'formatexception',
      'is not a subtype of type',
      'requires a path',
      'requires string content',
      'command is required',
      'search query is required',
    ])) {
      return 'invalid_tool_arguments';
    }

    if (normalised == 'tool call skipped by task runner.' &&
        reason.contains('repeated the same tool call')) {
      return 'loop_guard';
    }

    return null;
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  TaskGateResult _noFailedCommands(
    TaskGate gate,
    List<TaskToolCallRecord> toolCalls,
    DateTime now,
  ) {
    final failed = <Map<String, dynamic>>[];
    final lastMutation = _lastMutationIndex(toolCalls);
    for (var i = lastMutation + 1; i < toolCalls.length; i++) {
      final call = toolCalls[i];
      if (call.toolName != 'run_command') continue;
      final result = _resultSummaryMap(call);
      final exitCode = jsonInt(result['exit_code'], fallback: 0);
      if (exitCode != 0) {
        failed.add({
          'command': result['command'] ?? _commandText(call),
          'exitCode': exitCode,
        });
      }
    }
    if (failed.isNotEmpty) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'A command failed after the last workspace mutation.',
        now,
        {'failedCommands': failed},
      );
    }
    return _result(
      gate,
      _passStatus(gate),
      'No failed commands after the last workspace mutation.',
      now,
    );
  }

  Future<TaskGateResult> _contentContains(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
  ) async {
    final content = await _readGateFile(workspace, gate);
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

  Future<TaskGateResult> _contentNotContains(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
  ) async {
    final content = await _readGateFile(workspace, gate);
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

  Future<TaskGateResult> _jsonValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
  ) async {
    final content = await _readGateFile(workspace, gate);
    jsonDecode(content);
    return _result(gate, _passStatus(gate), 'JSON is valid.', now);
  }

  Future<TaskGateResult> _yamlValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
  ) async {
    final content = await _readGateFile(workspace, gate);
    loadYaml(content);
    return _result(gate, _passStatus(gate), 'YAML is valid.', now);
  }

  Future<TaskGateResult> _xmlValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
  ) async {
    final content = (await _readGateFile(workspace, gate)).trim();
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

  Future<TaskGateResult> _markdownLinksValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
  ) async {
    final filePath = _gatePath(gate);
    final content = await _readGateFile(workspace, gate);
    final missing = <String>[];
    final linkPattern = RegExp(r'\[[^\]]+\]\(([^)]+)\)');
    for (final match in linkPattern.allMatches(content)) {
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
      final resolved = await _sandbox.resolve(
        workspace.rootPath,
        relative,
        mustExist: false,
      );
      if (await FileSystemEntity.type(resolved.absolutePath) ==
          FileSystemEntityType.notFound) {
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

  Future<TaskGateResult> _schemaMatches(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
  ) async {
    final content = await _readGateFile(workspace, gate);
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

  Future<TaskGateResult> _workspaceCleanEnough(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
  ) async {
    final git = Directory(path.join(workspace.rootPath, '.git'));
    if (!await git.exists()) {
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
      executable: 'git',
      arguments: const ['status', '--porcelain'],
    );
    final exitCode = jsonInt(result['exit_code'], fallback: -1);
    if (exitCode != 0) {
      return _result(
        gate,
        TaskGateStatus.failed,
        'git status failed with exit code $exitCode.',
        now,
        result,
      );
    }
    final stdout = jsonString(result['stdout']);
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

  Future<TaskGateResult> _modelReview(
    TaskDocument task,
    TaskStep step,
    TaskGate gate,
    ChatClient? client,
    String baseSystemPrompt,
    DateTime now,
  ) async {
    if (client == null) {
      return _result(
        gate,
        gate.required ? TaskGateStatus.pending : TaskGateStatus.advisory,
        'Model review was not available.',
        now,
      );
    }
    final prompt = jsonString(
      gate.params['prompt'],
      fallback:
          'Review whether the completed step appears to satisfy the goal. Return JSON {"passed": true|false, "summary": "..."}',
    );
    final text = await client.completeMessage(
      messages: [
        ChatMessage(
          role: 'system',
          content:
              '$baseSystemPrompt\n\nYou are a read-only task completion reviewer. Do not request tools. Return only JSON.',
        ),
        ChatMessage(
          role: 'user',
          content:
              '''
Task goal:
${task.goal}

Step:
${jsonEncode(ModelJson.encode(step))}

Review instruction:
$prompt
''',
        ),
      ],
    );
    final json = TaskJson.tryParseObject(text) ?? const <String, dynamic>{};
    final passed = jsonBool(json['passed'], fallback: true);
    final summary = jsonString(
      json['summary'],
      fallback: passed ? 'Model review passed.' : 'Model review failed.',
    );
    if (!passed && gate.required) {
      return _result(gate, TaskGateStatus.failed, summary, now, json);
    }
    return _result(
      gate,
      gate.required ? TaskGateStatus.passed : TaskGateStatus.advisory,
      summary,
      now,
      json,
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
  ) async {
    final resolved = await _sandbox.resolve(
      workspace.rootPath,
      _gatePath(gate),
    );
    final file = File(resolved.absolutePath);
    if (!await file.exists()) {
      throw StateError('File not found: ${resolved.relativePath}');
    }
    return file.readAsString();
  }

  int _lastMutationIndex(List<TaskToolCallRecord> toolCalls) {
    var index = -1;
    for (var i = 0; i < toolCalls.length; i++) {
      if (_isMutatingCall(toolCalls[i])) index = i;
    }
    return index;
  }

  bool _isMutatingCall(TaskToolCallRecord call) {
    if (const {
      'write_file',
      'patch_file',
      'create_directory',
      'rename_path',
      'delete_path',
    }.contains(call.toolName)) {
      return true;
    }
    if (call.toolName != 'run_command') return false;
    return TerminalCommandClassifier.isClearlyMutating(
      TerminalCommandClassifier.classify(_commandText(call)),
    );
  }

  Map<String, dynamic> _resultSummaryMap(TaskToolCallRecord call) {
    final structured = call.result;
    if (structured is Map<String, dynamic>) return structured;
    if (structured is Map) return Map<String, dynamic>.from(structured);
    final summary = call.resultSummary;
    if (summary == null) return const {};
    return TaskJson.tryParseObject(summary) ?? const {};
  }

  String _commandText(TaskToolCallRecord call) {
    final args = jsonMap(call.arguments);
    final command = jsonString(args['command']);
    final commandArgs = jsonStringList(args['args']);
    return _commandTextFromParts(command, commandArgs);
  }

  String _commandTextFromParts(String command, List<String> args) {
    return [command, ...args].where((item) => item.isNotEmpty).join(' ').trim();
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

  TaskGateStatus _passStatus(TaskGate gate) {
    return gate.required ? TaskGateStatus.passed : TaskGateStatus.advisory;
  }

  TaskGateResult _result(
    TaskGate gate,
    TaskGateStatus status,
    String summary,
    DateTime evaluatedAt, [
    Map<String, dynamic> details = const {},
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
      evaluatedAt: evaluatedAt,
    );
  }
}
