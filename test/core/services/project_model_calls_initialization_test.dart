import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_model_calls.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  test('initial project creation uses generated planning IDs', () async {
    final now = DateTime(2026, 1, 1);
    final calls = ProjectModelCalls(
      toolService: ToolService(workspaceSandbox: WorkspaceSandbox()),
    );
    final client = _Client([
      _call('plan_set_project_details', {
        'title': 'Bounded Project',
        'refined_goal': 'Deliver one verified bounded outcome.',
        'constraints': ['Stay within the attached workspace.'],
      }),
      _call('plan_add_criteria', {
        'criteria': [
          {'ref': 'quality', 'statement': 'The bounded outcome is verified.'},
        ],
      }),
      _call('plan_add_tasks', {
        'tasks': [
          {
            'ref': 'implement',
            'objective': 'Implement the bounded outcome.',
            'criterion_refs': ['quality'],
            'done_criteria': ['The outcome is verified.'],
            'out_of_scope': ['Unrelated project work.'],
          },
        ],
      }),
      _call('plan_add_check', {
        'task': 'implement',
        'kind': 'command',
        'command': 'dart test',
        'criterion_refs': ['quality'],
      }),
      _call('plan_commit', const {}),
    ]);
    final initialisation = await calls.initializeProject(
      client: client,
      baseSystemPrompt: 'system',
      workspace: WorkspaceAttachment(
        rootPath: '/workspace',
        displayName: 'Workspace',
        lastOpenedAt: now,
      ),
      originalGoal: 'Deliver a bounded outcome.',
      workspaceMetadata: const {
        'workspaceName': 'Workspace',
        'workspaceProfile': {
          'treePaths': ['lib/'],
          'highSignalFiles': [],
        },
      },
    );

    expect(initialisation.title, 'Bounded Project');
    expect(initialisation.refinedGoal, 'Deliver one verified bounded outcome.');
    expect(initialisation.criteria.single.id, startsWith('criterion_'));
    expect(initialisation.milestones.single.id, startsWith('milestone_'));
    expect(initialisation.tasks.single.id, startsWith('task_'));
    expect(
      initialisation.tasks.single.milestoneId,
      initialisation.milestones.single.id,
    );
    expect(initialisation.tasks.single.gates.single.id, 'command_passes');
    expect(initialisation.tasks.single.expectedEvidence.length, 2);
    expect(initialisation.planningMetrics.planningCalls, 5);
    expect(initialisation.planningMetrics.planningCommandCount, 5);
    expect(initialisation.planningMetrics.promptTokenEstimate, greaterThan(0));
    final toolNames = [
      for (final item in (client.lastExtraParams?['tools'] as List))
        ((item as Map)['function'] as Map)['name'],
    ];
    expect(toolNames, contains('plan_set_project_details'));
    expect(toolNames, isNot(contains('finaliseProjectCreation')));
  });
}

ChatCompletionToolCall _call(String name, Map<String, dynamic> arguments) =>
    ChatCompletionToolCall(
      id: 'call_${name}_${arguments.hashCode}',
      name: name,
      arguments: jsonEncode(arguments),
    );

class _Client extends ChatClient {
  _Client(this._responses) : super(baseUrl: 'http://localhost', model: 'test');

  final List<ChatCompletionToolCall> _responses;
  Map<String, dynamic>? lastExtraParams;
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
    lastExtraParams = extraParams;
    return ChatCompletionResponse(
      content: '',
      toolCalls: [_responses[_index++]],
    );
  }

  @override
  void dispose() {}
}
