import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/chat/task_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;
  late ChatLibraryService chatLibrary;
  late LlamaServerManager serverManager;
  late ToolService toolService;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    final sandbox = WorkspaceSandbox();
    toolService = ToolService(workspaceSandbox: sandbox);
    final taskService = TaskService(toolService: toolService, sandbox: sandbox);

    preferences = PreferencesService();
    final chatLibraryRepository = ChatLibraryRepository(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    chatLibrary = ChatLibraryService(repository: chatLibraryRepository);
    serverManager = LlamaServerManager();
    chat = ChatService(
      serverManager: serverManager,
      toolService: toolService,
      taskService: taskService,
      projectService: ProjectService(taskService: taskService),
      chatLibrary: chatLibrary,
      workspaceService: WorkspaceService(sandbox: sandbox),
      preferencesService: preferences,
    );
  });

  tearDown(() async {
    await chat.dispose();
    await serverManager.dispose();
    await chatLibrary.dispose();
  });

  testWidgets(
    'expanded panel renders artifact tiles without ListTile asserts',
    (tester) async {
      chat.activeTask = _taskWithArtifact();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: TaskPanel(
                chat: chat,
                expanded: true,
                onToggleExpanded: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('.agent/tasks/task_test/output.md'), findsOneWidget);
    },
  );

  testWidgets('expanded panel renders project state', (tester) async {
    chat.activeProject = _projectWithTask();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 640,
            child: TaskPanel(
              chat: chat,
              expanded: true,
              onToggleExpanded: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Project task'), findsOneWidget);
    expect(find.text('Recent Decisions'), findsOneWidget);
  });

  testWidgets('blocked recovery renders structured diagnostics and retry', (
    tester,
  ) async {
    chat.activeProject = _projectWithExhaustedRecovery();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 900,
            child: TaskPanel(
              chat: chat,
              expanded: true,
              onToggleExpanded: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Retry Recovery'), findsOneWidget);
    expect(find.text('workspace_io_failure'), findsOneWidget);
    expect(find.text('unresolved: 1'), findsOneWidget);
  });

  testWidgets(
    'project UX renders outcome, milestone, readiness, evidence, and revision review',
    (tester) async {
      chat.activeProject = _projectWithPlanReview();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1000,
              child: TaskPanel(
                chat: chat,
                expanded: true,
                onToggleExpanded: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('project-outcome-section')), findsOne);
      expect(find.byKey(const ValueKey('criterion-accessible')), findsOne);
      expect(find.byKey(const ValueKey('project-roadmap-section')), findsOne);
      expect(find.byKey(const ValueKey('milestone-foundation')), findsOne);
      expect(find.byKey(const ValueKey('roadmap-task-ready_task')), findsOne);
      expect(
        find.textContaining('Waiting for dependency ready_task'),
        findsOne,
      );
      expect(find.byKey(const ValueKey('project-evidence-section')), findsOne);
      expect(find.byKey(const ValueKey('evidence-report')), findsOne);
      expect(find.byKey(const ValueKey('project-revision-section')), findsOne);
      expect(find.textContaining('Replace the reporting API'), findsWidgets);
      expect(find.byKey(const ValueKey('approve-plan-revision')), findsOne);
      expect(find.byKey(const ValueKey('reject-plan-revision')), findsOne);
    },
  );

  testWidgets('manual replan control collects an optional reason', (
    tester,
  ) async {
    chat.activeProject = _projectWithTask();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 640,
            child: TaskPanel(
              chat: chat,
              expanded: true,
              onToggleExpanded: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final replan = find.byKey(const ValueKey('replan-project'));
    expect(replan, findsOneWidget);
    await tester.tap(replan);
    await tester.pumpAndSettle();

    expect(find.text('Replan Project'), findsOneWidget);
    expect(find.text('Reason (optional)'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('project-replan-reason')),
      'Focus on the keyboard flow.',
    );
    expect(find.byKey(const ValueKey('confirm-project-replan')), findsOne);
  });
}

TaskDocument _taskWithArtifact() {
  final now = DateTime(2024, 1, 1);
  return TaskDocument(
    id: 'task_test',
    title: 'Test task',
    originalPrompt: 'Create an artifact.',
    goal: 'Create an artifact.',
    constraints: const [],
    successCriteria: const [],
    steps: const [
      TaskStep(
        id: 'write',
        title: 'Write artifact',
        objective: 'Write the output artifact.',
        instructions: [],
        mayEditFiles: false,
        artifacts: [
          TaskArtifact(
            path: '.agent/tasks/task_test/output.md',
            description: 'Generated output',
          ),
        ],
        status: TaskStepStatus.completed,
      ),
    ],
    status: TaskStatus.completed,
    currentStepId: null,
    memorySummary: '',
    runs: [
      TaskRun(
        runId: 'run_test',
        stepId: 'write',
        status: TaskRunStatus.completed,
        summary: 'Wrote the artifact.',
        memoryUpdate: '',
        toolCalls: [],
        artifacts: [],
        startedAt: now,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

ProjectDocument _projectWithTask() {
  final now = DateTime(2024, 1, 1);
  return ProjectDocument(
    id: 'project_test',
    title: 'Test project',
    originalPrompt: 'Build project.',
    goal: 'Build project.',
    constraints: const [],
    successCriteria: const [],
    status: ProjectStatus.paused,
    activeTaskId: null,
    memorySummary: 'Project memory.',
    completionSummary: '',
    tasks: [
      ProjectTaskRef(
        taskId: 'task_test',
        title: 'Project task',
        status: TaskStatus.completed,
        summary: 'Finished.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    decisions: [
      ProjectDecisionRecord(
        id: 'decision_test',
        decision: ProjectDecisionType.createTask,
        summary: 'Created task.',
        memoryUpdate: '',
        taskId: 'task_test',
        taskTitle: 'Project task',
        taskPrompt: 'Do work.',
        createdAt: now,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

ProjectDocument _projectWithExhaustedRecovery() {
  final now = DateTime(2024, 1, 1);
  final failure = const ProjectTaskFailure(
    gateId: 'no_tool_errors',
    disposition: TaskGateFailureDisposition.repairable,
    failureKey: 'no_tool_errors|workspace_io_failure',
    summary: 'A retryable workspace operation failed.',
    errorCodes: ['workspace_io_failure'],
    toolCallIds: ['call_1'],
    unresolvedErrorCount: 1,
  );
  return ProjectDocument(
    id: 'project_recovery',
    title: 'Recovery project',
    originalGoal: 'Build project.',
    refinedGoal: 'Build project.',
    constraints: const [],
    successCriteria: const ['Project works.'],
    failedTasks: [
      ProjectTask(
        id: 'failed_task',
        title: 'Failed task',
        objective: 'Build the project.',
        relevantSuccessCriteria: const ['Project works.'],
        doneCriteria: const ['Project works.'],
        outOfScope: const [],
        context: const [],
        expectedArtifacts: const [],
        status: ProjectTaskStatus.failed,
        taskDocumentId: 'task_failed',
        recoveryIncidentId: 'recovery_1',
        fingerprint: 'failed_task',
        rejectionReason: failure.summary,
        failure: failure,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    recoveryIncidents: [
      ProjectRecoveryIncident(
        id: 'recovery_1',
        status: ProjectRecoveryIncidentStatus.exhausted,
        sourceTaskIds: const ['task_failed'],
        sourceTaskTitles: const ['Failed task'],
        failedGateId: 'no_tool_errors',
        failureSummary: failure.summary,
        attemptCount: 3,
        recoveryTaskIds: const [],
        createdAt: now,
        updatedAt: now,
        resolvedAt: now,
      ),
    ],
    status: ProjectStatus.blocked,
    phase: ProjectPhase.execution,
    activeTaskId: null,
    blocker: ProjectBlocker(
      type: ProjectBlockerType.recoveryFailed,
      message: 'Recovery exhausted.',
      createdAt: now,
    ),
    createdAt: now,
    updatedAt: now,
  );
}

ProjectDocument _projectWithPlanReview() {
  final now = DateTime(2024, 1, 1);
  final criterion = ProjectCriterion(
    id: 'accessible',
    statement: 'The workflow is keyboard accessible.',
    status: ProjectCriterionStatus.partial,
    evidenceIds: const ['report'],
    notes: 'The primary path is covered; dialogs remain.',
    createdAt: now,
    updatedAt: now,
  );
  final ready = ProjectTask(
    id: 'ready_task',
    title: 'Finish keyboard flow',
    objective: 'Complete the remaining keyboard interactions.',
    criterionIds: const ['accessible'],
    milestoneId: 'foundation',
    priority: ProjectTaskPriority.high,
    doneCriteria: const ['Keyboard tests pass.'],
    outOfScope: const ['Visual redesign.'],
    context: const [],
    expectedArtifacts: const [],
    status: ProjectTaskStatus.queued,
    taskDocumentId: null,
    fingerprint: 'ready',
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
  final waiting = ProjectTask(
    id: 'waiting_task',
    title: 'Polish the dialog',
    objective: 'Polish the completed keyboard dialog.',
    criterionIds: const ['accessible'],
    milestoneId: 'foundation',
    dependsOnTaskIds: const ['ready_task'],
    doneCriteria: const ['Dialog polish is complete.'],
    outOfScope: const [],
    context: const [],
    expectedArtifacts: const [],
    status: ProjectTaskStatus.queued,
    taskDocumentId: null,
    fingerprint: 'waiting',
    rejectionReason: null,
    createdAt: now.add(const Duration(minutes: 1)),
    updatedAt: now,
  );
  final proposed = ready.copyWith(
    id: 'replacement_task',
    title: 'Replace the reporting API',
    objective: 'Adopt the safer reporting API.',
    fingerprint: 'replacement',
  );
  return ProjectDocument(
    id: 'project_review',
    title: 'Review project',
    originalGoal: 'Ship the workflow.',
    refinedGoal: 'Ship an accessible project workflow.',
    criteria: [criterion],
    constraints: const ['Preserve existing task execution.'],
    backlog: [ready, waiting],
    milestones: [
      ProjectMilestone(
        id: 'foundation',
        title: 'Workflow foundation',
        objective: 'Make planning understandable.',
        criterionIds: const ['accessible'],
        status: ProjectMilestoneStatus.active,
        exitConditions: const ['All keyboard tests pass.'],
        taskIds: const ['ready_task', 'waiting_task'],
        order: 1,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    evidence: [
      ProjectEvidence(
        id: 'report',
        type: ProjectEvidenceType.command,
        criterionIds: const ['accessible'],
        sourceRef: 'flutter test test/ui/chat/task_panel_test.dart',
        summary: 'The existing panel tests pass.',
        status: ProjectEvidenceStatus.accepted,
        strength: ProjectEvidenceStrength.supporting,
        createdAt: now,
      ),
    ],
    pendingPlanApproval: PendingProjectPlanApproval(
      revision: 2,
      reason: 'This changes a material API boundary.',
      summary: 'Revise the reporting integration.',
      highRiskChanges: const ['Replace the reporting API.'],
      proposal: ProjectPlanProposal(
        revision: 2,
        triggers: const [ProjectPlanRevisionTrigger.manual],
        summary: 'Revise the reporting integration.',
        rationale: 'The current API cannot meet the accessibility requirement.',
        taskAdditions: [proposed],
        deferredTaskIds: const ['waiting_task'],
        requiresApproval: true,
        approvalReason: 'Material API change.',
        createdAt: now,
      ),
      createdAt: now,
    ),
    status: ProjectStatus.waitingForUser,
    phase: ProjectPhase.planning,
    activeTaskId: null,
    blocker: ProjectBlocker(
      type: ProjectBlockerType.planApproval,
      message: 'Revision 2 needs approval.',
      createdAt: now,
    ),
    createdAt: now,
    updatedAt: now,
  );
}
