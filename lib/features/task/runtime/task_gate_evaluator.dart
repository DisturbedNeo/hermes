import 'dart:convert';

import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/model_json.dart';
import 'package:hermes/core/wire_case.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/model/application/model_capabilities.dart';
import 'package:hermes/features/model/application/model_errors.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/persistence/application/task_json.dart';
import 'package:hermes/features/workspace/application/terminal_command_classifier.dart';
import 'package:hermes/features/workspace/application/terminal_command_parser.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:hermes/features/task/application/yaml_validation_port.dart';
import 'package:hermes/features/task/runtime/task_gate_file_validation_service.dart';
import 'package:path/path.dart' as path;

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
  TaskGateEvaluator({
    required WorkspaceVerificationPort sandbox,
    required YamlValidationPort yamlValidator,
  }) {
    _fileValidation = TaskGateFileValidationService(
      sandbox: sandbox,
      yamlValidator: yamlValidator,
    );
  }

  late final TaskGateFileValidationService _fileValidation;

  Future<TaskGateEvaluation> evaluate({
    required WorkspaceAttachment workspace,
    required TaskAggregate task,
    required TaskStep step,
    required List<TaskGate> gates,
    List<TaskToolCallRecord> toolCalls = const [],
    List<TaskArtifact> artifacts = const [],
    TaskGateEvidence? evidence,
    ModelTextCompletionPort? client,
    String baseSystemPrompt = '',
    bool humanApprovalGranted = false,
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
          humanApprovalGranted: humanApprovalGranted,
          cancellationToken: cancellationToken,
        ),
      );
    }
    return TaskGateEvaluation(results: results);
  }

  Future<TaskGateResult> _evaluateGate({
    required WorkspaceAttachment workspace,
    required TaskAggregate task,
    required TaskStep step,
    required TaskGate gate,
    required List<TaskToolCallRecord> toolCalls,
    required List<TaskArtifact> artifacts,
    required ModelTextCompletionPort? client,
    required String baseSystemPrompt,
    required bool humanApprovalGranted,
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
        'artifact_exists' => await _fileValidation.artifactExists(
          workspace,
          gate,
          artifacts,
          now,
        ),
        'artifact_nonempty' => await _fileValidation.artifactNonempty(
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
        'content_contains' => await _fileValidation.contentContains(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'content_not_contains' => await _fileValidation.contentNotContains(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'json_valid' => await _fileValidation.jsonValid(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'yaml_valid' => await _fileValidation.yamlValid(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'xml_valid' => await _fileValidation.xmlValid(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'markdown_links_valid' => await _fileValidation.markdownLinksValid(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'schema_matches' => await _fileValidation.schemaMatches(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'workspace_clean_enough' => await _fileValidation.workspaceCleanEnough(
          workspace,
          gate,
          now,
          cancellationToken,
        ),
        'human_approval' =>
          humanApprovalGranted
              ? _result(
                  gate,
                  _passStatus(gate),
                  'Human approval was granted for this step.',
                  now,
                )
              : _result(
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
      final error = call.toolError;
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

  TaskGateResult _noFailedCommands(
    TaskAggregate task,
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
      final exitCode = call.toolError == null ? _runCommandExitCode(call) : -1;
      if (exitCode != 0) {
        final failure = <String, dynamic>{
          'command': result['command'] ?? _commandText(call),
        };
        if (exitCode == null) {
          failure['reason'] = 'missing_exit_code';
        } else {
          failure['exitCode'] = exitCode;
        }
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
    TaskAggregate task,
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

  Future<TaskGateResult> _modelReview(
    TaskAggregate task,
    TaskStep step,
    TaskGate gate,
    ModelTextCompletionPort? client,
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
Task objective:
${task.objective}

Step:
${jsonEncode(snakeCaseWire(ModelJson.encode(step)))}

Review instruction:
$prompt
''',
        ),
      ],
      cancellationToken: cancellationToken,
      diagnosticsLabel: 'Task gate review',
    );
    final json = TaskJson.tryParseObject(text);
    if (json == null || json['passed'] is! bool) {
      return _result(
        gate,
        gate.required ? TaskGateStatus.pending : TaskGateStatus.advisory,
        'Model review did not return a valid boolean decision.',
        now,
        {'invalidResponse': true},
      );
    }
    final passed = json['passed'] as bool;
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
    if (call.toolError != null) return false;
    if (call.outcome != TaskToolCallOutcome.succeeded) return false;
    if (call.toolName != 'run_command') return true;
    return _runCommandExitCode(call) == 0;
  }

  int? _runCommandExitCode(TaskToolCallRecord call) {
    if (call.toolName != 'run_command') return null;
    final result = _resultSummaryMap(call);
    if (!result.containsKey('exit_code')) return null;
    final raw = result['exit_code'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
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
