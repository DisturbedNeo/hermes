import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_planning_gateway.dart';
import 'package:hermes/core/services/project_system/project_scheduler.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  late Directory root;
  late WorkspaceAttachment workspace;
  late TaskService taskService;
  late ProjectService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hermes_project_service_');
    workspace = WorkspaceAttachment(
      rootPath: root.path,
      displayName: 'Workspace',
      lastOpenedAt: DateTime(2026, 1, 1),
    );
    final sandbox = WorkspaceSandbox();
    taskService = TaskService(
      toolService: ToolService(workspaceSandbox: sandbox),
      sandbox: sandbox,
    );
    service = ProjectService(taskService: taskService);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('creates the clean-slate project schema', () async {
    final project = await service.createProject(
      workspace: workspace,
      userPrompt: 'Build the reporting screen',
    );

    expect(project.originalGoal, 'Build the reporting screen');
    expect(project.tasks, isEmpty);
    expect(project.planHistory.single.revision, 1);
    expect(project.nextRevision, 2);
  });

  test('persists task IDs and hydrates canonical task records', () async {
    final project = _project(
      tasks: [_task().copyWith(status: TaskStatus.running)],
      activeTaskId: 'task_1',
      status: ProjectStatus.runningTask,
    );

    await service.cancelProject(workspace: workspace, snapshot: project);

    final projectFile = File(
      '${root.path}/.agent/projects/${project.id}/project.json',
    );
    final rawProject = jsonDecode(await projectFile.readAsString());
    expect(rawProject['taskIds'], [project.tasks.single.id]);
    expect(rawProject, isNot(contains('tasks')));

    final loaded = await service.loadProject(workspace, project.id);
    expect(loaded?.tasks.single.id, project.tasks.single.id);
    expect(loaded?.tasks.single.status, TaskStatus.cancelled);
    expect(
      (await taskService.loadTask(
        workspace,
        project.tasks.single.id,
      ))?.projectId,
      project.id,
    );
  });

  test(
    'blocks initial plans with invalid dependencies and verification contracts',
    () async {
      final gateway = _InitialisationGateway(_invalidInitialisation());
      final planningService = ProjectService(
        taskService: taskService,
        modelCalls: gateway,
      );

      final project = await planningService.createProject(
        workspace: workspace,
        userPrompt: 'Build the reporting screen',
        client: _QueueChatClient(const ['unused']),
      );

      expect(project.status, ProjectStatus.blocked);
      expect(
        gateway.validationIssues!.map((issue) => issue['code']),
        containsAll([
          'cyclic_dependencies',
          'impossible_deterministic_verification',
          'missing_write_paths',
        ]),
      );
    },
  );

  test(
    'automatically retries an invalid initial plan before blocking',
    () async {
      final gateway = _InitialisationGateway(
        _invalidInitialisation(),
        repairedInitialisations: [
          _invalidInitialisation(),
          _validInitialisation(),
        ],
      );
      final planningService = ProjectService(
        taskService: taskService,
        modelCalls: gateway,
      );

      final project = await planningService.createProject(
        workspace: workspace,
        userPrompt: 'Build the reporting screen',
        client: _QueueChatClient(const ['unused']),
      );

      expect(project.status, ProjectStatus.active);
      expect(project.tasks, hasLength(1));
      expect(gateway.repairCalls, 2);
    },
  );

  test(
    'automatically replans a persisted validation blocker when resumed',
    () async {
      final now = DateTime(2026, 1, 1);
      final blocked = _project(
        status: ProjectStatus.blocked,
        blocker: ProjectBlocker(
          type: ProjectBlockerType.validation,
          message: 'The persisted plan failed validation.',
          createdAt: now,
        ),
      );
      final milestone = ProjectMilestone(
        id: 'milestone_1',
        title: 'Bounded implementation',
        objective: 'Implement the bounded project slice.',
        criterionIds: const ['criterion_1'],
        order: 1,
        createdAt: now,
        updatedAt: now,
      );
      final revisedTask = _task().copyWith(
        milestoneId: milestone.id,
        writePaths: const ['lib/project_slice.dart'],
        selectionRationale: 'The task is the smallest executable next step.',
        expectedEvidence: const [
          TaskEvidenceExpectation(
            id: 'expectation_gate',
            type: ProjectEvidenceType.gate,
            criterionIds: ['criterion_1'],
            description: 'The bounded implementation gate passes.',
          ),
        ],
      );
      final revisedProject = blocked.copyWith(
        tasks: [revisedTask],
        milestones: [milestone],
        status: ProjectStatus.active,
        blocker: null,
      );
      final gateway = _InitialisationGateway(
        _validInitialisation(),
        revisedProject: revisedProject,
      );
      final planningService = ProjectService(
        taskService: taskService,
        modelCalls: gateway,
      );

      final result = await planningService.runProject(
        client: _QueueChatClient([
          jsonEncode({
            'status': 'completed',
            'summary': 'The bounded task is complete.',
            'memoryUpdate': '',
          }),
          jsonEncode({
            'complete': false,
            'finalSummary': 'The project still needs review.',
            'remainingCriteria': ['The bounded task is complete.'],
            'openQuestions': [],
          }),
        ]),
        workspace: workspace,
        snapshot: blocked,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
        planApprovalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(gateway.revisePlanCalls, 1);
      expect(
        result.project.taskById(revisedTask.id)?.status,
        TaskStatus.completed,
      );
      expect(result.project.blocker, isNull);
    },
  );

  test('runs a queued bounded task and retains terminal history', () async {
    final project = _project(tasks: [_task()]);
    final result = await service.runProject(
      client: _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'The bounded task is complete.',
          'memoryUpdate': 'The task completed successfully.',
        }),
        jsonEncode({
          'complete': true,
          'finalSummary': 'The project is complete.',
          'remainingCriteria': [],
          'openQuestions': [],
        }),
      ]),
      workspace: workspace,
      snapshot: project,
      baseSystemPrompt: 'system',
      maxNewTasks: 1,
    );

    expect(result.project.tasks, hasLength(1));
    expect(result.project.tasks.single.status, TaskStatus.completed);
    expect(result.project.activeTaskId, isNull);
    expect(result.project.status, ProjectStatus.paused);
    expect(result.activeTask?.status, TaskStatus.completed);
  });

  test(
    'does not replan immediately after a successful task in the same batch',
    () async {
      final gateway = _InitialisationGateway(_validInitialisation());
      final planningService = ProjectService(
        taskService: taskService,
        modelCalls: gateway,
      );
      final secondTask = _task().copyWith(
        id: 'task_2',
        title: 'Second bounded task',
        objective: 'Complete a second bounded project slice.',
        fingerprint: 'task_2',
      );

      final result = await planningService.runProject(
        client: _QueueChatClient([
          jsonEncode({
            'status': 'completed',
            'summary': 'The first bounded task is complete.',
            'memoryUpdate': '',
          }),
          jsonEncode({
            'status': 'completed',
            'summary': 'The second bounded task is complete.',
            'memoryUpdate': '',
          }),
        ]),
        workspace: workspace,
        snapshot: _project(tasks: [_task(), secondTask]),
        baseSystemPrompt: 'system',
        maxNewTasks: 2,
        planApprovalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(gateway.revisePlanCalls, 0);
      expect(
        result.project.tasks.map((task) => task.status),
        everyElement(TaskStatus.completed),
      );
      expect(result.project.diagnostics.planRevisionAttempts, 0);
      expect(result.project.pendingReplanTriggers, isEmpty);
    },
  );

  test(
    'persists a fixed batch cursor and queues its boundary replan',
    () async {
      final scheduler = _CountingScheduler();
      final batchService = ProjectService(
        taskService: taskService,
        scheduler: scheduler,
      );
      final task2 = _task().copyWith(
        id: 'task_2',
        title: 'Second bounded task',
        objective: 'Complete the second bounded project slice.',
        fingerprint: 'task_2',
      );
      final task3 = _task().copyWith(
        id: 'task_3',
        title: 'Third bounded task',
        objective: 'Complete the third bounded project slice.',
        fingerprint: 'task_3',
      );

      final result = await batchService.runProject(
        client: _QueueChatClient([
          jsonEncode({
            'status': 'completed',
            'summary': 'The first bounded task is complete.',
            'memoryUpdate': '',
          }),
          jsonEncode({
            'status': 'completed',
            'summary': 'The second bounded task is complete.',
            'memoryUpdate': '',
          }),
        ]),
        workspace: workspace,
        snapshot: _project(tasks: [_task(), task2, task3]),
        baseSystemPrompt: 'system',
        maxNewTasks: 2,
      );

      expect(scheduler.scheduleCalls, 1);
      expect(result.project.tasks[0].status, TaskStatus.completed);
      expect(result.project.tasks[1].status, TaskStatus.completed);
      expect(result.project.tasks[2].status, TaskStatus.queued);
      expect(result.project.currentBatchTaskIds, ['task_1', 'task_2']);
      expect(result.project.currentBatchIndex, 2);
      expect(
        result.project.pendingReplanTriggers,
        contains(ProjectPlanRevisionTrigger.batchComplete),
      );
      expect(result.project.pendingReplanReason, contains('batch'));

      final loaded = await batchService.loadProject(
        workspace,
        result.project.id,
      );
      expect(loaded?.currentBatchTaskIds, ['task_1', 'task_2']);
      expect(loaded?.currentBatchIndex, 2);
      expect(
        loaded?.pendingReplanTriggers,
        contains(ProjectPlanRevisionTrigger.batchComplete),
      );
    },
  );

  test('resumes the persisted batch cursor without reselection', () async {
    final scheduler = _CountingScheduler();
    final batchService = ProjectService(
      taskService: taskService,
      scheduler: scheduler,
    );
    final now = DateTime(2026, 1, 1);
    final task1 = _task().copyWith(
      status: TaskStatus.completed,
      completedAt: now,
    );
    final task2 = _task().copyWith(
      id: 'task_2',
      title: 'Second bounded task',
      objective: 'Complete the second bounded project slice.',
      fingerprint: 'task_2',
    );
    final task3 = _task().copyWith(
      id: 'task_3',
      title: 'Third bounded task',
      objective: 'Complete the third bounded project slice.',
      fingerprint: 'task_3',
    );
    final snapshot =
        _project(
          tasks: [task1, task2, task3],
          status: ProjectStatus.paused,
        ).copyWith(
          currentBatchTaskIds: const ['task_1', 'task_2', 'task_3'],
          currentBatchIndex: 1,
          currentBatchPlanRevision: 1,
        );

    final first = await batchService.runProject(
      client: _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'The second bounded task is complete.',
          'memoryUpdate': '',
        }),
      ]),
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: 'system',
      maxNewTasks: 1,
    );
    expect(first.project.tasks[1].status, TaskStatus.completed);
    expect(first.project.currentBatchIndex, 2);
    expect(first.project.status, ProjectStatus.paused);

    final second = await batchService.runProject(
      client: _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'The third bounded task is complete.',
          'memoryUpdate': '',
        }),
      ]),
      workspace: workspace,
      snapshot: first.project,
      baseSystemPrompt: 'system',
      maxNewTasks: 1,
    );
    expect(second.project.tasks[2].status, TaskStatus.completed);
    expect(second.project.currentBatchIndex, 3);
    expect(second.project.pendingReplanTriggers, isEmpty);
    expect(scheduler.scheduleCalls, 0);
  });

  test('answers project questions without a pending plan field', () async {
    final now = DateTime(2026, 1, 1);
    final question = PendingProjectQuestion(
      id: 'question_1',
      question: 'Which platform?',
      createdAt: now,
    );
    final project = _project(
      status: ProjectStatus.waitingForUser,
      openQuestions: [question],
      blocker: ProjectBlocker(
        type: ProjectBlockerType.question,
        message: question.question,
        createdAt: now,
      ),
    );

    final answered = await service.answerOpenQuestion(
      workspace: workspace,
      snapshot: project,
      answer: 'Desktop first.',
    );

    expect(answered.openQuestions, isEmpty);
    expect(answered.blocker, isNull);
    expect(
      answered.memory.map((entry) => entry.content),
      contains(contains('Desktop first.')),
    );
  });

  test(
    'cancelling an active project task updates its lifecycle status in place',
    () async {
      final project = _project(
        tasks: [_task().copyWith(status: TaskStatus.running)],
        activeTaskId: 'task_1',
        status: ProjectStatus.runningTask,
      );

      final cancelled = await service.cancelProject(
        workspace: workspace,
        snapshot: project,
      );

      expect(cancelled.status, ProjectStatus.cancelled);
      expect(cancelled.tasks.single.status, TaskStatus.cancelled);
      expect(cancelled.activeTaskId, isNull);
    },
  );

  test('clearing a task approval blocker restores the project', () async {
    final now = DateTime(2026, 1, 1);
    final project = _project(
      status: ProjectStatus.blocked,
      blocker: ProjectBlocker(
        type: ProjectBlockerType.taskEditApproval,
        message: 'Approval required before continuing.',
        createdAt: now,
      ),
    );

    final cleared = await service.clearTaskBlocker(
      workspace: workspace,
      snapshot: project,
    );

    expect(cleared.status, ProjectStatus.active);
    expect(cleared.blocker, isNull);
  });

  test('resumes a task using its canonical ID', () async {
    final task = await taskService.createProjectTask(
      workspace: workspace,
      userPrompt: 'Complete the bounded task',
      chatSessionId: null,
      projectId: 'project_1',
      planningContext: const TaskPlanningContext(
        projectGoal: 'Build the project safely.',
        projectTaskObjective: 'Complete the bounded task.',
        doneCriteria: ['The bounded task is complete.'],
        outOfScope: ['Unrelated work.'],
      ),
    );
    final terminalTask = task.copyWith(
      status: TaskStatus.completed,
      completedAt: DateTime(2026, 1, 2),
    );
    await taskService.repository.saveSnapshot(root.path, terminalTask);

    final project = _project(
      tasks: [terminalTask.copyWith(status: TaskStatus.running)],
      activeTaskId: terminalTask.id,
      status: ProjectStatus.reviewingTask,
    );
    final result = await service.runProject(
      client: _QueueChatClient(const []),
      workspace: workspace,
      snapshot: project,
      baseSystemPrompt: 'system',
      maxNewTasks: 1,
    );

    expect(result.project.tasks.single.status, TaskStatus.completed);
    expect(result.project.activeTaskId, isNull);
  });

  test('recovery retries retain the complete incident task history', () async {
    final now = DateTime(2026, 1, 1);
    final source = _task().copyWith(
      status: TaskStatus.failed,
      recoveryIncidentId: 'incident_1',
    );
    final previousRecovery = _task().copyWith(
      id: 'recovery_old',
      title: 'Previous recovery attempt',
      status: TaskStatus.failed,
      recoveryIncidentId: 'incident_1',
    );
    final incident = ProjectRecoveryIncident(
      id: 'incident_1',
      status: ProjectRecoveryIncidentStatus.exhausted,
      sourceTaskIds: [source.id],
      sourceTaskTitles: [source.title],
      failedGateId: 'gate_1',
      failureSummary: 'The required check failed.',
      attemptCount: 2,
      maxAttempts: 2,
      recoveryTaskIds: [previousRecovery.id],
      createdAt: now,
      updatedAt: now,
    );
    final project = _project(
      tasks: [source, previousRecovery],
      recoveryIncidents: [incident],
      status: ProjectStatus.blocked,
    );

    final retried = await service.retryRecoveryIncident(
      workspace: workspace,
      snapshot: project,
      incidentId: incident.id,
    );

    expect(retried.tasks, hasLength(3));
    expect(retried.taskById(source.id)?.status, TaskStatus.failed);
    expect(retried.taskById(previousRecovery.id), isNotNull);
    expect(
      retried.tasks.where((task) => task.recoveryIncidentId == incident.id),
      hasLength(3),
    );
    final recoveryTask = retried.tasks.firstWhere(
      (task) => task.id != source.id && task.id != previousRecovery.id,
    );
    expect(recoveryTask.expectedEvidence, hasLength(2));
    expect(
      recoveryTask.expectedEvidence.map((item) => item.id),
      everyElement(isNot('expectation_1')),
    );
    expect(
      recoveryTask.expectedEvidence,
      contains(
        isA<TaskEvidenceExpectation>()
            .having((item) => item.type, 'type', ProjectEvidenceType.gate)
            .having((item) => item.sourceRef, 'sourceRef', 'gate_1')
            .having((item) => item.required, 'required', isTrue),
      ),
    );
    expect(retried.recoveryIncidents.single.maxAttempts, 3);
    expect(retried.recoveryIncidents.single.recoveryTaskIds, hasLength(2));
  });

  test(
    'duplicate failed work creates a retry with fresh evidence ownership',
    () async {
      final failed = _task().copyWith(
        id: 'failed_task',
        status: TaskStatus.failed,
        fingerprint: 'duplicate_work',
      );
      final duplicate = _task().copyWith(
        id: 'duplicate_task',
        fingerprint: 'duplicate_work',
      );
      final result = await service.runProject(
        client: _QueueChatClient([
          jsonEncode({
            'status': 'completed',
            'summary': 'The retry completed.',
            'memoryUpdate': '',
          }),
          jsonEncode({
            'complete': false,
            'finalSummary': 'The project still needs review.',
            'remainingCriteria': ['The bounded task is complete.'],
            'openQuestions': [],
          }),
        ]),
        workspace: workspace,
        snapshot: _project(tasks: [failed, duplicate]),
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      final retry = result.project.tasks.firstWhere(
        (task) => task.title == 'Retry Bounded task',
      );
      expect(retry.status, TaskStatus.completed);
      expect(retry.expectedEvidence, hasLength(1));
      expect(retry.expectedEvidence.single.id, isNot('expectation_1'));
      expect(result.project.taskById('failed_task')?.status, TaskStatus.failed);
      expect(
        result.project.taskById('duplicate_task')?.status,
        TaskStatus.rejected,
      );
    },
  );

  test(
    'duplicate queued work is removed in favour of the existing task',
    () async {
      final candidate = _task();
      final existing = _task().copyWith(id: 'task_2');
      final result = await service.runProject(
        client: _QueueChatClient([
          jsonEncode({
            'status': 'completed',
            'summary': 'The existing task completed.',
            'memoryUpdate': '',
          }),
          jsonEncode({
            'complete': false,
            'finalSummary': 'The project still needs review.',
            'remainingCriteria': ['The bounded task is complete.'],
            'openQuestions': [],
          }),
        ]),
        workspace: workspace,
        snapshot: _project(tasks: [candidate, existing]),
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      expect(result.project.taskById(candidate.id), isNull);
      expect(
        result.project.taskById(existing.id)?.status,
        TaskStatus.completed,
      );
    },
  );
}

ProjectDocument _project({
  List<Task> tasks = const [],
  String? activeTaskId,
  ProjectStatus status = ProjectStatus.active,
  List<PendingProjectQuestion> openQuestions = const [],
  ProjectBlocker? blocker,
  List<ProjectRecoveryIncident> recoveryIncidents = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectDocument(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Build the project',
    refinedGoal: 'Build the project safely',
    criteria: [
      ProjectCriterion(
        id: 'criterion_1',
        statement: 'The bounded task is complete.',
        verificationMode: ProjectVerificationMode.deterministic,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    constraints: const [],
    tasks: tasks,
    recoveryIncidents: recoveryIncidents,
    status: status,
    activeTaskId: activeTaskId,
    openQuestions: openQuestions,
    blocker: blocker,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task() {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: 'task_1',
    title: 'Bounded task',
    objective: 'Complete one bounded project slice.',
    criterionIds: const ['criterion_1'],
    expectedEvidence: const [
      TaskEvidenceExpectation(
        id: 'expectation_1',
        type: ProjectEvidenceType.taskClaim,
        criterionIds: ['criterion_1'],
        description: 'The bounded slice is complete.',
      ),
    ],
    doneCriteria: const ['The bounded slice is complete.'],
    outOfScope: const ['Unrelated work.'],
    context: const [],
    expectedArtifacts: const [],
    status: TaskStatus.queued,
    fingerprint: 'task_1',
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}

class _QueueChatClient extends ChatClient {
  _QueueChatClient(this.responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<String> responses;
  var index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    final response =
        responses[index < responses.length ? index : responses.length - 1];
    index++;
    return ChatCompletionResponse(content: response);
  }

  @override
  void dispose() {}
}

class _InitialisationGateway implements ProjectPlanningGateway {
  _InitialisationGateway(
    this.initialisation, {
    this.repairedInitialisations = const [],
    this.revisedProject,
  });

  final ProjectInitialisation initialisation;
  final List<ProjectInitialisation> repairedInitialisations;
  final ProjectDocument? revisedProject;
  List<Map<String, String>>? validationIssues;
  var repairCalls = 0;
  var revisePlanCalls = 0;

  @override
  Future<ProjectInitialisation> initializeProject({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required String originalGoal,
    required Map<String, dynamic> workspaceMetadata,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async => initialisation;

  @override
  Future<ProjectInitialisation?> repairInitialisation({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required String originalGoal,
    required Map<String, dynamic> workspaceMetadata,
    required ProjectInitialisation initialisation,
    required List<Map<String, String>> validationIssues,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    repairCalls++;
    this.validationIssues = validationIssues;
    if (repairCalls <= repairedInitialisations.length) {
      return repairedInitialisations[repairCalls - 1];
    }
    return null;
  }

  @override
  Future<ProjectIncrementalPlanResult> revisePlanWithCommands({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectEvidenceSnapshot evidenceSnapshot,
    required List<ProjectPlanRevisionTrigger> triggers,
    required ProjectPlanApprovalPolicy approvalPolicy,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    revisePlanCalls++;
    final revised = revisedProject;
    if (revised == null) throw UnimplementedError();
    return ProjectIncrementalPlanResult(
      project: revised,
      committed: true,
      changed: true,
      awaitingApproval: false,
      modelCalls: 1,
    );
  }

  @override
  Future<ProjectIncrementalPlanResult> splitTaskWithCommands({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required Task oversizedTask,
    required List<String> violations,
    required ProjectPlanApprovalPolicy approvalPolicy,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async => ProjectIncrementalPlanResult(
    project: project,
    committed: false,
    changed: false,
    awaitingApproval: false,
    modelCalls: 1,
    error: 'test gateway does not split tasks',
  );

  @override
  Future<ProjectCompletionAssessment> evaluateCompletion({
    required ChatClient client,
    required String baseSystemPrompt,
    required ProjectState project,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    return ProjectCompletionAssessment(
      complete: false,
      finalSummary: 'The project still needs review.',
      remainingCriteria: project.criteria
          .where((criterion) => criterion.required)
          .map((criterion) => criterion.statement)
          .toList(),
      openQuestions: const [],
    );
  }
}

class _CountingScheduler extends ProjectScheduler {
  var scheduleCalls = 0;

  @override
  ProjectScheduleResult schedule(ProjectDocument project) {
    scheduleCalls++;
    return super.schedule(project);
  }
}

ProjectInitialisation _invalidInitialisation() {
  final now = DateTime(2026, 1, 1);
  final criterion = ProjectCriterion(
    id: 'criterion_1',
    statement: 'The reporting screen is verified.',
    verificationMode: ProjectVerificationMode.deterministic,
    createdAt: now,
    updatedAt: now,
  );
  final milestone = ProjectMilestone(
    id: 'milestone_1',
    title: 'Reporting screen',
    objective: 'Deliver the reporting screen.',
    criterionIds: const ['criterion_1'],
    order: 1,
    createdAt: now,
    updatedAt: now,
  );

  Task task(String id, String dependencyId) => Task(
    id: id,
    title: id,
    objective: 'Implement $id.',
    criterionIds: const ['criterion_1'],
    milestoneId: milestone.id,
    dependsOnTaskIds: [dependencyId],
    expectedEvidence: const [
      TaskEvidenceExpectation(
        id: 'expectation_task_claim',
        type: ProjectEvidenceType.taskClaim,
        criterionIds: ['criterion_1'],
        description: 'The task result is checked.',
      ),
    ],
    expectedArtifacts: [
      TaskArtifact(
        id: 'artifact',
        path: 'lib/reporting.dart',
        description: 'The reporting implementation.',
        kind: 'file',
        createdAt: now,
      ),
    ],
    context: const [],
    doneCriteria: const ['The task is complete.'],
    outOfScope: const ['Unrelated work.'],
    status: TaskStatus.queued,
    fingerprint: id,
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );

  return ProjectInitialisation(
    title: 'Reporting screen',
    refinedGoal: 'Deliver the reporting screen.',
    criteria: [criterion],
    constraints: const [],
    openQuestions: const [],
    tasks: [task('task_a', 'task_b'), task('task_b', 'task_a')],
    milestones: [milestone],
  );
}

ProjectInitialisation _validInitialisation() {
  final now = DateTime(2026, 1, 1);
  final criterion = ProjectCriterion(
    id: 'criterion_1',
    statement: 'The reporting screen is verified.',
    verificationMode: ProjectVerificationMode.deterministic,
    createdAt: now,
    updatedAt: now,
  );
  final milestone = ProjectMilestone(
    id: 'milestone_1',
    title: 'Reporting screen',
    objective: 'Deliver the reporting screen.',
    criterionIds: const ['criterion_1'],
    order: 1,
    createdAt: now,
    updatedAt: now,
  );
  final task = Task(
    id: 'task_1',
    title: 'Implement reporting screen',
    objective: 'Implement the reporting screen.',
    criterionIds: const ['criterion_1'],
    milestoneId: milestone.id,
    expectedEvidence: const [
      TaskEvidenceExpectation(
        id: 'expectation_gate',
        type: ProjectEvidenceType.gate,
        criterionIds: ['criterion_1'],
        description: 'The reporting screen verification gate passes.',
      ),
    ],
    writePaths: const ['lib/reporting.dart'],
    doneCriteria: const ['The reporting screen is implemented.'],
    outOfScope: const ['Unrelated screens.'],
    context: const [],
    expectedArtifacts: const [],
    status: TaskStatus.queued,
    fingerprint: 'task_1',
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
  return ProjectInitialisation(
    title: 'Reporting screen',
    refinedGoal: 'Deliver the reporting screen.',
    criteria: [criterion],
    constraints: const [],
    openQuestions: const [],
    tasks: [task],
    milestones: [milestone],
  );
}
