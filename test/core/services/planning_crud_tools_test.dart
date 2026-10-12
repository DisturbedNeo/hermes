import 'package:flutter_test/flutter_test.dart';
import '../helpers/planning_test_helpers.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/application/contracts/project_task_models.dart';
import 'package:hermes/features/project/runtime/project_planning_tools.dart';
import 'package:hermes/features/project/runtime/project_planning_frontier.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/runtime/task_planning_tools.dart';

void main() {
  test(
    'task planning exposes update, remove, read, and finalization tools',
    () {
      final registry = TaskPlanningToolRegistry(
        context: TaskPlanningToolContext(
          task: _task(),
          workspaceRoot: '/workspace',
          maxSteps: 3,
        ),
      );

      expect(registry.toolDefinitions.map((tool) => tool.id), [
        'task_read',
        'task_update',
        'task_remove',
        'plan_finalize',
      ]);
    },
  );

  test('task update, remove, and finalize use one-call mutations', () async {
    final context = TaskPlanningToolContext(
      task: _task(),
      workspaceRoot: '/workspace',
      maxSteps: 3,
    );
    final registry = TaskPlanningToolRegistry(context: context);

    final planned = await invokePlanning(registry, 'task_update', {
      'title': 'Build the bounded outcome',
      'objective': 'Build the bounded outcome.',
      'out_of_scope': ['Unrelated work.'],
      'acceptance': [
        {
          'ref': 'verified',
          'statement': 'The bounded outcome is verified.',
          'criterion_ids': [],
          'verifiers': [
            {'kind': 'review'},
          ],
        },
      ],
      'steps': [
        {
          'ref': 'implement',
          'objective': 'Implement the bounded outcome.',
          'acceptance_refs': ['verified'],
        },
      ],
    });
    expect(planned['ok'], isTrue);
    expect((planned['task'] as Map)['steps'], hasLength(1));

    final updated = await invokePlanning(registry, 'task_update', {
      'title': 'Updated bounded outcome',
    });
    expect(updated['ok'], isTrue);
    expect((updated['task'] as Map)['title'], 'Updated bounded outcome');

    final removed = await invokePlanning(registry, 'task_remove', {});
    expect(removed['ok'], isTrue);
    expect((removed['task'] as Map)['status'], 'obsolete');

    final finalized = await invokePlanning(registry, 'plan_finalize', {});
    expect(finalized['ok'], isTrue);
    expect(finalized['finalized'], isTrue);
  });

  test('task_read returns the current task without changing it', () async {
    final context = TaskPlanningToolContext(
      task: _task(),
      workspaceRoot: '/workspace',
      maxSteps: 3,
    );
    final registry = TaskPlanningToolRegistry(context: context);

    final before = context.currentTask;
    final result = await invokePlanning(registry, 'task_read', {});

    expect(result['ok'], isTrue);
    expect(result['resource'], 'task');
    expect((result['task'] as Map)['task_id'], 1);
    expect(context.currentTask, same(before));
  });

  test('project planning exposes the new project/task contract', () {
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      ),
    );

    expect(registry.toolDefinitions.map((tool) => tool.id), [
      'plan_read',
      'project_update',
      'task_add',
      'task_update',
      'task_remove',
      'project_request_user_decision',
      'plan_finalize',
    ]);
  });

  test(
    'plan_read returns compact-project details by stable references',
    () async {
      final project = _project().copyWith(
        tasks: [
          ProjectTaskNode(
            id: 'task_existing',
            title: 'Existing task',
            objective: 'Inspect the existing task.',
            status: TaskStatus.queued,
            constraints: const ['Keep it bounded.'],
            outOfScope: const ['Unrelated work.'],
            acceptance: const [
              AcceptanceItem(
                ref: 'verified',
                statement: 'The task is verified.',
                criterionIds: ['criterion_001'],
                verifiers: [
                  AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
                ],
              ),
            ],
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        taskAgentNumbers: const {'task_existing': 1},
        nextTaskAgentNumber: 2,
      );
      final registry = ProjectPlanningToolRegistry(
        context: ProjectPlanningContext(
          project: project,
          workspaceRoot: '/workspace',
          approvalPolicy: ProjectPlanApprovalPolicy.never,
        ),
      );

      final task = await invokePlanning(registry, 'plan_read', {
        'resource': 'task',
        'id': 1,
      });
      final criterion = await invokePlanning(registry, 'plan_read', {
        'resource': 'criterion',
        'id': 1,
      });
      final graph = await invokePlanning(registry, 'plan_read', {
        'resource': 'workspace_graph',
        'ref': 'summary',
      });

      expect(task['ok'], isTrue);
      expect((task['task'] as Map)['constraints'], ['Keep it bounded.']);
      expect(criterion['ok'], isTrue);
      expect((criterion['criterion'] as Map)['criterion_id'], 1);
      expect(graph['ok'], isTrue);
      expect((graph['workspace_graph'] as Map)['orientation'], '');

      final unknown = await invokePlanning(registry, 'plan_read', {
        'resource': 'task',
        'id': 99,
      });
      expect(unknown['ok'], isFalse);
      expect(unknown['code'], 'unknown_reference');
    },
  );

  test(
    'project frontier omits full task detail while retaining references',
    () {
      final project = _project().copyWith(
        tasks: [
          ProjectTaskNode(
            id: 'task_existing',
            title: 'Existing task',
            objective: 'Inspect the existing task.',
            status: TaskStatus.queued,
            constraints: const ['Do not expand scope.'],
            outOfScope: const ['Unrelated work.'],
            acceptance: const [
              AcceptanceItem(
                ref: 'verified',
                statement: 'The task is verified.',
                criterionIds: ['criterion_001'],
                verifiers: [
                  AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
                ],
              ),
            ],
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        taskAgentNumbers: const {'task_existing': 1},
        nextTaskAgentNumber: 2,
      );
      final frontier = ProjectPlanningFrontierBuilder.build(project: project);
      final task = (frontier['tasks'] as List).single as Map;

      expect(frontier['schema_version'], 1);
      expect(task['task_id'], 1);
      expect(task.containsKey('acceptance'), isFalse);
      expect(task.containsKey('constraints'), isFalse);
      expect(task.containsKey('steps'), isFalse);
    },
  );

  test('project task mutations persist between immediate calls', () async {
    final persisted = <ProjectAggregate>[];
    final context = ProjectPlanningContext(
      project: _project(),
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
      persistProject: (workspaceRoot, project) async {
        final next = project.copyWith(
          persistenceRevision: project.persistenceRevision + 1,
        );
        persisted.add(next);
        return next;
      },
    );
    final registry = ProjectPlanningToolRegistry(context: context);

    final added = await invokePlanning(registry, 'task_add', {
      'objective': 'Implement the project slice.',
      'acceptance': [
        {
          'ref': 'slice-verified',
          'statement': 'The project slice is verified.',
          'criterion_ids': [1],
          'verifiers': [
            {'kind': 'review'},
          ],
        },
      ],
      'out_of_scope': ['The rest of the project.'],
      'steps': [
        {'objective': 'Implement the project slice.'},
      ],
    });
    expect(added['ok'], isTrue);
    expect(added['task_id'], 1);

    final updated = await invokePlanning(registry, 'task_update', {
      'task_id': 1,
      'title': 'Updated project slice',
    });
    expect(updated['ok'], isTrue);
    expect((updated['task'] as Map)['title'], 'Updated project slice');

    final project = context.currentProject;
    expect(project.tasks.single.title, 'Updated project slice');
    expect(persisted, hasLength(2));
  });

  test(
    'project task creation persists executable steps at the task boundary',
    () async {
      TaskAggregate? persistedTask;
      final context = ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
        persistProjectWithTasks: (workspaceRoot, project, dirtyTasks) async {
          persistedTask = dirtyTasks.single;
          return project;
        },
      );

      final result = await invokePlanning(
        ProjectPlanningToolRegistry(context: context),
        'task_add',
        {
          'objective': 'Implement the project slice.',
          'acceptance': [
            {
              'ref': 'slice-verified',
              'statement': 'The project slice is verified.',
              'criterion_ids': [1],
              'verifiers': [
                {'kind': 'review'},
              ],
            },
          ],
          'out_of_scope': ['The rest of the project.'],
          'steps': [
            {'objective': 'Implement the slice.'},
            {'objective': 'Verify the slice.'},
          ],
        },
      );

      expect(result['ok'], isTrue);
      expect(persistedTask?.steps, hasLength(2));
      expect(persistedTask?.steps.map((step) => step.objective), [
        'Implement the slice.',
        'Verify the slice.',
      ]);
      expect((result['task'] as Map).containsKey('steps'), isFalse);
    },
  );

  test('project decisions persist a waiting-for-user boundary', () async {
    final context = ProjectPlanningContext(
      project: _project(),
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );
    final registry = ProjectPlanningToolRegistry(context: context);

    final result = await invokePlanning(
      registry,
      'project_request_user_decision',
      {'question': 'Which supported platform should this use?'},
    );

    expect(result['ok'], isTrue);
    expect(result['awaiting_user_input'], isTrue);
    expect(
      context.currentProject.openQuestions.single.question,
      'Which supported platform should this use?',
    );
    expect(context.currentProject.status, ProjectStatus.waitingForUser);
    expect(
      await invokePlanning(registry, 'plan_finalize', {}),
      containsPair('code', 'planning_closed'),
    );
  });

  test(
    'inherited acceptance is returned once and cannot be re-added',
    () async {
      const inherited = AcceptanceItem(
        ref: 'project-check',
        statement: 'The project criterion is satisfied.',
        criterionIds: ['1'],
        verifiers: [AcceptanceVerifier(kind: AcceptanceVerifierKind.review)],
      );
      final context = TaskPlanningToolContext(
        task: _task().copyWith(acceptance: const [inherited]),
        workspaceRoot: '/workspace',
        maxSteps: 2,
        acceptance: const [inherited],
      );
      final registry = TaskPlanningToolRegistry(context: context);

      final added = await invokePlanning(registry, 'task_update', {
        'objective': 'Complete the inherited project task.',
        'out_of_scope': ['Unrelated work.'],
        'steps': [
          {
            'objective': 'Complete the bounded work.',
            'acceptance_refs': ['project-check'],
          },
        ],
      });
      expect(added['ok'], isTrue);
      expect((added['task'] as Map)['inherited_acceptance'], hasLength(1));
      expect((added['task'] as Map)['local_acceptance'], isEmpty);
      expect((added['task'] as Map)['effective_acceptance'], hasLength(1));
      expect((added['task'] as Map)['inherited_acceptance'], hasLength(1));

      final duplicate = await invokePlanning(registry, 'task_update', {
        'acceptance': [
          {
            'ref': 'project-check',
            'statement': 'The project criterion is satisfied.',
            'criterion_ids': [1],
            'verifiers': [
              {'kind': 'review'},
            ],
          },
        ],
      });
      expect(duplicate['ok'], isFalse);
      expect(duplicate['code'], 'duplicate_acceptance_ref');
    },
  );

  test(
    'task mutations persist immediately and finalization only changes lifecycle',
    () async {
      final persisted = <TaskAggregate>[];
      final context = TaskPlanningToolContext(
        task: _task(),
        workspaceRoot: '/workspace',
        maxSteps: 3,
        persistTask: (candidate) async {
          final next = candidate.copyWith(
            persistenceRevision: candidate.persistenceRevision + 1,
          );
          persisted.add(next);
          return next;
        },
      );
      final registry = TaskPlanningToolRegistry(context: context);

      await invokePlanning(registry, 'task_update', {
        'objective': 'Persist a complete task.',
        'out_of_scope': ['Unrelated work.'],
        'acceptance': [
          {
            'ref': 'done',
            'statement': 'The task is done.',
            'verifiers': [
              {'kind': 'review'},
            ],
          },
        ],
        'steps': [
          {
            'objective': 'Do the work.',
            'acceptance_refs': ['done'],
          },
        ],
      });
      expect(persisted, hasLength(1));
      final beforeFinalize = context.currentTask;
      final finalized = await invokePlanning(registry, 'plan_finalize', {});
      expect(finalized['finalized'], isTrue);
      expect(persisted, hasLength(2));
      expect(context.currentTask.title, beforeFinalize.title);
      expect(context.currentTask.objective, beforeFinalize.objective);
      expect(context.currentTask.status, TaskStatus.planned);
    },
  );

  test('task persistence failure leaves the current state unchanged', () async {
    final context = TaskPlanningToolContext(
      task: _task(),
      workspaceRoot: '/workspace',
      maxSteps: 2,
      persistTask: (candidate) async {
        throw StateError('task write failed');
      },
    );
    final registry = TaskPlanningToolRegistry(context: context);
    final result = await invokePlanning(registry, 'task_update', {
      'objective': 'This must not be applied.',
      'out_of_scope': ['Unrelated work.'],
      'acceptance': [
        {
          'ref': 'done',
          'statement': 'The task is done.',
          'verifiers': [
            {'kind': 'review'},
          ],
        },
      ],
      'steps': [
        {
          'objective': 'Do the work.',
          'acceptance_refs': ['done'],
        },
      ],
    });
    expect(result['ok'], isFalse);
    expect(result['code'], 'planning_tool_failed');
    expect(context.currentTask.objective, 'Initial objective.');
  });

  test('task removal rejects terminal tasks', () async {
    final context = TaskPlanningToolContext(
      task: _task().copyWith(status: TaskStatus.completed),
      workspaceRoot: '/workspace',
      maxSteps: 2,
    );
    final result = await invokePlanning(
      TaskPlanningToolRegistry(context: context),
      'task_remove',
      {},
    );
    expect(result['ok'], isFalse);
    expect(result['code'], 'invalid_transition');
    expect(context.currentTask.status, TaskStatus.completed);
  });

  test('task removal rejects running tasks', () async {
    final context = TaskPlanningToolContext(
      task: _task().copyWith(status: TaskStatus.running),
      workspaceRoot: '/workspace',
      maxSteps: 2,
    );
    final result = await invokePlanning(
      TaskPlanningToolRegistry(context: context),
      'task_remove',
      {},
    );
    expect(result['ok'], isFalse);
    expect(result['code'], 'invalid_transition');
    expect(context.currentTask.status, TaskStatus.running);
  });

  test('task update replaces unfinished steps during a replan', () async {
    final context = TaskPlanningToolContext(
      task: _task().copyWith(
        acceptance: const [
          AcceptanceItem(
            ref: 'done',
            statement: 'The task is done.',
            verifiers: [
              AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
            ],
          ),
        ],
        steps: const [
          TaskStep(
            id: 'done',
            title: 'Done',
            objective: 'Already complete.',
            instructions: [],
            mayEditFiles: false,
            artifacts: [],
            status: TaskStepStatus.completed,
          ),
          TaskStep(
            id: 'stale',
            title: 'Stale',
            objective: 'Replace this approach.',
            instructions: [],
            mayEditFiles: false,
            artifacts: [],
            status: TaskStepStatus.pending,
          ),
        ],
      ),
      workspaceRoot: '/workspace',
      maxSteps: 3,
      preserveCompletedStepsOnly: true,
    );
    final result = await invokePlanning(
      TaskPlanningToolRegistry(context: context),
      'task_update',
      {
        'steps': [
          {'objective': 'Use the corrected approach.'},
        ],
      },
    );

    expect(result['ok'], isTrue);
    expect(context.currentTask.steps.map((step) => step.id), [
      'done',
      startsWith('step_'),
    ]);
  });

  test(
    'project references are numeric and unknown references fail atomically',
    () async {
      final context = ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );
      final registry = ProjectPlanningToolRegistry(context: context);

      final unknown = await invokePlanning(registry, 'task_add', {
        'objective': 'Reference an unknown criterion.',
        'acceptance': [
          {
            'ref': 'done',
            'statement': 'The task is done.',
            'criterion_ids': [99],
            'verifiers': [
              {'kind': 'review'},
            ],
          },
        ],
        'out_of_scope': ['Unrelated work.'],
        'steps': [
          {'objective': 'Reference the project criterion.'},
        ],
      });
      expect(unknown['ok'], isFalse);
      expect(unknown['code'], 'unknown_reference');
      expect(context.currentProject.tasks, isEmpty);
    },
  );

  test(
    'project persistence failure rolls back the editable aggregate',
    () async {
      final context = ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
        persistProject: (workspaceRoot, project) async {
          throw StateError('project write failed');
        },
      );
      final registry = ProjectPlanningToolRegistry(context: context);

      final result = await invokePlanning(registry, 'task_add', {
        'objective': 'This must not be persisted.',
        'acceptance': [
          {
            'ref': 'done',
            'statement': 'The task is done.',
            'criterion_ids': [1],
            'verifiers': [
              {'kind': 'review'},
            ],
          },
        ],
        'out_of_scope': ['Unrelated work.'],
        'steps': [
          {'objective': 'Do not persist this work.'},
        ],
      });
      expect(result['ok'], isFalse);
      expect(result['code'], 'planning_tool_failed');
      expect(context.currentProject.tasks, isEmpty);
    },
  );

  test('project finalization validates without adding content', () async {
    final now = DateTime(2026, 1, 1);
    final project = _project().copyWith(
      tasks: [
        ProjectTaskNode(
          id: 'task_existing',
          title: 'Existing task',
          objective: 'Complete the existing task.',
          status: TaskStatus.queued,
          outOfScope: const ['Unrelated project work.'],
          acceptance: const [
            AcceptanceItem(
              ref: 'existing-task-verified',
              statement: 'The existing task is verified.',
              criterionIds: ['criterion_001'],
              verifiers: [
                AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
              ],
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      taskAgentNumbers: const {'task_existing': 1},
      nextTaskAgentNumber: 2,
    );
    final persisted = <ProjectAggregate>[];
    final context = ProjectPlanningContext(
      project: project,
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
      persistProject: (workspaceRoot, candidate) async {
        persisted.add(candidate);
        return candidate.copyWith(
          persistenceRevision: candidate.persistenceRevision + 1,
        );
      },
    );

    final result = await invokePlanning(
      ProjectPlanningToolRegistry(context: context),
      'plan_finalize',
      {},
    );

    expect(result['ok'], isTrue);
    expect(context.currentProject.milestones, isEmpty);
    expect(
      context.currentProject.tasks.single.objective,
      'Complete the existing task.',
    );
    expect(context.currentProject.status, ProjectStatus.active);
    expect(persisted, hasLength(1));
  });
}

TaskAggregate _task() {
  final now = DateTime(2026, 1, 1);
  return TaskAggregate(
    id: 'task_1',
    title: 'Initial task',
    objective: 'Initial objective.',
    status: TaskStatus.paused,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectAggregate _project() {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Deliver a bounded outcome.',
    refinedGoal: 'Deliver a bounded outcome.',
    criteria: [
      ProjectCriterion(
        id: 'criterion_001',
        statement: 'The bounded outcome is verified.',
        createdAt: now,
        updatedAt: now,
        verifiedAt: null,
      ),
    ],
    constraints: const [],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}
