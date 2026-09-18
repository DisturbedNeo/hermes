import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_planning_tool_call_runner.dart';
import 'package:hermes/core/services/project_system/project_planning_tools.dart';

void main() {
  test('runs initial planning commands through commit', () async {
    final context = ProjectPlanningContext(
      project: _project(),
      workspaceRoot: '/workspace',
      now: DateTime(2026, 1, 1),
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );
    final registry = ProjectPlanningToolRegistry(
      context: context,
      includeProjectDetails: true,
    );
    final runner = const ProjectPlanningToolCallRunner();
    final result = await runner.complete(
      client: _Client([
        _call('plan_set_project_details', {
          'title': 'Bounded Project',
          'refined_goal': 'Deliver one verified bounded outcome.',
          'constraints': ['Stay within the attached workspace.'],
        }, id: 'call_details'),
        _call('plan_add_criteria', {
          'criteria': [
            {'ref': 'quality', 'statement': 'The bounded outcome is verified.'},
          ],
        }, id: 'call_criteria'),
        _call('plan_add_milestones', {
          'milestones': [
            {
              'ref': 'delivery',
              'title': 'Deliver the slice',
              'objective': 'Deliver and verify the bounded slice.',
              'criterion_refs': ['quality'],
            },
          ],
        }, id: 'call_milestone'),
        _call('plan_add_tasks', {
          'tasks': [
            {
              'ref': 'implement',
              'objective': 'Implement the bounded outcome.',
              'criterion_refs': ['quality'],
              'milestone_ref': 'delivery',
              'done_criteria': ['The outcome is verified.'],
              'out_of_scope': ['Unrelated project work.'],
            },
          ],
        }, id: 'call_tasks'),
        _call('plan_add_check', {
          'task': 'implement',
          'kind': 'command',
          'command': 'dart test',
          'criterion_refs': ['quality'],
        }, id: 'call_check'),
        _call('plan_commit', const {}, id: 'call_commit'),
      ]),
      registry: registry,
      label: 'Test Initial Planning',
      system: 'Use planning tools.',
      user: 'Create the project plan.',
    );

    expect(result['ok'], isTrue);
    expect(context.closed, isTrue);
    expect(
      context.committedProposal?.criteria.single.statement,
      'The bounded outcome is verified.',
    );
    expect(context.committedProposal?.tasks.single.id, startsWith('task_'));
    expect(context.draftTitle, 'Bounded Project');
    expect(context.draftRefinedGoal, 'Deliver one verified bounded outcome.');
    final metrics = result['planning_metrics'] as Map<String, dynamic>;
    expect(metrics['planningCalls'], 6);
    expect(metrics['planningCommandCount'], 6);
    expect(metrics['invalidCommandCount'], 0);
  });

  test('does not expose workspace tools to the planning model', () async {
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
      ),
    );
    final client = _Client([_call('plan_commit', const {}, id: 'commit')]);
    final result = await const ProjectPlanningToolCallRunner().complete(
      client: client,
      registry: registry,
      label: 'Test Planning',
      system: 'Use planning tools.',
      user: 'Commit the empty draft.',
    );

    expect(result['ok'], isTrue);
    final tools = client.lastExtraParams?['tools'] as List;
    final names = [
      for (final item in tools) ((item as Map)['function'] as Map)['name'],
    ];
    expect(names, isNot(contains('read_file')));
    expect(names, isNot(contains('write_file')));
  });

  test(
    'continues past the old tool-call limit until the draft is committed',
    () async {
      final context = ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        now: DateTime(2026, 1, 1),
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );
      final client = _Client([
        for (var index = 0; index < 32; index++)
          _call('project_view', {'max_items': 1}, id: 'view_$index'),
        _call('plan_commit', const {}, id: 'commit'),
      ]);
      final result = await const ProjectPlanningToolCallRunner().complete(
        client: client,
        registry: ProjectPlanningToolRegistry(
          context: context,
          includeProjectDetails: true,
        ),
        label: 'Test Unbounded Planning',
        system: 'Use planning tools.',
        user: 'Keep working until the draft is committed.',
      );

      expect(result['ok'], isTrue);
      final metrics = result['planning_metrics'] as Map<String, dynamic>;
      expect(metrics['planningCommandCount'], 33);
      expect(
        client.messagesByCall.any(
          (messages) => messages.any(
            (message) => message.content.contains('planning_history_compacted'),
          ),
        ),
        isTrue,
      );
    },
  );

  test('stops a non-terminating planning loop at the safety ceiling', () async {
    final context = ProjectPlanningContext(
      project: _project(),
      workspaceRoot: '/workspace',
      now: DateTime(2026, 1, 1),
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );
    final result = await const ProjectPlanningToolCallRunner().complete(
      client: _Client([
        _call('project_view', const {}, id: 'view_1'),
        _call('project_view', const {}, id: 'view_2'),
        _call('project_view', const {}, id: 'view_3'),
      ]),
      registry: ProjectPlanningToolRegistry(context: context),
      label: 'Test Planning Safety Ceiling',
      system: 'Use planning tools.',
      user: 'Keep working forever.',
      maxToolCalls: 2,
    );

    expect(result['ok'], isFalse);
    expect(result['code'], 'planning_safety_limit');
  });

  test(
    'records invalid planning commands without retaining model payloads',
    () async {
      final context = ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        now: DateTime(2026, 1, 1),
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );
      final result = await const ProjectPlanningToolCallRunner().complete(
        client: _Client([
          _call('plan_add_tasks', {
            'tasks': [
              {
                'ref': 'invalid',
                'objective': 'Missing criterion reference.',
                'criterion_refs': ['missing'],
              },
            ],
          }, id: 'invalid-task'),
          _call('plan_add_criteria', {
            'criteria': [
              {'ref': 'quality', 'statement': 'The outcome is verified.'},
            ],
          }, id: 'criteria'),
          _call('plan_add_tasks', {
            'tasks': [
              {
                'ref': 'valid',
                'objective': 'Verify the outcome.',
                'criterion_refs': ['quality'],
                'done_criteria': ['The outcome is verified.'],
                'out_of_scope': ['Unrelated work.'],
              },
            ],
          }, id: 'valid-task'),
          _call('plan_commit', const {}, id: 'commit'),
        ]),
        registry: ProjectPlanningToolRegistry(
          context: context,
          includeProjectDetails: true,
        ),
        label: 'Test Planning Metrics',
        system: 'Use planning tools.',
        user: 'Exercise an invalid command.',
      );

      final metrics = result['planning_metrics'] as Map<String, dynamic>;
      expect(metrics['invalidCommandCount'], greaterThan(0));
      expect(metrics, isNot(contains('prompt')));
      expect(metrics, isNot(contains('arguments')));
    },
  );
}

ChatCompletionToolCall _call(
  String name,
  Map<String, dynamic> arguments, {
  required String id,
}) => ChatCompletionToolCall(
  id: id,
  name: name,
  arguments: jsonEncode(arguments),
);

ProjectState _project() {
  final now = DateTime(2026, 1, 1);
  return ProjectState(
    id: 'planning_seed',
    title: 'Project',
    originalGoal: 'Deliver a bounded outcome.',
    refinedGoal: 'Deliver a bounded outcome.',
    criteria: const [],
    constraints: const ['Stay within the attached workspace.'],
    tasks: const [],
    milestones: const [],
    memory: const [],
    planHistory: const [],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

class _Client extends ChatClient {
  _Client(this._responses) : super(baseUrl: 'http://localhost', model: 'test');

  final List<ChatCompletionToolCall> _responses;
  final messagesByCall = <List<ChatMessage>>[];
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
    messagesByCall.add(List<ChatMessage>.of(messages));
    lastExtraParams = extraParams;
    return ChatCompletionResponse(
      content: '',
      toolCalls: [_responses[_index++]],
    );
  }

  @override
  void dispose() {}
}
