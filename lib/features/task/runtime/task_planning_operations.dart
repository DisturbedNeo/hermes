// ignore_for_file: dead_code, dead_code_on_catch_subtype, unused_element
part of 'task_runtime_collaborators.dart';

class _IncrementalTaskPlanAttempt {
  final Task? task;
  final bool usedPlanningTools;
  final PlanningMetrics planningMetrics;
  final String? planningError;

  const _IncrementalTaskPlanAttempt({
    this.task,
    this.usedPlanningTools = false,
    this.planningMetrics = const PlanningMetrics(),
    this.planningError,
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

extension TaskPlanningOperations on TaskRuntimeContext {
  Future<Task> createTask({
    required ModelCompletionPort client,
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required String baseSystemPrompt,
    String? chatSessionId,
    String? projectId,
    String? canonicalTaskId,
    TaskPlanningContext? planningContext,
    ModelOutputSink? onModelOutput,
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
      final plannedTask = incremental.task;
      if (plannedTask != null) {
        task = plannedTask;
      } else {
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
        task = task.copyWith(
          planningError:
              incremental.planningError ??
              'Task planner did not commit an executable plan; safe fallback used.',
        );
      }
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (error) {
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
      task = task.copyWith(
        planningError: 'Task planning failed; safe fallback used: $error',
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
    final existing = await _persistenceStore.persistence.loadTaskSnapshot(
      workspace.rootPath,
      task.id,
      includeHistory: false,
    );
    if (existing != null) {
      task = task.copyWith(persistenceRevision: existing.revision);
    }
    return _persistTask(workspace.rootPath, task);
  }

  Future<_IncrementalTaskPlanAttempt> _completeTaskPlanWithCommands({
    required ModelCompletionPort client,
    required WorkspaceAttachment workspace,
    required String baseSystemPrompt,
    required String taskId,
    required String userPrompt,
    required WorkspaceMetadata metadata,
    required TaskPlanningContext? planningContext,
    required DateTime now,
    required String? chatSessionId,
    required String? projectId,
    ModelOutputSink? onModelOutput,
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
    final planningResult = await _planningCoordinator.plan(
      client: client,
      context: context,
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

Workspace context is read-only task context. Do not mutate the project
workspace graph directly; durable graph changes belong to the project planner
or an explicit user command. Task memories remain separate from that graph.
''',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );

    return _IncrementalTaskPlanAttempt(
      task: context.committedTask,
      usedPlanningTools: context.committedTask != null,
      planningMetrics: planningResult.planningMetrics,
      planningError: planningResult.error,
    );
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
    'workspace_orientation': context.workspaceOrientation,
    'workspace_context': context.workspaceContext,
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
    final existing = await _persistenceStore.persistence.loadTaskSnapshot(
      workspace.rootPath,
      task.id,
      includeHistory: false,
    );
    final prepared = existing == null
        ? task
        : task.copyWith(persistenceRevision: existing.revision);
    return _persistTask(workspace.rootPath, prepared);
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
        persistenceRevision: snapshot.persistenceRevision,
        chatSessionId: snapshot.chatSessionId,
        projectId: snapshot.projectId,
      ),
      snapshot,
      now,
    );
    return _persistTask(workspace.rootPath, normalised);
  }

  Future<Task> runNextStep({
    required ModelCompletionPort client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    TaskExecutionRequest executionRequest = const TaskExecutionRequest(),
    bool persist = true,
  }) => _stepRunner.run(
    workspace: workspace,
    snapshot: snapshot,
    cancellationToken: cancellationToken,
    persist: persist,
    execute: (recovered) => _runNextStepCore(
      client: client,
      workspace: workspace,
      snapshot: recovered,
      baseSystemPrompt: baseSystemPrompt,
      requirePhaseApproval: requirePhaseApproval,
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
      questionAutonomy: questionAutonomy,
      executionRequest: executionRequest,
      persist: persist,
    ),
  );
}
