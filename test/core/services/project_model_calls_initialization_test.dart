import 'dart:convert';
import 'dart:io';

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
    final initialPlan = await calls.initializePlan(
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

    final plan = initialPlan.patch.plan;
    expect(initialPlan.patch.title, 'Bounded Project');
    expect(
      initialPlan.patch.refinedGoal,
      'Deliver one verified bounded outcome.',
    );
    expect(plan.criteria.single.id, startsWith('criterion_'));
    expect(plan.milestones.single.id, startsWith('milestone_'));
    expect(plan.tasks.single.id, startsWith('task_'));
    expect(plan.tasks.single.milestoneId, plan.milestones.single.id);
    expect(plan.tasks.single.gates.single.id, 'command_passes');
    expect(plan.tasks.single.expectedEvidence.length, 2);
    expect(initialPlan.planningMetrics.planningCalls, 5);
    expect(initialPlan.planningMetrics.planningCommandCount, 5);
    expect(initialPlan.planningMetrics.promptTokenEstimate, greaterThan(0));
    final toolNames = [
      for (final item in (client.lastExtraParams?['tools'] as List))
        ((item as Map)['function'] as Map)['name'],
    ];
    expect(toolNames, contains('plan_set_project_details'));
  });

  test(
    'initial planning can read an authoritative design through the bounded reader',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hermes_initial_planning_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      const design =
          'Authoritative design\n\nThe report must remain keyboard accessible.';
      await File('${root.path}/Design.md').writeAsString(design);
      final calls = ProjectModelCalls(
        toolService: ToolService(workspaceSandbox: WorkspaceSandbox()),
      );
      final client = _Client([
        _call('planning_read_file', {'path': 'Design.md'}),
        _call('plan_set_project_details', {
          'title': 'Accessible Report',
          'refined_goal': 'Deliver the accessible report workflow.',
        }),
        _call('plan_add_criteria', {
          'criteria': [
            {
              'ref': 'accessibility',
              'statement': 'The report remains keyboard accessible.',
            },
          ],
        }),
        _call('plan_add_tasks', {
          'tasks': [
            {
              'ref': 'implement',
              'objective': 'Implement the accessible report workflow.',
              'criterion_refs': ['accessibility'],
              'done_criteria': ['The report remains keyboard accessible.'],
              'out_of_scope': ['Unrelated visual redesign.'],
            },
          ],
        }),
        _call('plan_commit', const {}),
      ]);

      final initialPlan = await calls.initializePlan(
        client: client,
        baseSystemPrompt: 'system',
        workspace: WorkspaceAttachment(
          rootPath: root.path,
          displayName: 'Workspace',
          lastOpenedAt: DateTime(2026, 1, 1),
        ),
        originalGoal: 'Deliver an accessible report workflow.',
        workspaceMetadata: const {
          'workspaceName': 'Workspace',
          'workspaceProfile': {
            'treePaths': ['Design.md'],
            'highSignalFiles': [
              {
                'path': 'Design.md',
                'content': 'Authoritative design...',
                'truncated': true,
              },
            ],
          },
        },
      );

      expect(initialPlan.patch.plan.tasks, hasLength(1));
      expect(
        client.seenMessages.first.last.content,
        isNot(contains('Authoritative design...')),
      );
      final toolResult =
          jsonDecode(
                client.seenMessages[1]
                    .where((message) => message.role == 'tool')
                    .single
                    .content,
              )
              as Map;
      expect(toolResult['content'], design);
      final tools = client.lastExtraParams?['tools'] as List;
      expect([
        for (final item in tools) ((item as Map)['function'] as Map)['name'],
      ], contains('planning_read_file'));

      final prompt = client.seenMessages
          .expand((messages) => messages)
          .map((message) => message.content)
          .join('\n');
      expect(prompt, contains('domain-neutral'));
      expect(
        prompt,
        contains('Task agents must not mutate the workspace context graph'),
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

class _Client extends ChatClient {
  _Client(this._responses) : super(baseUrl: 'http://localhost', model: 'test');

  final List<ChatCompletionToolCall> _responses;
  Map<String, dynamic>? lastExtraParams;
  final List<List<ChatMessage>> seenMessages = [];
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
    seenMessages.add(List<ChatMessage>.from(messages));
    return ChatCompletionResponse(
      content: '',
      toolCalls: [_responses[_index++]],
    );
  }

  @override
  void dispose() {}
}
