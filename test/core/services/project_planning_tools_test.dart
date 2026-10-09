import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/planning_test_helpers.dart';
import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/persistence/infrastructure/dto/aggregate_snapshot_codecs.dart';
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
    );
    expect(bootstrap.toolDefinitions.map((tool) => tool.id).toSet(), {
      'project_view',
      'project_submit_plan',
      'project_update',
      'task_upsert',
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
        'project_update',
        'task_upsert',
        'plan_commit',
      ]),
    );
    expect(ids, isNot(contains('read_file')));
    expect(ids, isNot(contains('write_file')));
    expect(registry.allowsWorkspaceMutation, isFalse);

    final schema = registry.toolDefinitions
        .singleWhere((item) => item.id == 'task_upsert')
        .schema
        .toWire();
    final taskProperties = schema['properties'] as Map;
    expect(taskProperties.keys, contains('acceptance'));
    final acceptanceProperties =
        ((taskProperties['acceptance'] as Map)['items'] as Map)['properties']
            as Map;
    expect(
      acceptanceProperties.keys,
      containsAll(['ref', 'statement', 'criterion_refs', 'verifiers']),
    );
    final verifierProperties =
        (((acceptanceProperties['verifiers'] as Map)['items']
                as Map)['properties'])
            as Map;
    expect(verifierProperties.keys, containsAll(['kind', 'required']));

    expect(
      registry.toolDefinitions.map((item) => item.schema.toString()).join(),
      isNot(contains('ProjectAggregate')),
    );
  });

  test('task upsert requires a complete acceptance payload', () async {
    final context = ProjectPlanningContext(
      project: _project(),
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );
    final registry = ProjectPlanningToolRegistry(context: context);

    final invalid = await invokePlanning(registry, 'task_upsert', {
      'objective': 'Implement the bounded outcome.',
    });
    expect(invalid['ok'], isFalse);
    expect(invalid['code'], 'invalid_argument');
    expect(invalid['path'], 'task.acceptance');

    final previewAfterFailure = await invokePlanning(
      registry,
      'project_view',
      const {},
    );
    expect(previewAfterFailure['ok'], isTrue);
    expect(
      ((previewAfterFailure['draft'] as Map)['diff'] as Map)['added_tasks'],
      isEmpty,
    );

    final added = await invokePlanning(registry, 'task_upsert', {
      'objective': 'Implement the bounded outcome.',
      'acceptance': [
        {
          'ref': 'outcome-verified',
          'statement': 'The bounded outcome is verified.',
          'criterion_refs': ['criterion_001'],
          'verifiers': [
            {'kind': 'review', 'required': true},
          ],
        },
      ],
      'out_of_scope': ['Unrelated project work.'],
    });
    expect(added['ok'], isTrue);
    expect(added['task_id'], 1);
    final addedView = await invokePlanning(registry, 'project_view', {});
    expect(
      ((addedView['draft'] as Map)['diff'] as Map)['added_tasks'],
      isNotEmpty,
    );
  });

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
    expect((second['tasks'] as List).single['task_id'], 2);
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

  test('singular task creates acceptance atomically', () async {
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _deterministicProject(),
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      ),
    );
    final added = await invokePlanning(registry, 'task_upsert', {
      'objective': 'Implement the deterministic slice.',
      'acceptance': [
        {
          'ref': 'deterministic-slice',
          'statement': 'The deterministic slice is verified.',
          'criterion_refs': ['criterion_001'],
          'verifiers': [
            {
              'kind': 'command',
              'command': 'dart test test/feature_test.dart',
              'working_directory': '.',
              'required': true,
            },
          ],
        },
      ],
      'out_of_scope': ['Unrelated project work.'],
    });

    expect(added['ok'], isTrue);
    final detail = await invokePlanning(registry, 'project_view', {
      'task_id': 1,
    });
    expect(detail['ok'], isTrue);
    final task = detail['task_detail'] as Map;
    expect(task['acceptance'], hasLength(1));
    expect((task['acceptance'] as List).single['verifiers'], hasLength(1));
  });

  test('invalid acceptance rolls back the complete task', () async {
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
    final result = await invokePlanning(registry, 'task_upsert', {
      'objective': 'Implement the first outcome.',
      'acceptance': [
        {
          'ref': 'invalid-link',
          'statement': 'The first outcome is verified.',
          'criterion_refs': ['criterion_missing'],
          'verifiers': [
            {'kind': 'review', 'required': true},
          ],
        },
      ],
      'out_of_scope': ['Unrelated project work.'],
    });

    expect(result['ok'], isFalse);
    expect(result['code'], 'unknown_reference');
    final preview = await invokePlanning(registry, 'project_view', {});
    expect(((preview['draft'] as Map)['diff'] as Map)['added_tasks'], isEmpty);
  });

  test(
    'missing acceptance is reported before deterministic verification',
    () async {
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
      final result = await invokePlanning(registry, 'task_upsert', {
        'objective': 'Implement both deterministic outcomes.',
        'out_of_scope': ['Unrelated project work.'],
      });

      expect(result['ok'], isFalse);
      expect(result['code'], 'invalid_argument');
      expect(result['path'], 'task.acceptance');
      final preview = await invokePlanning(registry, 'project_view', {});
      expect(
        ((preview['draft'] as Map)['diff'] as Map)['added_tasks'],
        isEmpty,
      );
    },
  );

  test('single task creation requires an objective', () async {
    final added = await invokePlanning(_registry(), 'task_upsert', {
      'title': 'Verify the bounded outcome.',
      'acceptance': [_acceptance('outcome', 'The outcome is verified.')],
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
        planningPass: ProjectPlanningPass.bootstrap,
      ),
      profile: ProjectPlanningToolProfile.bootstrap,
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
    'project update exposes project details as a flexible command',
    () async {
      final registry = ProjectPlanningToolRegistry(
        context: ProjectPlanningContext(
          project: _project(),
          workspaceRoot: '/workspace',
        ),
      );

      expect(
        registry.toolDefinitions.map((item) => item.id),
        contains('project_update'),
      );
      final updated = await invokePlanning(registry, 'project_update', {
        'title': 'A more precise project',
        'refined_goal': 'Deliver the verified bounded outcome.',
        'constraints': ['Use only the attached workspace.'],
      });

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

  test('task upsert creates and updates a task by numeric reference', () async {
    final registry = _registry();
    final added = await invokePlanning(registry, 'task_upsert', {
      'title': 'Scaffold the bounded slice',
      'objective': 'Create the bounded project slice.',
      'acceptance': [_acceptance('slice', 'The bounded slice is implemented.')],
      'out_of_scope': ['Unrelated project work.'],
    }, commandId: 'add-1');

    expect(added['ok'], isTrue);
    expect(added['task_id'], 1);

    final repeated = await invokePlanning(registry, 'task_upsert', {
      'title': 'Scaffold the bounded slice',
      'objective': 'Create the bounded project slice.',
      'acceptance': [_acceptance('slice', 'The bounded slice is implemented.')],
      'out_of_scope': ['Unrelated project work.'],
    }, commandId: 'add-1');
    expect(repeated['ok'], isTrue);
    expect(repeated['task_id'], 1);

    final updated = await invokePlanning(registry, 'task_upsert', {
      'task_id': 1,
      'title': 'Scaffold the reviewed slice',
    });
    expect(updated['ok'], isTrue);
    expect(updated['task_id'], 1);

    final attemptedCreateWithId = await invokePlanning(
      registry,
      'task_upsert',
      {
        'id': 'pretend_replace',
        'title': 'Invalid replacement',
        'objective': 'Invalid replacement.',
        'acceptance': [_acceptance('checked', 'It is checked.')],
        'out_of_scope': ['Unrelated work.'],
      },
    );
    expect(attemptedCreateWithId['ok'], isFalse);
    expect(attemptedCreateWithId['code'], 'invalid_argument');
    expect(attemptedCreateWithId['path'], 'id');

    final view = await invokePlanning(registry, 'project_view', {});
    expect(view['ok'], isTrue);
    expect(((view['draft'] as Map)['diff'] as Map)['added_tasks'], isNotEmpty);
    expect(
      ((view['tasks'] as List).single as Map)['title'],
      'Scaffold the reviewed slice',
    );

    final detail = await invokePlanning(registry, 'project_view', {
      'task_id': 1,
    });
    expect(detail['ok'], isTrue);
    expect((detail['task_detail'] as Map)['task_id'], 1);
    expect(
      (detail['task_detail'] as Map)['title'],
      'Scaffold the reviewed slice',
    );
  });

  test(
    'preview and commit return compact validation and diff results',
    () async {
      final registry = _registry();
      final added = await invokePlanning(registry, 'task_upsert', {
        'objective': 'Implement and verify the bounded slice.',
        'acceptance': [_acceptance('slice', 'The bounded slice is verified.')],
        'out_of_scope': ['Unrelated project work.'],
      });
      expect(added['ok'], isTrue);

      final preview = await invokePlanning(registry, 'project_view', {});
      expect(preview['ok'], isTrue);
      expect((preview['draft'] as Map)['valid'], isTrue);
      expect(
        ((preview['draft'] as Map)['diff'] as Map)['added_tasks'],
        hasLength(1),
      );

      final committed = await invokePlanning(registry, 'plan_commit', {});
      expect(committed['ok'], isTrue);
      expect(committed['changed'], isTrue);
      expect(committed['awaiting_approval'], isFalse);

      final afterCommit = await invokePlanning(registry, 'task_upsert', {
        'task_id': 1,
        'title': 'This must not be applied after commit.',
      });
      expect(afterCommit['ok'], isFalse);
      expect(afterCommit['code'], 'draft_closed');
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
    expect((detail['failure'] as Map)['key'], 'command_passes|exit_1');
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
        final added = await invokePlanning(registry, 'task_upsert', {
          'objective': 'Implement bounded slice $index.',
          'acceptance': [
            _acceptance('slice_$index', 'Bounded slice $index is verified.'),
          ],
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

  test(
    'simplified planning surface submits a complete draft atomically',
    () async {
      final base = _emptyProject();
      final registry = ProjectPlanningToolRegistry(
        context: ProjectPlanningContext(
          project: base,
          workspaceRoot: '/workspace',
          planningPass: ProjectPlanningPass.bootstrap,
          planningLimits: ProjectPlanningLimits.bootstrap,
          approvalPolicy: ProjectPlanApprovalPolicy.never,
        ),
        profile: ProjectPlanningToolProfile.bootstrap,
      );

      final submitted = await invokePlanning(registry, 'project_submit_plan', {
        'title': 'Verified project',
        'refined_goal': 'Deliver the verified outcome.',
        'constraints': ['Stay within the workspace.'],
        'criteria': [
          {'statement': 'The main outcome is verified.'},
        ],
        'milestones': [
          {
            'title': 'First slice',
            'objective': 'Deliver the first executable slice.',
            'criterion_ids': [1],
          },
        ],
        'tasks': [
          {
            'objective': 'Implement the first slice.',
            'acceptance': [
              _acceptance(
                'implementation-verified',
                'The first slice is implemented.',
                criterion: '1',
                command: 'dart test',
              ),
            ],
            'out_of_scope': ['Unrelated work.'],
            'milestone_id': 1,
          },
          {
            'objective': 'Verify the first slice.',
            'acceptance': [
              _acceptance(
                'report-verified',
                'The verification report is available.',
                criterion: '1',
              ),
            ],
            'dependency_task_ids': [1],
            'out_of_scope': ['Changing the implementation.'],
          },
        ],
      });

      expect(submitted['ok'], isTrue);
      expect(submitted['next_action'], 'plan_commit');
      expect((submitted['draft'] as Map)['valid'], isTrue);
      final draftProject = (submitted['draft'] as Map)['project'] as Map;
      expect(
        (draftProject['tasks'] as List).map((item) => (item as Map)['task_id']),
        [1, 2],
      );
      expect(
        (draftProject['criteria'] as List).map(
          (item) => (item as Map)['criterion_id'],
        ),
        [1],
      );

      final committed = await invokePlanning(registry, 'plan_commit', {});
      expect(committed['ok'], isTrue);
      expect(committed['changed'], isTrue);
    },
  );

  test(
    'simplified planning mutations roll back inline work on failure',
    () async {
      final base = _project().copyWith(
        criteria: const [],
        milestones: const [],
      );
      final context = ProjectPlanningContext(
        project: base,
        workspaceRoot: '/workspace',
        planningPass: ProjectPlanningPass.bootstrap,
        planningLimits: ProjectPlanningLimits.bootstrap,
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );
      final registry = ProjectPlanningToolRegistry(
        context: context,
        profile: ProjectPlanningToolProfile.bootstrap,
      );

      final invalid = await invokePlanning(registry, 'project_submit_plan', {
        'title': 'Invalid project',
        'refined_goal': 'This must not partially apply.',
        'criteria': [
          {
            'statement': 'The outcome is deterministic.',
            'verification_mode': 'deterministic',
          },
        ],
        'tasks': [
          {
            'objective': 'Forget the required acceptance.',
            'acceptance': [
              _acceptance(
                'invalid-link',
                'It is done.',
                criterion: 'missing-criterion',
              ),
            ],
            'out_of_scope': ['Everything else.'],
          },
        ],
      });

      expect(invalid['ok'], isFalse);
      expect(invalid['path'], contains('criterion'));
      final view = await invokePlanning(registry, 'project_view', {});
      expect((view['criteria'] as List), isEmpty);
      expect((view['tasks'] as List), isEmpty);
    },
  );

  test(
    'project update and task upsert support independent metadata and acceptance',
    () async {
      final registry = _registry();
      final projectUpdate = await invokePlanning(registry, 'project_update', {
        'title': 'Updated project',
        'criteria': [
          {'criterion_id': 1, 'statement': 'The updated outcome is verified.'},
        ],
        'milestones': [
          {
            'title': 'Verification',
            'objective': 'Verify the updated outcome.',
            'criterion_ids': [1],
          },
        ],
      });
      expect(projectUpdate['ok'], isTrue);

      final created = await invokePlanning(registry, 'task_upsert', {
        'objective': 'Implement the updated outcome.',
        'acceptance': [
          _acceptance('updated-outcome', 'The updated outcome is implemented.'),
        ],
        'milestone_id': 1,
        'out_of_scope': ['Unrelated work.'],
      });
      expect(created['ok'], isTrue);
      expect(created['task_id'], 1);

      final updated = await invokePlanning(registry, 'task_upsert', {
        'task_id': 1,
        'objective': 'Implement and verify the updated outcome.',
        'acceptance': [
          _acceptance(
            'updated-outcome',
            'The updated outcome is implemented and verified.',
            command: 'dart test',
          ),
        ],
      });
      expect(updated['ok'], isTrue);
      expect(updated['task_id'], 1);

      final view = await invokePlanning(registry, 'project_view', {
        'task_id': 1,
      });
      expect(view['ok'], isTrue);
      expect((view['task_detail'] as Map)['objective'], contains('verify'));
      final acceptance =
          (view['task_detail'] as Map)['acceptance'] as List<dynamic>;
      expect(acceptance, hasLength(1));
      expect((acceptance.single as Map)['ref'], 'updated-outcome');
    },
  );

  test('numeric planning references survive commit and reload', () async {
    final context = ProjectPlanningContext(
      project: _emptyProject(),
      workspaceRoot: '/workspace',
      planningPass: ProjectPlanningPass.bootstrap,
      planningLimits: ProjectPlanningLimits.bootstrap,
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );
    final registry = ProjectPlanningToolRegistry(
      context: context,
      profile: ProjectPlanningToolProfile.bootstrap,
    );

    final submitted = await invokePlanning(registry, 'project_submit_plan', {
      'title': 'Stable references',
      'refined_goal': 'Keep references stable.',
      'criteria': [
        {'statement': 'The references remain stable.'},
      ],
      'tasks': [
        {
          'objective': 'Persist the reference table.',
          'acceptance': [
            _acceptance(
              'reference-table',
              'The table is persisted.',
              criterion: '1',
            ),
          ],
          'out_of_scope': ['Changing execution.'],
        },
      ],
    });
    expect(submitted['ok'], isTrue);
    final committed = await invokePlanning(registry, 'plan_commit', {});
    expect(committed['ok'], isTrue);

    final committedProject = context.committedProject!;
    expect(
      committedProject.criterionAgentNumber(
        committedProject.criteria.single.id,
      ),
      1,
    );
    expect(
      committedProject.taskAgentNumber(committedProject.tasks.single.id),
      1,
    );

    final reloaded = ProjectSnapshotCodec.decode(
      ProjectSnapshotCodec.encode(committedProject),
    );
    expect(reloaded.criterionAgentNumber(reloaded.criteria.single.id), 1);
    expect(reloaded.taskAgentNumber(reloaded.taskIds.single), 1);
  });
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

ProjectAggregate _emptyProject() {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
    id: 'project_empty',
    title: 'Untitled project',
    originalGoal: 'Deliver a bounded outcome.',
    refinedGoal: 'Deliver a bounded outcome.',
    criteria: const [],
    constraints: const [],
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
  final artifactPath = 'artifacts/$id.txt';
  return TaskAggregate(
    id: id,
    title: 'Bounded slice $id',
    objective: objective,
    writePaths: [artifactPath],
    acceptance: [
      AcceptanceItem(
        ref: 'slice-check',
        statement: 'The bounded slice is independently checked.',
        criterionIds: const ['criterion_001'],
        verifiers: [
          AcceptanceVerifier(
            kind: AcceptanceVerifierKind.artifact,
            path: artifactPath,
            description: 'The bounded slice is independently checked.',
          ),
        ],
      ),
    ],
    outOfScope: const ['Unrelated project work.'],
    status: TaskStatus.queued,
    fingerprint: projectTaskFingerprint(objective, const ['criterion_001']),
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, dynamic> _acceptance(
  String ref,
  String statement, {
  String criterion = 'criterion_001',
  String? command,
}) => {
  'ref': ref,
  'statement': statement,
  'criterion_refs': [criterion],
  'verifiers': [
    {
      'kind': command == null ? 'review' : 'command',
      'required': true,
      if (command case final value?) 'command': value,
      if (command != null) 'working_directory': '.',
    },
  ],
};

bool _containsKey(Object? value, String key) {
  if (value is Map) {
    if (value.containsKey(key)) return true;
    return value.values.any((item) => _containsKey(item, key));
  }
  if (value is Iterable) return value.any((item) => _containsKey(item, key));
  return false;
}
