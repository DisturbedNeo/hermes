import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/compaction_manager.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/message_store.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/sandbox_policy.dart';
import 'package:hermes/core/services/task_system/task_gate_evaluator.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_planning_tool_call_runner.dart';
import 'package:hermes/core/services/task_system/task_planning_tools.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/services/task_system/task_summary.dart';
import 'package:hermes/core/services/task_system/task_view_service.dart';
import 'package:hermes/core/services/terminal_command_parser.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_discovery_profile.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/tools/tool_error.dart';
import 'package:path/path.dart' as path;

part 'task_service.mapper.dart';

typedef TaskCompactionStatusSink = void Function(String status);

class _IncrementalTaskPlanAttempt {
  final Task? task;
  final bool usedPlanningTools;
  final PlanningMetrics planningMetrics;

  const _IncrementalTaskPlanAttempt({
    this.task,
    this.usedPlanningTools = false,
    this.planningMetrics = const PlanningMetrics(),
  });
}

@MappableClass(generateMethods: GenerateMethods.encode)
class TaskPlanningContext with TaskPlanningContextMappable {
  final String projectGoal;
  final String projectTaskTitle;
  final String projectTaskObjective;
  final List<String> knownFacts;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<TaskArtifact> expectedArtifacts;
  final List<TaskGate> requiredGates;
  final List<String> criterionIds;
  final List<TaskProjectCriterion> criteria;
  final List<TaskProjectEvidenceExpectation> expectedEvidence;
  final List<String> readPaths;
  final List<String> writePaths;
  final int maxSteps;

  const TaskPlanningContext({
    required this.projectGoal,
    this.projectTaskTitle = '',
    required this.projectTaskObjective,
    this.knownFacts = const [],
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.expectedArtifacts = const [],
    this.requiredGates = const [],
    this.criterionIds = const [],
    this.criteria = const [],
    this.expectedEvidence = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.maxSteps = 3,
  });
}

/// Transient project context used only while executing one task document.
class TaskExecutionRequest {
  final List<String> criterionIds;
  final List<TaskProjectCriterion> criteria;
  final List<TaskProjectEvidenceExpectation> expectedEvidence;

  const TaskExecutionRequest({
    this.criterionIds = const [],
    this.criteria = const [],
    this.expectedEvidence = const [],
  });

  factory TaskExecutionRequest.fromPlanningContext(
    TaskPlanningContext context,
  ) => TaskExecutionRequest(
    criterionIds: context.criterionIds,
    criteria: context.criteria,
    expectedEvidence: context.expectedEvidence,
  );
}

class _StreamingTaskToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

class _PendingTaskToolResult {
  const _PendingTaskToolResult({
    required this.messageIndex,
    required this.toolIndex,
  });

  final int messageIndex;
  final int toolIndex;
}

class _AllowedTaskCommand {
  final String command;
  final String workingDirectory;

  const _AllowedTaskCommand({
    required this.command,
    required this.workingDirectory,
  });
}

const int _maxConsecutiveRepeatedToolCalls = 3;

const Set<String> _readOnlyTaskToolIds = {
  'calculator',
  'list_directory',
  'read_file',
  'search_files',
  'write_file',
};

const Set<String> _mutatingTaskToolIds = {
  'write_file',
  'patch_file',
  'create_directory',
  'rename_path',
  'delete_path',
  'run_command',
};

const String _finishTaskStepToolId = 'finish_task_step';
const String _requestTaskUserDecisionToolId = 'task_request_user_decision';
const String _requestTaskReplanToolId = 'task_request_replan';

const ToolDefinition _finishTaskStepToolDefinition = ToolDefinition(
  id: _finishTaskStepToolId,
  name: 'Finish task step',
  description:
      'Finish the current task step with its observed status and a concise summary. Calling this ends the step; do not call workspace tools after it. Use the explicit question or replan tools for those outcomes.',
  schema: {
    'type': 'object',
    'properties': {
      'status': {
        'type': 'string',
        'enum': ['completed', 'failed'],
        'description':
            'Observed final status. Completion is still subject to Hermes gate evaluation.',
      },
      'summary': {
        'type': 'string',
        'description': 'Concise summary of what happened in this step.',
      },
    },
    'required': ['status', 'summary'],
  },
);

const ToolDefinition _requestTaskUserDecisionToolDefinition = ToolDefinition(
  id: _requestTaskUserDecisionToolId,
  name: 'Request task user decision',
  description:
      'Pause the current task step and ask the user one genuinely blocking question. Calling this ends the step; do not call finish_task_step afterwards.',
  schema: {
    'type': 'object',
    'properties': {
      'question': {'type': 'string', 'description': 'The blocking question.'},
      'reason': {
        'type': 'string',
        'description': 'Why the task cannot safely continue without an answer.',
      },
      'defaultIfUnanswered': {
        'type': 'string',
        'description': 'Safe default, if one exists.',
      },
      'riskOfAssuming': {
        'type': 'string',
        'description': 'Risk of choosing the default without the user.',
      },
      'kind': {
        'type': 'string',
        'enum': ['blocking', 'preference', 'advisory'],
      },
    },
    'required': ['question'],
  },
);

const ToolDefinition _requestTaskReplanToolDefinition = ToolDefinition(
  id: _requestTaskReplanToolId,
  name: 'Request task replan',
  description:
      'Stop the current task step and request a concrete replan when the current approach is wrong or incomplete. Calling this ends the step; do not call finish_task_step afterwards.',
  schema: {
    'type': 'object',
    'properties': {
      'reason': {
        'type': 'string',
        'description':
            'Concrete contradiction or missing work requiring a replan.',
      },
    },
    'required': ['reason'],
  },
);

class TaskService {
  TaskService({
    required ToolService toolService,
    required WorkspaceSandbox sandbox,
    TaskRepository? repository,
    WorkspaceDiscoveryProfileService profileService =
        const WorkspaceDiscoveryProfileService(),
  }) : _toolService = toolService,
       _planningRunner = const TaskPlanningToolCallRunner(),
       _repository = repository ?? TaskRepository(),
       _sandbox = sandbox,
       _profileService = profileService,
       _gateEvaluator = TaskGateEvaluator(sandbox: sandbox);

  final ToolService _toolService;
  final TaskPlanningToolCallRunner _planningRunner;
  final TaskViewService _taskViewService = const TaskViewService();
  final TaskRepository _repository;
  final WorkspaceSandbox _sandbox;
  final WorkspaceDiscoveryProfileService _profileService;
  final TaskGateEvaluator _gateEvaluator;
  final QuestionPolicyService _questionPolicy = const QuestionPolicyService();
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  TaskRepository get repository => _repository;
  ToolService get toolService => _toolService;

  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) {
    return _repository.listTasks(
      workspace.rootPath,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
  }

  Future<Task?> loadLatestTask(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) {
    return _repository.loadLatestTask(
      workspace.rootPath,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
  }

  Future<Task?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
    String? projectId,
  }) {
    return _repository.loadTask(
      workspace.rootPath,
      taskId,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
  }

  Future<int> deleteTasksForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) {
    if (workspace.missing) return Future.value(0);
    return _repository.deleteTasksForChatSession(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteOrphanedChatTasks(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) {
    if (workspace.missing) return Future.value(0);
    return _repository.deleteOrphanedChatTasks(
      workspace.rootPath,
      retainedChatSessionIds: retainedChatSessionIds,
    );
  }

  Future<Task> updateTaskChatSessionId({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String chatSessionId,
  }) async {
    if (snapshot.chatSessionId == chatSessionId) return snapshot;
    final updated = snapshot.copyWith(
      chatSessionId: chatSessionId,
      updatedAt: DateTime.now(),
    );
    await _repository.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) async {
    if (snapshot.status != TaskStatus.running) return snapshot;
    final now = DateTime.now();
    final steps = snapshot.steps.map((step) {
      if (step.status == TaskStepStatus.running) {
        return step.copyWith(status: TaskStepStatus.blocked);
      }
      return step;
    }).toList();
    final recovered = snapshot.copyWith(
      status: TaskStatus.blocked,
      steps: steps,
      updatedAt: now,
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        'Recovered an interrupted task. Review the current step before continuing.',
      ),
    );
    await _repository.saveSnapshot(workspace.rootPath, recovered);
    return recovered;
  }

  String encodeTask(Task task) =>
      '${_encoder.convert(ModelJson.encode(task))}\n';

  Future<String> readArtifact({
    required WorkspaceAttachment workspace,
    required String artifactPath,
    CancellationToken? cancellationToken,
  }) async {
    try {
      return await _sandbox.readFilePreview(
        workspace.rootPath,
        artifactPath,
        maxChars: 240000,
        cancellationToken: cancellationToken,
      );
    } on WorkspaceSandboxException catch (error) {
      if (error.message.contains('Path not found')) {
        throw StateError('Artifact not found: $artifactPath');
      }
      rethrow;
    }
  }

  Future<RefinedTaskBrief> refineTaskBrief({
    required ChatClient client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final metadata = workspace == null || workspace.missing
        ? const WorkspaceMetadata()
        : await _collectWorkspaceMetadata(workspace);

    try {
      final json = await _completeJson(
        client: client,
        system: _refinerSystemInstruction,
        label: 'Prompt Refiner',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user:
            '''
Refine this request into a concise brief for a long-horizon task planner.

Return only JSON:
{
  "title": "...",
  "goal": "...",
  "constraints": ["..."],
  "successCriteria": ["..."],
  "assumptions": ["..."],
  "questions": ["..."]
}

Selected mode: ${selectedMode.wire}
Workspace metadata:
${_encoder.convert(ModelJson.encode(metadata))}

Request:
$userPrompt
''',
      );
      return _normaliseBrief(
        ModelJson.decode<RefinedTaskBrief>(json),
        userPrompt,
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return _fallbackBrief(userPrompt);
    }
  }

  Future<Task> createTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required String baseSystemPrompt,
    String? chatSessionId,
    String? projectId,
    String? canonicalTaskId,
    TaskPlanningContext? planningContext,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final now = DateTime.now();
    final taskId = canonicalTaskId ?? _newTaskId(userPrompt);
    final metadata = await _collectWorkspaceMetadata(
      workspace,
      chatSessionId: chatSessionId,
    );

    Task task;
    var planningMetrics = PlanningMetrics(planningStartedAt: now);
    try {
      final incremental = await _completeTaskPlanWithCommands(
        client: client,
        baseSystemPrompt: baseSystemPrompt,
        workspace: workspace,
        taskId: taskId,
        userPrompt: userPrompt,
        metadata: metadata,
        planningContext: planningContext,
        now: now,
        chatSessionId: chatSessionId,
        projectId: projectId,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      planningMetrics = planningMetrics.add(incremental.planningMetrics);
      task =
          incremental.task ??
          (planningContext == null
              ? _fallbackTask(
                  taskId: taskId,
                  userPrompt: userPrompt,
                  chatSessionId: chatSessionId,
                  projectId: projectId,
                  now: now,
                )
              : _fallbackProjectBoundedTask(
                  taskId: taskId,
                  userPrompt: userPrompt,
                  chatSessionId: chatSessionId,
                  projectId: projectId,
                  planningContext: planningContext,
                  now: now,
                ));
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      task = planningContext == null
          ? _fallbackTask(
              taskId: taskId,
              userPrompt: userPrompt,
              chatSessionId: chatSessionId,
              projectId: projectId,
              now: now,
            )
          : _fallbackProjectBoundedTask(
              taskId: taskId,
              userPrompt: userPrompt,
              chatSessionId: chatSessionId,
              projectId: projectId,
              planningContext: planningContext,
              now: now,
            );
    }

    final firstExecutableAt = task.currentStepId == null
        ? null
        : DateTime.now();
    planningMetrics = planningMetrics.copyWith(
      timeToFirstExecutableMs: firstExecutableAt == null
          ? null
          : DateTime.now().difference(now).inMilliseconds,
    );
    task = task.copyWith(
      planningMetrics: task.planningMetrics.add(planningMetrics),
    );
    await _repository.saveSnapshot(workspace.rootPath, task);
    return task;
  }

  Future<_IncrementalTaskPlanAttempt> _completeTaskPlanWithCommands({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required String baseSystemPrompt,
    required String taskId,
    required String userPrompt,
    required WorkspaceMetadata metadata,
    required TaskPlanningContext? planningContext,
    required DateTime now,
    required String? chatSessionId,
    required String? projectId,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final task = _taskPlanningSeed(
      taskId: taskId,
      userPrompt: userPrompt,
      planningContext: planningContext,
      chatSessionId: chatSessionId,
      projectId: projectId,
      now: now,
    );
    final requiredArtifacts = [
      for (final artifact in planningContext?.expectedArtifacts ?? const [])
        TaskArtifact(
          path: artifact.path.replaceAll('{{task_id}}', taskId),
          description: artifact.description,
          kind: artifact.kind,
        ),
    ];
    final maxSteps = planningContext?.maxSteps.clamp(1, 6).toInt() ?? 3;
    final context = TaskPlanningToolContext(
      task: task,
      workspaceRoot: workspace.rootPath,
      maxSteps: maxSteps,
      projectGoal: planningContext?.projectGoal ?? '',
      doneCriteria: planningContext?.doneCriteria ?? const [],
      outOfScope: planningContext?.outOfScope ?? const [],
      readPaths: planningContext?.readPaths ?? const [],
      writePaths: planningContext?.writePaths ?? const [],
      requiredArtifacts: requiredArtifacts,
      requiredGates: planningContext?.requiredGates ?? const [],
      requiredEvidence: planningContext?.expectedEvidence ?? const [],
      requireDeclaredWriteBoundary: planningContext != null,
    );
    final registry = TaskPlanningToolRegistry(context: context);
    final result = await _planningRunner.complete(
      client: client,
      registry: registry,
      label: 'Incremental Task Planner',
      system:
          '''
$baseSystemPrompt

$_taskPlanningToolsSystemInstruction
''',
      user:
          '''
Plan this task with the task planning tools. Hermes owns the task ID
$taskId; never use it as a step ID and never supply persistent IDs.

For a bounded Project task, the Project goal is context only: do not plan or
perform the whole Project. Plan only the selected task objective.

User request:
$userPrompt

Bounded workspace profile:
${_encoder.convert(_compactTaskMetadata(metadata))}

      ${planningContext == null ? '' : 'Bounded Project task context:\n${_encoder.convert(_taskPlanningContextMap(planningContext, taskId: taskId))}'}
''',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );

    return _IncrementalTaskPlanAttempt(
      task: context.committedTask,
      usedPlanningTools: context.committedTask != null,
      planningMetrics: _planningMetricsFromResult(result),
    );
  }

  PlanningMetrics _planningMetricsFromResult(Map<String, dynamic> result) {
    final raw = result['planning_metrics'];
    if (raw is! Map) return const PlanningMetrics();
    try {
      return ModelJson.decode<PlanningMetrics>(Map<String, dynamic>.from(raw));
    } catch (_) {
      return const PlanningMetrics();
    }
  }

  Task _taskPlanningSeed({
    required String taskId,
    required String userPrompt,
    required TaskPlanningContext? planningContext,
    required String? chatSessionId,
    required String? projectId,
    required DateTime now,
  }) {
    final objective =
        planningContext?.projectTaskObjective.trim().isNotEmpty == true
        ? planningContext!.projectTaskObjective.trim()
        : userPrompt;
    final title = planningContext?.projectTaskTitle.trim().isNotEmpty == true
        ? planningContext!.projectTaskTitle.trim()
        : _titleFromPrompt(objective);
    final constraints = [
      'Stay within the attached workspace.',
      if (planningContext?.readPaths.isNotEmpty == true)
        'Read paths: ${planningContext!.readPaths.join(', ')}',
      if (planningContext?.writePaths.isNotEmpty == true)
        'Write paths: ${planningContext!.writePaths.join(', ')}',
      if (planningContext?.outOfScope.isNotEmpty == true)
        ...planningContext!.outOfScope.map((item) => 'Out of scope: $item'),
    ];
    return Task(
      id: taskId,
      title: title,
      originalPrompt: userPrompt,
      objective: objective,
      constraints: constraints,
      successCriteria: planningContext?.doneCriteria.isNotEmpty == true
          ? [...planningContext!.doneCriteria]
          : ['Complete the requested task.'],
      gates: planningContext?.requiredGates ?? const [],
      criterionIds: planningContext?.criterionIds ?? const [],
      readPaths: planningContext?.readPaths ?? const [],
      writePaths: planningContext?.writePaths ?? const [],
      doneCriteria: planningContext?.doneCriteria ?? const [],
      outOfScope: planningContext?.outOfScope ?? const [],
      context: planningContext?.knownFacts ?? const [],
      status: TaskStatus.paused,
      chatSessionId: chatSessionId,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> _taskPlanningContextMap(
    TaskPlanningContext context, {
    String? taskId,
  }) => {
    'project_goal': context.projectGoal,
    'task_title': context.projectTaskTitle,
    'task_objective': context.projectTaskObjective,
    'known_facts': context.knownFacts,
    'done_criteria': context.doneCriteria,
    'out_of_scope': context.outOfScope,
    'criterion_ids': context.criterionIds,
    'criteria': [
      for (final criterion in context.criteria)
        {
          'id': criterion.id,
          'statement': criterion.statement,
          'required': criterion.required,
          'verification_mode': criterion.verificationMode,
        },
    ],
    'read_paths': context.readPaths,
    'write_paths': context.writePaths,
    'expected_artifacts': [
      for (final artifact in context.expectedArtifacts)
        {
          'path': artifact.path.replaceAll(
            '{{task_id}}',
            taskId ?? '{{task_id}}',
          ),
          'description': artifact.description,
          'kind': artifact.kind,
        },
    ],
    'max_steps': context.maxSteps.clamp(1, 6),
    'required_checks': [
      for (final gate in context.requiredGates)
        {
          'kind': gate.id,
          'required': gate.required,
          'scope': gate.scope,
          'command': gate.params['command'],
          'working_directory':
              gate.params['working_directory'] ??
              gate.params['workingDirectory'],
        },
    ],
    'expected_evidence': [
      for (final item in context.expectedEvidence)
        {
          'type': item.type,
          'description': item.description,
          'required': item.required,
          'source_ref': item.sourceRef,
          'details': item.details,
        },
    ],
  };

  Map<String, dynamic> _compactTaskMetadata(WorkspaceMetadata metadata) {
    final raw = ModelJson.encode(metadata);
    final profile = raw['workspaceProfile'];
    final profileMap = profile is Map
        ? Map<String, dynamic>.from(profile)
        : const <String, dynamic>{};
    List<String> strings(Object? value, {int limit = 80}) => [
      if (value is List)
        for (final item in value)
          if (item is String) item,
    ].take(limit).toList();
    final highSignalFiles = <Map<String, dynamic>>[];
    final rawHighSignalFiles = profileMap['highSignalFiles'];
    if (rawHighSignalFiles is List) {
      for (final rawFile in rawHighSignalFiles.take(6)) {
        if (rawFile is! Map) continue;
        final file = Map<String, dynamic>.from(rawFile);
        final content = file['content']?.toString() ?? '';
        highSignalFiles.add({
          'path': file['path']?.toString() ?? '',
          'content': content.length <= 2200
              ? content
              : '${content.substring(0, 2199).trimRight()}…',
          'truncated': file['truncated'] == true || content.length > 2200,
        });
      }
    }
    return {
      'workspaceName': raw['workspaceName'],
      'commandExecutionApproved': raw['commandExecutionApproved'],
      'rootFiles': strings(raw['rootFiles']),
      'gitAvailable': raw['gitAvailable'] == true,
      'treePaths': strings(profileMap['treePaths'], limit: 160),
      'highSignalFiles': highSignalFiles,
      'packageName': profileMap['packageName'],
      'scripts': profileMap['scripts'],
      'dependencies': strings(profileMap['dependencies']),
      'languages': strings(profileMap['languages']),
      'frameworks': strings(profileMap['frameworks']),
      'treeTruncated': profileMap['treeTruncated'] == true,
    };
  }

  /// Converts an already-bounded Project task directly into one executable
  /// task step without invoking the Task Planner model.
  Future<Task> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  }) async {
    final now = DateTime.now();
    final taskId = canonicalTaskId ?? _newTaskId(userPrompt);
    final task = _fallbackProjectBoundedTask(
      taskId: taskId,
      userPrompt: userPrompt,
      chatSessionId: chatSessionId,
      projectId: projectId,
      planningContext: planningContext,
      now: now,
    );
    await _repository.saveSnapshot(workspace.rootPath, task);
    return task;
  }

  Future<Task> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String rawJson,
  }) async {
    final parsed = ModelJson.decode<Task>(TaskJson.parseObject(rawJson));
    final now = DateTime.now();
    final normalised = _normaliseEditedTask(
      parsed.copyWith(
        id: snapshot.id,
        chatSessionId: snapshot.chatSessionId,
        projectId: snapshot.projectId,
      ),
      snapshot,
      now,
    );
    await _repository.saveSnapshot(workspace.rootPath, normalised);
    return normalised;
  }

  Future<Task> runNextStep({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    TaskExecutionRequest executionRequest = const TaskExecutionRequest(),
  }) async {
    cancellationToken?.throwIfCancelled();
    var working = await recoverTask(workspace: workspace, snapshot: snapshot);
    if (working.isTerminal) return working;
    final step = working.nextRunnableStep;
    if (step == null) {
      final completed = _markCompleted(working);
      await _repository.saveSnapshot(workspace.rootPath, completed);
      return completed;
    }

    if (working.pendingQuestion != null) return working;

    if (requirePhaseApproval &&
        step.mayEditFiles &&
        step.status != TaskStepStatus.approved) {
      final blocked =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: TaskStepStatus.blocked),
          ).copyWith(
            status: TaskStatus.blocked,
            currentStepId: step.id,
            pendingApproval: PendingTaskApproval(
              stepId: step.id,
              reason: 'Step "${step.title}" may edit workspace files.',
              createdAt: DateTime.now(),
            ),
            updatedAt: DateTime.now(),
          );
      await _repository.saveSnapshot(workspace.rootPath, blocked);
      return blocked;
    }

    final now = DateTime.now();
    final run = TaskRun(
      runId: 'run_${uuid.v7()}',
      stepId: step.id,
      status: TaskRunStatus.running,
      summary: '',
      memoryUpdate: '',
      toolCalls: const [],
      artifacts: const [],
      startedAt: now,
    );

    working =
        _replaceStep(
          working,
          step.id,
          step.copyWith(status: TaskStepStatus.running),
        ).copyWith(
          status: TaskStatus.running,
          currentStepId: step.id,
          runs: [...working.runs, run],
          pendingApproval: null,
          pendingQuestion: null,
          updatedAt: now,
        );
    await _repository.saveSnapshot(workspace.rootPath, working);

    try {
      var execution = await _executeStep(
        client: client,
        workspace: workspace,
        task: working,
        step: step,
        run: run,
        baseSystemPrompt: baseSystemPrompt,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        executionRequest: executionRequest,
      );

      final finishedAt = DateTime.now();
      if (execution.status == _StepExecutionStatus.completed) {
        execution = await _applyCompletionGates(
          client: client,
          workspace: workspace,
          task: working,
          step: step,
          execution: execution,
          baseSystemPrompt: baseSystemPrompt,
          cancellationToken: cancellationToken,
        );
      } else if (execution.status == _StepExecutionStatus.blocked) {
        execution = _applyQuestionPolicy(execution, autonomy: questionAutonomy);
      }
      final completedRun = run.copyWith(
        status: execution.runStatus,
        completedAt: finishedAt,
        summary: execution.summary,
        memoryUpdate: execution.memoryUpdate,
        toolCalls: execution.toolCalls,
        artifacts: execution.artifacts,
        gateResults: execution.gateResults,
        evidenceClaims: [
          for (final claim in execution.evidenceClaims)
            TaskEvidenceClaim(
              criterionId: claim.criterionId,
              claim: claim.claim,
              evidenceType: claim.evidenceType,
              sourceRef: claim.sourceRef,
              suggestedStrength: claim.suggestedStrength,
              expectationId: claim.expectationId,
              runId: run.runId,
            ),
        ],
        replanReason: execution.replanRequest,
        error: execution.error,
      );
      working = _replaceLastRun(working, completedRun);

      switch (execution.status) {
        case _StepExecutionStatus.completed:
          working = _completeStep(working, step, execution, finishedAt);
          break;
        case _StepExecutionStatus.blocked:
          working = _blockStep(working, step, execution, finishedAt);
          break;
        case _StepExecutionStatus.failed:
          working = _failStep(working, step, execution, finishedAt);
          break;
        case _StepExecutionStatus.needsReplan:
          working = await _replanUnfinished(
            client: client,
            workspace: workspace,
            snapshot: working,
            baseSystemPrompt: baseSystemPrompt,
            reason: execution.replanRequest?.trim().isNotEmpty == true
                ? execution.replanRequest!.trim()
                : execution.summary,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          );
          break;
      }

      await _repository.saveSnapshot(workspace.rootPath, working);
      return working;
    } on OperationCancelledException catch (e) {
      final cancelledAt = DateTime.now();
      final cancelledRun = run.copyWith(
        status: TaskRunStatus.cancelled,
        completedAt: cancelledAt,
        summary: 'Step cancelled by the user.',
        error: e.toString(),
      );
      working = _replaceLastRun(working, cancelledRun);
      working =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: TaskStepStatus.pending),
          ).copyWith(
            status: TaskStatus.paused,
            currentStepId: step.id,
            pendingApproval: null,
            pendingQuestion: null,
            updatedAt: cancelledAt,
          );
      await _repository.saveSnapshot(workspace.rootPath, working);
      return working;
    } on ChatTransportException catch (e) {
      final pausedAt = DateTime.now();
      final pausedRun = run.copyWith(
        status: TaskRunStatus.failed,
        completedAt: pausedAt,
        summary:
            'Model transport was interrupted after automatic retry. '
            'Resume the task to retry this step.',
        error: e.toString(),
      );
      working = _replaceLastRun(working, pausedRun);
      working =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: TaskStepStatus.pending),
          ).copyWith(
            status: TaskStatus.paused,
            currentStepId: step.id,
            pendingApproval: null,
            pendingQuestion: null,
            updatedAt: pausedAt,
          );
      await _repository.saveSnapshot(workspace.rootPath, working);
      return working;
    } catch (e) {
      final failedRun = run.copyWith(
        status: TaskRunStatus.failed,
        completedAt: DateTime.now(),
        summary: 'Step failed: $e',
        error: e.toString(),
      );
      working = _replaceLastRun(working, failedRun);
      working =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: TaskStepStatus.failed),
          ).copyWith(
            status: TaskStatus.failed,
            currentStepId: step.id,
            updatedAt: DateTime.now(),
          );
      await _repository.saveSnapshot(workspace.rootPath, working);
      return working;
    }
  }

  Future<Task> approvePendingStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) async {
    final approval = snapshot.pendingApproval;
    if (approval == null) return snapshot;
    final step = snapshot.stepById(approval.stepId);
    if (step == null) return snapshot;
    final updated =
        _replaceStep(
          snapshot,
          step.id,
          step.copyWith(status: TaskStepStatus.approved),
        ).copyWith(
          status: TaskStatus.paused,
          currentStepId: step.id,
          pendingApproval: null,
          updatedAt: DateTime.now(),
        );
    await _repository.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<Task> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) async {
    final step = snapshot.currentStep ?? snapshot.nextRunnableStep;
    if (step == null) return snapshot;
    final updated =
        _replaceStep(
          snapshot,
          step.id,
          step.copyWith(status: TaskStepStatus.pending),
        ).copyWith(
          status: TaskStatus.paused,
          currentStepId: step.id,
          pendingApproval: null,
          pendingQuestion: null,
          updatedAt: DateTime.now(),
        );
    await _repository.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<Task> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) async {
    final step = snapshot.currentStep ?? snapshot.nextRunnableStep;
    if (step == null) return snapshot;
    final now = DateTime.now();
    final updatedStep = step.copyWith(status: TaskStepStatus.skipped);
    var updated = _replaceStep(snapshot, step.id, updatedStep);
    updated = _advanceAfterStep(updated, now).copyWith(
      runs: [
        ...updated.runs,
        TaskRun(
          runId: 'run_${uuid.v7()}',
          stepId: step.id,
          status: TaskRunStatus.skipped,
          summary: 'Step skipped by the user.',
          memoryUpdate: '',
          toolCalls: const [],
          artifacts: const [],
          startedAt: now,
          completedAt: now,
        ),
      ],
    );
    await _repository.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<Task> stopTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) async {
    final now = DateTime.now();
    final updated = snapshot.copyWith(
      status: TaskStatus.cancelled,
      currentStepId: null,
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: now,
      updatedAt: now,
    );
    await _repository.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<Task> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String answer,
  }) async {
    final question = snapshot.pendingQuestion;
    final trimmed = answer.trim();
    if (question == null || trimmed.isEmpty) return snapshot;
    final step = snapshot.stepById(question.stepId);
    final updated =
        _replaceStep(
          snapshot,
          question.stepId,
          (step ?? snapshot.nextRunnableStep)?.copyWith(
                status: TaskStepStatus.pending,
              ) ??
              TaskStep(
                id: question.stepId,
                title: question.stepId,
                objective: '',
                instructions: const [],
                mayEditFiles: false,
                artifacts: const [],
                status: TaskStepStatus.pending,
              ),
        ).copyWith(
          status: TaskStatus.paused,
          pendingQuestion: null,
          memorySummary: _appendMemory(
            snapshot.memorySummary,
            'User answered: ${question.question}\nAnswer: $trimmed',
          ),
          updatedAt: DateTime.now(),
        );
    await _repository.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<Task> replanUnfinished({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final updated = await _replanUnfinished(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      reason: reason,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    await _repository.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<WorkspaceMetadata> _collectWorkspaceMetadata(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async {
    final profile = await _profileService.collect(workspace: workspace);
    return WorkspaceMetadata(
      workspaceName: workspace.displayName,
      rootFiles: profile.rootEntries,
      gitAvailable:
          await FileSystemEntity.type(
            path.join(workspace.rootPath, '.git'),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound,
      commandExecutionApproved: workspace.commandExecutionApproved,
      existingTaskIds: (await _repository.listTasks(
        workspace.rootPath,
        chatSessionId: chatSessionId,
      )).map((task) => task.id).toList(),
      workspaceProfile: profile,
    );
  }

  Future<_StepExecutionOutput> _executeStep({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required Task task,
    required TaskStep step,
    required TaskRun run,
    required String baseSystemPrompt,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    required TaskExecutionRequest executionRequest,
  }) async {
    final allowedCommands = _allowedCommandsForStep(task, step);
    final allowedToolIds = _allowedToolIdsForStep(step, allowedCommands);
    final toolDefs = [
      ..._toolService.getToolDefinitions(
        ids: allowedToolIds.toList(),
        includeWorkspaceTools: true,
      ),
      _finishTaskStepToolDefinition,
      _requestTaskUserDecisionToolDefinition,
      _requestTaskReplanToolDefinition,
    ];
    final messages = <ChatMessage>[
      ChatMessage(
        role: 'system',
        content: '$baseSystemPrompt\n\n$_executorSystemInstruction',
      ),
      ChatMessage(
        role: 'user',
        content: _buildStepPrompt(task, step, workspace, executionRequest),
      ),
    ];
    final context = WorkspaceToolContext(
      workspace: workspace,
      cancellationToken: cancellationToken,
    );
    final toolCalls = <TaskToolCallRecord>[];
    var finalText = '';
    var finalContent = '';
    _StepExecutionOutput? forcedOutput;
    String? previousToolKey;
    var consecutiveRepeatCount = 0;

    while (true) {
      cancellationToken?.throwIfCancelled();
      final completion = await _completeChatForTask(
        client: client,
        label: 'Step Executor: ${step.title}',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        messages: messages,
        extraParams: ToolCaller.buildExtraParams(
          addGenerationPrompt: true,
          toolDefs: toolDefs,
        ),
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
      );

      cancellationToken?.throwIfCancelled();
      finalContent = completion.content.trim();
      finalText = [
        if (completion.reasoning.trim().isNotEmpty)
          'Reasoning summary:\n${completion.reasoning.trim()}',
        if (finalContent.isNotEmpty) finalContent,
      ].join('\n\n').trim();

      if (completion.toolCalls.isEmpty) break;

      final terminalCallIndex = completion.toolCalls.indexWhere(
        (call) => _isTaskTerminalTool(call.name),
      );
      if (terminalCallIndex >= 0) {
        final terminalCall = completion.toolCalls[terminalCallIndex];
        final callId = terminalCall.id ?? 'call_$terminalCallIndex';
        final args = TaskJson.decodeJsonOrString(terminalCall.arguments);
        final terminal = _terminalTaskToolCall(
          callName: terminalCall.name,
          args: args,
          task: task,
          step: step,
          existingToolCalls: toolCalls,
          executionRequest: executionRequest,
        );
        final resultJson = terminal.resultJson;
        final result = _structuredToolResult(terminalCall.name, resultJson);
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: terminalCall.name,
            arguments: args,
            result: result,
            resultSummary: _cap(resultJson, 1200),
            outcome: terminal.error == null
                ? TaskToolCallOutcome.succeeded
                : TaskToolCallOutcome.failed,
            operationKey: terminalCall.name,
            toolError: terminal.error == null
                ? null
                : TaskToolError(
                    code: 'invalid_task_control_arguments',
                    message: terminal.error!,
                    disposition: TaskToolErrorDisposition.advisory,
                  ),
            timestamp: DateTime.now(),
          ),
        );
        _emitTerminalToolResults(
          onModelOutput: onModelOutput,
          label: 'Step Executor: ${step.title}',
          calls: completion.toolCalls,
          terminalCallIndex: terminalCallIndex,
          terminalResultJson: resultJson,
        );
        finalContent = terminal.finalContent;
        finalText = [
          if (completion.reasoning.trim().isNotEmpty)
            'Reasoning summary:\n${completion.reasoning.trim()}',
          if (finalContent.isNotEmpty) finalContent,
        ].join('\n\n').trim();
        forcedOutput = terminal.output.copyWith(toolCalls: toolCalls);
        break;
      }

      if (_isStepResultJson(finalContent)) {
        for (var i = 0; i < completion.toolCalls.length; i++) {
          _emitTaskModelOutput(
            onModelOutput,
            TaskModelOutputEvent(
              type: TaskModelOutputEventType.toolResult,
              label: 'Step Executor: ${step.title}',
              text: jsonEncode({
                'skipped': true,
                'reason':
                    'The step already returned final JSON, so this extra tool call was ignored.',
              }),
              toolIndex: i,
            ),
          );
        }
        break;
      }

      String? loopGuardReason;

      messages.add(
        ChatMessage(
          role: 'assistant',
          content: completion.content,
          reasoningContent: completion.reasoning,
          toolCalls: [
            for (var i = 0; i < completion.toolCalls.length; i++)
              {
                'id': completion.toolCalls[i].id ?? 'call_$i',
                'type': 'function',
                'function': {
                  'name': completion.toolCalls[i].name,
                  'arguments': TaskJson.decodeJsonOrString(
                    completion.toolCalls[i].arguments,
                  ),
                },
              },
          ],
        ),
      );

      for (var i = 0; i < completion.toolCalls.length; i++) {
        cancellationToken?.throwIfCancelled();
        final call = completion.toolCalls[i];
        final callId = call.id ?? 'call_$i';
        final args = TaskJson.decodeJsonOrString(call.arguments);
        final toolKey = _toolCallKey(call);
        if (toolKey == previousToolKey) {
          consecutiveRepeatCount++;
        } else {
          previousToolKey = toolKey;
          consecutiveRepeatCount = 1;
        }

        if (loopGuardReason == null &&
            consecutiveRepeatCount >= _maxConsecutiveRepeatedToolCalls) {
          loopGuardReason =
              'The step repeated the same tool call $consecutiveRepeatCount times: ${call.name}.';
        }

        final resultJson = await _executeTaskToolCall(
          call: call,
          task: task,
          step: step,
          allowedToolIds: allowedToolIds,
          allowedCommands: allowedCommands,
          context: context,
          blockedReason: loopGuardReason,
        );
        cancellationToken?.throwIfCancelled();
        final result = _structuredToolResult(call.name, resultJson);
        final toolError = _toolErrorInfoForCall(call.name, result);
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: call.name,
            arguments: args,
            result: result,
            resultSummary: _cap(resultJson, 1200),
            outcome: _toolCallOutcome(result, toolError),
            operationKey: _operationKey(call.name, args),
            toolError: toolError,
            timestamp: DateTime.now(),
          ),
        );
        _emitTaskModelOutput(
          onModelOutput,
          TaskModelOutputEvent(
            type: TaskModelOutputEventType.toolResult,
            label: 'Step Executor: ${step.title}',
            text: resultJson,
            toolIndex: i,
          ),
        );
        messages.add(
          ChatMessage(role: 'tool', content: resultJson, toolCallId: callId),
        );

        if (loopGuardReason != null) break;
      }

      if (loopGuardReason != null) {
        final finalizer = await _finalizeStepAfterToolGuard(
          client: client,
          step: step,
          messages: messages,
          reason: loopGuardReason,
          compactionSettings: compactionSettings,
          contextLimitTokens: contextLimitTokens,
          onCompactionStatus: onCompactionStatus,
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
        finalContent = finalizer.content.trim();
        finalText = [
          if (finalizer.reasoning.trim().isNotEmpty)
            'Reasoning summary:\n${finalizer.reasoning.trim()}',
          if (finalContent.isNotEmpty) finalContent,
        ].join('\n\n').trim();
        if (_isStepResultJson(finalContent)) {
          forcedOutput = _parseStepOutput(
            finalContent,
            task,
            step,
            toolCalls,
            executionRequest,
          );
        } else {
          forcedOutput = _StepExecutionOutput(
            status: _StepExecutionStatus.failed,
            runStatus: TaskRunStatus.failed,
            summary:
                'Stopped step after a tool-call loop guard fired. $loopGuardReason',
            memoryUpdate: '',
            artifacts: const [],
            toolCalls: toolCalls,
            error: loopGuardReason,
          );
        }
        break;
      }
    }

    await _repository.saveLog(
      workspace.rootPath,
      task.id,
      '${step.id}-${run.runId}.md',
      finalText,
    );

    return forcedOutput ??
        _parseStepOutput(
          finalContent.isEmpty ? finalText : finalContent,
          task,
          step,
          toolCalls,
          executionRequest,
        );
  }

  Future<_StepExecutionOutput> _applyCompletionGates({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required Task task,
    required TaskStep step,
    required _StepExecutionOutput execution,
    required String baseSystemPrompt,
    CancellationToken? cancellationToken,
  }) async {
    final gates = _completionGates(task, step);
    if (gates.isEmpty) return execution;
    // Gate scope comes from the persisted plan, never from model output or a
    // partial set of observed writes. This keeps artifact existence/content
    // checks authoritative for every declared artifact.
    final stepArtifacts = step.artifacts.isEmpty
        ? execution.artifacts
        : step.artifacts;
    final taskToolCalls = [
      for (final run in task.runs) ...run.toolCalls,
      ...execution.toolCalls,
    ];
    final taskArtifacts = <TaskArtifact>[
      for (final run in task.runs) ...run.artifacts,
      for (final taskStep in task.steps) ...taskStep.artifacts,
      ...stepArtifacts,
    ];

    final evaluation = await _gateEvaluator.evaluate(
      workspace: workspace,
      task: task,
      step: step,
      gates: gates,
      evidence: TaskGateEvidence(
        stepToolCalls: execution.toolCalls,
        taskToolCalls: taskToolCalls,
        stepArtifacts: stepArtifacts,
        taskArtifacts: taskArtifacts,
      ),
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      humanApprovalGranted: step.status == TaskStepStatus.approved,
      cancellationToken: cancellationToken,
    );
    if (!evaluation.hasRequiredFailure && !evaluation.hasRequiredPending) {
      return execution.copyWith(gateResults: evaluation.results);
    }

    final summary = [
      execution.summary,
      'Completion gates did not pass:',
      evaluation.blockingSummary,
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
    if (evaluation.hasRequiredFailure) {
      return execution.copyWith(
        status: _StepExecutionStatus.failed,
        runStatus: TaskRunStatus.failed,
        summary: summary,
        error: evaluation.blockingSummary,
        gateResults: evaluation.results,
      );
    }
    if (evaluation.hasHumanApprovalPending) {
      return execution.copyWith(
        status: _StepExecutionStatus.blocked,
        runStatus: TaskRunStatus.blocked,
        summary: summary,
        userQuestion: 'Approve completion after reviewing gate results.',
        gateResults: evaluation.results,
      );
    }
    return execution.copyWith(
      status: _StepExecutionStatus.needsReplan,
      runStatus: TaskRunStatus.needsReplan,
      summary: summary,
      replanRequest:
          'Add or run the missing verification needed to satisfy completion gates.',
      gateResults: evaluation.results,
    );
  }

  _StepExecutionOutput _applyQuestionPolicy(
    _StepExecutionOutput execution, {
    required QuestionAutonomy autonomy,
  }) {
    final questionText = execution.userQuestion?.trim();
    if (questionText == null || questionText.isEmpty) return execution;
    final decision = _questionPolicy.decide(
      question: execution.agentQuestion ?? AgentQuestion.fromText(questionText),
      autonomy: autonomy,
    );
    if (decision.shouldBlock) return execution;
    final summary = [
      execution.summary,
      'Question policy continued with an assumption:',
      decision.assumption,
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
    return execution.copyWith(
      status: _StepExecutionStatus.completed,
      runStatus: TaskRunStatus.completed,
      summary: summary,
      memoryUpdate: _appendMemory(execution.memoryUpdate, decision.assumption),
      userQuestion: null,
      agentQuestion: null,
      error: null,
    );
  }

  List<TaskGate> _completionGates(Task task, TaskStep step) {
    final hasRemainingSteps = task.steps.any((candidate) {
      if (candidate.id == step.id) return false;
      return candidate.status == TaskStepStatus.pending ||
          candidate.status == TaskStepStatus.approved ||
          candidate.status == TaskStepStatus.blocked ||
          candidate.status == TaskStepStatus.failed;
    });
    return [...step.gates, if (!hasRemainingSteps) ...task.gates];
  }

  Set<String> _allowedToolIdsForStep(
    TaskStep step,
    List<_AllowedTaskCommand> allowedCommands,
  ) {
    if (!step.mayEditFiles) {
      return {
        ..._readOnlyTaskToolIds,
        if (allowedCommands.isNotEmpty) 'run_command',
      };
    }
    return {..._readOnlyTaskToolIds, ..._mutatingTaskToolIds};
  }

  List<_AllowedTaskCommand> _allowedCommandsForStep(Task task, TaskStep step) {
    final seen = <String>{};
    final commands = <_AllowedTaskCommand>[];
    for (final gate in _completionGates(task, step)) {
      if (gate.id != 'command_passes') continue;
      final command = _commandTextFromParts(
        jsonString(gate.params['command']),
        jsonStringList(gate.params['args']),
      );
      if (command.isEmpty) continue;
      final workingDirectory = path.normalize(
        jsonString(
          gate.params['working_directory'] ?? gate.params['workingDirectory'],
          fallback: '.',
        ),
      );
      final key = '$workingDirectory\x00$command';
      if (!seen.add(key)) continue;
      commands.add(
        _AllowedTaskCommand(
          command: command,
          workingDirectory: workingDirectory,
        ),
      );
    }
    return commands;
  }

  String _commandTextFromParts(String command, List<String> args) {
    return TerminalCommandParser.commandTextFromParts(command, args);
  }

  bool _isTaskTerminalTool(String name) {
    return name == _finishTaskStepToolId ||
        name == _requestTaskUserDecisionToolId ||
        name == _requestTaskReplanToolId;
  }

  _TaskTerminalToolCallResult _terminalTaskToolCall({
    required String callName,
    required Object args,
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
    required TaskExecutionRequest executionRequest,
  }) {
    return switch (callName) {
      _finishTaskStepToolId => _finishStepFromToolCall(
        args: args,
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
        executionRequest: executionRequest,
      ),
      _requestTaskUserDecisionToolId => _requestUserDecisionFromToolCall(
        args: args,
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      ),
      _requestTaskReplanToolId => _requestReplanFromToolCall(
        args: args,
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      ),
      _ => _invalidTaskControlCall(
        'Unknown task control tool: $callName.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      ),
    };
  }

  _TaskTerminalToolCallResult _invalidTaskControlCall(
    String error, {
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
  }) {
    final resultJson = _taskToolErrorJson(
      code: 'invalid_task_control_arguments',
      message: error,
      disposition: TaskToolErrorDisposition.advisory,
    );
    return _TaskTerminalToolCallResult(
      resultJson: resultJson,
      finalContent: resultJson,
      error: error,
      output: _StepExecutionOutput(
        status: _StepExecutionStatus.failed,
        runStatus: TaskRunStatus.failed,
        summary: error,
        memoryUpdate: '',
        artifacts: _artifactsFromToolCalls(task.id, step, existingToolCalls),
        toolCalls: existingToolCalls,
        error: error,
      ),
    );
  }

  _TaskTerminalToolCallResult _requestUserDecisionFromToolCall({
    required Object args,
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
  }) {
    if (args is! Map) {
      return _invalidTaskControlCall(
        'task_request_user_decision arguments must be a JSON object.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final question = AgentQuestion.parse(args);
    if (question == null || question.question.trim().isEmpty) {
      return _invalidTaskControlCall(
        'task_request_user_decision requires a question.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final resultJson = jsonEncode({
      'recorded': true,
      'status': 'blocked',
      'question': question.question.trim(),
    });
    return _TaskTerminalToolCallResult(
      resultJson: resultJson,
      finalContent: resultJson,
      output: _StepExecutionOutput(
        status: _StepExecutionStatus.blocked,
        runStatus: TaskRunStatus.blocked,
        summary: 'Waiting for a user decision: ${question.question.trim()}',
        memoryUpdate: '',
        artifacts: _artifactsFromToolCalls(task.id, step, existingToolCalls),
        toolCalls: existingToolCalls,
        userQuestion: question.displayText,
        agentQuestion: question,
      ),
    );
  }

  _TaskTerminalToolCallResult _requestReplanFromToolCall({
    required Object args,
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
  }) {
    if (args is! Map) {
      return _invalidTaskControlCall(
        'task_request_replan arguments must be a JSON object.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final reason = jsonString(args['reason']).trim();
    if (reason.isEmpty) {
      return _invalidTaskControlCall(
        'task_request_replan requires a concrete reason.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final resultJson = jsonEncode({
      'recorded': true,
      'status': 'needs_replan',
      'reason': reason,
    });
    return _TaskTerminalToolCallResult(
      resultJson: resultJson,
      finalContent: resultJson,
      output: _StepExecutionOutput(
        status: _StepExecutionStatus.needsReplan,
        runStatus: TaskRunStatus.needsReplan,
        summary: reason,
        memoryUpdate: '',
        artifacts: _artifactsFromToolCalls(task.id, step, existingToolCalls),
        toolCalls: existingToolCalls,
        replanRequest: reason,
      ),
    );
  }

  _TaskTerminalToolCallResult _finishStepFromToolCall({
    required Object args,
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
    required TaskExecutionRequest executionRequest,
  }) {
    if (args is! Map) {
      const error = 'finish_task_step arguments must be a JSON object.';
      final resultJson = _taskToolErrorJson(
        code: 'invalid_finish_arguments',
        message: error,
        disposition: TaskToolErrorDisposition.advisory,
      );
      return _TaskTerminalToolCallResult(
        resultJson: resultJson,
        finalContent: resultJson,
        error: error,
        output: _StepExecutionOutput(
          status: _StepExecutionStatus.failed,
          runStatus: TaskRunStatus.failed,
          summary: error,
          memoryUpdate: '',
          artifacts: _artifactsFromToolCalls(task.id, step, existingToolCalls),
          toolCalls: existingToolCalls,
          error: error,
        ),
      );
    }

    final json = Map<String, dynamic>.from(args);
    final rawStatus = jsonString(
      json['status'],
    ).trim().toLowerCase().replaceAll('-', '_');
    final parsedStatus = _parseStepExecutionStatusStrict(rawStatus);
    if (parsedStatus == null) {
      return _invalidTaskControlCall(
        'finish_task_step requires status to be either completed or failed.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final summary = jsonString(
      json['summary'],
      fallback: parsedStatus == _StepExecutionStatus.failed
          ? 'Step failed.'
          : 'Step completed.',
    );
    // memoryUpdate and evidence claims are model-output fields only. Artifact
    // paths never become execution artifacts; evidence claims are advisory.
    // Authoritative facts come from executed workspace calls and gate
    // evaluation below.
    final finalContent = _encoder.convert({
      'status': rawStatus,
      'summary': summary,
    });
    return _TaskTerminalToolCallResult(
      resultJson: jsonEncode({'finished': true, 'status': rawStatus}),
      finalContent: finalContent,
      output: _StepExecutionOutput(
        status: parsedStatus,
        runStatus: switch (parsedStatus) {
          _StepExecutionStatus.completed => TaskRunStatus.completed,
          _StepExecutionStatus.blocked => TaskRunStatus.blocked,
          _StepExecutionStatus.failed => TaskRunStatus.failed,
          _StepExecutionStatus.needsReplan => TaskRunStatus.needsReplan,
        },
        summary: summary,
        memoryUpdate: jsonString(json['memoryUpdate'] ?? json['memory_update']),
        artifacts: _artifactsFromToolCalls(task.id, step, existingToolCalls),
        evidenceClaims: _evidenceClaimsFromJson(
          json['evidenceClaims'] ?? json['evidence_claims'],
          executionRequest.criterionIds,
          expectedEvidence: executionRequest.expectedEvidence,
        ),
        toolCalls: existingToolCalls,
        error: jsonNullableString(json['error']),
      ),
    );
  }

  void _emitTerminalToolResults({
    required TaskModelOutputSink? onModelOutput,
    required String label,
    required List<ChatCompletionToolCall> calls,
    required int terminalCallIndex,
    required String terminalResultJson,
  }) {
    for (var i = 0; i < calls.length; i++) {
      _emitTaskModelOutput(
        onModelOutput,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.toolResult,
          label: label,
          text: i == terminalCallIndex
              ? terminalResultJson
              : jsonEncode({
                  'skipped': true,
                  'reason':
                      'The task control tool ended the step, so this tool call was ignored.',
                }),
          toolIndex: i,
        ),
      );
    }
  }

  Future<String> _executeTaskToolCall({
    required ChatCompletionToolCall call,
    required Task task,
    required TaskStep step,
    required Set<String> allowedToolIds,
    required List<_AllowedTaskCommand> allowedCommands,
    required WorkspaceToolContext context,
    required String? blockedReason,
  }) async {
    if (blockedReason != null) {
      return _taskToolErrorJson(
        code: 'loop_guard',
        message: 'Tool call skipped by task runner.',
        disposition: TaskToolErrorDisposition.advisory,
        details: {'reason': blockedReason, 'skipped': true},
      );
    }

    if (!allowedToolIds.contains(call.name)) {
      return _taskToolErrorJson(
        code: 'tool_not_available',
        message: 'Tool is not available for this task step.',
        disposition: TaskToolErrorDisposition.advisory,
        details: {
          'tool': call.name,
          'mayEditFiles': step.mayEditFiles,
          'availableTools': allowedToolIds.toList()..sort(),
          'reason': step.mayEditFiles
              ? 'The tool was not exposed to the task runner.'
              : 'This read-only step can read files and create new task-owned artifact files, but cannot edit source files, overwrite files, run terminal commands, rename paths, or delete paths.',
        },
      );
    }

    if (!step.mayEditFiles && call.name == 'run_command') {
      final whitelistError = _readOnlyCommandWhitelistError(
        call,
        allowedCommands,
      );
      if (whitelistError != null) return whitelistError;
    }

    if (!step.mayEditFiles && call.name == 'write_file') {
      return _executeReadOnlyArtifactWrite(
        call: call,
        task: task,
        step: step,
        context: context,
      );
    }
    if (step.mayEditFiles && call.name == 'write_file') {
      final artifactWriteError = await _taskArtifactWriteError(
        call: call,
        task: task,
        step: step,
        context: context,
      );
      if (artifactWriteError != null) return artifactWriteError;
    }

    return _toolService.execute(
      toolId: call.name,
      argumentsJson: call.arguments,
      context: context,
    );
  }

  String? _readOnlyCommandWhitelistError(
    ChatCompletionToolCall call,
    List<_AllowedTaskCommand> allowedCommands,
  ) {
    final decoded = TaskJson.decodeJsonOrString(call.arguments);
    if (decoded is! Map) {
      return _taskToolErrorJson(
        code: 'invalid_tool_arguments',
        message: 'run_command arguments must be a JSON object.',
        disposition: TaskToolErrorDisposition.advisory,
      );
    }
    final args = jsonMap(decoded);
    final command = _commandTextFromParts(
      jsonString(args['command']),
      jsonStringList(args['args']),
    );
    final workingDirectory = path.normalize(
      jsonString(
        args['working_directory'] ?? args['workingDirectory'],
        fallback: '.',
      ),
    );
    final allowed = allowedCommands.any(
      (item) =>
          item.command == command &&
          path.normalize(item.workingDirectory) == workingDirectory,
    );
    if (allowed) return null;
    return _taskToolErrorJson(
      code: 'command_not_whitelisted',
      message:
          'Terminal command and working directory must exactly match a command_passes gate for this read-only step. Use the command exactly as listed without adding or removing arguments, flags, pipes, redirects, shell wrappers, or combined commands.',
      disposition: TaskToolErrorDisposition.advisory,
      details: {
        'command': command,
        'working_directory': workingDirectory,
        'allowedCommands': [
          for (final item in allowedCommands)
            {
              'command': item.command,
              'working_directory': item.workingDirectory,
            },
        ],
      },
    );
  }

  Future<String> _executeReadOnlyArtifactWrite({
    required ChatCompletionToolCall call,
    required Task task,
    required TaskStep step,
    required WorkspaceToolContext context,
  }) async {
    try {
      final decoded = TaskJson.decodeJsonOrString(call.arguments);
      if (decoded is! Map) {
        return _taskToolErrorJson(
          code: 'invalid_tool_arguments',
          message: 'write_file arguments must be a JSON object.',
          disposition: TaskToolErrorDisposition.advisory,
        );
      }

      final rawPath = decoded['path'];
      final content = decoded['content'];
      if (rawPath is! String || rawPath.trim().isEmpty) {
        return _taskToolErrorJson(
          code: 'invalid_tool_arguments',
          message: 'write_file requires a path.',
          disposition: TaskToolErrorDisposition.advisory,
        );
      }
      if (content is! String) {
        return _taskToolErrorJson(
          code: 'invalid_tool_arguments',
          message: 'write_file requires string content.',
          disposition: TaskToolErrorDisposition.advisory,
        );
      }

      final resolved = await _sandbox.resolve(
        context.workspace.rootPath,
        rawPath,
        mustExist: false,
      );
      if (!_isInsideTaskDirectory(resolved.relativePath, task.id)) {
        return _taskToolErrorJson(
          code: 'artifact_path_denied',
          message: 'Read-only steps may only create task-owned artifact files.',
          disposition: TaskToolErrorDisposition.advisory,
          details: {
            'path': resolved.relativePath,
            'allowedPrefix': path.join('.agent', 'tasks', task.id),
          },
        );
      }
      final allowedPaths = _declaredCurrentStepArtifactPaths(task.id, step);
      if (!allowedPaths.contains(path.normalize(resolved.relativePath))) {
        return _taskToolErrorJson(
          code: 'artifact_not_declared',
          message:
              'Read-only steps may only create artifacts declared on the current step.',
          disposition: TaskToolErrorDisposition.advisory,
          details: {
            'path': resolved.relativePath,
            'allowedArtifactPaths': allowedPaths.toList()..sort(),
          },
        );
      }

      final existingType = await FileSystemEntity.type(resolved.absolutePath);
      if (existingType != FileSystemEntityType.notFound) {
        return _taskToolErrorJson(
          code: 'read_only_overwrite_denied',
          message: 'Read-only steps cannot overwrite existing files.',
          disposition: TaskToolErrorDisposition.advisory,
          details: {'path': resolved.relativePath},
        );
      }

      final result = await _sandbox.writeFile(
        context.workspace.rootPath,
        resolved.relativePath,
        content,
      );
      return jsonEncode(result);
    } on WorkspaceSandboxException catch (e) {
      return _taskToolErrorJson(
        code: e.code,
        message: e.message,
        disposition: TaskToolErrorDisposition.advisory,
      );
    } catch (e) {
      return _taskToolErrorJson(
        code: 'workspace_io_failure',
        message: e.toString(),
        disposition: TaskToolErrorDisposition.retryable,
      );
    }
  }

  Future<String?> _taskArtifactWriteError({
    required ChatCompletionToolCall call,
    required Task task,
    required TaskStep step,
    required WorkspaceToolContext context,
  }) async {
    try {
      final decoded = TaskJson.decodeJsonOrString(call.arguments);
      if (decoded is! Map) return null;
      final rawPath = decoded['path'];
      if (rawPath is! String || rawPath.trim().isEmpty) return null;

      final resolved = await _sandbox.resolve(
        context.workspace.rootPath,
        rawPath,
        mustExist: false,
      );
      final artifactPath = path.normalize(resolved.relativePath);
      if (!_isInsideTaskDirectory(artifactPath, task.id)) return null;

      final allowedPaths = _declaredCurrentStepArtifactPaths(task.id, step);
      if (allowedPaths.contains(artifactPath)) return null;

      return _taskToolErrorJson(
        code: 'artifact_not_declared',
        message:
            'Task steps may only create artifacts declared on the current step.',
        disposition: TaskToolErrorDisposition.advisory,
        details: {
          'path': resolved.relativePath,
          'allowedArtifactPaths': allowedPaths.toList()..sort(),
        },
      );
    } on WorkspaceSandboxException catch (e) {
      return _taskToolErrorJson(
        code: e.code,
        message: e.message,
        disposition: TaskToolErrorDisposition.advisory,
      );
    } catch (e) {
      return _taskToolErrorJson(
        code: 'workspace_io_failure',
        message: e.toString(),
        disposition: TaskToolErrorDisposition.retryable,
      );
    }
  }

  bool _isInsideTaskDirectory(String relativePath, String taskId) {
    final segments = path.split(path.normalize(relativePath));
    return segments.length > 3 &&
        segments[0] == '.agent' &&
        segments[1] == 'tasks' &&
        segments[2] == taskId;
  }

  Set<String> _declaredCurrentStepArtifactPaths(String taskId, TaskStep step) {
    return {
          for (final artifact in step.artifacts)
            if (artifact.path.trim().isNotEmpty)
              path.normalize(artifact.path.trim()),
        }
        .where((artifactPath) => _isInsideTaskDirectory(artifactPath, taskId))
        .toSet();
  }

  /// Builds artifact provenance from successful workspace mutations. The
  /// executor may describe work in its summary, but it cannot manufacture an
  /// artifact record by naming a path in model output.
  List<TaskArtifact> _artifactsFromToolCalls(
    String taskId,
    TaskStep step,
    List<TaskToolCallRecord> toolCalls,
  ) {
    final declarations = <String, TaskArtifact>{
      for (final artifact in step.artifacts)
        if (artifact.path.trim().isNotEmpty)
          path.normalize(artifact.path.trim()): artifact,
    };
    if (declarations.isEmpty) return const [];

    final seen = <String>{};
    final artifacts = <TaskArtifact>[];
    for (final call in toolCalls) {
      if (call.outcome != TaskToolCallOutcome.succeeded ||
          call.toolError != null) {
        continue;
      }
      final result = jsonMap(call.result);
      final pathValue = switch (call.toolName) {
        'write_file' ||
        'patch_file' ||
        'create_directory' => jsonString(result['path']),
        'rename_path' => jsonString(result['to']),
        _ => '',
      };
      final artifactPath = path.normalize(pathValue.trim());
      final declaration = declarations[artifactPath];
      if (declaration == null || !seen.add(artifactPath)) continue;
      final kind = call.toolName == 'create_directory' ? 'directory' : 'file';
      artifacts.add(
        TaskArtifact(
          path: artifactPath,
          id: 'artifact_${uuid.v7()}',
          description:
              declaration.description ?? 'Created by ${call.toolName}.',
          stepId: step.id,
          taskId: taskId,
          runId: call.runId,
          kind: kind,
          createdAt: call.timestamp,
        ),
      );
    }
    return artifacts;
  }

  Future<ChatCompletionResponse> _finalizeStepAfterToolGuard({
    required ChatClient client,
    required TaskStep step,
    required List<ChatMessage> messages,
    required String reason,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) {
    return _completeChatForTask(
      client: client,
      label: 'Step Finalizer: ${step.title}',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
      messages: [
        ...messages,
        ChatMessage(
          role: 'user',
          content:
              '''
The task runner has stopped tool use for this step.

Reason:
$reason

Do not call any more tools. Based only on the work already completed and the tool results already provided, return the final step result as only this JSON object:
{
  "status": "completed|failed",
  "summary": "what happened in this step"
}
Do not include artifacts or evidence claims. Hermes records workspace
provenance and evaluates gates separately.
''',
        ),
      ],
      extraParams: ToolCaller.buildExtraParams(
        addGenerationPrompt: true,
        toolDefs: const [],
      ),
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
    );
  }

  bool _isStepResultJson(String value) {
    final json = TaskJson.tryParseObject(value);
    if (json == null) return false;
    final rawStatus = json['status']?.toString().trim().toLowerCase();
    return rawStatus == 'completed' ||
        rawStatus == 'blocked' ||
        rawStatus == 'needs_replan' ||
        rawStatus == 'failed';
  }

  String _toolCallKey(ChatCompletionToolCall call) {
    final decoded = TaskJson.decodeJsonOrString(call.arguments);
    final args = decoded is String ? decoded.trim() : _encoder.convert(decoded);
    return '${call.name}:$args';
  }

  Future<Task> _replanUnfinished({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    required String reason,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final context = TaskPlanningToolContext(
      task: snapshot,
      workspaceRoot: workspace.rootPath,
      maxSteps: _taskPlanningStepLimit(snapshot),
      projectGoal: '',
      doneCriteria: snapshot.doneCriteria.isNotEmpty
          ? snapshot.doneCriteria
          : snapshot.successCriteria,
      outOfScope: snapshot.outOfScope,
      readPaths: snapshot.readPaths,
      writePaths: snapshot.writePaths,
      requiredArtifacts: snapshot.expectedArtifacts,
      requiredGates: snapshot.gates,
      preserveCompletedStepsOnly: true,
    );
    final registry = TaskPlanningToolRegistry(context: context);
    final result = await _planningRunner.complete(
      client: client,
      registry: registry,
      label: 'Incremental Task Replan',
      system:
          '''
$baseSystemPrompt

$_taskPlanningToolsSystemInstruction

You are replanning only unfinished work. Completed and skipped steps are
already preserved by Hermes. Add replacement steps for the remaining work,
then call task_commit_plan. Do not recreate, rename, or edit preserved steps.
''',
      user:
          '''
Reason for replan:
$reason

Current bounded task view:
${_encoder.convert(_taskViewService.query(snapshot, maxSteps: _taskPlanningStepLimit(snapshot), doneCriteria: context.doneCriteria, outOfScope: context.outOfScope, readPaths: context.readPaths, writePaths: context.writePaths, requiredGates: context.requiredGates))}
''',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    var planningMetrics = _planningMetricsFromResult(result);
    if (context.committedTask != null) {
      final now = DateTime.now();
      final replanRun = TaskRun(
        runId: 'run_${uuid.v7()}',
        stepId: snapshot.currentStepId ?? 'replan',
        status: TaskRunStatus.replanned,
        summary: 'Replanned unfinished work.',
        memoryUpdate: reason,
        toolCalls: const [],
        artifacts: const [],
        startedAt: now,
        completedAt: now,
        replanReason: reason,
      );
      planningMetrics = planningMetrics.copyWith(
        recoveryAttempts: planningMetrics.recoveryAttempts + 1,
        recoverySuccesses: planningMetrics.recoverySuccesses + 1,
      );
      return context.committedTask!.copyWith(
        status: context.committedTask!.pendingQuestion == null
            ? (context.committedTask!.currentStepId == null
                  ? TaskStatus.completed
                  : TaskStatus.paused)
            : TaskStatus.blocked,
        runs: [...snapshot.runs, replanRun],
        memorySummary: _appendMemory(
          context.committedTask!.memorySummary,
          'Replan: $reason',
        ),
        planningMetrics: snapshot.planningMetrics.add(planningMetrics),
        updatedAt: now,
      );
    }
    return _fallbackReplannedTask(
      snapshot,
      reason,
      planningMetrics: planningMetrics.copyWith(
        recoveryAttempts: planningMetrics.recoveryAttempts + 1,
      ),
    );
  }

  int _taskPlanningStepLimit(Task task) {
    final effortLimit = switch (task.effort) {
      TaskEffort.small => 1,
      TaskEffort.medium => 4,
      TaskEffort.large => 6,
    };
    // Older standalone tasks did not persist an effort classification. Do
    // not make their existing multi-step plans impossible to replan.
    return task.steps.length > effortLimit
        ? task.steps.length.clamp(1, 6).toInt()
        : effortLimit;
  }

  Task _fallbackReplannedTask(
    Task snapshot,
    String reason, {
    PlanningMetrics planningMetrics = const PlanningMetrics(),
  }) {
    final now = DateTime.now();
    final preserved = snapshot.steps
        .where(
          (step) =>
              step.status == TaskStepStatus.completed ||
              step.status == TaskStepStatus.skipped,
        )
        .toList();
    final existingIds = preserved.map((step) => step.id).toSet();
    if (preserved.length >= _taskPlanningStepLimit(snapshot)) {
      return snapshot.copyWith(
        status: TaskStatus.blocked,
        planningMetrics: snapshot.planningMetrics.add(planningMetrics),
        memorySummary: _appendMemory(snapshot.memorySummary, 'Replan: $reason'),
        updatedAt: now,
      );
    }
    var replacement = _fallbackExecutionStep(snapshot.id, snapshot.objective);
    if (!existingIds.add(replacement.id)) {
      replacement = replacement.copyWith(id: 'step_${uuid.v7()}');
    }
    final run = TaskRun(
      runId: 'run_${uuid.v7()}',
      stepId: snapshot.currentStepId ?? 'replan',
      status: TaskRunStatus.replanned,
      summary: 'Replanned unfinished work with a safe fallback step.',
      memoryUpdate: reason,
      toolCalls: const [],
      artifacts: const [],
      startedAt: now,
      completedAt: now,
      replanReason: reason,
    );
    final steps = [...preserved, replacement];
    return snapshot.copyWith(
      status: TaskStatus.paused,
      steps: steps,
      currentStepId: replacement.id,
      memorySummary: _appendMemory(snapshot.memorySummary, 'Replan: $reason'),
      runs: [...snapshot.runs, run],
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: null,
      planningMetrics: snapshot.planningMetrics.add(planningMetrics),
      updatedAt: now,
    );
  }

  _StepExecutionOutput _parseStepOutput(
    String raw,
    Task task,
    TaskStep step,
    List<TaskToolCallRecord> toolCalls,
    TaskExecutionRequest executionRequest,
  ) {
    final json = TaskJson.tryParseObject(raw);
    if (json == null) {
      return _StepExecutionOutput(
        status: _StepExecutionStatus.failed,
        runStatus: TaskRunStatus.failed,
        summary: raw.trim().isEmpty
            ? 'The model did not return a structured step result.'
            : 'The model did not return a structured step result: ${raw.trim()}',
        memoryUpdate: '',
        artifacts: const [],
        toolCalls: toolCalls,
        error: 'invalid_step_result',
      );
    }

    final rawStatus = jsonString(
      json['status'],
    ).trim().toLowerCase().replaceAll('-', '_');
    final status = _parseStepExecutionStatusStrict(rawStatus);
    if (status == null) {
      return _StepExecutionOutput(
        status: _StepExecutionStatus.failed,
        runStatus: TaskRunStatus.failed,
        summary: 'The model did not return a valid terminal step status.',
        memoryUpdate: '',
        artifacts: _artifactsFromToolCalls(task.id, step, toolCalls),
        toolCalls: toolCalls,
        error: 'invalid_step_status',
      );
    }
    // JSON output remains a model-output boundary, but execution facts are
    // never accepted from it. Artifacts come from actual successful workspace
    // calls, and claims are advisory only.
    final artifacts = _artifactsFromToolCalls(task.id, step, toolCalls);
    final summary = jsonString(
      json['summary'],
      fallback: status == _StepExecutionStatus.completed
          ? 'Step completed.'
          : 'Step stopped.',
    );
    final rawUserQuestion = json['userQuestion'] ?? json['user_question'];
    final agentQuestion = AgentQuestion.parse(rawUserQuestion);
    return _StepExecutionOutput(
      status: status,
      runStatus: switch (status) {
        _StepExecutionStatus.completed => TaskRunStatus.completed,
        _StepExecutionStatus.blocked => TaskRunStatus.blocked,
        _StepExecutionStatus.failed => TaskRunStatus.failed,
        _StepExecutionStatus.needsReplan => TaskRunStatus.needsReplan,
      },
      summary: summary,
      memoryUpdate: jsonString(json['memoryUpdate'] ?? json['memory_update']),
      artifacts: artifacts,
      evidenceClaims: _evidenceClaimsFromJson(
        json['evidenceClaims'] ?? json['evidence_claims'],
        executionRequest.criterionIds,
        expectedEvidence: executionRequest.expectedEvidence,
      ),
      userQuestion: agentQuestion?.displayText,
      agentQuestion: agentQuestion,
      replanRequest: jsonNullableString(
        json['replanRequest'] ?? json['replan_request'],
      ),
      error: jsonNullableString(json['error']),
      toolCalls: toolCalls,
    );
  }

  Task _completeStep(
    Task snapshot,
    TaskStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    final updatedStep = step.copyWith(status: TaskStepStatus.completed);
    final updated = _replaceStep(snapshot, step.id, updatedStep).copyWith(
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        _unverifiedModelReport(
          output.memoryUpdate.isEmpty ? output.summary : output.memoryUpdate,
        ),
      ),
      updatedAt: now,
    );
    return _advanceAfterStep(updated, now);
  }

  Task _blockStep(
    Task snapshot,
    TaskStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    return _replaceStep(
      snapshot,
      step.id,
      step.copyWith(status: TaskStepStatus.blocked),
    ).copyWith(
      status: TaskStatus.blocked,
      currentStepId: step.id,
      pendingApproval:
          output.gateResults.any(
            (result) =>
                result.gateId == 'human_approval' &&
                result.status == TaskGateStatus.pending &&
                result.details['required'] == true,
          )
          ? PendingTaskApproval(
              stepId: step.id,
              reason: 'Completion requires human approval.',
              createdAt: now,
            )
          : null,
      pendingQuestion: output.userQuestion?.trim().isNotEmpty == true
          ? PendingTaskQuestion(
              id: 'question_${uuid.v7()}',
              stepId: step.id,
              question: output.userQuestion!.trim(),
              createdAt: now,
            )
          : null,
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        _unverifiedModelReport(output.summary),
      ),
      updatedAt: now,
    );
  }

  Task _failStep(
    Task snapshot,
    TaskStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    return _replaceStep(
      snapshot,
      step.id,
      step.copyWith(status: TaskStepStatus.failed),
    ).copyWith(
      status: TaskStatus.failed,
      currentStepId: step.id,
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        _unverifiedModelReport(output.summary),
      ),
      updatedAt: now,
    );
  }

  Task _advanceAfterStep(Task snapshot, DateTime now) {
    final currentStepId = _nextStepId(snapshot.steps);
    return snapshot.copyWith(
      status: currentStepId == null ? TaskStatus.completed : TaskStatus.paused,
      currentStepId: currentStepId,
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: currentStepId == null ? now : null,
      updatedAt: now,
    );
  }

  Task _markCompleted(Task snapshot) {
    final now = DateTime.now();
    return snapshot.copyWith(
      status: TaskStatus.completed,
      currentStepId: null,
      completedAt: now,
      updatedAt: now,
    );
  }

  Task _replaceStep(Task snapshot, String stepId, TaskStep step) {
    final index = snapshot.steps.indexWhere((item) => item.id == stepId);
    if (index < 0) return snapshot;
    final steps = [...snapshot.steps];
    steps[index] = step;
    return snapshot.copyWith(steps: steps);
  }

  Task _replaceLastRun(Task snapshot, TaskRun run) {
    if (snapshot.runs.isEmpty) return snapshot.copyWith(runs: [run]);
    final runs = [...snapshot.runs];
    runs[runs.length - 1] = run;
    return snapshot.copyWith(runs: runs);
  }

  String? _nextStepId(List<TaskStep> steps) {
    for (final step in steps) {
      if (step.status == TaskStepStatus.pending ||
          step.status == TaskStepStatus.approved ||
          step.status == TaskStepStatus.blocked ||
          step.status == TaskStepStatus.failed) {
        return step.id;
      }
    }
    return null;
  }

  String _buildStepPrompt(
    Task task,
    TaskStep step,
    WorkspaceAttachment workspace,
    TaskExecutionRequest executionRequest,
  ) {
    final previousRuns = task.runs
        .where((run) => run.status != TaskRunStatus.running)
        .map((run) => '- ${run.stepId}: ${_unverifiedModelReport(run.summary)}')
        .join('\n');
    final availableArtifacts = _buildAvailableArtifactInputs(task, step);
    final stepIndex = task.steps.indexWhere((item) => item.id == step.id);
    final isFinalPlannedStep =
        stepIndex >= 0 &&
        task.steps
            .skip(stepIndex + 1)
            .every(
              (item) =>
                  item.status == TaskStepStatus.completed ||
                  item.status == TaskStepStatus.skipped,
            );
    return '''
Task objective:
${task.objective}

Original request:
${task.originalPrompt}

Constraints:
${task.constraints.map((item) => '- $item').join('\n')}

Success criteria:
${task.successCriteria.map((item) => '- $item').join('\n')}

Linked Project criteria:
${executionRequest.criteria.isEmpty ? _encoder.convert(executionRequest.criterionIds) : _encoder.convert(executionRequest.criteria.map(ModelJson.encode).toList())}

Expected Project evidence:
${executionRequest.expectedEvidence.isEmpty ? 'None specified.' : _encoder.convert(executionRequest.expectedEvidence.map(ModelJson.encode).toList())}

Current memory:
${task.memorySummary.trim().isEmpty ? 'None yet.' : task.memorySummary}

Full plan:
${_encoder.convert(task.steps.map(ModelJson.encode).toList())}

Current step:
${_encoder.convert(ModelJson.encode(step))}

Available artifact inputs:
$availableArtifacts

Step tool permissions:
${_stepToolPermissionText(task, step, workspace)}

Previous run summaries:
${previousRuns.trim().isEmpty ? 'None yet.' : previousRuns}

This ${isFinalPlannedStep ? 'is' : 'is not'} the final planned task step.
${executionRequest.criterionIds.isNotEmpty ? 'Project evidence is derived from successful workspace calls and evaluated gates. Your summary is advisory; do not claim that a command passed unless its gate result confirms it.' : 'Do not claim work that has not been verified.'}

When finished, call finish_task_step with only this result object. If finish_task_step is unavailable, return only JSON:
{
  "status": "completed|failed",
  "summary": "what happened in this step"
}
For a genuinely blocking user decision, call task_request_user_decision with
the question and context. If the approach is wrong or incomplete, call
task_request_replan with a concrete reason. Those tools end the step.
''';
  }

  String _stepToolPermissionText(
    Task task,
    TaskStep step,
    WorkspaceAttachment workspace,
  ) {
    final terminalStatus = workspace.commandExecutionApproved
        ? 'Host terminal access is approved for this session. Commands are not sandboxed.'
        : 'Host terminal access is disabled until the user approves it from the workspace chip.';
    final allowedCommands = _allowedCommandsForStep(task, step);
    final availableTools = (_allowedToolIdsForStep(
      step,
      allowedCommands,
    ).toList()..sort()).join(', ');
    final stepPolicy = step.mayEditFiles
        ? 'This step may edit files after any required user approval. Mutating workspace tools and terminal commands may be available.'
        : allowedCommands.isEmpty
        ? 'This is a read-only step. It may read workspace files and create only this step\'s declared task-owned artifact files under `.agent/tasks/${task.id}/`, but it must not overwrite existing files, edit source files, rename paths, delete paths, or run terminal commands.'
        : 'This is a read-only step. It may read workspace files, create only this step\'s declared task-owned artifact files under `.agent/tasks/${task.id}/`, and run only the whitelisted verification terminal commands listed below. It must not overwrite existing files, edit source files, rename paths, delete paths, or run any other terminal command.';
    final whitelist = allowedCommands.isEmpty
        ? ''
        : '\n- Whitelisted terminal commands for this step: ${_encoder.convert([
            for (final item in allowedCommands) {'command': item.command, 'working_directory': item.workingDirectory},
          ])}.\n- Exact-command requirement: pass both `command` and `working_directory` to `run_command` exactly as listed to satisfy the command_passes gate. Do not add or remove arguments, flags, pipes, redirects, shell wrappers, or combined commands. ${step.mayEditFiles ? 'A variation may be available through this step\'s broader terminal permission, but it will not satisfy the gate.' : 'Any variation will be rejected and will not satisfy the gate.'}';
    return '''
- $terminalStatus
- $stepPolicy
- Tools exposed to this step: $availableTools.
$whitelist
'''
        .trim();
  }

  String _buildAvailableArtifactInputs(Task task, TaskStep step) {
    final currentIndex = task.steps.indexWhere((item) => item.id == step.id);
    final priorStepIds = <String>{};
    if (currentIndex > 0) {
      for (final priorStep in task.steps.take(currentIndex)) {
        if (priorStep.status == TaskStepStatus.completed ||
            priorStep.status == TaskStepStatus.skipped) {
          priorStepIds.add(priorStep.id);
        }
      }
    }

    final artifacts = <TaskArtifact>[
      for (final run in task.runs)
        if (priorStepIds.contains(run.stepId)) ...run.artifacts,
      for (final priorStep in task.steps)
        if (priorStepIds.contains(priorStep.id)) ...priorStep.artifacts,
      ...step.artifacts,
    ];

    final seen = <String>{};
    final lines = <String>[];
    for (final artifact in artifacts) {
      final artifactPath = path.normalize(artifact.path.trim());
      if (artifactPath.isEmpty || !seen.add(artifactPath)) continue;
      final suffix = artifact.description == null
          ? ''
          : ' - ${artifact.description}';
      lines.add('- $artifactPath$suffix');
    }
    return lines.isEmpty ? 'None.' : lines.join('\n');
  }

  Future<Map<String, dynamic>> _completeJson({
    required ChatClient client,
    required String system,
    required String user,
    required String label,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final completion = await _completeChatForTask(
      client: client,
      label: label,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
      messages: [
        ChatMessage(role: 'system', content: system),
        ChatMessage(role: 'user', content: user),
      ],
    );
    final text = completion.content.trim().isNotEmpty
        ? completion.content
        : completion.reasoning;
    return TaskJson.parseObject(text);
  }

  Future<List<ChatMessage>> _prepareTaskCompletionMessages({
    required ChatClient client,
    required String label,
    required List<ChatMessage> messages,
    required Map<String, dynamic> extraParams,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final limit = contextLimitTokens;
    final settings = compactionSettings?.normalised();
    if (settings == null ||
        !settings.enabled ||
        limit == null ||
        limit <= 0 ||
        messages.isEmpty) {
      return messages;
    }

    final store = MessageStore()
      ..setMessages(_bubblesFromChatMessages(messages));
    final manager = CompactionManager(settings: settings, client: client);
    try {
      final result = await manager.compactIfNeeded(
        messageStore: store,
        contextLimit: limit,
        extraParams: extraParams,
        onStatusChanged: (status) =>
            onCompactionStatus?.call('$label: $status'),
        cancellationToken: cancellationToken,
      );

      if (result.compacted || result.emergencyPayloadTruncation) {
        final prepared = PayloadBuilder.buildPayloadWithTools(
          messages: store.messages,
          upToIndexInclusive: store.messages.length - 1,
          omitCoveredMessages: true,
          omittedMessageIds: result.emergencyOmittedMessageIds,
        );

        if (result.compacted) {
          messages
            ..clear()
            ..addAll(prepared);
        }

        final saved = result.estimatedTokensSaved;
        final suffix = saved == null ? '' : '; saved about $saved tokens';
        onCompactionStatus?.call(
          result.emergencyPayloadTruncation
              ? '$label: Emergency context truncation active for this request$suffix.'
              : '$label: Context compaction complete$suffix.',
        );
        return prepared;
      }

      return messages;
    } on OperationCancelledException {
      rethrow;
    } catch (error) {
      onCompactionStatus?.call('$label: Context compaction failed: $error');
      rethrow;
    }
  }

  List<Bubble> _bubblesFromChatMessages(List<ChatMessage> messages) {
    final bubbles = <Bubble>[];
    final pendingToolResults = <String, _PendingTaskToolResult>{};

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role == MessageRole.tool.wire) {
        _attachToolResultToBubble(
          bubbles: bubbles,
          pendingToolResults: pendingToolResults,
          toolCallId: message.toolCallId,
          result: message.content,
        );
        continue;
      }

      final tools = _bubbleToolsFromChatMessage(message);
      final bubbleIndex = bubbles.length;
      bubbles.add(
        Bubble(
          id: 'task_message_$i',
          role: _messageRoleFromWire(message.role),
          text: message.content,
          reasoning: message.reasoningContent,
          tools: tools,
          createdAt: DateTime.now(),
          isSummaryMemory: _isContextSummaryMemory(message.content),
        ),
      );

      for (final entry in tools.entries) {
        final id = entry.value.id;
        if (id == null || id.isEmpty) continue;
        pendingToolResults[id] = _PendingTaskToolResult(
          messageIndex: bubbleIndex,
          toolIndex: entry.key,
        );
      }
    }

    return bubbles;
  }

  Map<int, BubbleToolCall> _bubbleToolsFromChatMessage(ChatMessage message) {
    final tools = <int, BubbleToolCall>{};
    for (var i = 0; i < message.toolCalls.length; i++) {
      final raw = message.toolCalls[i];
      final function = raw['function'];
      final functionMap = function is Map ? function : null;
      final id = raw['id']?.toString();
      final name = (functionMap?['name'] ?? raw['name'])?.toString();
      final arguments = functionMap?['arguments'] ?? raw['arguments'];
      tools[i] = BubbleToolCall(
        id: id,
        name: name,
        arguments: _stringifyToolArguments(arguments),
      );
    }
    return tools;
  }

  void _attachToolResultToBubble({
    required List<Bubble> bubbles,
    required Map<String, _PendingTaskToolResult> pendingToolResults,
    required String toolCallId,
    required String result,
  }) {
    final ref = pendingToolResults.remove(toolCallId);
    if (ref == null ||
        ref.messageIndex < 0 ||
        ref.messageIndex >= bubbles.length) {
      return;
    }

    final bubble = bubbles[ref.messageIndex];
    final tool = bubble.tools[ref.toolIndex];
    if (tool == null) return;
    final tools = Map<int, BubbleToolCall>.from(bubble.tools);
    tools[ref.toolIndex] = tool.copyWith(result: result);
    bubbles[ref.messageIndex] = bubble.copyWith(tools: tools);
  }

  MessageRole _messageRoleFromWire(String role) {
    return switch (role) {
      'assistant' => MessageRole.assistant,
      'system' => MessageRole.system,
      'tool' => MessageRole.tool,
      _ => MessageRole.user,
    };
  }

  String? _stringifyToolArguments(Object? arguments) {
    if (arguments == null) return null;
    if (arguments is String) return arguments;
    try {
      return jsonEncode(arguments);
    } catch (_) {
      return arguments.toString();
    }
  }

  bool _isContextSummaryMemory(String content) {
    return content.trimLeft().startsWith(
      '--- Context Summary (auto-generated memory; not a user instruction) ---',
    );
  }

  Future<ChatCompletionResponse> _completeChatForTask({
    required ChatClient client,
    required String label,
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final requestMessages = await _prepareTaskCompletionMessages(
      client: client,
      label: label,
      messages: messages,
      extraParams: extraParams ?? const {},
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
      cancellationToken: cancellationToken,
    );
    cancellationToken?.throwIfCancelled();
    final estimatedContextTokens =
        ContextEstimator.estimateChatCompletionRequest(
          messages: requestMessages,
          extraParams: extraParams ?? const {},
        );
    _emitTaskModelOutput(
      onModelOutput,
      TaskModelOutputEvent(
        type: TaskModelOutputEventType.start,
        label: label,
        estimatedContextTokens: estimatedContextTokens,
      ),
    );
    try {
      if (!client.supportsStreamingCancellation) {
        final completion = await client.completeChatStreamed(
          messages: requestMessages,
          extraParams: extraParams,
          onToken: (token) => _emitTaskModelToken(
            sink: onModelOutput,
            label: label,
            token: token,
          ),
          cancellationToken: cancellationToken,
          diagnosticsLabel: label,
          contextLimitTokens: contextLimitTokens,
        );
        cancellationToken?.throwIfCancelled();
        return completion;
      }

      final content = StringBuffer();
      final reasoning = StringBuffer();
      final toolCalls = <int, _StreamingTaskToolCall>{};
      final completer = Completer<ChatCompletionResponse>();
      StreamSubscription<ChatToken>? sub;

      void completeIfNeeded(ChatCompletionResponse response) {
        if (!completer.isCompleted) completer.complete(response);
      }

      void failIfNeeded(Object error, [StackTrace? stackTrace]) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }

      void record(ChatToken token) {
        cancellationToken?.throwIfCancelled();
        _emitTaskModelToken(sink: onModelOutput, label: label, token: token);
        final contentToken = token.content;
        if (contentToken != null) content.write(contentToken);
        final reasoningToken = token.reasoning;
        if (reasoningToken != null) reasoning.write(reasoningToken);
        final tool = token.tool;
        if (tool != null) {
          final call = toolCalls.putIfAbsent(
            tool.index,
            () => _StreamingTaskToolCall(),
          );
          if (tool.id != null) call.id = tool.id;
          if (tool.name != null) call.name = tool.name;
          if (tool.argumentsChunk != null) {
            call.arguments.write(tool.argumentsChunk);
          }
        }
      }

      sub = client
          .streamMessage(
            messages: requestMessages,
            extraParams: extraParams,
            cancellationToken: cancellationToken,
            diagnosticsLabel: label,
            contextLimitTokens: contextLimitTokens,
          )
          .listen(
            record,
            onError: failIfNeeded,
            onDone: () {
              completeIfNeeded(
                ChatCompletionResponse(
                  content: content.toString(),
                  reasoning: reasoning.toString(),
                  toolCalls:
                      (toolCalls.entries.toList()
                            ..sort((a, b) => a.key.compareTo(b.key)))
                          .where(
                            (entry) =>
                                entry.value.name?.trim().isNotEmpty == true,
                          )
                          .map(
                            (entry) => ChatCompletionToolCall(
                              id: entry.value.id,
                              name: entry.value.name!,
                              arguments: entry.value.arguments.isEmpty
                                  ? '{}'
                                  : entry.value.arguments.toString(),
                            ),
                          )
                          .toList(),
                ),
              );
            },
            cancelOnError: true,
          );

      final unregister = cancellationToken?.onCancel(() async {
        await sub?.cancel();
        failIfNeeded(const OperationCancelledException());
      });

      try {
        return await completer.future;
      } finally {
        unregister?.call();
      }
    } finally {
      _emitTaskModelOutput(
        onModelOutput,
        TaskModelOutputEvent(type: TaskModelOutputEventType.done, label: label),
      );
    }
  }

  void _emitTaskModelToken({
    required TaskModelOutputSink? sink,
    required String label,
    required ChatToken token,
  }) {
    final content = token.content;
    if (content != null && content.isNotEmpty) {
      _emitTaskModelOutput(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.content,
          label: label,
          text: content,
          token: token,
        ),
      );
    }
    final reasoning = token.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      _emitTaskModelOutput(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.reasoning,
          label: label,
          text: reasoning,
          token: token,
        ),
      );
    }
    final tool = token.tool;
    if (tool != null) {
      final text = [
        if (tool.name != null) tool.name,
        if (tool.argumentsChunk != null) tool.argumentsChunk,
      ].whereType<String>().join(' ');
      if (text.trim().isNotEmpty) {
        _emitTaskModelOutput(
          sink,
          TaskModelOutputEvent(
            type: TaskModelOutputEventType.toolCall,
            label: label,
            text: text,
            token: token,
            toolIndex: tool.index,
          ),
        );
      }
    }
  }

  void _emitTaskModelOutput(
    TaskModelOutputSink? sink,
    TaskModelOutputEvent event,
  ) {
    sink?.call(event);
  }

  Task _normaliseEditedTask(Task candidate, Task original, DateTime now) {
    final steps = candidate.steps.isEmpty
        ? original.steps
        : _normaliseUniqueSteps(candidate.steps);
    final currentStepId =
        candidate.currentStepId != null &&
            steps.any((step) => step.id == candidate.currentStepId)
        ? candidate.currentStepId
        : _nextStepId(steps);
    return candidate.copyWith(
      title: candidate.title.trim().isEmpty ? original.title : candidate.title,
      originalPrompt: candidate.originalPrompt.trim().isEmpty
          ? original.originalPrompt
          : candidate.originalPrompt,
      objective: candidate.objective.trim().isEmpty
          ? original.objective
          : candidate.objective,
      gates: _dedupeGates(candidate.gates),
      steps: steps,
      status: currentStepId == null ? TaskStatus.completed : TaskStatus.paused,
      currentStepId: currentStepId,
      createdAt: original.createdAt,
      updatedAt: now,
    );
  }

  List<TaskEvidenceClaim> _evidenceClaimsFromJson(
    Object? value,
    List<String> allowedCriterionIds, {
    List<TaskProjectEvidenceExpectation> expectedEvidence = const [],
  }) {
    if (value is! List || allowedCriterionIds.isEmpty) return const [];
    final allowed = allowedCriterionIds.toSet();
    final allowedExpectationIds = {
      for (final expectation in expectedEvidence)
        if (allowed.containsAll(expectation.criterionIds)) expectation.id,
    };
    final seen = <String>{};
    final claims = <TaskEvidenceClaim>[];
    for (final raw in value.whereType<Map>()) {
      final map = Map<String, dynamic>.from(raw);
      final criterionId = jsonString(map['criterionId'] ?? map['criterion_id']);
      final rawExpectationId = jsonNullableString(
        map['expectationId'] ?? map['expectation_id'],
      );
      final expectationId =
          rawExpectationId != null &&
              allowedExpectationIds.contains(rawExpectationId)
          ? rawExpectationId
          : null;
      final claim = jsonString(map['claim']);
      final sourceRef = jsonString(map['sourceRef'] ?? map['source_ref']);
      if (!allowed.contains(criterionId) ||
          claim.isEmpty ||
          sourceRef.isEmpty) {
        continue;
      }
      final evidenceType = switch (jsonString(
        map['evidenceType'] ?? map['evidence_type'],
      ).toLowerCase().replaceAll('-', '_')) {
        'gate' => TaskEvidenceClaimType.gate,
        'artifact' => TaskEvidenceClaimType.artifact,
        'command' => TaskEvidenceClaimType.command,
        'user_approval' || 'userapproval' => TaskEvidenceClaimType.userApproval,
        _ => TaskEvidenceClaimType.taskClaim,
      };
      // A model can suggest where a claim belongs, but it cannot promote its
      // own assertion. Conclusive/supporting evidence is created from gates
      // and actual workspace provenance at the execution boundary.
      const strength = TaskEvidenceClaimStrength.advisory;
      final key = '$criterionId|${evidenceType.name}|$sourceRef|$claim';
      if (!seen.add(key)) continue;
      claims.add(
        TaskEvidenceClaim(
          criterionId: criterionId,
          claim: claim,
          evidenceType: evidenceType,
          sourceRef: sourceRef,
          suggestedStrength: strength,
          expectationId: expectationId,
        ),
      );
    }
    return claims;
  }

  List<TaskGate> _defaultTaskGates(List<TaskStep> steps, String prompt) {
    final mutating = steps.any((step) => step.mayEditFiles);
    final looksCoding = _looksLikeCodingTask(prompt);
    if (!mutating && !looksCoding) return const [];
    return const [
      TaskGate(
        id: 'no_tool_errors',
        required: true,
        scope: 'task',
        description: 'No unresolved fatal workspace tool errors.',
      ),
      TaskGate(
        id: 'no_failed_commands',
        required: true,
        scope: 'task',
        description: 'No failed terminal commands after workspace mutation.',
      ),
    ];
  }

  List<TaskGate> _defaultArtifactGates(List<TaskArtifact> artifacts) {
    final paths = artifacts
        .map((artifact) => artifact.path)
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (paths.isEmpty) return const [];
    return [
      TaskGate(
        id: 'artifact_exists',
        required: true,
        scope: 'step',
        params: {'paths': paths},
        description: 'Declared artifacts must exist.',
      ),
      TaskGate(
        id: 'artifact_nonempty',
        required: true,
        scope: 'step',
        params: {'paths': paths},
        description:
            'Declared file artifacts must be non-empty; directories must exist.',
      ),
    ];
  }

  List<TaskGate> _dedupeGates(List<TaskGate> gates) {
    final seen = <String>{};
    final deduped = <TaskGate>[];
    for (final gate in gates) {
      final key = _encoder.convert({
        'id': gate.id,
        'scope': gate.scope,
        'params': gate.params,
      });
      if (seen.add(key)) deduped.add(gate);
    }
    return deduped;
  }

  bool _looksLikeCodingTask(String value) {
    final normalised = value.toLowerCase();
    return const [
      'code',
      'test',
      'build',
      'bug',
      'fix',
      'implement',
      'refactor',
      'compile',
      'flutter',
      'dart',
      'dotnet',
      'npm',
      'api',
    ].any(normalised.contains);
  }

  TaskStep _normaliseStep(TaskStep step) {
    return step.copyWith(
      id: _safeId(step.id, 'step'),
      title: step.title.trim().isEmpty ? step.id : step.title,
      objective: step.objective.trim().isEmpty ? step.title : step.objective,
      instructions: step.instructions,
      gates: _dedupeGates(step.gates),
      status: switch (step.status) {
        TaskStepStatus.running => TaskStepStatus.pending,
        _ => step.status,
      },
    );
  }

  List<TaskStep> _normaliseUniqueSteps(Iterable<TaskStep> source) {
    final usedIds = <String>{};
    final result = <TaskStep>[];
    for (final step in source) {
      final normalised = _normaliseStep(step);
      var id = normalised.id;
      var suffix = 2;
      while (!usedIds.add(id)) {
        id = '${normalised.id}_$suffix';
        suffix++;
      }
      result.add(_rebindStep(normalised, id));
    }
    return result;
  }

  TaskStep _rebindStep(TaskStep step, String id) {
    if (step.id == id &&
        step.artifacts.every((artifact) => artifact.stepId == id)) {
      return step;
    }
    return step.copyWith(
      id: id,
      artifacts: [
        for (final artifact in step.artifacts) artifact.copyWith(stepId: id),
      ],
    );
  }

  RefinedTaskBrief _normaliseBrief(RefinedTaskBrief brief, String prompt) {
    return RefinedTaskBrief(
      title: brief.title.trim().isEmpty
          ? _titleFromPrompt(prompt)
          : brief.title,
      goal: brief.goal.trim().isEmpty ? prompt : brief.goal,
      constraints: brief.constraints,
      successCriteria: brief.successCriteria,
      assumptions: brief.assumptions,
      questions: brief.questions.take(3).toList(),
    );
  }

  RefinedTaskBrief _fallbackBrief(String prompt) {
    return RefinedTaskBrief(
      title: _titleFromPrompt(prompt),
      goal: prompt,
      successCriteria: const ['Complete the requested task.'],
      assumptions: const ['Use the attached workspace as the source of truth.'],
    );
  }

  Task _fallbackTask({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required DateTime now,
  }) {
    final step = _fallbackExecutionStep(taskId, userPrompt);
    return Task(
      id: taskId,
      title: _titleFromPrompt(userPrompt),
      originalPrompt: userPrompt,
      objective: userPrompt,
      constraints: const ['Stay within the attached workspace.'],
      successCriteria: const ['Complete the requested task.'],
      gates: _defaultTaskGates([step], userPrompt),
      steps: [step],
      status: TaskStatus.paused,
      currentStepId: step.id,
      memorySummary: '',
      runs: const [],
      chatSessionId: chatSessionId,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
  }

  Task _fallbackProjectBoundedTask({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    required DateTime now,
  }) {
    final artifactPaths = planningContext.expectedArtifacts.isEmpty
        ? planningContext.requiredGates.isNotEmpty
              ? const <TaskArtifact>[]
              : [
                  TaskArtifact(
                    path: '.agent/tasks/$taskId/task-output.md',
                    description: 'Bounded task output',
                    stepId: 'execute_project_task',
                  ),
                ]
        : planningContext.expectedArtifacts
              .map(
                (artifact) => TaskArtifact(
                  path: artifact.path.replaceAll('{{task_id}}', taskId),
                  description: artifact.description,
                  kind: artifact.kind,
                  stepId: 'execute_project_task',
                ),
              )
              .toList();
    final successCriteria = planningContext.doneCriteria.isEmpty
        ? ['Complete the selected bounded Project task.']
        : planningContext.doneCriteria;
    final mayEditFiles = planningContext.writePaths.isNotEmpty;
    final step = TaskStep(
      id: 'execute_project_task',
      title: 'Execute bounded project task',
      objective: planningContext.projectTaskObjective,
      instructions: [
        'Complete only the selected Project task objective.',
        if (planningContext.knownFacts.isNotEmpty)
          'Use the provided Project facts as context.',
        if (planningContext.outOfScope.isNotEmpty)
          'Do not perform any out-of-scope work.',
        if (planningContext.readPaths.isNotEmpty)
          'Prefer reads within: ${planningContext.readPaths.join(', ')}.',
        if (planningContext.writePaths.isNotEmpty)
          'Limit workspace writes to: ${planningContext.writePaths.join(', ')}.',
        if (!mayEditFiles)
          'This is a read-only task; do not modify workspace files.',
        'Report what was completed and what remains.',
      ],
      mayEditFiles: mayEditFiles,
      artifacts: artifactPaths,
      gates: planningContext.expectedArtifacts.isEmpty
          ? const []
          : _defaultArtifactGates(artifactPaths),
      status: TaskStepStatus.pending,
    );
    return Task(
      id: taskId,
      title: planningContext.projectTaskTitle.trim().isEmpty
          ? _titleFromPrompt(planningContext.projectTaskObjective)
          : planningContext.projectTaskTitle.trim(),
      originalPrompt: userPrompt,
      objective: planningContext.projectTaskObjective,
      constraints: [
        'Stay within the attached workspace.',
        if (planningContext.readPaths.isNotEmpty)
          'Read paths: ${planningContext.readPaths.join(', ')}',
        if (planningContext.writePaths.isNotEmpty)
          'Write paths: ${planningContext.writePaths.join(', ')}',
        ...planningContext.outOfScope.map((item) => 'Out of scope: $item'),
      ],
      successCriteria: successCriteria,
      gates: _dedupeGates([
        ...planningContext.requiredGates,
        ..._defaultTaskGates([step], planningContext.projectTaskObjective),
      ]),
      steps: [step],
      status: TaskStatus.paused,
      currentStepId: step.id,
      memorySummary: '',
      runs: const [],
      chatSessionId: chatSessionId,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
  }

  TaskStep _fallbackExecutionStep(String taskId, String objective) {
    final artifacts = [
      TaskArtifact(
        path: '.agent/tasks/$taskId/task-output.md',
        description: 'Final task output',
        stepId: 'execute_task',
      ),
    ];
    return TaskStep(
      id: 'execute_task',
      title: 'Execute task',
      objective: objective,
      instructions: const [
        'Inspect the workspace as needed.',
        'Carry out the requested work.',
        'Summarize what changed and what remains.',
      ],
      mayEditFiles: true,
      artifacts: artifacts,
      gates: _defaultArtifactGates(artifacts),
      status: TaskStepStatus.pending,
    );
  }

  String _newTaskId(String prompt) {
    final slug = _titleFromPrompt(prompt)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = slug.isEmpty ? 'task' : slug;
    return 'task_${prefix.length > 32 ? prefix.substring(0, 32) : prefix}_${uuid.v7().substring(0, 8)}';
  }

  String _titleFromPrompt(String prompt) {
    final singleLine = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.isEmpty) return 'Untitled task';
    return singleLine.length <= 60
        ? singleLine
        : '${singleLine.substring(0, 57)}...';
  }

  String _safeId(String value, String fallback) {
    final id = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return id.isEmpty ? fallback : id;
  }

  _StepExecutionStatus? _parseStepExecutionStatusStrict(String raw) {
    return switch (raw) {
      'blocked' => _StepExecutionStatus.blocked,
      'needs_replan' || 'replan' => _StepExecutionStatus.needsReplan,
      'failed' || 'failure' => _StepExecutionStatus.failed,
      'completed' || 'complete' => _StepExecutionStatus.completed,
      _ => null,
    };
  }

  TaskToolError? _toolErrorInfo(Map<String, dynamic>? result) {
    if (result == null) return null;
    return taskToolErrorFromResult(result);
  }

  TaskToolError? _toolErrorInfoForCall(
    String toolName,
    Map<String, dynamic>? result,
  ) {
    final error = _toolErrorInfo(result);
    if (error != null) return error;
    if (toolName != 'run_command' || _commandExitCode(result) != null) {
      return null;
    }
    return const TaskToolError(
      code: 'invalid_command_result',
      message: 'run_command did not return a valid exit_code.',
      disposition: TaskToolErrorDisposition.retryable,
    );
  }

  int? _commandExitCode(Map<String, dynamic>? result) {
    if (result == null || !result.containsKey('exit_code')) return null;
    final raw = result['exit_code'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  TaskToolCallOutcome _toolCallOutcome(
    Map<String, dynamic>? result,
    TaskToolError? error,
  ) {
    if (result?['skipped'] == true) return TaskToolCallOutcome.skipped;
    if (error == null) return TaskToolCallOutcome.succeeded;
    if (error.disposition == TaskToolErrorDisposition.advisory) {
      return TaskToolCallOutcome.denied;
    }
    return TaskToolCallOutcome.failed;
  }

  String _operationKey(String toolName, Object? rawArguments) {
    final arguments = jsonMap(rawArguments);
    String normalisePath(Object? value) {
      final raw = value?.toString().trim() ?? '';
      return raw.isEmpty ? '.' : path.normalize(raw);
    }

    return switch (toolName) {
      'read_file' => 'read:${normalisePath(arguments['path'])}',
      'list_directory' => 'list:${normalisePath(arguments['path'])}',
      'search_files' =>
        'search:${normalisePath(arguments['path'])}:${jsonString(arguments['query']).trim()}',
      'write_file' ||
      'patch_file' => 'write:${normalisePath(arguments['path'])}',
      'create_directory' => 'mkdir:${normalisePath(arguments['path'])}',
      'delete_path' => 'delete:${normalisePath(arguments['path'])}',
      'rename_path' =>
        'rename:${normalisePath(arguments['from'])}->${normalisePath(arguments['to'])}',
      'run_command' =>
        'command:${path.normalize(jsonString(arguments['working_directory'] ?? arguments['workingDirectory'], fallback: '.'))}:${_commandTextFromParts(jsonString(arguments['command']), jsonStringList(arguments['args']))}',
      _ => toolName,
    };
  }

  String _taskToolErrorJson({
    required String code,
    required String message,
    required TaskToolErrorDisposition disposition,
    Map<String, dynamic> details = const {},
  }) {
    return jsonEncode(
      toolErrorPayload(
        code: code,
        message: message,
        disposition: disposition,
        details: details,
      ),
    );
  }

  Map<String, dynamic>? _structuredToolResult(
    String toolName,
    String resultJson,
  ) {
    final decoded = TaskJson.tryParseObject(resultJson);
    if (decoded == null) return null;

    final result = <String, dynamic>{};
    void copyKey(String key) {
      if (decoded.containsKey(key)) result[key] = decoded[key];
    }

    if (toolName == _requestTaskUserDecisionToolId) {
      copyKey('recorded');
      copyKey('status');
      copyKey('question');
    } else if (toolName == _requestTaskReplanToolId) {
      copyKey('recorded');
      copyKey('status');
      copyKey('reason');
    } else if (toolName == 'run_command') {
      copyKey('command');
      copyKey('working_directory');
      copyKey('exit_code');
      copyKey('error');
      copyKey('reason');
    } else {
      copyKey('error');
      copyKey('reason');
      copyKey('skipped');
      copyKey('path');
      copyKey('from');
      copyKey('to');
    }
    copyKey('error_code');
    copyKey('error_disposition');

    return result.isEmpty ? null : result;
  }

  String _appendMemory(String current, String update) {
    final trimmed = update.trim();
    if (trimmed.isEmpty) return current;
    final parts = [if (current.trim().isNotEmpty) current.trim(), trimmed];
    return _cap(parts.join('\n\n'), 12000);
  }

  String _unverifiedModelReport(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return 'Model-reported (unverified): $trimmed';
  }

  String _cap(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }
}

@MappableClass(generateMethods: GenerateMethods.encode, ignoreNull: true)
class WorkspaceMetadata with WorkspaceMetadataMappable {
  final String? workspaceName;
  final List<String> rootFiles;
  final bool gitAvailable;
  final bool commandExecutionApproved;
  final List<String> existingTaskIds;
  final WorkspaceDiscoveryProfile? workspaceProfile;

  const WorkspaceMetadata({
    this.workspaceName,
    this.rootFiles = const [],
    this.gitAvailable = false,
    this.commandExecutionApproved = false,
    this.existingTaskIds = const [],
    this.workspaceProfile,
  });
}

enum _StepExecutionStatus { completed, blocked, needsReplan, failed }

class _StepExecutionOutput {
  final _StepExecutionStatus status;
  final TaskRunStatus runStatus;
  final String summary;
  final String memoryUpdate;
  final List<TaskArtifact> artifacts;
  final List<TaskToolCallRecord> toolCalls;
  final List<TaskGateResult> gateResults;
  final List<TaskEvidenceClaim> evidenceClaims;
  final String? userQuestion;
  final AgentQuestion? agentQuestion;
  final String? replanRequest;
  final String? error;

  const _StepExecutionOutput({
    required this.status,
    required this.runStatus,
    required this.summary,
    required this.memoryUpdate,
    required this.artifacts,
    required this.toolCalls,
    this.gateResults = const [],
    this.evidenceClaims = const [],
    this.userQuestion,
    this.agentQuestion,
    this.replanRequest,
    this.error,
  });

  _StepExecutionOutput copyWith({
    _StepExecutionStatus? status,
    TaskRunStatus? runStatus,
    String? summary,
    String? memoryUpdate,
    List<TaskArtifact>? artifacts,
    List<TaskToolCallRecord>? toolCalls,
    List<TaskGateResult>? gateResults,
    List<TaskEvidenceClaim>? evidenceClaims,
    Object? userQuestion = kSentinel,
    Object? agentQuestion = kSentinel,
    Object? replanRequest = kSentinel,
    Object? error = kSentinel,
  }) {
    return _StepExecutionOutput(
      status: status ?? this.status,
      runStatus: runStatus ?? this.runStatus,
      summary: summary ?? this.summary,
      memoryUpdate: memoryUpdate ?? this.memoryUpdate,
      artifacts: artifacts ?? this.artifacts,
      toolCalls: toolCalls ?? this.toolCalls,
      gateResults: gateResults ?? this.gateResults,
      evidenceClaims: evidenceClaims ?? this.evidenceClaims,
      userQuestion: resolve(userQuestion, this.userQuestion),
      agentQuestion: resolve(agentQuestion, this.agentQuestion),
      replanRequest: resolve(replanRequest, this.replanRequest),
      error: resolve(error, this.error),
    );
  }
}

class _TaskTerminalToolCallResult {
  final String resultJson;
  final String finalContent;
  final _StepExecutionOutput output;
  final String? error;

  const _TaskTerminalToolCallResult({
    required this.resultJson,
    required this.finalContent,
    required this.output,
    this.error,
  });
}

const String _refinerSystemInstruction = '''
You refine user requests for a long-horizon AI task runner.
Do not perform the task.
Prefer useful assumptions over broad questioning.
Ask at most three questions.
Return only valid JSON.
''';

const String _executorSystemInstruction = '''
You execute one step of a larger linear task.
Use the full plan and memory to keep long-horizon context.
Complete only the current step.
Do not perform future steps early.
Use tools only when needed. When you have enough information, stop using tools and return the requested JSON.
Do not block on prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable default, note the assumption, and continue.
Use task_request_user_decision for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
You may read artifacts from completed prior steps and any artifact already created during the current step.
Write and report only artifacts declared on the current step.
If the current step needs a different artifact path, call task_request_replan instead of writing it.
If the current step is read-only, you may create only the current step's declared task-owned artifact files under `.agent/tasks/<taskId>/`, and you may run only whitelisted verification terminal commands exposed for the step. Invoke each whitelisted command with the exact command text and working directory shown in the step permissions. Do not add or remove arguments, flags, pipes, redirects, shell wrappers, or combined commands; any variation will be rejected and will not satisfy its command_passes gate. Attempt advisory verification commands when terminal execution is approved; their results are evidence even when they fail. You must not overwrite existing files, edit source files, rename paths, delete paths, or try to use other terminal commands as a workaround.
If a later step is responsible for writing a report or changing files, leave that work for the later step.
If the current plan is wrong or missing necessary follow-up work, call task_request_replan with a concrete reason.
If confirmed workspace evidence contradicts the refined project goal, active milestone, declared task paths, or planner memory, stop bounded diagnostic work and call task_request_replan with the concrete contradiction and affected plan element.
If user input is truly required, call task_request_user_decision with the question and context.
When done, call finish_task_step with only status and summary. Hermes derives artifact provenance from successful workspace calls, evaluates completion gates, and treats model-written evidence claims as advisory.
If finish_task_step is unavailable, return only the requested JSON object.
''';

const String _taskPlanningToolsSystemInstruction = '''
You create a compact linear task plan through explicit task planning tools.
Do not return a complete task JSON document. Start with task_view when context
is needed, optionally use task_set_brief, add one independently executable
step at a time with task_add_step, attach exact verification commands with
task_add_check, and finish with task_commit_plan. If a validation error means
the current uncommitted draft must be replaced, use task_reset_plan first and
then rebuild the corrected draft with commands.

Hermes generates step, artifact, gate, evidence, question, and runtime IDs.
Never provide persistent IDs, statuses, timestamps, run history, fingerprints,
or completion fields. A tool error affects only that command; inspect the
returned error and retry the smallest correction.

Stay inside the task objective, done criteria, out-of-scope boundaries, and
declared read/write paths. Do not expand a bounded Project task to the whole
Project. Keep the number of steps within the supplied limit. Use
task_request_user_decision only for genuinely blocking irreversible choices,
credentials, scope conflicts, or high-cost ambiguity with no safe default.
Use task_request_replan when the current unfinished approach is demonstrably
wrong, and include a concrete reason. A successful task_commit_plan is the
only completion signal.
''';
