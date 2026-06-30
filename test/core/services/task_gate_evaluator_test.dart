import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/task_system/task_gate_evaluator.dart';
import 'package:path/path.dart' as path;

void main() {
  group('TaskGateEvaluator', () {
    late Directory root;
    late WorkspaceAttachment workspace;
    late TaskGateEvaluator evaluator;
    late TaskDocument task;
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
      task = TaskDocument(
        id: 'task_1',
        title: 'Task',
        originalPrompt: 'Do work',
        goal: 'Do work',
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
      expect(
        evaluation.results.first.details['recoverableErrors'],
        hasLength(3),
      );
      expect(evaluation.results.last.status, TaskGateStatus.failed);
    });

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
      expect(evaluation.results.single.details['errors'], hasLength(1));
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
  Map<String, dynamic> arguments = const {},
  Map<String, dynamic> result = const {},
  String? resultSummary,
  String? error,
}) {
  return TaskToolCallRecord(
    id: 'call_$toolName',
    stepId: 'step_1',
    runId: 'run_1',
    toolName: toolName,
    arguments: arguments,
    result: result,
    resultSummary: resultSummary ?? jsonEncode(result),
    error: error,
    timestamp: DateTime(2026, 1, 1),
  );
}

class _ReviewClient extends ChatClient {
  _ReviewClient() : super(baseUrl: 'http://localhost', model: 'test');

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
    return ChatCompletionResponse(
      content: jsonEncode({'passed': false, 'summary': 'Needs polish.'}),
    );
  }

  @override
  void dispose() {}
}
