import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/terminal_command_classifier.dart';
import 'package:hermes/core/services/terminal_command_parser.dart';
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

class TaskGateEvidence {
  final List<TaskToolCallRecord> stepToolCalls;
  final List<TaskToolCallRecord> taskToolCalls;
  final List<TaskArtifact> stepArtifacts;
  final List<TaskArtifact> taskArtifacts;

  const TaskGateEvidence({
    required this.stepToolCalls,
    required this.taskToolCalls,
    required this.stepArtifacts,
    required this.taskArtifacts,
  });
}

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
    List<TaskToolCallRecord> toolCalls = const [],
    List<TaskArtifact> artifacts = const [],
    TaskGateEvidence? evidence,
    ChatClient? client,
    String baseSystemPrompt = '',
    CancellationToken? cancellationToken,
  }) async {
    final results = <TaskGateResult>[];
    for (final gate in gates) {
      cancellationToken?.throwIfCancelled();
      final taskScoped = gate.scope.trim().toLowerCase() == 'task';
      results.add(
        await _evaluateGate(
          workspace: workspace,
          task: task,
          step: step,
          gate: gate,
          toolCalls: evidence == null
              ? toolCalls
              : taskScoped
              ? evidence.taskToolCalls
              : evidence.stepToolCalls,
          artifacts: evidence == null
              ? artifacts
              : taskScoped
              ? evidence.taskArtifacts
              : evidence.stepArtifacts,
          client: client,
          baseSystemPrompt: baseSystemPrompt,
          cancellationToken: cancellationToken,
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
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
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
        'no_failed_commands' => _noFailedCommands(
          task,
          step,
          gate,
          toolCalls,
          now,
        ),
        'content_contains' => await _contentContains(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'content_not_contains' => await _contentNotContains(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'json_valid' => await _jsonValid(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'yaml_valid' => await _yamlValid(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'xml_valid' => await _xmlValid(workspace, gate, now, cancellationToken),
        'markdown_links_valid' => await _markdownLinksValid(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'schema_matches' => await _schemaMatches(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'workspace_clean_enough' => await _workspaceCleanEnough(
          workspace,
          gate,
          now,
          cancellationToken,
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
          cancellationToken,
        ),
        _ => _result(
          gate,
          TaskGateStatus.advisory,
          'Unknown gate "${gate.id}" was ignored.',
          now,
        ),
      };
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
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
    for (var i = toolCalls.length - 1; i > lastMutation; i--) {
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
        gate.required
            ? 'Required verification command failed with exit code $exitCode: $commandText.'
            : 'Advisory verification command failed with exit code $exitCode: $commandText.',
        now,
        {'command': commandText, 'exitCode': exitCode},
      );
    }
    return _result(
      gate,
      TaskGateStatus.pending,
      gate.required
          ? 'Required verification command has not run after the last workspace mutation: $commandText.'
          : 'Advisory verification command was not run after the last workspace mutation: $commandText.',
      now,
      {'command': commandText, 'workingDirectory': workingDirectory},
    );
  }

  TaskGateResult _noToolErrors(
    TaskGate gate,
    List<TaskToolCallRecord> toolCalls,
    DateTime now,
  ) {
    final advisory = <Map<String, String>>[];
    final resolved = <Map<String, String>>[];
    final unresolved = <Map<String, String>>[];

    for (var i = 0; i < toolCalls.length; i++) {
      final call = toolCalls[i];
      if (call.toolName == 'finish_task_step') continue;
      final error = _effectiveToolError(call);
      if (error == null) continue;
      final operationKey = _operationKey(call);
      final entry = <String, String>{
        'callId': call.id,
        'stepId': call.stepId,
        'runId': call.runId,
        'toolName': call.toolName,
        'operationKey': operationKey,
        'code': error.code,
        'message': error.message,
        'disposition': error.disposition.wire,
      };
      if (error.disposition == TaskToolErrorDisposition.advisory) {
        advisory.add(entry);
        continue;
      }
      final resolvingCall = toolCalls.indexed
          .skip(i + 1)
          .where(
            (indexed) =>
                _operationKey(indexed.$2) == operationKey &&
                _callSucceeded(indexed.$2),
          )
          .map((indexed) => indexed.$2)
          .firstOrNull;
      if (resolvingCall != null) {
        resolved.add({...entry, 'resolvedByCallId': resolvingCall.id});
      } else {
        unresolved.add(entry);
      }
    }

    if (unresolved.isNotEmpty) {
      final blocking = unresolved.any(
        (entry) => entry['disposition'] == TaskToolErrorDisposition.fatal.wire,
      );
      final origins = unresolved
          .map((entry) => '${entry['toolName']} in step ${entry['stepId']}')
          .toSet()
          .join(', ');
      return _result(
        gate,
        TaskGateStatus.failed,
        'Unresolved tool errors must be fixed before completion: $origins.',
        now,
        {
          'unresolvedErrors': unresolved,
          if (resolved.isNotEmpty) 'resolvedErrors': resolved,
          if (advisory.isNotEmpty) 'advisoryErrors': advisory,
        },
        blocking
            ? TaskGateFailureDisposition.blocking
            : TaskGateFailureDisposition.repairable,
      );
    }

    return _result(
      gate,
      _passStatus(gate),
      advisory.isEmpty && resolved.isEmpty
          ? 'No unresolved tool errors.'
          : 'No unresolved tool errors. ${advisory.length} advisory and ${resolved.length} resolved error(s) were recorded.',
      now,
      {
        if (resolved.isNotEmpty) 'resolvedErrors': resolved,
        if (advisory.isNotEmpty) 'advisoryErrors': advisory,
      },
    );
  }

  TaskToolError? _effectiveToolError(TaskToolCallRecord call) {
    return call.effectiveToolError;
  }

  TaskGateResult _noFailedCommands(
    TaskDocument task,
    TaskStep step,
    TaskGate gate,
    List<TaskToolCallRecord> toolCalls,
    DateTime now,
  ) {
    final advisoryCommands = _advisoryCommandKeys(task, step, gate);
    final latestCommands = <String, TaskToolCallRecord>{};
    final lastMutation = _lastMutationIndex(toolCalls);
    for (var i = lastMutation + 1; i < toolCalls.length; i++) {
      final call = toolCalls[i];
      if (call.toolName != 'run_command') continue;
      latestCommands[_operationKey(call)] = call;
    }
    final failed = <Map<String, dynamic>>[];
    final advisoryFailed = <Map<String, dynamic>>[];
    for (final call in latestCommands.values) {
      final result = _resultSummaryMap(call);
      final exitCode = _effectiveToolError(call) == null
          ? jsonInt(result['exit_code'], fallback: 0)
          : -1;
      if (exitCode != 0) {
        final failure = <String, dynamic>{
          'command': result['command'] ?? _commandText(call),
          'exitCode': exitCode,
        };
        if (advisoryCommands.contains(_commandKeyFromCall(call))) {
          advisoryFailed.add(failure);
          continue;
        }
        failed.add(failure);
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
      advisoryFailed.isEmpty
          ? 'No failed commands after the last workspace mutation.'
          : 'No blocking command failures after the last workspace mutation. ${advisoryFailed.length} advisory verification command(s) failed.',
      now,
      {if (advisoryFailed.isNotEmpty) 'advisoryFailures': advisoryFailed},
    );
  }

  Set<String> _advisoryCommandKeys(
    TaskDocument task,
    TaskStep step,
    TaskGate noFailedGate,
  ) {
    final taskScoped = noFailedGate.scope.trim().toLowerCase() == 'task';
    final gates = taskScoped
        ? <TaskGate>[
            ...task.gates,
            for (final taskStep in task.steps) ...taskStep.gates,
          ]
        : step.gates;
    final required = <String>{};
    final advisory = <String>{};
    for (final gate in gates) {
      if (gate.id != 'command_passes') continue;
      final key = _commandKeyFromGate(gate);
      if (key == null) continue;
      (gate.required ? required : advisory).add(key);
    }
    return advisory.difference(required);
  }

  String? _commandKeyFromGate(TaskGate gate) {
    final command = _commandTextFromParts(
      jsonString(gate.params['command']),
      jsonStringList(gate.params['args']),
    );
    if (command.isEmpty) return null;
    final cwd = path.normalize(
      jsonString(
        gate.params['working_directory'] ?? gate.params['workingDirectory'],
        fallback: '.',
      ),
    );
    return '$cwd\x00$command';
  }

  String _commandKeyFromCall(TaskToolCallRecord call) {
    final arguments = jsonMap(call.arguments);
    final command = _commandTextFromParts(
      jsonString(arguments['command']),
      jsonStringList(arguments['args']),
    );
    final cwd = path.normalize(
      jsonString(
        arguments['working_directory'] ?? arguments['workingDirectory'],
        fallback: '.',
      ),
    );
    return '$cwd\x00$command';
  }

  Future<TaskGateResult> _contentContains(
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

  Future<TaskGateResult> _contentNotContains(
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

  Future<TaskGateResult> _jsonValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final content = await _readGateFile(workspace, gate, cancellationToken);
    jsonDecode(content);
    return _result(gate, _passStatus(gate), 'JSON is valid.', now);
  }

  Future<TaskGateResult> _yamlValid(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
  ) async {
    final content = await _readGateFile(workspace, gate, cancellationToken);
    loadYaml(content);
    return _result(gate, _passStatus(gate), 'YAML is valid.', now);
  }

  Future<TaskGateResult> _xmlValid(
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

  Future<TaskGateResult> _markdownLinksValid(
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

  Future<TaskGateResult> _workspaceCleanEnough(
    WorkspaceAttachment workspace,
    TaskGate gate,
    DateTime now,
    CancellationToken? cancellationToken,
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
      cancellationToken: cancellationToken,
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
    CancellationToken? cancellationToken,
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
      cancellationToken: cancellationToken,
      diagnosticsLabel: 'Task gate review',
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
    CancellationToken? cancellationToken,
  ) async {
    final result = await _sandbox.readFile(
      workspace.rootPath,
      _gatePath(gate),
      cancellationToken: cancellationToken,
    );
    return result['content'] as String;
  }

  int _lastMutationIndex(List<TaskToolCallRecord> toolCalls) {
    var index = -1;
    for (var i = 0; i < toolCalls.length; i++) {
      if (_callSucceeded(toolCalls[i]) && _isMutatingCall(toolCalls[i])) {
        index = i;
      }
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

  bool _callSucceeded(TaskToolCallRecord call) {
    if (_effectiveToolError(call) != null) return false;
    if (call.outcome != TaskToolCallOutcome.succeeded) return false;
    if (call.toolName != 'run_command') return true;
    return jsonInt(_resultSummaryMap(call)['exit_code'], fallback: 0) == 0;
  }

  String _operationKey(TaskToolCallRecord call) {
    final recorded = call.operationKey?.trim();
    if (recorded != null && recorded.isNotEmpty) return recorded;
    final arguments = jsonMap(call.arguments);
    String normalisePath(Object? value) {
      final raw = value?.toString().trim() ?? '';
      return raw.isEmpty ? '.' : path.normalize(raw);
    }

    return switch (call.toolName) {
      'read_file' => 'read:${normalisePath(arguments['path'])}',
      'list_directory' => 'list:${normalisePath(arguments['path'])}',
      'search_files' =>
        'search:${normalisePath(arguments['path'])}:${jsonString(arguments['query']).trim()}',
      'write_file' ||
      'patch_file' => 'write:${normalisePath(arguments['path'])}',
      'create_directory' => 'mkdir:${normalisePath(arguments['path'])}',
      'delete_path' => 'delete:${normalisePath(arguments['path'])}',
      'rename_path' =>
        'rename:${normalisePath(arguments['from'])}->${normalisePath(arguments['to'])}',
      'run_command' =>
        'command:${path.normalize(jsonString(arguments['working_directory'] ?? arguments['workingDirectory'], fallback: '.'))}:${_commandText(call)}',
      _ => call.toolName,
    };
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
    return TerminalCommandParser.commandTextFromParts(command, args);
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
