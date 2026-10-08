import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/planning_test_helpers.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/project/runtime/project_planning_tools.dart';
import 'package:hermes/features/project/runtime/project_planning_workspace_reader.dart';
import 'package:hermes/features/project/runtime/project_view_service.dart';
import 'package:hermes/features/project/runtime/project_planning_policy.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/platform/workspace_sandbox.dart';

void main() {
  test('planning profiles expose only their intended tool surface', () {
    final bootstrap = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        planningPass: ProjectPlanningPass.bootstrap,
        planningLimits: ProjectPlanningLimits.bootstrap,
      ),
      profile: ProjectPlanningToolProfile.bootstrap,
      includeProjectDetails: true,
    );
    expect(bootstrap.toolDefinitions.map((tool) => tool.id).toSet(), {
      'plan_set_project_details',
      'project_view',
      'plan_add_criteria',
      'plan_add_milestones',
      'plan_add_task',
      'plan_add_note',
      'plan_set_workspace_orientation',
      'plan_add_workspace_nodes',
      'plan_update_workspace_node',
      'plan_add_workspace_edges',
      'plan_update_workspace_edge',
      'plan_remove_workspace_item',
      'plan_request_user_decision',
      'plan_commit',
    });

    final graphMaintenance = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        planningPass: ProjectPlanningPass.graphMaintenance,
        planningLimits: ProjectPlanningLimits.graphMaintenance,
      ),
      profile: ProjectPlanningToolProfile.graphMaintenance,
    );
    expect(graphMaintenance.toolDefinitions.map((tool) => tool.id).toSet(), {
      'project_view',
      'plan_set_workspace_orientation',
      'plan_add_workspace_nodes',
      'plan_update_workspace_node',
      'plan_add_workspace_edges',
      'plan_update_workspace_edge',
      'plan_remove_workspace_item',
      'plan_preview',
      'plan_commit',
    });

    final split = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        planningPass: ProjectPlanningPass.split,
        planningLimits: ProjectPlanningLimits.split,
      ),
      profile: ProjectPlanningToolProfile.split,
    );
    expect(split.toolDefinitions.map((tool) => tool.id).toSet(), {
      'project_view',
      'plan_split_task',
      'plan_preview',
      'plan_commit',
    });
  });

  test('planning schemas expose commands without persistence fields', () {
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
      ),
    );
    final ids = registry.toolDefinitions.map((item) => item.id).toSet();

    expect(
      ids,
      containsAll([
        'project_view',
        'plan_add_task',
        'plan_update_task',
        'plan_split_task',
        'plan_retry_task',
        'plan_preview',
        'plan_commit',
      ]),
    );
    expect(ids, isNot(contains('read_file')));
    expect(ids, isNot(contains('write_file')));
    expect(ids, isNot(contains('plan_set_project_details')));
    expect(registry.allowsWorkspaceMutation, isFalse);

    final schema = registry.toolDefinitions
        .singleWhere((item) => item.id == 'plan_add_task')
        .schema
        .toWire();
    final taskProperties = schema['properties'] as Map;
    expect(taskProperties.keys, contains('checks'));
    final checkProperties =
        ((taskProperties['checks'] as Map)['items'] as Map)['properties']
            as Map;
    expect(
      checkProperties.keys,
      containsAll([
        'command',
        'working_directory',
        'criterion_refs',
        'required',
        'description',
      ]),
    );
    expect(((taskProperties['checks'] as Map)['items'] as Map)['required'], [
      'command',
    ]);

    final splitSchema = registry.toolDefinitions
        .singleWhere((tool) => tool.id == 'plan_split_task')
        .schema
        .toWire();
    final childProperties =
        ((((splitSchema['properties'] as Map)['children'] as Map)['items']
                as Map)['properties']
            as Map);
    expect(childProperties.keys, contains('checks'));

    expect(ids, isNot(contains('plan_add_tasks')));
    expect(
      registry.toolDefinitions.map((item) => item.schema.toString()).join(),
      isNot(contains('ProjectAggregate')),
    );
  });

  test(
    'singular task creation is complete and reports all missing fields',
    () async {
      final context = ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );
      final registry = ProjectPlanningToolRegistry(context: context);

      final invalid = await invokePlanning(registry, 'plan_add_task', {
        'objective': 'Implement the bounded outcome.',
      });
      expect(invalid['ok'], isFalse);
      expect(invalid['code'], 'invalid_task_spec');
      expect(invalid['path'], 'task');
      final details = invalid['details'] as Map;
      expect(details['missing_fields'], [
        'criterion_refs',
        'done_criteria',
        'out_of_scope',
      ]);
      expect(details['instruction'], contains('complete task object'));

      final previewAfterFailure = await invokePlanning(
        registry,
        'plan_preview',
        const {},
      );
      expect(previewAfterFailure['ok'], isTrue);
      expect(
        ((previewAfterFailure['preview'] as Map)['diff'] as Map)['added_tasks'],
        isEmpty,
      );

      final added = await invokePlanning(registry, 'plan_add_task', {
        'ref': 'implement',
        'objective': 'Implement the bounded outcome.',
        'criterion_refs': ['criterion_001'],
        'done_criteria': ['The bounded outcome is verified.'],
        'out_of_scope': ['Unrelated project work.'],
      });
      expect(added['ok'], isTrue);
      expect((added['task'] as Map)['ref'], 'implement');
      expect(
        ((added['state'] as Map)['diff'] as Map)['added_tasks'],
        isNotEmpty,
      );
    },
  );

  test('project view exposes approval and user-input control state', () {
    final now = DateTime(2026, 1, 1);
    final project = _project().copyWith(
      status: ProjectStatus.paused,
      pendingPlanApproval: PendingProjectPlanApproval(
        revision: 2,
        reason: 'The revision changes a high-risk task.',
        summary: 'Review the high-risk revision.',
        highRiskChanges: const ['A task now edits source files.'],
        highRiskReasonCodes: const ['high_risk_task'],
        createdAt: now,
      ),
      blocker: ProjectBlocker(
        type: ProjectBlockerType.planApproval,
        message: 'The revision needs approval.',
        createdAt: now,
      ),
      openQuestions: [
        PendingProjectQuestion(
          id: 'question_1',
          question: 'Should the high-risk revision proceed?',
          createdAt: now,
        ),
      ],
    );

    final view = const ProjectViewService().query(project);
    final control = view['control'] as Map;
    expect(control['outcome'], 'awaiting_plan_approval');
    expect(control['action'], 'approve_or_reject_plan');
    expect(
      (control['pending_plan_approval'] as Map)['high_risk_reason_codes'],
      ['high_risk_task'],
    );
    expect((control['open_questions'] as List).single['id'], 'question_1');
  });

  test('project view exposes cursors for navigating bounded collections', () {
    final project = _project(
      tasks: [for (var index = 1; index <= 3; index++) _task('task_$index')],
    );
    final first = const ProjectViewService().query(project, maxItems: 1);
    final firstPage =
        ((first['navigation'] as Map)['pages'] as Map)['tasks'] as Map;

    expect(firstPage['total'], 3);
    expect(firstPage['offset'], 0);
    expect(firstPage['has_more'], isTrue);
    expect(firstPage['next_cursor'], 'tasks:1');
    expect((first['tasks'] as List), hasLength(1));

    final second = const ProjectViewService().query(
      project,
      maxItems: 1,
      section: 'tasks',
      cursor: firstPage['next_cursor'] as String,
    );
    final secondPage =
        ((second['navigation'] as Map)['pages'] as Map)['tasks'] as Map;

    expect(secondPage['offset'], 1);
    expect(secondPage['next_cursor'], 'tasks:2');
    expect((second['tasks'] as List).single['ref'], 'task_2');
  });

  test('project view rejects malformed navigation cursors', () {
    expect(
      () => const ProjectViewService().query(
        _project(),
        section: 'tasks',
        cursor: 'tasks:not-a-number',
      ),
      throwsA(
        isA<ProjectViewException>().having(
          (error) => error.code,
          'code',
          'invalid_cursor',
        ),
      ),
    );
  });

  test('project search cursors retain their search scope', () {
    final now = DateTime(2026, 1, 1);
    final project = _project().copyWith(
      memory: [
        for (var index = 1; index <= 3; index++)
          ProjectMemoryEntry(
            id: 'memory_$index',
            kind: ProjectMemoryKind.fact,
            content: 'needle memory $index',
            sourceType: ProjectMemorySourceType.system,
            confidence: ProjectMemoryConfidence.confirmed,
            createdAt: now,
            updatedAt: now,
          ),
      ],
    );
    final first = const ProjectViewService().query(
      project,
      memoryQuery: 'needle',
      maxItems: 1,
    );
    final firstPage =
        ((first['navigation'] as Map)['pages'] as Map)['memory'] as Map;

    final second = const ProjectViewService().query(
      project,
      maxItems: 1,
      section: 'memory',
      cursor: firstPage['next_cursor'] as String,
    );

    expect((second['memory_detail'] as List).single['id'], 'memory_2');
  });

  test('singular task creates inline checks atomically', () async {
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _deterministicProject(),
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      ),
    );
    final added = await invokePlanning(registry, 'plan_add_task', {
      'ref': 'checked',
      'objective': 'Implement the deterministic slice.',
      'criterion_refs': ['criterion_001'],
      'done_criteria': ['The deterministic slice is verified.'],
      'out_of_scope': ['Unrelated project work.'],
      'checks': [
        {
          'command': 'dart test test/feature_test.dart',
          'criterion_refs': ['criterion_001'],
          'required': true,
        },
      ],
    });

    expect(added['ok'], isTrue);
    final detail = await invokePlanning(registry, 'project_view', {
      'task_ref': 'checked',
    });
    expect(detail['ok'], isTrue);
    final task = detail['task_detail'] as Map;
    expect(task['checks'], hasLength(1));
    expect(task['evidence_intents'], hasLength(2));
  });

  test('invalid inline checks roll back the complete task', () async {
    final base = _project();
    final project = base.copyWith(
      criteria: [
        base.criteria.single,
        base.criteria.single.copyWith(
          id: 'criterion_002',
          statement: 'The second outcome is verified.',
        ),
      ],
    );
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: project,
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      ),
    );
    final result = await invokePlanning(registry, 'plan_add_task', {
      'ref': 'invalid',
      'objective': 'Implement the first outcome.',
      'criterion_refs': ['criterion_001'],
      'done_criteria': ['The first outcome is verified.'],
      'out_of_scope': ['Unrelated project work.'],
      'checks': [
        {
          'command': 'dart test test/feature_test.dart',
          'criterion_refs': ['criterion_002'],
        },
      ],
    });

    expect(result['ok'], isFalse);
    expect(result['code'], 'unlinked_criterion');
    final preview = await invokePlanning(registry, 'plan_preview', {});
    expect(
      ((preview['preview'] as Map)['diff'] as Map)['added_tasks'],
      isEmpty,
    );
  });

  test('missing inline checks list every deterministic criterion', () async {
    final base = _project();
    final project = base.copyWith(
      criteria: [
        base.criteria.single.copyWith(
          verificationMode: ProjectVerificationMode.deterministic,
        ),
        ProjectCriterion(
          id: 'criterion_002',
          statement: 'The second deterministic outcome is verified.',
          verificationMode: ProjectVerificationMode.deterministic,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: project,
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      ),
    );
    final result = await invokePlanning(registry, 'plan_add_task', {
      'objective': 'Implement both deterministic outcomes.',
      'criterion_refs': ['criterion_001', 'criterion_002'],
      'done_criteria': ['Both outcomes are verified.'],
      'out_of_scope': ['Unrelated project work.'],
    });

    expect(result['ok'], isFalse);
    expect(result['code'], 'missing_deterministic_task_check');
    expect(
      ((result['details'] as Map)['missing_criterion_refs'] as List),
      containsAll(['criterion_001', 'criterion_002']),
    );
    final preview = await invokePlanning(registry, 'plan_preview', {});
    expect(
      ((preview['preview'] as Map)['diff'] as Map)['added_tasks'],
      isEmpty,
    );
  });

  test('single task creation requires an objective', () async {
    final added = await invokePlanning(_registry(), 'plan_add_task', {
      'title': 'Verify the bounded outcome.',
      'criterion_refs': ['criterion_001'],
      'done_criteria': ['The bounded outcome is verified.'],
      'out_of_scope': ['Unrelated project work.'],
    });

    expect(added['ok'], isFalse);
    expect(added['code'], 'invalid_task_spec');
  });

  test('initial planning exposes only the bounded context reader', () async {
    final root = await Directory.systemTemp.createTemp(
      'hermes_planning_tools_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File('${root.path}/Design.md').writeAsString('authoritative design');
    final reader = ProjectPlanningWorkspaceReader(
      workspace: WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      ),
      sandbox: WorkspaceSandbox(),
      allowedPaths: const ['Design.md'],
    );
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _project(),
        workspaceRoot: root.path,
        workspaceReader: reader,
      ),
      includeProjectDetails: true,
    );

    final ids = registry.toolDefinitions.map((item) => item.id).toSet();
    expect(ids, contains('planning_read_file'));
    expect(ids, isNot(contains('read_file')));
    expect(ids, isNot(contains('write_file')));
    expect(registry.allowsWorkspaceMutation, isFalse);

    final result = await invokePlanning(registry, 'planning_read_file', {
      'path': 'Design.md',
    });
    expect(result['ok'], isTrue);
    expect(result['content'], 'authoritative design');
  });

  test(
    'initial planning exposes project details as a separate command',
    () async {
      final registry = ProjectPlanningToolRegistry(
        context: ProjectPlanningContext(
          project: _project(),
          workspaceRoot: '/workspace',
        ),
        includeProjectDetails: true,
      );

      expect(
        registry.toolDefinitions.map((item) => item.id),
        contains('plan_set_project_details'),
      );
      final updated = await invokePlanning(
        registry,
        'plan_set_project_details',
        {
          'title': 'A more precise project',
          'refined_goal': 'Deliver the verified bounded outcome.',
          'constraints': ['Use only the attached workspace.'],
        },
      );

      expect(updated['ok'], isTrue);
      final view = await invokePlanning(registry, 'project_view', {});
      expect((view['project'] as Map)['title'], 'A more precise project');
      expect(
        (view['goal'] as Map)['refined'],
        'Deliver the verified bounded outcome.',
      );
      expect((view['constraints'] as List), [
        'Use only the attached workspace.',
      ]);
    },
  );

  test(
    'draft commands use generated IDs and keep create separate from update',
    () async {
      final registry = _registry();
      final added = await invokePlanning(registry, 'plan_add_task', {
        'ref': 'scaffold',
        'title': 'Scaffold the bounded slice',
        'objective': 'Create the bounded project slice.',
        'criterion_refs': ['criterion_001'],
        'done_criteria': ['The bounded slice is implemented.'],
        'out_of_scope': ['Unrelated project work.'],
      }, commandId: 'add-1');

      expect(added['ok'], isTrue);
      final taskId = ((added['task'] as Map)['id']) as String;
      expect(taskId, startsWith('task_'));

      final repeated = await invokePlanning(registry, 'plan_add_task', {
        'ref': 'scaffold',
        'title': 'Scaffold the bounded slice',
        'objective': 'Create the bounded project slice.',
        'criterion_refs': ['criterion_001'],
        'done_criteria': ['The bounded slice is implemented.'],
        'out_of_scope': ['Unrelated project work.'],
      }, commandId: 'add-1');
      expect(repeated['ok'], isTrue);
      expect(((repeated['task'] as Map)['id']) as String, taskId);

      final updated = await invokePlanning(registry, 'plan_update_task', {
        'task': 'scaffold',
        'title': 'Scaffold the reviewed slice',
      });
      expect(updated['ok'], isTrue);
      expect((((updated['task'] as Map)['id']) as String), taskId);

      final attemptedCreateWithId = await invokePlanning(
        registry,
        'plan_add_task',
        {
          'id': 'pretend_replace',
          'title': 'Invalid replacement',
          'objective': 'Invalid replacement.',
          'criterion_refs': ['criterion_001'],
          'done_criteria': ['It is checked.'],
          'out_of_scope': ['Unrelated work.'],
        },
      );
      expect(attemptedCreateWithId['ok'], isFalse);
      expect(attemptedCreateWithId['code'], 'invalid_argument');
      expect(attemptedCreateWithId['path'], 'id');

      final view = await invokePlanning(registry, 'project_view', {});
      expect(view['ok'], isTrue);
      expect(
        ((view['draft'] as Map)['diff'] as Map)['added_tasks'],
        contains(taskId),
      );
      expect(
        ((view['tasks'] as List).single as Map)['title'],
        'Scaffold the reviewed slice',
      );

      final detail = await invokePlanning(registry, 'project_view', {
        'task_ref': 'scaffold',
      });
      expect(detail['ok'], isTrue);
      expect((detail['task_detail'] as Map)['ref'], taskId);
      expect(
        (detail['task_detail'] as Map)['title'],
        'Scaffold the reviewed slice',
      );
    },
  );

  test(
    'preview and commit return compact validation and diff results',
    () async {
      final registry = _registry();
      final added = await invokePlanning(registry, 'plan_add_task', {
        'ref': 'checked',
        'objective': 'Implement and verify the bounded slice.',
        'criterion_refs': ['criterion_001'],
        'done_criteria': ['The bounded slice is verified.'],
        'out_of_scope': ['Unrelated project work.'],
      });
      expect(added['ok'], isTrue);

      final preview = await invokePlanning(registry, 'plan_preview', {
        'summary': 'Add the checked slice.',
        'rationale': 'The criterion needs one bounded implementation task.',
      });
      expect(preview['ok'], isTrue);
      expect((preview['preview'] as Map)['valid'], isTrue);
      expect(
        ((preview['preview'] as Map)['diff'] as Map)['added_tasks'],
        hasLength(1),
      );

      final committed = await invokePlanning(registry, 'plan_commit', {});
      expect(committed['ok'], isTrue);
      expect(committed['changed'], isTrue);
      expect(committed['awaiting_approval'], isFalse);

      final afterCommit = await invokePlanning(registry, 'plan_add_note', {
        'kind': 'assumption',
        'content': 'This must not be applied after commit.',
      });
      expect(afterCommit['ok'], isFalse);
      expect(afterCommit['code'], 'draft_closed');
    },
  );

  test(
    'a failed batch criteria command does not leave an earlier item in the draft',
    () async {
      final registry = _registry();
      final result = await invokePlanning(registry, 'plan_add_criteria', {
        'criteria': [
          {'ref': 'temporary', 'statement': 'This item must be rolled back.'},
          {'ref': 'invalid'},
        ],
      });

      expect(result['ok'], isFalse);
      expect(result['path'], 'criteria[1].statement');

      final dependent = await invokePlanning(registry, 'plan_add_task', {
        'ref': 'dependent',
        'objective': 'Use a criterion that should not exist.',
        'criterion_refs': ['temporary'],
        'done_criteria': ['The task is checked.'],
        'out_of_scope': ['Unrelated work.'],
      });
      expect(dependent['ok'], isFalse);
      expect(dependent['code'], 'unknown_reference');
    },
  );

  test('project view is bounded and excludes runtime execution records', () {
    final task = _task('task_001').copyWith(
      context: List.filled(30, 'context that should be bounded'),
      runs: const [],
      status: TaskStatus.failed,
      rejectionReason: 'The required verification command failed.',
      failure: const TaskFailure(
        gateId: 'command_passes',
        disposition: TaskGateFailureDisposition.repairable,
        failureKey: 'command_passes|exit_1',
        summary: 'The verification command exited with status 1.',
        errorCodes: ['exit_1'],
        unresolvedErrorCount: 1,
      ),
    );
    final project = _project(tasks: [task]);
    final view = const ProjectViewService(
      maxTextLength: 40,
    ).query(project, taskRef: task.id, maxItems: 1);

    expect(view['project'], isA<Map>());
    expect(view['task_detail'], isA<Map>());
    expect(_containsKey(view, 'runs'), isFalse);
    expect(_containsKey(view, 'logs'), isFalse);
    expect(_containsKey(view, 'evidence'), isFalse);
    final detail = view['task_detail'] as Map;
    expect(
      (detail['context'] as List).single.toString().length,
      lessThanOrEqualTo(40),
    );
    expect((detail['failure'] as Map)['gate_ref'], 'command_passes');
    expect((detail['failure'] as Map)['error_codes'], ['exit_1']);
  });

  test(
    'bootstrap commit diagnostics list blockers and repairability',
    () async {
      final registry = ProjectPlanningToolRegistry(
        context: ProjectPlanningContext(
          project: _deterministicProject(tasks: [_task('existing')]),
          workspaceRoot: '/workspace',
          planningPass: ProjectPlanningPass.bootstrap,
          planningLimits: ProjectPlanningLimits.bootstrap,
          approvalPolicy: ProjectPlanApprovalPolicy.never,
        ),
        profile: ProjectPlanningToolProfile.bootstrap,
      );
      final result = await invokePlanning(registry, 'plan_commit', {});

      expect(result['ok'], isFalse);
      expect(result['code'], 'impossible_deterministic_verification');
      final details = result['details'] as Map;
      expect(details['repairable'], isFalse);
      expect(details['blockers'], isNotEmpty);
      expect(details['suggested_actions'], isEmpty);
    },
  );

  test(
    'bootstrap commits three tasks with deterministic backlog criteria',
    () async {
      final base = _project();
      final project = base.copyWith(
        criteria: [
          base.criteria.single,
          ProjectCriterion(
            id: 'criterion_future',
            statement: 'The future deterministic outcome is verified.',
            verificationMode: ProjectVerificationMode.deterministic,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final registry = ProjectPlanningToolRegistry(
        context: ProjectPlanningContext(
          project: project,
          workspaceRoot: '/workspace',
          planningPass: ProjectPlanningPass.bootstrap,
          planningLimits: ProjectPlanningLimits.bootstrap,
          approvalPolicy: ProjectPlanApprovalPolicy.never,
        ),
        profile: ProjectPlanningToolProfile.bootstrap,
      );

      for (var index = 1; index <= 3; index++) {
        final added = await invokePlanning(registry, 'plan_add_task', {
          'ref': 'slice_$index',
          'objective': 'Implement bounded slice $index.',
          'criterion_refs': ['criterion_001'],
          'done_criteria': ['Bounded slice $index is verified.'],
          'out_of_scope': ['Unrelated project work.'],
        });
        expect(added['ok'], isTrue);
      }

      final committed = await invokePlanning(registry, 'plan_commit', {});
      expect(committed['ok'], isTrue);
      expect(
        (committed['validation'] as List).any(
          (issue) =>
              (issue as Map)['code'] == 'unassigned_deterministic_criterion',
        ),
        isTrue,
      );
      expect(
        ((committed['diff'] as Map)['added_milestones'] as List),
        hasLength(1),
      );
    },
  );
}

ProjectPlanningToolRegistry _registry() => ProjectPlanningToolRegistry(
  context: ProjectPlanningContext(
    project: _project(),
    workspaceRoot: '/workspace',
    approvalPolicy: ProjectPlanApprovalPolicy.never,
  ),
);

ProjectAggregate _project({List<TaskAggregate> tasks = const []}) {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Deliver a bounded outcome.',
    refinedGoal: 'Deliver a bounded outcome safely.',
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
    tasks: [for (final task in tasks) ProjectTaskNode.fromTask(task)],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectAggregate _deterministicProject({List<TaskAggregate> tasks = const []}) {
  final project = _project(tasks: tasks);
  return project.copyWith(
    criteria: [
      project.criteria.single.copyWith(
        verificationMode: ProjectVerificationMode.deterministic,
      ),
    ],
  );
}

TaskAggregate _task(String id) {
  final now = DateTime(2026, 1, 1);
  final objective = 'Implement bounded slice $id.';
  return TaskAggregate(
    id: id,
    title: 'Bounded slice $id',
    objective: objective,
    criterionIds: const ['criterion_001'],
    expectedEvidence: [
      TaskEvidenceExpectation(
        id: 'expect_$id',
        criterionIds: const ['criterion_001'],
        description: 'The bounded slice is independently checked.',
      ),
    ],
    doneCriteria: const ['The bounded slice is implemented and checked.'],
    outOfScope: const ['Unrelated project work.'],
    status: TaskStatus.queued,
    fingerprint: projectTaskFingerprint(objective, const ['criterion_001']),
    createdAt: now,
    updatedAt: now,
  );
}

bool _containsKey(Object? value, String key) {
  if (value is Map) {
    if (value.containsKey(key)) return true;
    return value.values.any((item) => _containsKey(item, key));
  }
  if (value is Iterable) return value.any((item) => _containsKey(item, key));
  return false;
}
