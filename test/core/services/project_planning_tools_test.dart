import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/project_system/project_planning_tools.dart';
import 'package:hermes/core/services/project_system/project_planning_workspace_reader.dart';
import 'package:hermes/core/services/project_system/project_view_service.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
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
        'plan_add_tasks',
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

    final taskProperties =
        ((registry.toolDefinitions
                        .singleWhere((item) => item.id == 'plan_add_tasks')
                        .schema['properties']
                    as Map)['tasks']
                as Map)['items']
            as Map;
    final properties = taskProperties['properties'] as Map;
    expect(properties.keys, isNot(contains('id')));
    expect(properties.keys, isNot(contains('status')));
    expect(properties.keys, isNot(contains('runs')));
    expect(properties.keys, isNot(contains('gates')));
    expect(
      registry.toolDefinitions.map((item) => item.schema.toString()).join(),
      isNot(contains('ProjectState')),
    );
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

    final result = await registry.invoke('planning_read_file', {
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
      final updated = await registry.invoke('plan_set_project_details', {
        'title': 'A more precise project',
        'refined_goal': 'Deliver the verified bounded outcome.',
        'constraints': ['Use only the attached workspace.'],
      });

      expect(updated['ok'], isTrue);
      final view = await registry.invoke('project_view', {});
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
      final added = await registry.invoke('plan_add_tasks', {
        'tasks': [
          {
            'ref': 'scaffold',
            'title': 'Scaffold the bounded slice',
            'objective': 'Create the bounded project slice.',
            'criterion_refs': ['criterion_001'],
            'done_criteria': ['The bounded slice is implemented.'],
            'out_of_scope': ['Unrelated project work.'],
          },
        ],
      }, commandId: 'add-1');

      expect(added['ok'], isTrue);
      final taskId = (((added['tasks'] as List).single as Map)['id']) as String;
      expect(taskId, startsWith('task_'));

      final repeated = await registry.invoke('plan_add_tasks', {
        'tasks': [
          {
            'ref': 'scaffold',
            'title': 'Scaffold the bounded slice',
            'objective': 'Create the bounded project slice.',
            'criterion_refs': ['criterion_001'],
            'done_criteria': ['The bounded slice is implemented.'],
            'out_of_scope': ['Unrelated project work.'],
          },
        ],
      }, commandId: 'add-1');
      expect(repeated['ok'], isTrue);
      expect(
        (((repeated['tasks'] as List).single as Map)['id']) as String,
        taskId,
      );

      final updated = await registry.invoke('plan_update_task', {
        'task': 'scaffold',
        'title': 'Scaffold the reviewed slice',
      });
      expect(updated['ok'], isTrue);
      expect((((updated['task'] as Map)['id']) as String), taskId);

      final attemptedCreateWithId = await registry.invoke('plan_add_tasks', {
        'tasks': [
          {
            'id': 'pretend_replace',
            'title': 'Invalid replacement',
            'criterion_refs': ['criterion_001'],
            'done_criteria': ['It is checked.'],
            'out_of_scope': ['Unrelated work.'],
          },
        ],
      });
      expect(attemptedCreateWithId['ok'], isFalse);
      expect(attemptedCreateWithId['code'], 'invalid_argument');
      expect(attemptedCreateWithId['path'], 'tasks[0].id');

      final view = await registry.invoke('project_view', {});
      expect(view['ok'], isTrue);
      expect(
        ((view['draft'] as Map)['diff'] as Map)['added_tasks'],
        contains(taskId),
      );
      expect(
        ((view['tasks'] as List).single as Map)['title'],
        'Scaffold the reviewed slice',
      );

      final detail = await registry.invoke('project_view', {
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
      final added = await registry.invoke('plan_add_tasks', {
        'tasks': [
          {
            'ref': 'checked',
            'objective': 'Implement and verify the bounded slice.',
            'criterion_refs': ['criterion_001'],
            'done_criteria': ['The bounded slice is verified.'],
            'out_of_scope': ['Unrelated project work.'],
          },
        ],
      });
      expect(added['ok'], isTrue);

      final preview = await registry.invoke('plan_preview', {
        'summary': 'Add the checked slice.',
        'rationale': 'The criterion needs one bounded implementation task.',
      });
      expect(preview['ok'], isTrue);
      expect((preview['preview'] as Map)['valid'], isTrue);
      expect(
        ((preview['preview'] as Map)['diff'] as Map)['added_tasks'],
        hasLength(1),
      );

      final committed = await registry.invoke('plan_commit', {});
      expect(committed['ok'], isTrue);
      expect(committed['changed'], isTrue);
      expect(committed['awaiting_approval'], isFalse);

      final afterCommit = await registry.invoke('plan_add_note', {
        'kind': 'assumption',
        'content': 'This must not be applied after commit.',
      });
      expect(afterCommit['ok'], isFalse);
      expect(afterCommit['code'], 'draft_closed');
    },
  );

  test(
    'a failed batch command does not leave an earlier item in the draft',
    () async {
      final registry = _registry();
      final result = await registry.invoke('plan_add_criteria', {
        'criteria': [
          {'ref': 'temporary', 'statement': 'This item must be rolled back.'},
          {'ref': 'invalid'},
        ],
      });

      expect(result['ok'], isFalse);
      expect(result['path'], 'criteria[1].statement');

      final dependent = await registry.invoke('plan_add_tasks', {
        'tasks': [
          {
            'ref': 'dependent',
            'objective': 'Use a criterion that should not exist.',
            'criterion_refs': ['temporary'],
            'done_criteria': ['The task is checked.'],
            'out_of_scope': ['Unrelated work.'],
          },
        ],
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
}

ProjectPlanningToolRegistry _registry() => ProjectPlanningToolRegistry(
  context: ProjectPlanningContext(
    project: _project(),
    workspaceRoot: '/workspace',
    approvalPolicy: ProjectPlanApprovalPolicy.never,
  ),
);

ProjectState _project({List<Task> tasks = const []}) {
  final now = DateTime(2026, 1, 1);
  return ProjectState(
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
    tasks: tasks,
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(String id) {
  final now = DateTime(2026, 1, 1);
  final objective = 'Implement bounded slice $id.';
  return Task(
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
