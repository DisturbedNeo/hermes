import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  test(
    'TaskService creates a plan through incremental task commands',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hermes_incremental_task_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final sandbox = WorkspaceSandbox();
      final service = TaskService(
        toolService: ToolService(workspaceSandbox: sandbox),
        sandbox: sandbox,
      );
      final client = _QueueClient([
        _call('task_set_brief', {
          'title': 'Incremental task',
          'objective': 'Implement the bounded change.',
          'success_criteria': ['The bounded change is complete.'],
        }),
        _call('task_add_step', {
          'ref': 'implement',
          'title': 'Implement change',
          'objective': 'Implement the bounded change.',
          'instructions': ['Make the change and keep it focused.'],
          'may_edit_files': true,
        }),
        _call('task_add_check', {
          'command': 'dart test test/example_test.dart',
          'working_directory': '.',
        }),
        _call('task_commit_plan', const {}),
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
      expect(task.gates.map((gate) => gate.id), contains('command_passes'));
      expect(task.planningMetrics.planningCalls, 4);
      expect(task.planningMetrics.planningCommandCount, 4);
      expect(task.planningMetrics.promptTokenEstimate, greaterThan(0));
      expect(task.planningMetrics.toolResultTokenEstimate, greaterThan(0));
      expect(client.toolNames, [
        'task_set_brief',
        'task_add_step',
        'task_add_check',
        'task_commit_plan',
      ]);
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
      final service = TaskService(
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

ChatCompletionToolCall _call(String name, Map<String, dynamic> arguments) =>
    ChatCompletionToolCall(
      id: 'call_${name}_${arguments.hashCode}',
      name: name,
      arguments: jsonEncode(arguments),
    );

class _QueueClient extends ChatClient {
  _QueueClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<ChatCompletionToolCall> _responses;
  final List<String> toolNames = [];
  final List<Set<String>> offeredToolNames = [];
  var _index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    final call = _responses[_index++];
    offeredToolNames.add(_toolNames(extraParams));
    toolNames.add(call.name);
    return ChatCompletionResponse(content: '', toolCalls: [call]);
  }

  Set<String> _toolNames(Map<String, dynamic>? extraParams) {
    final tools = extraParams?['tools'];
    if (tools is! List) return const {};
    return {
      for (final tool in tools.whereType<Map>())
        if (tool['function'] is Map)
          ((tool['function'] as Map)['name'] ?? '').toString(),
    }..remove('');
  }

  @override
  void dispose() {}
}
