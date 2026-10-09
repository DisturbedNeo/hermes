import 'dart:convert';
import 'package:hermes/app/test_factories.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/features/chat/application/contracts/chat_message.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/model/infrastructure/chat_client.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/platform/workspace_sandbox.dart';

void main() {
  test(
    'TaskController creates a complete plan through CRUD task commands',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hermes_incremental_task_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final sandbox = WorkspaceSandbox();
      final service = createTestTaskController(
        toolService: ToolService(workspaceSandbox: sandbox),
        sandbox: sandbox,
      );
      final client = _QueueClient([
        _call('task_add', {
          'title': 'Incremental task',
          'objective': 'Implement the bounded change.',
          'out_of_scope': ['Unrelated work.'],
          'acceptance': [
            {
              'ref': 'bounded-change',
              'statement': 'The bounded change is complete.',
              'criterion_ids': [],
              'verifiers': [
                {
                  'kind': 'command',
                  'command': 'dart test test/example_test.dart',
                },
              ],
            },
          ],
          'steps': [
            {
              'ref': 'implement',
              'title': 'Implement change',
              'objective': 'Implement the bounded change.',
              'instructions': ['Make the change and keep it focused.'],
              'may_edit_files': true,
              'acceptance_refs': ['bounded-change'],
            },
          ],
        }),
        _call('plan_finalize', const {}),
      ]);

      final task = await service.createTask(
        client: client,
        workspace: WorkspaceAttachment(
          rootPath: root.path,
          displayName: 'Workspace',
          lastOpenedAt: DateTime(2026, 1, 1),
        ),
        userPrompt: 'Implement a bounded change',
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: 'Use task planning tools.',
      );

      expect(task.title, 'Incremental task');
      expect(task.steps, hasLength(1));
      expect(task.steps.single.id, startsWith('step_'));
      expect(task.acceptance, isNotEmpty);
      expect(
        task.acceptance
            .expand((item) => item.verifiers)
            .map((verifier) => verifier.kind),
        contains(AcceptanceVerifierKind.command),
      );
      expect(task.planningMetrics.planningCalls, 2);
      expect(task.planningMetrics.planningCommandCount, 2);
      expect(task.planningMetrics.promptTokenEstimate, greaterThan(0));
      expect(task.planningMetrics.toolResultTokenEstimate, greaterThan(0));
      expect(client.toolNames, ['task_add', 'plan_finalize']);
    },
  );

  test(
    'falls back safely when the planner violates the command protocol',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hermes_strict_incremental_task_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final sandbox = WorkspaceSandbox();
      final service = createTestTaskController(
        toolService: ToolService(workspaceSandbox: sandbox),
        sandbox: sandbox,
      );
      final client = _QueueClient([
        _call('unsupported_planning_command', {
          'title': 'Unsupported replacement plan',
          'objective': 'This must not be accepted in strict mode.',
        }),
      ]);

      final task = await service.createTask(
        client: client,
        workspace: WorkspaceAttachment(
          rootPath: root.path,
          displayName: 'Workspace',
          lastOpenedAt: DateTime(2026, 1, 1),
        ),
        userPrompt: 'Use strict incremental planning',
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: 'Use task planning tools.',
      );

      expect(task.title, 'Use strict incremental planning');
      expect(task.currentStepId, isNotNull);
      expect(task.planningMetrics.fullPlanRepairCount, 0);
      expect(
        client.offeredToolNames.single,
        isNot(contains('unsupported_planning_command')),
      );
    },
  );
}

ModelToolCall _call(String name, Map<String, dynamic> arguments) =>
    ModelToolCall(
      id: 'call_${name}_${arguments.hashCode}',
      name: name,
      arguments: jsonEncode(arguments),
    );

class _QueueClient extends ChatClient {
  _QueueClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<ModelToolCall> _responses;
  final List<String> toolNames = [];
  final List<Set<String>> offeredToolNames = [];
  var _index = 0;

  @override
  Future<ModelCompletion> completeChat({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    final call = _responses[_index++];
    offeredToolNames.add(_toolNames(extraParams));
    toolNames.add(call.name);
    return ModelCompletion(content: '', toolCalls: [call]);
  }

  Set<String> _toolNames(ModelRequestOptions? extraParams) {
    return {for (final tool in extraParams?.tools ?? const []) tool.id};
  }

  @override
  void dispose() {}
}
