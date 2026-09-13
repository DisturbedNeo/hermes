import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/task_system/task_gate_evaluator.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;

void main() {
  group('TaskGateEvaluator', () {
    late Directory root;
    late WorkspaceAttachment workspace;
    late TaskGateEvaluator evaluator;
    late Task task;
    late TaskStep step;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_gate_test_');
      workspace = WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      evaluator = TaskGateEvaluator();
      step = const TaskStep(
        id: 'step_1',
        title: 'Step',
        objective: 'Work',
        instructions: ['Work'],
        mayEditFiles: true,
        artifacts: [TaskArtifact(path: 'out.md')],
        status: TaskStepStatus.pending,
      );
      task = Task(
        id: 'task_1',
        title: 'Task',
        originalPrompt: 'Do work',
        objective: 'Do work',
        constraints: const [],
        successCriteria: const ['Done'],
        steps: [step],
        status: TaskStatus.paused,
        currentStepId: step.id,
        memorySummary: '',
        runs: const [],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('artifact gates pass and fail deterministically', () async {
      await File(path.join(root.path, 'out.md')).writeAsString('done');

      final passed = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [
          TaskGate(
            id: 'artifact_exists',
            params: {
              'paths': ['out.md'],
            },
          ),
          TaskGate(
            id: 'artifact_nonempty',
            params: {
              'paths': ['out.md'],
            },
          ),
        ],
        toolCalls: const [],
        artifacts: const [TaskArtifact(path: 'out.md')],
      );

      expect(
        passed.results.map((result) => result.status),
        everyElement(TaskGateStatus.passed),
      );
      expect(passed.results.first.details['paths'], ['out.md']);
      expect(passed.results.last.details['paths'], ['out.md']);

      final failed = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [
          TaskGate(
            id: 'artifact_exists',
            params: {
              'paths': ['missing.md'],
            },
          ),
        ],
        toolCalls: const [],
        artifacts: const [],
      );

      expect(failed.results.single.status, TaskGateStatus.failed);
    });

    test(
      'directory artifacts do not use file length for non-empty checks',
      () async {
        await Directory(path.join(root.path, 'output')).create();
        final directoryStep = step.copyWith(
          artifacts: const [TaskArtifact(path: 'output', kind: 'directory')],
        );

        final evaluation = await evaluator.evaluate(
          workspace: workspace,
          task: task,
          step: directoryStep,
          gates: const [
            TaskGate(
              id: 'artifact_nonempty',
              params: {
                'paths': ['output'],
              },
            ),
          ],
        );

        expect(evaluation.results.single.status, TaskGateStatus.passed);
      },
    );

    test('content gates fail safely for oversized files', () async {
      await File(path.join(root.path, 'out.md')).writeAsString(
        List.filled(WorkspaceSandbox.maxReadBytes + 1, 'x').join(),
      );

      final evaluation = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [
          TaskGate(
            id: 'content_contains',
            params: {
              'path': 'out.md',
              'contains': ['x'],
            },
          ),
        ],
      );

      expect(evaluation.results.single.status, TaskGateStatus.failed);
      expect(evaluation.results.single.summary, contains('too large'));
    });

    test('content gates propagate cancellation', () async {
      await File(path.join(root.path, 'out.md')).writeAsString('done');
      final token = CancellationToken();
      await token.cancel();

      await expectLater(
        evaluator.evaluate(
          workspace: workspace,
          task: task,
          step: step,
          gates: const [
            TaskGate(
              id: 'content_contains',
              params: {
                'path': 'out.md',
                'contains': ['done'],
              },
            ),
          ],
          cancellationToken: token,
        ),
        throwsA(isA<OperationCancelledException>()),
      );
    });

    test(
      'command_passes requires a matching zero exit command after mutation',
      () async {
        final gate = const TaskGate(
          id: 'command_passes',
          params: {'command': 'dart test', 'working_directory': '.'},
        );

        final pending = await evaluator.evaluate(
          workspace: workspace,
          task: task,
          step: step,
          gates: [gate],
          toolCalls: const [],
          artifacts: const [],
        );
        expect(pending.results.single.status, TaskGateStatus.pending);

        final failed = await evaluator.evaluate(
          workspace: workspace,
          task: task,
          step: step,
          gates: [gate],
          toolCalls: [
            _toolCall('patch_file', result: {'path': 'lib/a.dart'}),
            _toolCall(
              'run_command',
              arguments: {
                'command': 'dart',
                'args': ['test'],
                'working_directory': '.',
              },
              result: {'exit_code': 1, 'command': 'dart test'},
            ),
          ],
          artifacts: const [],
        );
        expect(failed.results.single.status, TaskGateStatus.failed);

        final passed = await evaluator.evaluate(
          workspace: workspace,
          task: task,
          step: step,
          gates: [gate],
          toolCalls: [
            _toolCall('patch_file', result: {'path': 'lib/a.dart'}),
            _toolCall(
              'run_command',
              arguments: {'command': 'dart test', 'working_directory': '.'},
              result: {'exit_code': 0, 'command': 'dart test'},
            ),
          ],
          artifacts: const [],
        );
        expect(passed.results.single.status, TaskGateStatus.passed);

        final passedWithTruncatedSummary = await evaluator.evaluate(
          workspace: workspace,
          task: task,
          step: step,
          gates: [gate],
          toolCalls: [
            _toolCall('patch_file', result: {'path': 'lib/a.dart'}),
            _toolCall(
              'run_command',
              arguments: {'command': 'dart test', 'working_directory': '.'},
              result: {
                'exit_code': 0,
                'command': 'dart test',
                'stdout': List.filled(5000, 'x').join(),
              },
              resultSummary: '{"command":"dart test","stdout":"truncated...',
            ),
          ],
          artifacts: const [],
        );
        expect(
          passedWithTruncatedSummary.results.single.status,
          TaskGateStatus.passed,
        );
      },
    );

    test('command arguments are matched with exact shell grouping', () async {
      const gate = TaskGate(
        id: 'command_passes',
        params: {
          'command': 'printf',
          'args': ['%s', 'hello world'],
          'working_directory': '.',
        },
      );

      final differentlyGrouped = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [gate],
        toolCalls: [
          _toolCall(
            'run_command',
            arguments: {
              'command': 'printf',
              'args': ['%s hello', 'world'],
              'working_directory': '.',
            },
            result: {'exit_code': 0},
          ),
        ],
        artifacts: const [],
      );
      expect(differentlyGrouped.results.single.status, TaskGateStatus.pending);

      final exact = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [gate],
        toolCalls: [
          _toolCall(
            'run_command',
            arguments: {
              'command': 'printf',
              'args': ['%s', 'hello world'],
              'working_directory': '.',
            },
            result: {'exit_code': 0},
          ),
        ],
        artifacts: const [],
      );
      expect(exact.results.single.status, TaskGateStatus.passed);
    });

    test(
      'advisory command failures remain evidence and do not fail no_failed_commands',
      () async {
        const advisoryGate = TaskGate(
          id: 'command_passes',
          required: false,
          params: {'command': 'dart analyze', 'working_directory': '.'},
        );
        final advisoryStep = step.copyWith(gates: const [advisoryGate]);
        final advisoryTask = task.copyWith(steps: [advisoryStep]);
        final evaluation = await evaluator.evaluate(
          workspace: workspace,
          task: advisoryTask,
          step: advisoryStep,
          gates: const [
            advisoryGate,
            TaskGate(id: 'no_failed_commands', scope: 'task'),
          ],
          toolCalls: [
            _toolCall(
              'run_command',
              arguments: {'command': 'dart analyze', 'working_directory': '.'},
              result: {'exit_code': 1, 'command': 'dart analyze'},
            ),
          ],
          artifacts: const [],
        );

        expect(evaluation.results.first.status, TaskGateStatus.failed);
        expect(evaluation.results.first.details['required'], isFalse);
        expect(evaluation.results.first.summary, startsWith('Advisory'));
        expect(evaluation.results.last.status, TaskGateStatus.passed);
        expect(
          evaluation.results.last.details['advisoryFailures'],
          hasLength(1),
        );
        expect(evaluation.hasRequiredFailure, isFalse);
      },
    );

    test('unrelated failed commands remain blocking', () async {
      const advisoryGate = TaskGate(
        id: 'command_passes',
        required: false,
        params: {'command': 'dart analyze', 'working_directory': '.'},
      );
      final advisoryStep = step.copyWith(gates: const [advisoryGate]);
      final advisoryTask = task.copyWith(steps: [advisoryStep]);
      final evaluation = await evaluator.evaluate(
        workspace: workspace,
        task: advisoryTask,
        step: advisoryStep,
        gates: const [TaskGate(id: 'no_failed_commands')],
        toolCalls: [
          _toolCall(
            'run_command',
            arguments: {'command': 'dart analyze'},
            result: {'exit_code': 1, 'command': 'dart analyze'},
          ),
          _toolCall(
            'run_command',
            arguments: {'command': 'dart --version'},
            result: {'exit_code': 1, 'command': 'dart --version'},
          ),
        ],
        artifacts: const [],
      );

      expect(evaluation.results.single.status, TaskGateStatus.failed);
      expect(evaluation.hasRequiredFailure, isTrue);
    });

    test('missing advisory commands use non-required wording', () async {
      const gate = TaskGate(
        id: 'command_passes',
        required: false,
        params: {'command': 'flutter test'},
      );
      final evaluation = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [gate],
        toolCalls: const [],
        artifacts: const [],
      );

      expect(evaluation.results.single.status, TaskGateStatus.pending);
      expect(evaluation.results.single.summary, startsWith('Advisory'));
      expect(evaluation.hasRequiredPending, isFalse);
    });

    test('no_tool_errors treats guard denials as recoverable evidence', () async {
      final evaluation = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [
          TaskGate(id: 'no_tool_errors'),
          TaskGate(id: 'no_failed_commands'),
        ],
        toolCalls: [
          _toolCall('read_file', error: 'Path not found.'),
          _toolCall('write_file', error: 'Use workspace-relative paths only.'),
          _toolCall(
            'run_command',
            error:
                'File deletion commands are blocked by terminal policy. Use workspace delete tools for scoped file removal.',
          ),
          _toolCall(
            'run_command',
            arguments: {
              'command': 'flutter',
              'args': ['test'],
            },
            result: {'exit_code': 1, 'command': 'flutter test'},
          ),
        ],
        artifacts: const [],
      );

      expect(evaluation.results.first.status, TaskGateStatus.passed);
      expect(evaluation.results.first.details['advisoryErrors'], hasLength(3));
      expect(evaluation.results.last.status, TaskGateStatus.failed);
    });

    test(
      'no_tool_errors treats legacy request-mode path failures as advisory',
      () async {
        final evaluation = await evaluator.evaluate(
          workspace: workspace,
          task: task,
          step: step,
          gates: const [TaskGate(id: 'no_tool_errors')],
          toolCalls: [
            _toolCall(
              'read_file',
              arguments: const {
                'path': 'lib/missing.dart',
                'request': 'Summarize this file.',
              },
              error: 'Failed to extract information: Path not found.',
              toolError: const TaskToolError(
                code: 'subagent_extraction_failed',
                message: 'Failed to extract information: Path not found.',
                disposition: TaskToolErrorDisposition.retryable,
              ),
              outcome: TaskToolCallOutcome.failed,
            ),
          ],
          artifacts: const [],
        );

        expect(evaluation.results.single.status, TaskGateStatus.passed);
        expect(
          evaluation.results.single.details['advisoryErrors'],
          hasLength(1),
        );
      },
    );

    test('no_tool_errors fails on unclassified tool failures', () async {
      final evaluation = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [TaskGate(id: 'no_tool_errors')],
        toolCalls: [_toolCall('read_file', error: 'Tool crashed.')],
        artifacts: const [],
      );

      expect(evaluation.results.single.status, TaskGateStatus.failed);
      expect(
        evaluation.results.single.details['unresolvedErrors'],
        hasLength(1),
      );
      expect(
        evaluation.results.single.summary,
        contains('read_file in step step_1'),
      );
      final unresolved =
          evaluation.results.single.details['unresolvedErrors'] as List;
      expect(unresolved.single['stepId'], 'step_1');
      expect(unresolved.single['runId'], 'run_1');
      expect(
        evaluation.results.single.failureDisposition,
        TaskGateFailureDisposition.blocking,
      );
    });

    test('no_tool_errors accepts a later successful equivalent call', () async {
      final evaluation = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [TaskGate(id: 'no_tool_errors')],
        toolCalls: [
          _toolCall(
            'patch_file',
            id: 'failed_patch',
            arguments: {'path': 'lib/a.dart'},
            error: 'Temporary tool failure.',
            toolError: const TaskToolError(
              code: 'workspace_io_failure',
              message: 'Temporary tool failure.',
              disposition: TaskToolErrorDisposition.retryable,
            ),
            outcome: TaskToolCallOutcome.failed,
          ),
          _toolCall(
            'patch_file',
            id: 'successful_patch',
            arguments: {'path': 'lib/a.dart'},
          ),
        ],
        artifacts: const [],
      );

      expect(evaluation.results.single.status, TaskGateStatus.passed);
      expect(evaluation.results.single.details['resolvedErrors'], hasLength(1));
    });

    test(
      'command gates use latest outcomes and successful mutations',
      () async {
        final calls = [
          _toolCall(
            'patch_file',
            id: 'mutation',
            arguments: {'path': 'lib/a.dart'},
          ),
          _toolCall(
            'run_command',
            id: 'failed_test',
            arguments: {'command': 'dart test', 'working_directory': '.'},
            result: {'exit_code': 1, 'command': 'dart test'},
          ),
          _toolCall(
            'run_command',
            id: 'passed_test',
            arguments: {'command': 'dart test', 'working_directory': '.'},
            result: {'exit_code': 0, 'command': 'dart test'},
          ),
          _toolCall(
            'patch_file',
            id: 'failed_patch',
            arguments: {'path': 'lib/a.dart'},
            error: 'Patch text was not found.',
            outcome: TaskToolCallOutcome.denied,
          ),
        ];
        final evaluation = await evaluator.evaluate(
          workspace: workspace,
          task: task,
          step: step,
          gates: const [
            TaskGate(
              id: 'command_passes',
              params: {'command': 'dart test', 'working_directory': '.'},
            ),
            TaskGate(id: 'no_failed_commands'),
          ],
          toolCalls: calls,
          artifacts: const [],
        );

        expect(
          evaluation.results.map((result) => result.status),
          everyElement(TaskGateStatus.passed),
        );
      },
    );

    test('gate evidence respects task and step scope', () async {
      final priorFailure = _toolCall(
        'read_file',
        id: 'prior_failure',
        error: 'Tool crashed.',
        outcome: TaskToolCallOutcome.failed,
      );
      final evaluation = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [
          TaskGate(id: 'no_tool_errors', scope: 'step'),
          TaskGate(id: 'no_tool_errors', scope: 'task'),
        ],
        evidence: TaskGateEvidence(
          stepToolCalls: const [],
          taskToolCalls: [priorFailure],
          stepArtifacts: const [],
          taskArtifacts: const [],
        ),
      );

      expect(evaluation.results.first.status, TaskGateStatus.passed);
      expect(evaluation.results.last.status, TaskGateStatus.failed);
    });

    test('content and parser gates validate files', () async {
      await File(
        path.join(root.path, 'report.md'),
      ).writeAsString('# Summary\nSources\nNo placeholders\n');
      await File(
        path.join(root.path, 'data.json'),
      ).writeAsString(jsonEncode({'name': 'Ada', 'count': 1}));
      await File(
        path.join(root.path, 'data.yaml'),
      ).writeAsString('name: Ada\n');
      await File(path.join(root.path, 'data.xml')).writeAsString('<root />');

      final evaluation = await evaluator.evaluate(
        workspace: workspace,
        task: task,
        step: step,
        gates: const [
          TaskGate(
            id: 'content_contains',
            params: {
              'path': 'report.md',
              'mustContain': ['Summary', 'Sources'],
            },
          ),
          TaskGate(
            id: 'content_not_contains',
            params: {
              'path': 'report.md',
              'mustNotContain': ['TODO', '[...]'],
            },
          ),
          TaskGate(id: 'json_valid', params: {'path': 'data.json'}),
          TaskGate(id: 'yaml_valid', params: {'path': 'data.yaml'}),
          TaskGate(id: 'xml_valid', params: {'path': 'data.xml'}),
          TaskGate(
            id: 'schema_matches',
            params: {
              'path': 'data.json',
              'requiredKeys': ['name'],
              'types': {'count': 'number'},
            },
          ),
        ],
        toolCalls: const [],
        artifacts: const [],
      );

      expect(
        evaluation.results.map((result) => result.status),
        everyElement(TaskGateStatus.passed),
      );
    });

    test(
      'model_review is advisory by default and human_approval is pending',
      () async {
        final evaluation = await evaluator.evaluate(
          workspace: workspace,
          task: task,
          step: step,
          gates: const [
            TaskGate(id: 'model_review', required: false),
            TaskGate(id: 'human_approval'),
          ],
          toolCalls: const [],
          artifacts: const [],
          client: _ReviewClient(),
        );

        expect(evaluation.results.first.status, TaskGateStatus.advisory);
        expect(evaluation.results.last.status, TaskGateStatus.pending);
        expect(evaluation.hasHumanApprovalPending, isTrue);
      },
    );
  });
}

TaskToolCallRecord _toolCall(
  String toolName, {
  String? id,
  Map<String, dynamic> arguments = const {},
  Map<String, dynamic> result = const {},
  String? resultSummary,
  String? error,
  TaskToolCallOutcome outcome = TaskToolCallOutcome.succeeded,
  TaskToolError? toolError,
}) {
  return TaskToolCallRecord(
    id: id ?? 'call_$toolName',
    stepId: 'step_1',
    runId: 'run_1',
    toolName: toolName,
    arguments: arguments,
    result: result,
    resultSummary: resultSummary ?? jsonEncode(result),
    error: error,
    outcome: outcome,
    toolError: toolError,
    timestamp: DateTime(2026, 1, 1),
  );
}

class _ReviewClient extends ChatClient {
  _ReviewClient() : super(baseUrl: 'http://localhost', model: 'test');

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    return ChatCompletionResponse(
      content: jsonEncode({'passed': false, 'summary': 'Needs polish.'}),
    );
  }

  @override
  void dispose() {}
}
