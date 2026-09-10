import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/project_system/project_model_calls.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  test('parses a complete desired plan rather than patch commands', () async {
    final now = DateTime(2026, 1, 1);
    final criterion = ProjectCriterion(
      id: 'criterion_1',
      statement: 'The bounded outcome is verified.',
      createdAt: now,
      updatedAt: now,
    );
    final project = ProjectDocument(
      id: 'project_1',
      title: 'Project',
      originalGoal: 'Deliver the outcome.',
      refinedGoal: 'Deliver the outcome safely.',
      criteria: [criterion],
      constraints: const [],
      tasks: const [],
      status: ProjectStatus.active,
      activeTaskId: null,
      createdAt: now,
      updatedAt: now,
    );
    final workspaceRoot = await Directory.systemTemp.createTemp(
      'hermes_gateway_',
    );
    addTearDown(() async => workspaceRoot.delete(recursive: true));
    final workspace = WorkspaceAttachment(
      rootPath: workspaceRoot.path,
      displayName: 'Workspace',
      lastOpenedAt: now,
    );
    final calls = ProjectModelCalls(
      toolService: ToolService(workspaceSandbox: WorkspaceSandbox()),
    );
    final desiredTask = {
      'id': 'task_1',
      'title': 'Verify outcome',
      'objective': 'Verify one bounded outcome.',
      'criterionIds': ['criterion_1'],
      'doneCriteria': ['The outcome is verified.'],
      'outOfScope': ['Unrelated work.'],
      'context': [],
      'expectedArtifacts': [],
      'expectedEvidence': [
        {
          'id': 'expect_1',
          'type': 'task_claim',
          'criterionIds': ['criterion_1'],
          'description': 'The task is independently checked.',
        },
      ],
    };

    final plan = await calls.revisePlan(
      client: _Client(
        jsonEncode({
          'summary': 'Add verification.',
          'rationale': 'The outcome needs a bounded verification task.',
          'criteria': [ModelJson.encode(criterion)],
          'milestones': [],
          'tasks': [desiredTask],
          'deferredTaskIds': [],
          'obsoleteTaskIds': [],
          'memoryAdditions': [],
          'memorySupersessions': [],
          'openQuestions': [],
          'requiresApproval': false,
          'approvalReason': '',
        }),
      ),
      baseSystemPrompt: 'system',
      workspace: workspace,
      project: project,
      evidenceSnapshot: ProjectEvidenceSnapshot(
        workspaceName: 'Workspace',
        collectedAt: DateTime(2026, 1, 1),
      ),
      triggers: const [ProjectPlanRevisionTrigger.noReadyTask],
    );

    expect(plan.revision, project.nextRevision);
    expect(plan.tasks.single.id, 'task_1');
    expect(plan.tasks.single.criterionIds, ['criterion_1']);
    expect(plan.criteria.single.id, 'criterion_1');
  });

  test('distinguishes omitted and explicit empty plan collections', () async {
    final now = DateTime(2026, 1, 1);
    final criterion = ProjectCriterion(
      id: 'criterion_1',
      statement: 'The bounded outcome is verified.',
      createdAt: now,
      updatedAt: now,
    );
    final task = Task(
      id: 'task_1',
      title: 'Verify outcome',
      objective: 'Verify one bounded outcome.',
      criterionIds: const ['criterion_1'],
      expectedEvidence: const [
        TaskEvidenceExpectation(
          id: 'expect_1',
          type: ProjectEvidenceType.taskClaim,
          criterionIds: ['criterion_1'],
          description: 'The outcome is independently checked.',
        ),
      ],
      doneCriteria: const ['The outcome is verified.'],
      outOfScope: const ['Unrelated work.'],
      context: const [],
      expectedArtifacts: const [],
      status: TaskStatus.queued,
      fingerprint: 'task_1',
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
    final deferredTask = task.copyWith(
      id: 'task_deferred',
      title: 'Deferred verification',
      fingerprint: 'task_deferred',
      status: TaskStatus.deferred,
    );
    final question = PendingProjectQuestion(
      id: 'question_1',
      question: 'Which irreversible option should be chosen?',
      createdAt: now,
    );
    final milestone = ProjectMilestone(
      id: 'milestone_1',
      title: 'Verification',
      objective: 'Verify the bounded outcome.',
      criterionIds: const ['criterion_1'],
      order: 1,
      createdAt: now,
      updatedAt: now,
    );
    final project = ProjectDocument(
      id: 'project_1',
      title: 'Project',
      originalGoal: 'Deliver the outcome.',
      refinedGoal: 'Deliver the outcome safely.',
      criteria: [criterion],
      constraints: const [],
      tasks: [task, deferredTask],
      milestones: [milestone],
      openQuestions: [question],
      status: ProjectStatus.active,
      activeTaskId: null,
      createdAt: now,
      updatedAt: now,
    );
    final workspaceRoot = await Directory.systemTemp.createTemp(
      'hermes_gateway_',
    );
    addTearDown(() async => workspaceRoot.delete(recursive: true));
    final workspace = WorkspaceAttachment(
      rootPath: workspaceRoot.path,
      displayName: 'Workspace',
      lastOpenedAt: now,
    );
    final calls = ProjectModelCalls(
      toolService: ToolService(workspaceSandbox: WorkspaceSandbox()),
    );

    Future<ProjectDesiredPlan> revise(Map<String, dynamic> response) {
      return calls.revisePlan(
        client: _Client(jsonEncode(response)),
        baseSystemPrompt: 'system',
        workspace: workspace,
        project: project,
        evidenceSnapshot: ProjectEvidenceSnapshot(
          workspaceName: 'Workspace',
          collectedAt: now,
        ),
        triggers: const [ProjectPlanRevisionTrigger.noReadyTask],
      );
    }

    final omitted = await revise({
      'summary': 'Preserve the current plan.',
      'rationale': 'The model did not return collection fields.',
    });
    expect(omitted.criteria.map((item) => item.id), ['criterion_1']);
    expect(omitted.hasCompleteCollections, isFalse);
    expect(omitted.tasks.map((item) => item.id), ['task_1', 'task_deferred']);
    expect(omitted.tasks.last.status, TaskStatus.deferred);
    expect(omitted.milestones.map((item) => item.id), ['milestone_1']);
    expect(omitted.openQuestions, [question]);

    final malformed = await revise({
      'summary': 'Preserve the current plan.',
      'rationale': 'The collection fields are malformed.',
      'criteria': 'not a collection',
      'milestones': {'not': 'a collection'},
      'tasks': [42],
    });
    expect(malformed.criteria.map((item) => item.id), ['criterion_1']);
    expect(malformed.hasCompleteCollections, isFalse);
    expect(malformed.tasks.map((item) => item.id), ['task_1', 'task_deferred']);
    expect(malformed.milestones.map((item) => item.id), ['milestone_1']);
    expect(malformed.openQuestions, [question]);

    final cleared = await revise({
      'summary': 'Clear the current plan.',
      'rationale': 'The desired collections are intentionally empty.',
      'criteria': [],
      'milestones': [],
      'tasks': [],
      'openQuestions': [],
    });
    expect(cleared.criteria, isEmpty);
    expect(cleared.hasCompleteCollections, isTrue);
    expect(cleared.tasks, isEmpty);
    expect(cleared.milestones, isEmpty);
    expect(cleared.openQuestions, isEmpty);
  });
}

class _Client extends ChatClient {
  _Client(this.response) : super(baseUrl: 'http://localhost', model: 'test');
  final String response;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async => ChatCompletionResponse(content: response);

  @override
  void dispose() {}
}
