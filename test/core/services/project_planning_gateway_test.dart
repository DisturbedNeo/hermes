import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_model_calls.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  group('ProjectPlanningGateway contract', () {
    late Directory root;
    late WorkspaceAttachment workspace;
    late _FakeProjectPlanningGateway gateway;
    late ProjectService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_project_gateway_');
      workspace = WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      gateway = _FakeProjectPlanningGateway();
      final sandbox = WorkspaceSandbox();
      service = ProjectService(
        taskService: TaskService(
          toolService: ToolService(workspaceSandbox: sandbox),
          sandbox: sandbox,
        ),
        modelCalls: gateway,
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'initialization proposal still passes through question policy',
      () async {
        gateway.initialisation = ProjectInitialisation(
          title: 'Release project',
          refinedGoal: 'Publish a release',
          successCriteria: const ['The release is published.'],
          constraints: const ['Use the selected account.'],
          knownFacts: const [],
          openQuestions: [
            PendingProjectQuestion(
              id: 'question_account',
              question: 'Which publishing account should be used?',
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          backlog: const [],
        );

        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Publish the release',
          client: _QueueChatClient(const []),
          baseSystemPrompt: 'system',
        );

        expect(gateway.initializeCalls, 1);
        expect(project.status, ProjectStatus.waitingForUser);
        expect(project.pendingQuestion?.id, 'question_account');
        expect(project.blocker?.type, ProjectBlockerType.question);
      },
    );

    test('initialization persists a structured roadmap and backlog', () async {
      final now = DateTime(2026, 1, 1);
      final task = _projectTask().copyWith(
        criterionIds: const ['criterion_release'],
        milestoneId: 'milestone_release',
      );
      gateway.initialisation = ProjectInitialisation(
        title: 'Release project',
        refinedGoal: 'Publish a verified release',
        successCriteria: const ['The release is verified.'],
        constraints: const ['Stay in the workspace.'],
        knownFacts: const [],
        openQuestions: const [],
        backlog: [task],
        criteria: [
          ProjectCriterion(
            id: 'criterion_release',
            statement: 'The release is verified.',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        milestones: [
          ProjectMilestone(
            id: 'milestone_release',
            title: 'Prepare release',
            objective: 'Prepare and verify the release.',
            criterionIds: const ['criterion_release'],
            exitConditions: const ['The release is verified.'],
            taskIds: [task.id],
            order: 1,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );

      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Publish the release',
        client: _QueueChatClient(const []),
      );

      expect(project.criteria.single.id, 'criterion_release');
      expect(project.milestones.single.id, 'milestone_release');
      expect(project.milestones.single.status, ProjectMilestoneStatus.active);
      expect(project.backlog.single.milestoneId, 'milestone_release');
      expect(
        project.planHistory.single.trigger,
        ProjectPlanRevisionTrigger.initialization,
      );
    });

    test('initialization does not queue work with no criterion link', () async {
      final now = DateTime(2026, 1, 1);
      gateway.initialisation = ProjectInitialisation(
        title: 'Unlinked project',
        refinedGoal: 'Complete linked work only',
        successCriteria: const ['Criterion one', 'Criterion two'],
        constraints: const ['Stay in the workspace.'],
        knownFacts: const [],
        openQuestions: const [],
        backlog: [_projectTask().copyWith(criterionIds: const [])],
        criteria: [
          ProjectCriterion(
            id: 'criterion_one',
            statement: 'Criterion one',
            createdAt: now,
            updatedAt: now,
          ),
          ProjectCriterion(
            id: 'criterion_two',
            statement: 'Criterion two',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );

      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Complete the project',
        client: _QueueChatClient(const []),
      );

      expect(project.backlog, isEmpty);
      expect(project.planHistory.single.addedTaskIds, isEmpty);
    });

    test(
      'model revisions bind tasks to criteria introduced in the same revision',
      () async {
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the app',
        );
        final modelCalls = ProjectModelCalls(
          toolService: ToolService(workspaceSandbox: WorkspaceSandbox()),
        );
        final client = _QueueChatClient([
          jsonEncode({
            'summary': 'Add an accessibility outcome and bounded task.',
            'rationale': 'The new outcome needs explicit verification.',
            'criterionUpserts': [
              {
                'id': 'criterion_accessibility',
                'statement': 'The workflow is keyboard accessible.',
                'required': true,
                'verificationMode': 'deterministic',
              },
            ],
            'taskAdditions': [
              {
                'id': 'task_accessibility',
                'title': 'Verify keyboard access',
                'objective': 'Implement and verify keyboard navigation.',
                'criterionIds': ['criterion_accessibility'],
                'doneCriteria': ['Keyboard navigation is verified.'],
                'outOfScope': ['Do not redesign unrelated screens.'],
                'expectedEvidence': [
                  {
                    'id': 'expect_keyboard_test',
                    'type': 'command',
                    'criterionIds': ['criterion_accessibility'],
                    'description': 'The keyboard navigation tests pass.',
                    'sourceRef': 'flutter test',
                  },
                ],
              },
            ],
          }),
        ]);

        final proposal = await modelCalls.revisePlan(
          client: client,
          baseSystemPrompt: 'system',
          workspace: workspace,
          project: project,
          evidenceSnapshot: ProjectEvidenceSnapshot(
            workspaceName: workspace.displayName,
            collectedAt: DateTime(2026, 1, 2),
          ),
          triggers: const [ProjectPlanRevisionTrigger.newContext],
        );

        expect(proposal.criterionUpserts.single.id, 'criterion_accessibility');
        expect(proposal.taskAdditions.single.criterionIds, [
          'criterion_accessibility',
        ]);
        expect(
          proposal.taskAdditions.single.expectedEvidence.single.criterionIds,
          ['criterion_accessibility'],
        );
      },
    );

    test('multiple pending triggers produce one debounced revision', () async {
      final created = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
      );
      final queued = _projectTask().copyWith(
        criterionIds: [created.criteria.single.id],
        status: ProjectTaskStatus.deferred,
        readiness: ProjectTaskReadiness.notEligible,
        readinessReasons: const ['Deferred integration fixture.'],
        expectedEvidence: [
          ProjectEvidenceExpectation(
            id: 'expect_revision_task',
            type: ProjectEvidenceType.taskClaim,
            criterionIds: [created.criteria.single.id],
            description: 'Verify the bounded revision task.',
          ),
        ],
      );
      gateway.proposalBuilder = (project, triggers) => ProjectPlanProposal(
        revision: project.currentRevision + 1,
        triggers: triggers,
        summary: 'Respond to combined triggers.',
        rationale: 'One revision handles the whole transition.',
        taskAdditions: [queued],
        createdAt: DateTime(2026, 1, 2),
      );
      final pending = created.copyWith(
        pendingReplanTriggers: const [
          ProjectPlanRevisionTrigger.taskCompleted,
          ProjectPlanRevisionTrigger.milestoneCompleted,
          ProjectPlanRevisionTrigger.taskCompleted,
        ],
      );

      final result = await service.runProject(
        client: _FinalizerChatClient(),
        workspace: workspace,
        snapshot: pending,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
        requirePhaseApproval: true,
      );

      expect(gateway.reviseCalls, 1);
      expect(gateway.lastTriggers, {
        ProjectPlanRevisionTrigger.taskCompleted,
        ProjectPlanRevisionTrigger.milestoneCompleted,
      });
      expect(result.project.currentRevision, 2);
      expect(result.project.planHistory, hasLength(2));
      expect(result.project.pendingReplanTriggers, isEmpty);
    });

    test(
      'replanning receives bounded relevant memory without pruning history',
      () async {
        final created = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the app',
        );
        final now = DateTime(2026, 1, 1);
        final memory = [
          for (var index = 0; index < 30; index++)
            ProjectMemoryEntry(
              id: 'fact_$index',
              kind: ProjectMemoryKind.fact,
              content: 'Historical fact $index ${List.filled(500, 'x').join()}',
              sourceType: ProjectMemorySourceType.task,
              sourceId: 'task_$index',
              confidence: ProjectMemoryConfidence.inferred,
              createdAt: now,
              updatedAt: now.add(Duration(minutes: index)),
            ),
          ProjectMemoryEntry(
            id: 'protected_requirement',
            kind: ProjectMemoryKind.requirement,
            content: 'Never break the public API.',
            sourceType: ProjectMemorySourceType.user,
            confidence: ProjectMemoryConfidence.confirmed,
            protected: true,
            createdAt: now,
            updatedAt: now,
          ),
        ];
        final pending = created.copyWith(
          memory: memory,
          pendingReplanTriggers: const [ProjectPlanRevisionTrigger.manual],
        );

        final result = await service.runProject(
          client: _QueueChatClient(const []),
          workspace: workspace,
          snapshot: pending,
          baseSystemPrompt: 'system',
          maxNewTasks: 1,
        );

        expect(gateway.lastRevisionProject, isNotNull);
        expect(
          gateway.lastRevisionProject!.memory.length,
          lessThan(memory.length),
        );
        expect(
          gateway.lastRevisionProject!.memory.map((entry) => entry.id),
          contains('protected_requirement'),
        );
        expect(result.project.memory, hasLength(memory.length));
      },
    );

    test('rejecting a pending revision preserves the current plan', () async {
      final created = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
      );
      final proposal = ProjectPlanProposal(
        revision: 2,
        triggers: const [ProjectPlanRevisionTrigger.newContext],
        summary: 'Change the project scope.',
        rationale: 'New context suggested a scope change.',
        criterionUpserts: [
          created.criteria.single.copyWith(
            statement: 'A changed outcome is delivered.',
          ),
        ],
        createdAt: DateTime(2026, 1, 2),
      );
      final pending = created.copyWith(
        pendingPlanApproval: PendingProjectPlanApproval(
          revision: 2,
          reason: 'Success criteria would change.',
          summary: proposal.summary,
          highRiskChanges: const ['Success criteria change.'],
          createdAt: proposal.createdAt,
          proposal: proposal,
        ),
        status: ProjectStatus.paused,
        blocker: ProjectBlocker(
          type: ProjectBlockerType.planApproval,
          message: 'Success criteria would change.',
          createdAt: DateTime(2026, 1, 2),
        ),
      );

      final rejected = await service.rejectPlanRevision(
        workspace: workspace,
        snapshot: pending,
      );

      expect(rejected.pendingPlanApproval, isNull);
      expect(rejected.currentRevision, 1);
      expect(
        rejected.criteria.single.statement,
        created.criteria.single.statement,
      );
      expect(rejected.blocker?.type, ProjectBlockerType.planApproval);
      expect(
        rejected.decisions.last.decision,
        ProjectDecisionType.rejectPlanRevision,
      );
    });

    test(
      'queued work bypasses proposal and completes after assessment',
      () async {
        final created = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the app',
        );
        final queued = _projectTask();
        final project = created.copyWith(
          backlog: [queued],
          successCriteria: queued.relevantSuccessCriteria,
        );
        gateway.completionAssessment = const ProjectCompletionAssessment(
          complete: true,
          finalSummary: 'The queued project work is complete.',
          remainingCriteria: [],
          openQuestions: [],
        );
        final client = _QueueChatClient([
          jsonEncode(_taskPlanJson()),
          jsonEncode({
            'status': 'completed',
            'summary': 'Queued task complete.',
            'memoryUpdate': 'The bounded work is done.',
          }),
        ]);

        final result = await service.runProject(
          client: client,
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 1,
        );

        expect(result.project.status, ProjectStatus.completed);
        expect(gateway.reviseCalls, 0);
        expect(gateway.evaluateCalls, 1);
        expect(result.project.completedTasks.single.id, queued.id);
        expect(result.activeTask?.status, TaskStatus.completed);
      },
    );

    test(
      'deterministic accepted gate evidence completes without review',
      () async {
        final created = await service.createProject(
          workspace: workspace,
          userPrompt: 'Verify the queued slice',
        );
        final criterion = created.criteria.single.copyWith(
          verificationMode: ProjectVerificationMode.deterministic,
        );
        final queued = _projectTask().copyWith(
          criterionIds: [criterion.id],
          expectedEvidence: [
            ProjectEvidenceExpectation(
              id: 'expect_no_tool_errors',
              type: ProjectEvidenceType.gate,
              criterionIds: [criterion.id],
              description: 'The bounded task must have no tool errors.',
              sourceRef: 'no_tool_errors',
            ),
          ],
        );
        final project = created.copyWith(
          criteria: [criterion],
          backlog: [queued],
        );
        final client = _QueueChatClient([
          jsonEncode(_taskPlanJson()),
          jsonEncode({
            'status': 'completed',
            'summary': 'Verified without tool errors.',
            'memoryUpdate': '',
          }),
        ]);

        final result = await service.runProject(
          client: client,
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 1,
        );

        expect(result.project.status, ProjectStatus.completed);
        expect(
          result.project.criteria.single.status,
          ProjectCriterionStatus.satisfied,
        );
        expect(
          result.project.evidence.any((item) {
            return item.status == ProjectEvidenceStatus.accepted &&
                item.strength == ProjectEvidenceStrength.conclusive;
          }),
          isTrue,
        );
        expect(gateway.evaluateCalls, 0);
      },
    );

    test(
      'a completion assertion cannot bypass missing criterion evidence',
      () async {
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Complete without evidence',
        );
        gateway.completionAssessment = const ProjectCompletionAssessment(
          complete: true,
          finalSummary: 'Unsupported completion assertion.',
          remainingCriteria: [],
          openQuestions: [],
        );

        final result = await service.runProject(
          client: _QueueChatClient(const []),
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 1,
        );

        expect(result.project.status, ProjectStatus.blocked);
        expect(
          result.project.criteria.single.status,
          ProjectCriterionStatus.unsatisfied,
        );
        expect(gateway.evaluateCalls, 0);
      },
    );

    test('invalidated required criteria do not block completion', () async {
      final created = await service.createProject(
        workspace: workspace,
        userPrompt: 'Complete the remaining in-scope work',
      );
      final project = created.copyWith(
        criteria: [
          created.criteria.single.copyWith(
            status: ProjectCriterionStatus.invalidated,
            notes: 'Removed from scope by an approved revision.',
          ),
        ],
      );

      final result = await service.runProject(
        client: _QueueChatClient(const []),
        workspace: workspace,
        snapshot: project,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      expect(result.project.status, ProjectStatus.completed);
      expect(gateway.evaluateCalls, 0);
    });
  });
}

class _FakeProjectPlanningGateway implements ProjectPlanningGateway {
  ProjectInitialisation initialisation = const ProjectInitialisation(
    title: 'Project',
    refinedGoal: 'Complete the project',
    successCriteria: ['Complete the stated project goal.'],
    constraints: ['Stay within the attached workspace.'],
    knownFacts: [],
    openQuestions: [],
    backlog: [],
  );
  ProjectCompletionAssessment completionAssessment =
      const ProjectCompletionAssessment(
        complete: false,
        finalSummary: '',
        remainingCriteria: ['Complete the stated project goal.'],
        openQuestions: [],
      );
  int initializeCalls = 0;
  int reviseCalls = 0;
  int repairCalls = 0;
  ProjectPlanProposal Function(
    ProjectState project,
    List<ProjectPlanRevisionTrigger> triggers,
  )?
  proposalBuilder;
  Set<ProjectPlanRevisionTrigger> lastTriggers = const {};
  ProjectState? lastRevisionProject;
  int evaluateCalls = 0;

  @override
  Future<ProjectInitialisation> initializeProject({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required String originalGoal,
    required Map<String, dynamic> workspaceMetadata,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    initializeCalls++;
    return initialisation;
  }

  @override
  Future<ProjectCompletionAssessment> evaluateCompletion({
    required ChatClient client,
    required String baseSystemPrompt,
    required ProjectState project,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    evaluateCalls++;
    return completionAssessment;
  }

  @override
  Future<ProjectPlanProposal> revisePlan({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectEvidenceSnapshot evidenceSnapshot,
    required List<ProjectPlanRevisionTrigger> triggers,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    reviseCalls++;
    lastRevisionProject = project;
    lastTriggers = triggers.toSet();
    final builder = proposalBuilder;
    if (builder != null) return builder(project, triggers);
    return ProjectPlanProposal(
      revision: project.currentRevision + 1,
      triggers: triggers,
      summary: 'No change',
      rationale: 'No safe change is available.',
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<ProjectPlanProposal?> repairPlanProposal({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectPlanProposal proposal,
    required List<Map<String, String>> validationIssues,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    repairCalls++;
    return null;
  }

  @override
  Future<List<ProjectTask>> splitTask({
    required ChatClient client,
    required String baseSystemPrompt,
    required ProjectState project,
    required ProjectTask oversizedTask,
    required List<String> violations,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    return const [];
  }
}

class _QueueChatClient extends ChatClient {
  _QueueChatClient(this.responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<String> responses;
  int index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    if (responses.isEmpty) {
      throw StateError('No model response was expected for this test.');
    }
    final responseIndex = index >= responses.length
        ? responses.length - 1
        : index;
    index++;
    return ChatCompletionResponse(content: responses[responseIndex]);
  }

  @override
  void dispose() {}
}

class _FinalizerChatClient extends ChatClient {
  _FinalizerChatClient() : super(baseUrl: 'http://localhost', model: 'test');

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    return ChatCompletionResponse(
      content: '',
      toolCalls: [
        ChatCompletionToolCall(
          name: 'finaliseTaskCreation',
          arguments: jsonEncode(_taskPlanJson()),
        ),
      ],
    );
  }

  @override
  void dispose() {}
}

ProjectTask _projectTask() {
  final now = DateTime(2026, 1, 1);
  const objective = 'Implement the queued application slice.';
  const criteria = ['The queued application slice is complete.'];
  return ProjectTask(
    id: 'project_task_queued',
    title: 'Implement queued slice',
    objective: objective,
    relevantSuccessCriteria: criteria,
    doneCriteria: const ['The queued slice is implemented and summarized.'],
    outOfScope: const ['Do not implement unrelated project work.'],
    context: const [],
    expectedArtifacts: const [],
    status: ProjectTaskStatus.queued,
    taskDocumentId: null,
    fingerprint: projectTaskFingerprint(objective, criteria),
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, dynamic> _taskPlanJson() {
  return {
    'title': 'Implement queued slice',
    'goal': 'Implement the queued application slice.',
    'constraints': ['Stay inside the workspace.'],
    'successCriteria': ['The queued slice is implemented and summarized.'],
    'steps': [
      {
        'id': 'implement',
        'title': 'Implement slice',
        'objective': 'Implement the bounded queued slice.',
        'instructions': ['Complete only the queued project work.'],
        'mayEditFiles': false,
      },
    ],
  };
}
