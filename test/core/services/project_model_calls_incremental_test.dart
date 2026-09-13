import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_model_calls.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  test(
    'revision commands update an existing task without replacing its ID',
    () async {
      final calls = ProjectModelCalls(
        toolService: ToolService(workspaceSandbox: WorkspaceSandbox()),
      );
      final client = _Client([
        _call('plan_update_task', {
          'task': 'task_existing',
          'objective': 'Update the bounded implementation after the failure.',
        }),
        _call('plan_commit', const {}),
      ]);

      final result = await calls.revisePlanWithCommands(
        client: client,
        baseSystemPrompt: 'Use the planning tools.',
        workspace: _workspace(),
        project: _project(tasks: [_task('task_existing')]),
        evidenceSnapshot: _snapshot(),
        triggers: const [ProjectPlanRevisionTrigger.taskFailed],
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(result.committed, isTrue);
      expect(
        result.project.taskById('task_existing')?.objective,
        contains('after the failure'),
      );
      expect(
        result.project.tasks.where((task) => task.id == 'task_existing'),
        hasLength(1),
      );
      expect(client.toolNames, contains('plan_update_task'));
      expect(client.toolNames, isNot(contains('finaliseProjectCreation')));
    },
  );

  test(
    'split commands preserve the parent and generate fresh child IDs',
    () async {
      final calls = ProjectModelCalls(
        toolService: ToolService(workspaceSandbox: WorkspaceSandbox()),
      );
      final client = _Client([
        _call('project_view', {'task_ref': 'task_existing'}),
        _call('plan_split_task', {
          'task': 'task_existing',
          'children': [
            {
              'ref': 'inspect',
              'objective': 'Inspect the bounded implementation boundary.',
              'criterion_refs': ['criterion_1'],
              'done_criteria': ['The boundary is documented.'],
              'out_of_scope': ['Changing the implementation.'],
            },
            {
              'ref': 'repair',
              'objective': 'Repair the bounded implementation boundary.',
              'criterion_refs': ['criterion_1'],
              'done_criteria': ['The boundary repair is verified.'],
              'out_of_scope': ['Unrelated project work.'],
            },
          ],
        }),
        _call('plan_commit', const {}),
      ]);
      final project = _project(tasks: [_task('task_existing')]);

      final result = await calls.splitTaskWithCommands(
        client: client,
        baseSystemPrompt: 'Use the planning tools.',
        workspace: _workspace(),
        project: project,
        oversizedTask: project.taskById('task_existing')!,
        violations: const ['The task is too broad.'],
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(result.committed, isTrue);
      expect(
        result.project.taskById('task_existing')?.status,
        TaskStatus.split,
      );
      final children = result.project.tasks
          .where((task) => task.id != 'task_existing')
          .toList();
      expect(children, hasLength(2));
      expect(children.every((task) => task.id != 'task_existing'), isTrue);
      expect(
        children.every((task) => task.status == TaskStatus.queued),
        isTrue,
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

WorkspaceAttachment _workspace() => WorkspaceAttachment(
  rootPath: '/workspace',
  displayName: 'Workspace',
  lastOpenedAt: DateTime(2026, 1, 1),
);

ProjectEvidenceSnapshot _snapshot() => ProjectEvidenceSnapshot(
  workspaceName: 'Workspace',
  collectedAt: DateTime(2026, 1, 1),
);

ProjectState _project({List<Task> tasks = const []}) {
  final now = DateTime(2026, 1, 1);
  return ProjectState(
    id: 'project_incremental',
    title: 'Incremental project',
    originalGoal: 'Deliver a bounded outcome.',
    refinedGoal: 'Deliver a bounded outcome.',
    criteria: [
      ProjectCriterion(
        id: 'criterion_1',
        statement: 'The bounded outcome is verified.',
        createdAt: now,
        updatedAt: now,
        verifiedAt: null,
      ),
    ],
    constraints: const ['Stay within the attached workspace.'],
    tasks: tasks,
    milestones: const [],
    memory: const [],
    planHistory: const [],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(String id) {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: id,
    title: 'Bounded implementation',
    objective: 'Implement the bounded outcome.',
    criterionIds: const ['criterion_1'],
    expectedEvidence: const [
      TaskEvidenceExpectation(
        id: 'expectation_1',
        type: ProjectEvidenceType.taskClaim,
        criterionIds: ['criterion_1'],
        description: 'The bounded outcome is verified.',
      ),
    ],
    doneCriteria: const ['The bounded outcome is verified.'],
    outOfScope: const ['Unrelated project work.'],
    status: TaskStatus.queued,
    fingerprint: 'bounded-implementation',
    createdAt: now,
    updatedAt: now,
  );
}

class _Client extends ChatClient {
  _Client(this._responses) : super(baseUrl: 'http://localhost', model: 'test');

  final List<ChatCompletionToolCall> _responses;
  final List<String> toolNames = [];
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
    if (_index < _responses.length) toolNames.add(_responses[_index].name);
    return ChatCompletionResponse(
      content: '',
      toolCalls: [_responses[_index++]],
    );
  }

  @override
  void dispose() {}
}
