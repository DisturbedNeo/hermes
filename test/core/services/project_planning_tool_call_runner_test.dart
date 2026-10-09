import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/chat/application/contracts/chat_message.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/model/infrastructure/chat_client.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/project/runtime/project_planning_tools.dart';
import 'package:hermes/features/project/runtime/project_planning_policy.dart';

void main() {
  test('runs initial planning commands through finalization', () async {
    final context = ProjectPlanningContext(
      project: _project(),
      workspaceRoot: '/workspace',
      now: DateTime(2026, 1, 1),
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );
    final registry = ProjectPlanningToolRegistry(
      context: context,
      profile: ProjectPlanningToolProfile.bootstrap,
    );
    final result = await _complete(
      client: _Client([
        _call('project_update', {
          'project_id': 'planning_seed',
          'title': 'Bounded Project',
          'refined_goal': 'Deliver one verified bounded outcome.',
          'constraints': ['Stay within the attached workspace.'],
          'criteria': [
            {'statement': 'The bounded outcome is verified.'},
          ],
          'milestones': [
            {
              'title': 'Deliver the slice',
              'objective': 'Deliver and verify the bounded slice.',
              'criterion_ids': [1],
            },
          ],
        }, id: 'call_project_update'),
        _call('task_add', {
          'objective': 'Implement the bounded outcome.',
          'acceptance': [
            {
              'ref': 'quality-proof',
              'statement': 'The bounded outcome is verified.',
              'criterion_ids': [1],
              'verifiers': [
                {
                  'kind': 'command',
                  'command': 'dart test',
                  'working_directory': '.',
                  'required': true,
                },
              ],
            },
          ],
          'milestone_id': 1,
          'out_of_scope': ['Unrelated project work.'],
          'steps': [
            {'objective': 'Implement the bounded outcome.'},
          ],
        }, id: 'call_task_add'),
        _call('plan_finalize', const {}, id: 'call_finalize'),
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
    expect(metrics['planningCalls'], 3);
    expect(metrics['planningCommandCount'], 3);
    expect(metrics['invalidCommandCount'], 0);
  });

  test('does not expose workspace tools to the planning model', () async {
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
      ),
    );
    final client = _Client([_call('plan_finalize', const {}, id: 'finalize')]);
    final result = await _complete(
      client: client,
      registry: registry,
      label: 'Test Planning',
      system: 'Use planning tools.',
      user: 'Finalize the empty plan.',
    );

    expect(result['ok'], isTrue);
    final names = [
      for (final item in client.lastExtraParams?.tools ?? const []) item.id,
    ];
    expect(names, isNot(contains('read_file')));
    expect(names, isNot(contains('write_file')));
  });

  test('stops a non-terminating planning loop at the safety ceiling', () async {
    final context = ProjectPlanningContext(
      project: _project(),
      workspaceRoot: '/workspace',
      now: DateTime(2026, 1, 1),
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );
    final result = await _complete(
      client: _Client([
        _call('project_update', {
          'project_id': 'planning_seed',
          'title': 'Project',
        }, id: 'update_1'),
        _call('project_update', {
          'project_id': 'planning_seed',
          'title': 'Project',
        }, id: 'update_2'),
        _call('project_update', {
          'project_id': 'planning_seed',
          'title': 'Project',
        }, id: 'update_3'),
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

  test('bounds repeated task mutations at the reduced ceiling', () async {
    final context = ProjectPlanningContext(
      project: _project(),
      workspaceRoot: '/workspace',
      now: DateTime(2026, 1, 1),
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );
    final client = _Client([
      for (var index = 0; index < 33; index++)
        _call('task_add', {
          'objective': 'Implement bounded outcome $index.',
          'acceptance': [
            {
              'ref': 'outcome-$index',
              'statement': 'The bounded outcome is verified.',
              'criterion_ids': [],
              'verifiers': [
                {'kind': 'review'},
              ],
            },
          ],
          'out_of_scope': ['Unrelated work.'],
          'steps': [
            {'objective': 'Implement the bounded outcome.'},
          ],
        }, id: 'invalid_$index'),
    ]);

    final result = await _complete(
      client: client,
      registry: ProjectPlanningToolRegistry(context: context),
      label: 'Test Incomplete Task Repair Ceiling',
      system: 'Use planning tools.',
      user: 'Create the project plan.',
    );

    expect(result['ok'], isFalse);
    expect(result['code'], 'planning_safety_limit');
    expect(client.messagesByCall, hasLength(33));
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
      final result = await _complete(
        client: _Client([
          _call('task_add', {
            'ref': 'invalid',
            'objective': 'Missing criterion reference.',
            'acceptance': [],
          }, id: 'invalid-task'),
          _call('project_update', {
            'project_id': 'planning_seed',
            'criteria': [
              {'statement': 'The outcome is verified.'},
            ],
          }, id: 'criteria'),
          _call('task_add', {
            'objective': 'Verify the outcome.',
            'acceptance': [
              {
                'ref': 'quality-proof',
                'statement': 'The outcome is verified.',
                'criterion_ids': [1],
                'verifiers': [
                  {'kind': 'review', 'required': true},
                ],
              },
            ],
            'out_of_scope': ['Unrelated work.'],
          }, id: 'valid-task'),
          _call('plan_finalize', const {}, id: 'finalize'),
        ]),
        registry: ProjectPlanningToolRegistry(context: context),
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

Future<Map<String, dynamic>> _complete({
  required ModelCompletionPort client,
  required PlanningToolRegistry registry,
  required String label,
  required String system,
  required String user,
  int maxToolCalls = PlanningToolCallRunner.defaultMaxToolCalls,
}) async => (await const PlanningToolCallRunner().complete(
  PlanningRunRequest(
    client: client,
    registry: registry,
    label: label,
    system: system,
    user: user,
    maxToolCalls: maxToolCalls,
  ),
)).toMap();

ModelToolCall _call(
  String name,
  Map<String, dynamic> arguments, {
  required String id,
}) => ModelToolCall(id: id, name: name, arguments: jsonEncode(arguments));

ProjectAggregate _project() {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
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

  final List<ModelToolCall> _responses;
  final messagesByCall = <List<ChatMessage>>[];
  ModelRequestOptions? lastExtraParams;
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
    messagesByCall.add(List<ChatMessage>.of(messages));
    lastExtraParams = extraParams;
    return ModelCompletion(content: '', toolCalls: [_responses[_index++]]);
  }

  @override
  void dispose() {}
}
