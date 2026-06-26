import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_model_calls.dart';
import 'package:hermes/core/services/project_system/project_storage_service.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:path/path.dart' as path;

typedef ProjectTaskSnapshotSink = void Function(TaskDocument? task);
typedef ProjectCompactionStatusSink = void Function(String status);

class ProjectRunResult {
  final ProjectDocument project;
  final TaskDocument? activeTask;

  const ProjectRunResult({required this.project, this.activeTask});
}

class ProjectService {
  ProjectService({
    required TaskService taskService,
    ProjectStorageService? storage,
    ProjectModelCalls? modelCalls,
  }) : _taskService = taskService,
       _storage = storage ?? ProjectStorageService(),
       _modelCalls =
           modelCalls ??
           ProjectModelCalls(toolService: taskService.toolService);

  final TaskService _taskService;
  final ProjectStorageService _storage;
  final ProjectModelCalls _modelCalls;
  final QuestionPolicyService _questionPolicy = const QuestionPolicyService();
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  ProjectStorageService get storage => _storage;

  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _storage.listProjects(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<ProjectDocument?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _storage.loadLatestProject(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<ProjectDocument?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) {
    return _storage.loadProject(
      workspace.rootPath,
      projectId,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) {
    if (workspace.missing) return Future.value(0);
    return _storage.deleteProjectsForChatSession(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) {
    if (workspace.missing) return Future.value(0);
    return _storage.deleteOrphanedChatProjects(
      workspace.rootPath,
      retainedChatSessionIds: retainedChatSessionIds,
    );
  }

  Future<ProjectDocument> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String chatSessionId,
  }) async {
    if (snapshot.chatSessionId == chatSessionId) return snapshot;
    final updated = snapshot.copyWith(
      chatSessionId: chatSessionId,
      updatedAt: DateTime.now(),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  String encodeProject(ProjectDocument project) =>
      '${_encoder.convert(project.toJson())}\n';

  Future<ProjectDocument> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ChatClient? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    cancellationToken?.throwIfCancelled();
    final now = DateTime.now();
    final metadata = await _collectWorkspaceMetadata(
      workspace,
      chatSessionId: chatSessionId,
    );
    final init = client == null
        ? _fallbackInitialisation(userPrompt)
        : await _modelCalls.initializeProject(
            client: client,
            baseSystemPrompt: baseSystemPrompt,
            workspace: workspace,
            originalGoal: userPrompt,
            workspaceMetadata: metadata,
            onModelOutput: onModelOutput,
          );
    cancellationToken?.throwIfCancelled();
    final filteredQuestions = _filterProjectQuestions(
      init.openQuestions,
      autonomy: questionAutonomy,
    );
    final project = ProjectDocument(
      id: _newProjectId(userPrompt),
      title: init.title.trim().isEmpty
          ? _titleFromPrompt(userPrompt)
          : init.title,
      originalGoal: userPrompt,
      refinedGoal: init.refinedGoal.trim().isEmpty
          ? userPrompt
          : init.refinedGoal,
      constraints: init.constraints.isEmpty
          ? const ['Stay within the attached workspace.']
          : init.constraints,
      successCriteria: init.successCriteria.isEmpty
          ? const ['Complete the stated project goal.']
          : init.successCriteria,
      backlog: _normaliseBacklog(init.backlog),
      currentTask: null,
      completedTasks: const [],
      failedTasks: const [],
      artifacts: const [],
      knownFacts: _appendFacts(init.knownFacts, filteredQuestions.assumptions),
      openQuestions: filteredQuestions.blocking,
      status: filteredQuestions.blocking.isEmpty
          ? ProjectStatus.active
          : ProjectStatus.waitingForUser,
      phase: ProjectPhase.discovery,
      iterationCount: 0,
      maxIterations: _normaliseOptionalLimit(
        maxIterations,
        fallback: ProjectDocument.defaultMaxIterations,
      ),
      maxFailedTasks: ProjectDocument.defaultMaxFailedTasks,
      activeTaskId: null,
      chatSessionId: chatSessionId,
      completionSummary: '',
      blocker: filteredQuestions.blocking.isEmpty
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.question,
              message: filteredQuestions.blocking.first.question,
              createdAt: now,
            ),
      decisions: const [],
      createdAt: now,
      updatedAt: now,
    );
    await _storage.saveSnapshot(workspace.rootPath, project);
    return project;
  }

  Future<ProjectDocument> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String rawJson,
  }) async {
    final parsed = ProjectDocument.fromJson(TaskJson.parseObject(rawJson));
    final updated = parsed.copyWith(
      schemaVersion: ProjectDocument.currentSchemaVersion,
      id: snapshot.id,
      chatSessionId: snapshot.chatSessionId,
      createdAt: snapshot.createdAt,
      updatedAt: DateTime.now(),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<ProjectRunResult> recoverProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    ProjectTaskSnapshotSink? onTaskUpdated,
  }) async {
    if (snapshot.isTerminal) {
      return ProjectRunResult(
        project: snapshot,
        activeTask: await _loadActiveTask(workspace, snapshot),
      );
    }

    final activeTask = await _loadActiveTask(workspace, snapshot);
    if (!_wasInterrupted(snapshot.status)) {
      return ProjectRunResult(project: snapshot, activeTask: activeTask);
    }

    final now = DateTime.now();
    if (snapshot.activeTaskId == null) {
      final recovered = snapshot.copyWith(
        status: snapshot.openQuestions.isEmpty
            ? ProjectStatus.active
            : ProjectStatus.waitingForUser,
        phase: ProjectPhase.planning,
        updatedAt: now,
      );
      await _storage.saveSnapshot(workspace.rootPath, recovered);
      return ProjectRunResult(project: recovered);
    }

    if (activeTask == null) {
      final blocked = _blockProject(
        snapshot.copyWith(activeTaskId: null, updatedAt: now),
        ProjectBlockerType.error,
        'Recovered an interrupted project, but its active task was missing.',
        now,
      );
      await _storage.saveSnapshot(workspace.rootPath, blocked);
      onTaskUpdated?.call(null);
      return ProjectRunResult(project: blocked);
    }

    final recoveredTask = await _taskService.recoverTask(
      workspace: workspace,
      snapshot: activeTask,
    );
    onTaskUpdated?.call(recoveredTask);
    final taskStatusBlocker = _taskBlocker(recoveredTask);
    var recovered = _syncCurrentTaskFromTask(snapshot, recoveredTask, now);
    recovered = taskStatusBlocker == null
        ? recovered.copyWith(status: ProjectStatus.active, updatedAt: now)
        : _blockProject(
            recovered,
            taskStatusBlocker.$1,
            taskStatusBlocker.$2,
            now,
            taskId: recoveredTask.id,
          );
    await _storage.saveSnapshot(workspace.rootPath, recovered);
    return ProjectRunResult(project: recovered, activeTask: recoveredTask);
  }

  Future<ProjectRunResult> runNextProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    TaskCancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) {
    return runProject(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      maxNewTasks: 1,
      requirePhaseApproval: requirePhaseApproval,
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
      onModelOutput: onModelOutput,
      onTaskUpdated: onTaskUpdated,
      cancellationToken: cancellationToken,
      questionAutonomy: questionAutonomy,
    );
  }

  Future<ProjectRunResult> runProject({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String baseSystemPrompt,
    required int maxNewTasks,
    int? maxIterations,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    TaskCancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    cancellationToken?.throwIfCancelled();
    final recovered = await recoverProject(
      workspace: workspace,
      snapshot: snapshot,
      onTaskUpdated: onTaskUpdated,
    );
    var project = recovered.project;
    var activeTask = recovered.activeTask;
    if (maxIterations != null && project.maxIterations != maxIterations) {
      project = project.copyWith(
        maxIterations: _normaliseOptionalLimit(maxIterations),
        updatedAt: DateTime.now(),
      );
      await _storage.saveSnapshot(workspace.rootPath, project);
    }
    if (project.isTerminal) {
      return ProjectRunResult(project: project, activeTask: activeTask);
    }
    if (project.blocker?.type == ProjectBlockerType.budget) {
      project = project.copyWith(
        status: ProjectStatus.active,
        blocker: null,
        updatedAt: DateTime.now(),
      );
      await _storage.saveSnapshot(workspace.rootPath, project);
    }

    final allowedIterations = maxNewTasks <= 0 ? null : maxNewTasks;
    var runIterations = 0;

    while (!project.isTerminal) {
      cancellationToken?.throwIfCancelled();
      if (project.openQuestions.isNotEmpty) {
        final filtered = _filterProjectQuestions(
          project.openQuestions,
          autonomy: questionAutonomy,
        );
        if (filtered.assumptions.isNotEmpty) {
          project = project.copyWith(
            openQuestions: filtered.blocking,
            knownFacts: _appendFacts(project.knownFacts, filtered.assumptions),
            blocker: filtered.blocking.isEmpty
                ? null
                : ProjectBlocker(
                    type: ProjectBlockerType.question,
                    message: filtered.blocking.first.question,
                    createdAt: DateTime.now(),
                  ),
            status: filtered.blocking.isEmpty
                ? ProjectStatus.active
                : ProjectStatus.waitingForUser,
            updatedAt: DateTime.now(),
          );
          await _storage.saveSnapshot(workspace.rootPath, project);
        }
      }
      if (project.openQuestions.isNotEmpty ||
          project.blocker?.type == ProjectBlockerType.question) {
        project = _waitingForUser(project, DateTime.now());
        await _storage.saveSnapshot(workspace.rootPath, project);
        return ProjectRunResult(project: project, activeTask: activeTask);
      }
      if (project.status == ProjectStatus.blocked &&
          project.blocker?.type != ProjectBlockerType.budget) {
        return ProjectRunResult(project: project, activeTask: activeTask);
      }
      if (project.maxIterations > 0 &&
          project.iterationCount >= project.maxIterations) {
        project = _blockProject(
          project,
          ProjectBlockerType.budget,
          'Project reached the maximum iteration limit of ${project.maxIterations}.',
          DateTime.now(),
        );
        await _storage.saveSnapshot(workspace.rootPath, project);
        return ProjectRunResult(project: project, activeTask: activeTask);
      }
      if (allowedIterations != null && runIterations >= allowedIterations) {
        project = project.copyWith(
          status: ProjectStatus.paused,
          updatedAt: DateTime.now(),
        );
        await _storage.saveSnapshot(workspace.rootPath, project);
        return ProjectRunResult(project: project, activeTask: activeTask);
      }

      final candidate = project.currentTask == null
          ? await _proposeNextTask(
              client: client,
              workspace: workspace,
              project: project,
              baseSystemPrompt: baseSystemPrompt,
              onModelOutput: onModelOutput,
            )
          : project.currentTask!;

      if (candidate == null) {
        project = await _applyCompletionEvaluation(
          client: client,
          project: project,
          baseSystemPrompt: baseSystemPrompt,
          onModelOutput: onModelOutput,
          questionAutonomy: questionAutonomy,
        );
        if (!project.isTerminal &&
            project.status != ProjectStatus.waitingForUser &&
            project.openQuestions.isEmpty) {
          project = _blockProject(
            project,
            ProjectBlockerType.validation,
            'Project is not complete, but no next bounded task could be proposed.',
            DateTime.now(),
          );
        }
        await _storage.saveSnapshot(workspace.rootPath, project);
        return ProjectRunResult(project: project, activeTask: activeTask);
      }

      final validation = _validateProjectTask(candidate, project);
      if (!validation.valid) {
        project = await _handleInvalidProjectTask(
          client: client,
          workspace: workspace,
          project: project,
          task: candidate,
          violations: validation.violations,
          baseSystemPrompt: baseSystemPrompt,
          onModelOutput: onModelOutput,
        );
        if (project.status == ProjectStatus.blocked) {
          await _storage.saveSnapshot(workspace.rootPath, project);
          return ProjectRunResult(project: project, activeTask: activeTask);
        }
        await _storage.saveSnapshot(workspace.rootPath, project);
        continue;
      }

      final execution = await _executeProjectTask(
        client: client,
        workspace: workspace,
        project: project,
        projectTask: candidate,
        baseSystemPrompt: baseSystemPrompt,
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        onTaskUpdated: onTaskUpdated,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
      );
      project = execution.project;
      activeTask = execution.activeTask;
      if (execution.result == null) {
        return ProjectRunResult(project: project, activeTask: activeTask);
      }

      final now = DateTime.now();
      project = project.copyWith(
        status: ProjectStatus.reviewingTask,
        phase: ProjectPhase.verification,
        updatedAt: now,
      );
      await _storage.saveSnapshot(workspace.rootPath, project);

      final evaluation = _evaluateTaskResult(
        project.currentTask ?? candidate,
        execution.result!,
        project,
      );
      project = _updateProjectState(
        project,
        evaluation,
        now,
        questionAutonomy: questionAutonomy,
      );
      project = await _applyCompletionEvaluation(
        client: client,
        project: project,
        baseSystemPrompt: baseSystemPrompt,
        onModelOutput: onModelOutput,
        questionAutonomy: questionAutonomy,
      );
      project = project.copyWith(
        iterationCount: project.iterationCount + 1,
        updatedAt: DateTime.now(),
      );
      await _storage.saveSnapshot(workspace.rootPath, project);
      runIterations++;
      if (project.status == ProjectStatus.completed ||
          project.status == ProjectStatus.failed ||
          project.status == ProjectStatus.waitingForUser ||
          project.status == ProjectStatus.blocked) {
        return ProjectRunResult(project: project, activeTask: activeTask);
      }
    }

    return ProjectRunResult(project: project, activeTask: activeTask);
  }

  Future<ProjectDocument> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String answer,
  }) async {
    final question = snapshot.pendingQuestion;
    final trimmed = answer.trim();
    if (question == null || trimmed.isEmpty) return snapshot;
    final remainingQuestions = snapshot.openQuestions
        .where((item) => item.id != question.id)
        .toList();
    final updated = snapshot.copyWith(
      status: ProjectStatus.active,
      openQuestions: remainingQuestions,
      blocker: null,
      knownFacts: [
        ...snapshot.knownFacts,
        'User answered: ${question.question}\nAnswer: $trimmed',
      ],
      updatedAt: DateTime.now(),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<ProjectDocument> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return snapshot;
    if (snapshot.pendingQuestion != null) {
      return answerOpenQuestion(
        workspace: workspace,
        snapshot: snapshot,
        answer: trimmed,
      );
    }
    final updated = snapshot.copyWith(
      status: snapshot.isTerminal ? snapshot.status : ProjectStatus.active,
      blocker: snapshot.blocker?.type == ProjectBlockerType.question
          ? null
          : snapshot.blocker,
      knownFacts: [
        ...snapshot.knownFacts,
        'User added project context: $trimmed',
      ],
      updatedAt: DateTime.now(),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<ProjectDocument> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final updated = snapshot.copyWith(
      status: ProjectStatus.paused,
      updatedAt: DateTime.now(),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<ProjectDocument> approveNextProjectTask({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final task = snapshot.currentTask;
    if (task == null) return snapshot;
    final updated = snapshot.copyWith(
      currentTask: task.copyWith(
        status: ProjectTaskStatus.approved,
        updatedAt: DateTime.now(),
      ),
      status: ProjectStatus.active,
      blocker: null,
      updatedAt: DateTime.now(),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<ProjectDocument> cancelProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final now = DateTime.now();
    final updated = snapshot.copyWith(
      status: ProjectStatus.cancelled,
      activeTaskId: null,
      currentTask: snapshot.currentTask?.copyWith(
        status: ProjectTaskStatus.cancelled,
        updatedAt: now,
      ),
      openQuestions: const [],
      blocker: null,
      completedAt: now,
      updatedAt: now,
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<ProjectDocument> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) {
    return cancelProject(workspace: workspace, snapshot: snapshot);
  }

  Future<TaskDocument?> _loadActiveTask(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) {
    final activeTaskId = project.activeTaskId;
    if (activeTaskId == null) return Future.value();
    return _taskService.loadTask(
      workspace,
      activeTaskId,
      chatSessionId: project.chatSessionId,
      projectId: project.id,
    );
  }

  Future<Map<String, dynamic>> _collectWorkspaceMetadata(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async {
    final root = Directory(workspace.rootPath);
    final rootFiles = <String>[];
    if (await root.exists()) {
      await for (final entity in root.list(followLinks: false)) {
        rootFiles.add(path.basename(entity.path));
        if (rootFiles.length >= 80) break;
      }
    }
    rootFiles.sort();
    final taskIds = (await _taskService.listTasks(
      workspace,
      chatSessionId: chatSessionId,
    )).map((task) => task.id).toList();
    return {
      'workspaceName': workspace.displayName,
      'rootFiles': rootFiles,
      'gitAvailable': rootFiles.contains('.git'),
      'commandExecutionApproved': workspace.commandExecutionApproved,
      'existingTaskIds': taskIds,
    };
  }

  Future<ProjectTask?> _proposeNextTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required String baseSystemPrompt,
    TaskModelOutputSink? onModelOutput,
  }) async {
    final metadata = await _collectWorkspaceMetadata(
      workspace,
      chatSessionId: project.chatSessionId,
    );
    final proposed = await _modelCalls.proposeNextTask(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      project: project,
      workspaceMetadata: metadata,
      forbiddenFingerprints: _knownFingerprints(project),
      onModelOutput: onModelOutput,
    );
    return proposed ?? project.backlog.first;
  }

  Future<ProjectDocument> _handleInvalidProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required ProjectTask task,
    required List<String> violations,
    required String baseSystemPrompt,
    TaskModelOutputSink? onModelOutput,
  }) async {
    final duplicateViolation = violations.any(
      (violation) =>
          violation.toLowerCase().contains('duplicate') ||
          violation.toLowerCase().contains('repeat'),
    );
    if (duplicateViolation) {
      final now = DateTime.now();
      final rejected = task.copyWith(
        status: ProjectTaskStatus.rejected,
        rejectionReason: violations.join('\n'),
        updatedAt: now,
      );
      return _blockProject(
        project.copyWith(
          failedTasks: [...project.failedTasks, rejected],
          backlog: project.backlog.where((item) => item.id != task.id).toList(),
          decisions: [
            ...project.decisions,
            _decision(
              ProjectDecisionType.rejectTask,
              'Rejected repeated project task: ${task.title}',
              violations.join('\n'),
              task: rejected,
            ),
          ],
          updatedAt: now,
        ),
        ProjectBlockerType.duplicateTask,
        'Project task repeated previous work: ${violations.join('; ')}',
        now,
      );
    }

    final split = await _modelCalls.splitTask(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      project: project,
      oversizedTask: task,
      violations: violations,
      onModelOutput: onModelOutput,
    );
    final known = _knownFingerprints(project)..add(task.fingerprint);
    final splitTasks =
        _normaliseBacklog(
              split.isEmpty ? _deterministicSplit(project, task) : split,
            )
            .where((item) => !known.contains(item.fingerprint))
            .where((item) => _validateProjectTask(item, project).valid)
            .take(5)
            .toList();

    final now = DateTime.now();
    final rejected = task.copyWith(
      status: splitTasks.isEmpty
          ? ProjectTaskStatus.rejected
          : ProjectTaskStatus.split,
      rejectionReason: violations.join('\n'),
      updatedAt: now,
    );
    if (splitTasks.isEmpty) {
      return _blockProject(
        project.copyWith(
          failedTasks: [...project.failedTasks, rejected],
          backlog: project.backlog.where((item) => item.id != task.id).toList(),
          decisions: [
            ...project.decisions,
            _decision(
              ProjectDecisionType.rejectTask,
              'Rejected oversized project task: ${task.title}',
              violations.join('\n'),
              task: rejected,
            ),
          ],
          updatedAt: now,
        ),
        ProjectBlockerType.validation,
        'Project task was too broad and could not be split safely: ${violations.join('; ')}',
        now,
      );
    }

    return project.copyWith(
      backlog: [
        ...splitTasks,
        ...project.backlog.where((item) => item.id != task.id),
      ],
      failedTasks: [...project.failedTasks, rejected],
      status: ProjectStatus.active,
      phase: ProjectPhase.planning,
      decisions: [
        ...project.decisions,
        _decision(
          ProjectDecisionType.splitTask,
          'Split oversized project task into ${splitTasks.length} smaller task(s).',
          violations.join('\n'),
          task: rejected,
        ),
      ],
      updatedAt: now,
    );
  }

  Future<_ProjectTaskExecution> _executeProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required ProjectTask projectTask,
    required String baseSystemPrompt,
    required bool requirePhaseApproval,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    TaskCancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    cancellationToken?.throwIfCancelled();
    final now = DateTime.now();
    final runningProjectTask = projectTask.copyWith(
      status: ProjectTaskStatus.running,
      updatedAt: now,
    );
    var workingProject = project.copyWith(
      status: ProjectStatus.runningTask,
      phase: ProjectPhase.execution,
      currentTask: runningProjectTask,
      backlog: project.backlog
          .where((task) => task.id != projectTask.id)
          .toList(),
      blocker: null,
      decisions: [
        ...project.decisions,
        _decision(
          ProjectDecisionType.createTask,
          'Selected next bounded project task: ${projectTask.title}',
          '',
          task: projectTask,
        ),
      ],
      updatedAt: now,
    );
    await _storage.saveSnapshot(workspace.rootPath, workingProject);

    final existingTask = workingProject.activeTaskId == null
        ? null
        : await _loadActiveTask(workspace, workingProject);
    var activeTask =
        existingTask ??
        await _taskService.createTask(
          client: client,
          workspace: workspace,
          userPrompt: _taskPrompt(workingProject, projectTask),
          selectedMode: ExecutionMode.task,
          baseSystemPrompt: _buildTaskSystemPrompt(
            baseSystemPrompt,
            workingProject,
            null,
          ),
          chatSessionId: workingProject.chatSessionId,
          projectId: workingProject.id,
          planningContext: _planningContext(workingProject, projectTask),
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
    final taskDocumentId = activeTask.id;
    workingProject = workingProject.copyWith(
      activeTaskId: taskDocumentId,
      currentTask: runningProjectTask.copyWith(
        taskDocumentId: taskDocumentId,
        updatedAt: DateTime.now(),
      ),
      updatedAt: DateTime.now(),
    );
    await _storage.saveSnapshot(workspace.rootPath, workingProject);
    onTaskUpdated?.call(activeTask);

    while (activeTask.nextRunnableStep != null && !activeTask.isTerminal) {
      cancellationToken?.throwIfCancelled();
      activeTask = await _taskService.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: activeTask,
        baseSystemPrompt: _buildTaskSystemPrompt(
          baseSystemPrompt,
          workingProject,
          activeTask,
        ),
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
      );
      onTaskUpdated?.call(activeTask);
      workingProject = _syncCurrentTaskFromTask(
        workingProject,
        activeTask,
        DateTime.now(),
      );
      await _storage.saveSnapshot(workspace.rootPath, workingProject);

      if (cancellationToken?.isCancelled == true) {
        final paused = workingProject.copyWith(
          status: ProjectStatus.paused,
          updatedAt: DateTime.now(),
        );
        await _storage.saveSnapshot(workspace.rootPath, paused);
        return _ProjectTaskExecution(project: paused, activeTask: activeTask);
      }

      final blocker = _taskBlocker(activeTask);
      if (blocker != null) {
        final blocked = _blockProject(
          workingProject,
          blocker.$1,
          blocker.$2,
          DateTime.now(),
          taskId: activeTask.id,
        ).copyWith(status: ProjectStatus.waitingForUser);
        await _storage.saveSnapshot(workspace.rootPath, blocked);
        return _ProjectTaskExecution(project: blocked, activeTask: activeTask);
      }
    }

    if (!activeTask.isTerminal && activeTask.nextRunnableStep == null) {
      activeTask = await _taskService.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: activeTask,
        baseSystemPrompt: _buildTaskSystemPrompt(
          baseSystemPrompt,
          workingProject,
          activeTask,
        ),
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
      );
      onTaskUpdated?.call(activeTask);
    }

    final result = _taskResultFromTask(workingProject.currentTask!, activeTask);
    return _ProjectTaskExecution(
      project: _syncCurrentTaskFromTask(
        workingProject,
        activeTask,
        DateTime.now(),
      ),
      activeTask: activeTask,
      result: result,
    );
  }

  ProjectEvaluation _evaluateTaskResult(
    ProjectTask projectTask,
    TaskResult result,
    ProjectDocument project,
  ) {
    final accepted = result.status == TaskStatus.completed;
    final completedCriteria = accepted
        ? projectTask.relevantSuccessCriteria
        : const <String>[];
    return ProjectEvaluation(
      projectTaskId: projectTask.id,
      taskAccepted: accepted,
      projectComplete: false,
      summary: result.summary,
      completedCriteria: completedCriteria,
      remainingCriteria: _remainingCriteria(
        project,
        additionalCompletedCriteria: completedCriteria,
      ),
      newKnownFacts: [
        if (result.summary.trim().isNotEmpty) result.summary.trim(),
        if (result.memoryUpdate.trim().isNotEmpty) result.memoryUpdate.trim(),
      ],
      artifacts: result.artifacts,
      backlogAdditions: const [],
      openQuestions: result.userQuestion?.trim().isNotEmpty == true
          ? [
              PendingProjectQuestion(
                id: 'question_${uuid.v7()}',
                question: result.userQuestion!.trim(),
                createdAt: DateTime.now(),
              ),
            ]
          : const [],
      failureReason: accepted ? null : result.error ?? result.summary,
    );
  }

  ProjectDocument _updateProjectState(
    ProjectDocument project,
    ProjectEvaluation evaluation,
    DateTime now, {
    required QuestionAutonomy questionAutonomy,
  }) {
    final task = project.currentTask;
    if (task == null) return project;
    final filteredQuestions = _filterProjectQuestions(
      evaluation.openQuestions,
      autonomy: questionAutonomy,
    );
    if (!evaluation.taskAccepted) {
      final failedTask = task.copyWith(
        status: ProjectTaskStatus.failed,
        rejectionReason: evaluation.failureReason,
        updatedAt: now,
      );
      final failedTasks = [...project.failedTasks, failedTask];
      return project.copyWith(
        currentTask: null,
        activeTaskId: null,
        failedTasks: failedTasks,
        openQuestions: filteredQuestions.blocking,
        status: failedTasks.length >= project.maxFailedTasks
            ? ProjectStatus.failed
            : ProjectStatus.active,
        phase: ProjectPhase.execution,
        blocker: failedTasks.length >= project.maxFailedTasks
            ? ProjectBlocker(
                type: ProjectBlockerType.maxFailures,
                message:
                    'Project reached the maximum failed task limit of ${project.maxFailedTasks}.',
                createdAt: now,
              )
            : null,
        knownFacts: _appendFacts(project.knownFacts, [
          ...evaluation.newKnownFacts,
          ...filteredQuestions.assumptions,
        ]),
        decisions: [
          ...project.decisions,
          _decision(
            ProjectDecisionType.evaluateTask,
            'Project task failed: ${task.title}',
            evaluation.failureReason ?? '',
            task: failedTask,
          ),
        ],
        updatedAt: now,
      );
    }

    final completedTask = task.copyWith(
      status: ProjectTaskStatus.completed,
      updatedAt: now,
    );
    return project.copyWith(
      currentTask: null,
      activeTaskId: null,
      completedTasks: [...project.completedTasks, completedTask],
      artifacts: _mergeArtifacts(project.artifacts, evaluation.artifacts),
      knownFacts: _appendFacts(project.knownFacts, [
        ...evaluation.newKnownFacts,
        ...filteredQuestions.assumptions,
      ]),
      openQuestions: filteredQuestions.blocking,
      backlog: [...evaluation.backlogAdditions, ...project.backlog],
      status: filteredQuestions.blocking.isEmpty
          ? ProjectStatus.active
          : ProjectStatus.waitingForUser,
      phase: ProjectPhase.execution,
      blocker: filteredQuestions.blocking.isEmpty
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.question,
              message: filteredQuestions.blocking.first.question,
              createdAt: now,
            ),
      decisions: [
        ...project.decisions,
        _decision(
          ProjectDecisionType.evaluateTask,
          'Accepted completed project task: ${task.title}',
          evaluation.summary,
          task: completedTask,
        ),
      ],
      updatedAt: now,
    );
  }

  Future<ProjectDocument> _applyCompletionEvaluation({
    required ChatClient client,
    required ProjectDocument project,
    required String baseSystemPrompt,
    TaskModelOutputSink? onModelOutput,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    if (project.isTerminal ||
        project.openQuestions.isNotEmpty ||
        project.failedTasks.length >= project.maxFailedTasks) {
      return project;
    }
    final remainingByState = _remainingCriteria(project);
    final assessment = await _modelCalls.evaluateCompletion(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      project: project,
      onModelOutput: onModelOutput,
    );
    final remaining = {
      ...remainingByState,
      ...assessment.remainingCriteria,
    }.where((item) => item.trim().isNotEmpty).toList();
    final now = DateTime.now();
    if (assessment.openQuestions.isNotEmpty) {
      final filtered = _filterProjectQuestions(
        assessment.openQuestions,
        autonomy: questionAutonomy,
      );
      if (filtered.blocking.isEmpty) {
        return project.copyWith(
          status: ProjectStatus.active,
          knownFacts: _appendFacts(project.knownFacts, filtered.assumptions),
          phase: project.backlog.isEmpty
              ? ProjectPhase.planning
              : ProjectPhase.execution,
          blocker: null,
          updatedAt: now,
        );
      }
      return project.copyWith(
        status: ProjectStatus.waitingForUser,
        openQuestions: filtered.blocking,
        knownFacts: _appendFacts(project.knownFacts, filtered.assumptions),
        blocker: ProjectBlocker(
          type: ProjectBlockerType.question,
          message: filtered.blocking.first.question,
          createdAt: now,
        ),
        updatedAt: now,
      );
    }
    if (assessment.complete && remaining.isEmpty) {
      return project.copyWith(
        status: ProjectStatus.completed,
        phase: ProjectPhase.finalization,
        completionSummary: assessment.finalSummary.trim().isEmpty
            ? 'Project completed.'
            : assessment.finalSummary.trim(),
        completedAt: now,
        blocker: null,
        updatedAt: now,
      );
    }
    return project.copyWith(
      status: ProjectStatus.active,
      phase: project.backlog.isEmpty
          ? ProjectPhase.planning
          : ProjectPhase.execution,
      updatedAt: now,
    );
  }

  _ProjectTaskValidation _validateProjectTask(
    ProjectTask task,
    ProjectDocument project,
  ) {
    final violations = <String>[];
    if (task.objective.trim().isEmpty) {
      violations.add('Task objective is empty.');
    }
    if (task.doneCriteria.isEmpty) {
      violations.add('Task has no done criteria.');
    }
    if (task.outOfScope.isEmpty) {
      violations.add('Task has no out-of-scope boundaries.');
    }
    if (_knownFingerprints(
      project,
      excludingTaskId: task.id,
    ).contains(task.fingerprint)) {
      violations.add(
        'Task duplicates previous, current, failed, or queued work.',
      );
    }
    if (project.decisions.any(
      (decision) =>
          decision.taskPrompt?.trim().isNotEmpty == true &&
          _normalise(decision.taskPrompt!) == _normalise(task.objective),
    )) {
      violations.add('Task repeats a previous project task prompt.');
    }
    if (_normalise(task.objective) == _normalise(project.refinedGoal) ||
        _normalise(task.objective) == _normalise(project.originalGoal)) {
      violations.add('Task objective matches the whole project goal.');
    }
    if (_looksOversized(task.objective)) {
      violations.add('Task objective is too broad for a project task.');
    }
    if (task.relevantSuccessCriteria.length > 3) {
      violations.add('Task covers too many success criteria.');
    }
    if (project.successCriteria.length > 1 &&
        task.relevantSuccessCriteria.length >= project.successCriteria.length) {
      violations.add('Task covers the entire project success criteria set.');
    }
    if (task.doneCriteria.length > 5) {
      violations.add('Task has too many done criteria.');
    }
    if (task.objective.length > 700) {
      violations.add('Task objective is too long.');
    }
    return _ProjectTaskValidation(violations.isEmpty, violations);
  }

  bool _looksOversized(String value) {
    final text = _normalise(value);
    return text.contains('entire project') ||
        text.contains('whole project') ||
        text.contains('complete the project') ||
        text.contains('finish the project') ||
        text.contains('build the app') ||
        text.contains('implement all') ||
        text.contains('end to end') ||
        text.contains('end-to-end');
  }

  List<ProjectTask> _deterministicSplit(
    ProjectDocument project,
    ProjectTask task,
  ) {
    final criteria = task.relevantSuccessCriteria.isEmpty
        ? project.successCriteria
        : task.relevantSuccessCriteria;
    if (criteria.isEmpty) return const [];
    final now = DateTime.now();
    return criteria.take(5).map((criterion) {
      final objective = 'Make focused progress on: $criterion';
      return ProjectTask(
        id: 'project_task_${uuid.v7()}',
        title: _titleFromPrompt(criterion),
        objective: objective,
        relevantSuccessCriteria: [criterion],
        doneCriteria: [
          'Concrete progress for "$criterion" is completed and summarized.',
        ],
        outOfScope: [
          'Do not complete unrelated success criteria.',
          'Do not expand this into the whole project.',
        ],
        context: [task.objective],
        expectedArtifacts: const [],
        status: ProjectTaskStatus.queued,
        taskDocumentId: null,
        fingerprint: projectTaskFingerprint(objective, [criterion]),
        rejectionReason: null,
        createdAt: now,
        updatedAt: now,
      );
    }).toList();
  }

  TaskPlanningContext _planningContext(
    ProjectDocument project,
    ProjectTask task,
  ) {
    return TaskPlanningContext(
      projectGoal: project.refinedGoal,
      projectTaskObjective: task.objective,
      knownFacts: [...project.knownFacts, ...task.context],
      doneCriteria: task.doneCriteria,
      outOfScope: task.outOfScope,
      expectedArtifacts: task.expectedArtifacts
          .map(
            (artifact) => TaskArtifact(
              path: artifact.path,
              description: artifact.description,
            ),
          )
          .toList(),
      maxSteps: 3,
    );
  }

  TaskResult _taskResultFromTask(ProjectTask projectTask, TaskDocument task) {
    final latestRun = task.runs.isEmpty ? null : task.runs.last;
    final artifacts = <ProjectArtifact>[
      for (final run in task.runs)
        for (final artifact in run.artifacts)
          ProjectArtifact(
            id: 'artifact_${uuid.v7()}',
            projectTaskId: projectTask.id,
            taskDocumentId: task.id,
            path: artifact.path,
            description: artifact.description ?? '',
            kind: 'file',
            createdAt: artifact.createdAt ?? DateTime.now(),
          ),
    ];
    return TaskResult(
      taskDocumentId: task.id,
      status: task.status,
      summary: latestRun?.summary ?? task.memorySummary,
      memoryUpdate: latestRun?.memoryUpdate ?? task.memorySummary,
      artifacts: artifacts,
      toolCallCount: task.runs.fold<int>(
        0,
        (sum, run) => sum + run.toolCalls.length,
      ),
      userQuestion: task.pendingQuestion?.question,
      error: latestRun?.error,
    );
  }

  (ProjectBlockerType, String)? _taskBlocker(TaskDocument task) {
    if (task.pendingApproval != null) {
      return (ProjectBlockerType.taskApproval, task.pendingApproval!.reason);
    }
    if (task.pendingQuestion != null) {
      return (ProjectBlockerType.taskBlocked, task.pendingQuestion!.question);
    }
    if (task.status == TaskStatus.blocked) {
      return (
        ProjectBlockerType.taskBlocked,
        'Task `${task.title}` is blocked.',
      );
    }
    return null;
  }

  ProjectDocument _syncCurrentTaskFromTask(
    ProjectDocument project,
    TaskDocument task,
    DateTime now,
  ) {
    final current = project.currentTask;
    if (current == null) return project;
    return project.copyWith(
      currentTask: current.copyWith(
        taskDocumentId: task.id,
        status: switch (task.status) {
          TaskStatus.completed => ProjectTaskStatus.completed,
          TaskStatus.failed => ProjectTaskStatus.failed,
          TaskStatus.cancelled => ProjectTaskStatus.cancelled,
          _ => ProjectTaskStatus.running,
        },
        updatedAt: now,
      ),
      activeTaskId: task.id,
      updatedAt: now,
    );
  }

  ProjectDocument _waitingForUser(ProjectDocument project, DateTime now) {
    return project.copyWith(
      status: ProjectStatus.waitingForUser,
      blocker:
          project.blocker ??
          (project.openQuestions.isEmpty
              ? null
              : ProjectBlocker(
                  type: ProjectBlockerType.question,
                  message: project.openQuestions.first.question,
                  createdAt: now,
                )),
      updatedAt: now,
    );
  }

  _FilteredProjectQuestions _filterProjectQuestions(
    List<PendingProjectQuestion> questions, {
    required QuestionAutonomy autonomy,
  }) {
    final blocking = <PendingProjectQuestion>[];
    final assumptions = <String>[];
    for (final question in questions) {
      final decision = _questionPolicy.decide(
        question: AgentQuestion.fromText(question.question),
        autonomy: autonomy,
      );
      if (decision.shouldBlock) {
        blocking.add(question);
      } else {
        assumptions.add(decision.assumption);
      }
    }
    return _FilteredProjectQuestions(
      blocking: blocking,
      assumptions: assumptions,
    );
  }

  ProjectDocument _blockProject(
    ProjectDocument project,
    ProjectBlockerType type,
    String message,
    DateTime now, {
    String? taskId,
  }) {
    return project.copyWith(
      status: ProjectStatus.blocked,
      blocker: ProjectBlocker(
        type: type,
        message: message,
        taskId: taskId,
        createdAt: now,
      ),
      updatedAt: now,
    );
  }

  List<String> _remainingCriteria(
    ProjectDocument project, {
    List<String> additionalCompletedCriteria = const [],
  }) {
    final completed = {
      for (final task in project.completedTasks)
        for (final criterion in task.relevantSuccessCriteria)
          _normalise(criterion): true,
      for (final criterion in additionalCompletedCriteria)
        _normalise(criterion): true,
    };
    return project.successCriteria
        .where((criterion) => !completed.containsKey(_normalise(criterion)))
        .toList();
  }

  List<ProjectArtifact> _mergeArtifacts(
    List<ProjectArtifact> current,
    List<ProjectArtifact> additions,
  ) {
    final byPath = <String, ProjectArtifact>{
      for (final artifact in current) artifact.path: artifact,
    };
    for (final artifact in additions) {
      byPath[artifact.path] = artifact;
    }
    return byPath.values.toList();
  }

  List<String> _appendFacts(List<String> current, List<String> additions) {
    final seen = current.map(_normalise).toSet();
    final next = [
      ...current,
      for (final addition in additions)
        if (addition.trim().isNotEmpty && seen.add(_normalise(addition)))
          _cap(addition.trim(), 1200),
    ];
    final joined = next.join('\n\n');
    if (joined.length <= 18000) return next;
    return joined.substring(0, 18000).split('\n\n');
  }

  Set<String> _knownFingerprints(
    ProjectDocument project, {
    String? excludingTaskId,
  }) {
    return {
      for (final task in project.backlog)
        if (task.id != excludingTaskId) task.fingerprint,
      if (project.currentTask != null &&
          project.currentTask!.id != excludingTaskId)
        project.currentTask!.fingerprint,
      for (final task in project.completedTasks)
        if (task.id != excludingTaskId) task.fingerprint,
      for (final task in project.failedTasks)
        if (task.id != excludingTaskId) task.fingerprint,
      for (final decision in project.decisions)
        if (decision.taskPrompt?.trim().isNotEmpty == true)
          projectTaskFingerprint(decision.taskPrompt!, const []),
    };
  }

  List<ProjectTask> _normaliseBacklog(List<ProjectTask> tasks) {
    final seen = <String>{};
    return [
      for (final task in tasks)
        if (task.objective.trim().isNotEmpty && seen.add(task.fingerprint))
          task.copyWith(
            status: task.status == ProjectTaskStatus.running
                ? ProjectTaskStatus.queued
                : task.status,
            updatedAt: DateTime.now(),
          ),
    ];
  }

  ProjectInitialisation _fallbackInitialisation(String originalGoal) {
    return ProjectInitialisation(
      title: _titleFromPrompt(originalGoal),
      refinedGoal: originalGoal,
      successCriteria: const ['Complete the stated project goal.'],
      constraints: const ['Stay within the attached workspace.'],
      knownFacts: const [],
      openQuestions: const [],
      backlog: const [],
    );
  }

  ProjectDecisionRecord _decision(
    ProjectDecisionType type,
    String summary,
    String memoryUpdate, {
    ProjectTask? task,
    String? error,
  }) {
    return ProjectDecisionRecord(
      id: 'decision_${uuid.v7()}',
      decision: type,
      summary: summary,
      memoryUpdate: memoryUpdate,
      taskId: task?.taskDocumentId ?? task?.id,
      taskTitle: task?.title,
      taskPrompt: task?.objective,
      error: error,
      createdAt: DateTime.now(),
    );
  }

  String _taskPrompt(ProjectDocument project, ProjectTask task) {
    final buffer = StringBuffer()
      ..writeln('Project goal:')
      ..writeln(project.refinedGoal)
      ..writeln()
      ..writeln('Selected bounded Project task:')
      ..writeln(task.objective)
      ..writeln()
      ..writeln('Done criteria:')
      ..writeln(_bulletList(task.doneCriteria))
      ..writeln()
      ..writeln('Out of scope:')
      ..writeln(_bulletList(task.outOfScope))
      ..writeln()
      ..writeln('Relevant project success criteria:')
      ..writeln(_bulletList(task.relevantSuccessCriteria))
      ..writeln()
      ..writeln('Known project facts:')
      ..writeln(_bulletList([...project.knownFacts, ...task.context]));
    return buffer.toString().trim();
  }

  String _buildTaskSystemPrompt(
    String baseSystemPrompt,
    ProjectDocument project,
    TaskDocument? task,
  ) {
    final activeTaskLine = task == null
        ? ''
        : '\nActive task document: ${task.title} (${task.id})';
    return '''
$baseSystemPrompt

You are executing one bounded task inside a persistent Project orchestrator.
Project id: ${project.id}
Project goal: ${project.refinedGoal}
Complete only the active bounded Project task. Do not expand into the full project. The application will select the next task after this one is evaluated.$activeTaskLine
Do not block on prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable default, note the assumption, and continue.
Ask the user only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
'''
        .trim();
  }

  String _bulletList(List<String> items) {
    if (items.isEmpty) return '- None specified.';
    return items.map((item) => '- $item').join('\n');
  }

  bool _wasInterrupted(ProjectStatus status) {
    return status == ProjectStatus.initializing ||
        status == ProjectStatus.runningTask ||
        status == ProjectStatus.reviewingTask;
  }

  String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _cap(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }

  String _newProjectId(String prompt) {
    final slug = _titleFromPrompt(prompt)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = slug.isEmpty ? 'project' : slug;
    return 'project_${prefix.length > 32 ? prefix.substring(0, 32) : prefix}_${uuid.v7().substring(0, 8)}';
  }

  String _titleFromPrompt(String prompt) {
    final singleLine = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.isEmpty) return 'Untitled project';
    return singleLine.length <= 60
        ? singleLine
        : '${singleLine.substring(0, 57)}...';
  }

  int _normaliseOptionalLimit(int? value, {int fallback = 0}) {
    final resolved = value ?? fallback;
    return resolved < 0 ? 0 : resolved;
  }
}

class _ProjectTaskValidation {
  final bool valid;
  final List<String> violations;

  const _ProjectTaskValidation(this.valid, this.violations);
}

class _ProjectTaskExecution {
  final ProjectDocument project;
  final TaskDocument? activeTask;
  final TaskResult? result;

  const _ProjectTaskExecution({
    required this.project,
    this.activeTask,
    this.result,
  });
}

class _FilteredProjectQuestions {
  final List<PendingProjectQuestion> blocking;
  final List<String> assumptions;

  const _FilteredProjectQuestions({
    required this.blocking,
    required this.assumptions,
  });
}
