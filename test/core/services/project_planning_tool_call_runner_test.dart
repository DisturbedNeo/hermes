import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/app/modules/persistence_module.dart';
import 'package:hermes/app/modules/project_module.dart';
import 'package:hermes/app/modules/task_module.dart';
import 'package:hermes/app/modules/workspace_tools_module.dart';
import 'package:hermes/features/chat/application/contracts/chat_message.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/model/infrastructure/chat_client.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/project/runtime/project_planning_tools.dart';
import 'package:hermes/features/project/runtime/project_planning_policy.dart';
import 'package:hermes/features/project/runtime/project_model_calls.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final retry in [false, true]) {
    test(
      retry
          ? 'resumes a saved planning failure and persists its first slice'
          : 'plans and persists the first slice after saving a new shell',
      () async {
        final root = await Directory.systemTemp.createTemp('hermes_bootstrap_');
        addTearDown(() => root.delete(recursive: true));
        final workspace = WorkspaceAttachment.fromPath(root.path);
        final persistence = PersistenceModule.create();
        final workspaceTools = WorkspaceToolsModule.create();
        final task = TaskModule.create(
          persistence: persistence,
          workspace: workspaceTools,
        ).controller;
        final application = ProjectModule.create(
          persistence: persistence,
          workspace: workspaceTools,
          task: task,
        ).application;
        var shell = await application.createProject(
          workspace: workspace,
          userPrompt: 'Deliver a bounded outcome.',
        );
        if (retry) {
          shell = (await persistence.projects.saveSnapshot(
            root.path,
            shell.copyWith(
              status: ProjectStatus.active,
              pendingReplanTriggers: const [
                ProjectPlanRevisionTrigger.initialization,
              ],
              boundary: ProjectBoundary(
                outcome: ProjectControlOutcome.degradedPlanning,
                message: 'Previous planning attempt failed.',
                action: 'retry_planning',
                reasonCode: 'planning_failed',
                occurredAt: DateTime(2026, 11, 4),
              ),
            ),
          )).value;
        }
        final client = _Client([
          _call('plan_finalize', const {}, id: 'graph_finalize'),
          ..._bootstrapCalls(),
        ]);

        final result = await application.executeUntilStop(
          ProjectExecutionRequest(
            client: client,
            workspace: workspace,
            snapshot: shell,
            baseSystemPrompt: 'Use planning tools.',
            maxNewTasks: 1,
            planOnly: true,
          ),
          boundedRun: false,
        );

        expect(result.project.boundary?.message, isEmpty);
        expect(result.stopReason, ProjectCommandStopReason.active);
        expect(result.project.criteria, hasLength(1));
        expect(result.project.tasks, hasLength(1));
        expect(
          result.project.milestones.single.status,
          ProjectMilestoneStatus.active,
        );
        expect(client.messagesByCall, hasLength(4));
        final saved = await application.loadProject(workspace, shell.id);
        expect(saved?.tasks.single.id, result.project.tasks.single.id);
        expect(saved?.boundary?.outcome, ProjectControlOutcome.running);
        final canonicalTask = await task.loadTask(
          workspace,
          saved!.tasks.single.id,
        );
        expect(
          canonicalTask?.steps.single.objective,
          'Implement the bounded outcome.',
        );
      },
    );
  }

  test('builds the bootstrap prompt and commits the initial plan', () async {
    final result = await ProjectModelCalls().revisePlanWithCommands(
      client: _Client(_bootstrapCalls()),
      baseSystemPrompt: 'Use planning tools.',
      workspace: WorkspaceAttachment.fromPath('/workspace'),
      project: _project(),
      evidenceSnapshot: ProjectEvidenceSnapshot(
        workspaceName: 'Workspace',
        collectedAt: DateTime(2026, 1, 1),
      ),
      triggers: const [ProjectPlanRevisionTrigger.initialization],
      approvalPolicy: ProjectPlanApprovalPolicy.never,
      planningPass: ProjectPlanningPass.bootstrap,
      planningLimits: ProjectPlanningLimits.bootstrap,
    );

    expect(result.error, isNull);
    expect(result.committed, isTrue);
    expect(
      result.project.criteria.single.statement,
      'The bounded outcome is verified.',
    );
    expect(result.project.tasks.single.id, startsWith('task_'));
    expect(result.project.title, 'Bounded Project');
    expect(result.project.refinedGoal, 'Deliver one verified bounded outcome.');
    expect(result.planningMetrics.planningCalls, 3);
    expect(result.planningMetrics.planningCommandCount, 3);
    expect(result.planningMetrics.invalidCommandCount, 0);
  });

  test(
    'graph maintenance commits its draft without resuming the project',
    () async {
      final client = _Client([
        _call('plan_set_workspace_orientation', {
          'orientation': 'The workspace contains the bounded project.',
        }, id: 'orientation'),
        _call('plan_finalize', const {}, id: 'finalize'),
      ]);
      final result = await ProjectModelCalls().maintainWorkspaceGraph(
        client: client,
        baseSystemPrompt: 'Use planning tools.',
        workspace: WorkspaceAttachment.fromPath('/workspace'),
        project: _project().copyWith(
          status: ProjectStatus.paused,
          pendingReplanTriggers: const [
            ProjectPlanRevisionTrigger.initialization,
            ProjectPlanRevisionTrigger.workspaceGraphMaintenance,
          ],
        ),
        evidenceSnapshot: ProjectEvidenceSnapshot(
          workspaceName: 'Workspace',
          collectedAt: DateTime(2026, 1, 1),
        ),
      );

      expect(result.error, isNull);
      expect(result.committed, isTrue);
      expect(client.messagesByCall, hasLength(2));
      expect(result.project.status, ProjectStatus.paused);
      expect(result.project.pendingReplanTriggers, [
        ProjectPlanRevisionTrigger.initialization,
      ]);
      expect(
        result.project.workspaceGraph.orientation,
        'The workspace contains the bounded project.',
      );
    },
  );

  test(
    'a planner failure retains updates and their persisted revision',
    () async {
      final planner = ProjectModelCalls(
        persistProject: (_, project) async => project.copyWith(
          persistenceRevision: project.persistenceRevision + 1,
        ),
      );
      final result = await planner.revisePlanWithCommands(
        client: _Client([_bootstrapCalls().first]),
        baseSystemPrompt: 'Use planning tools.',
        workspace: WorkspaceAttachment.fromPath('/workspace'),
        project: _project(),
        evidenceSnapshot: ProjectEvidenceSnapshot(
          workspaceName: 'Workspace',
          collectedAt: DateTime(2026, 1, 1),
        ),
        triggers: const [ProjectPlanRevisionTrigger.initialization],
        approvalPolicy: ProjectPlanApprovalPolicy.never,
        planningPass: ProjectPlanningPass.bootstrap,
        planningLimits: ProjectPlanningLimits.bootstrap,
      );

      expect(result.committed, isFalse);
      expect(result.error, contains('Unexpected planning retry'));
      expect(result.project.persistenceRevision, 1);
      expect(result.project.criteria, hasLength(1));
      expect(result.project.milestones, hasLength(1));
      expect(result.project.tasks, isEmpty);
    },
  );

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
        _call('project_update', {'title': 'Project'}, id: 'update_1'),
        _call('project_update', {'title': 'Project'}, id: 'update_2'),
        _call('project_update', {'title': 'Project'}, id: 'update_3'),
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

List<ModelToolCall> _bootstrapCalls() => [
  _call('project_update', {
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
];

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
    if (_index >= _responses.length) {
      throw StateError('Unexpected planning retry: ${messages.last.content}');
    }
    return ModelCompletion(content: '', toolCalls: [_responses[_index++]]);
  }

  @override
  void dispose() {}
}
