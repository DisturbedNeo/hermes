import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_storage_service.dart';
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
  }) : _taskService = taskService,
       _storage = storage ?? ProjectStorageService();

  final TaskService _taskService;
  final ProjectStorageService _storage;
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
  }) async {
    final now = DateTime.now();
    final project = ProjectDocument(
      id: _newProjectId(userPrompt),
      title: _titleFromPrompt(userPrompt),
      originalPrompt: userPrompt,
      goal: userPrompt,
      constraints: const ['Stay within the attached workspace.'],
      successCriteria: const ['Complete the stated project goal.'],
      status: ProjectStatus.paused,
      activeTaskId: null,
      memorySummary: '',
      completionSummary: '',
      tasks: const [],
      decisions: const [],
      chatSessionId: chatSessionId,
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
    final now = DateTime.now();
    final updated = parsed.copyWith(
      schemaVersion: ProjectDocument.currentSchemaVersion,
      id: snapshot.id,
      chatSessionId: snapshot.chatSessionId,
      createdAt: snapshot.createdAt,
      updatedAt: now,
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<ProjectRunResult> recoverProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    ProjectTaskSnapshotSink? onTaskUpdated,
  }) async {
    if (snapshot.status != ProjectStatus.running) {
      return ProjectRunResult(
        project: snapshot,
        activeTask: await _loadActiveTask(workspace, snapshot),
      );
    }

    final now = DateTime.now();
    var project = snapshot.copyWith(
      status: ProjectStatus.paused,
      updatedAt: now,
    );
    final task = await _loadActiveTask(workspace, project);
    if (task == null) {
      project = project.copyWith(
        activeTaskId: null,
        blocker: ProjectBlocker(
          type: ProjectBlockerType.error,
          message:
              'Recovered an interrupted project, but its active task was missing.',
          createdAt: now,
        ),
        status: ProjectStatus.blocked,
        updatedAt: now,
      );
      await _storage.saveSnapshot(workspace.rootPath, project);
      onTaskUpdated?.call(null);
      return ProjectRunResult(project: project);
    }

    final recoveredTask = await _taskService.recoverTask(
      workspace: workspace,
      snapshot: task,
    );
    onTaskUpdated?.call(recoveredTask);
    project = _syncTaskRef(project, recoveredTask, now);
    project = _projectStatusFromTask(project, recoveredTask, now);
    await _storage.saveSnapshot(workspace.rootPath, project);
    return ProjectRunResult(project: project, activeTask: recoveredTask);
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
    );
  }

  Future<ProjectRunResult> runProject({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String baseSystemPrompt,
    required int maxNewTasks,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    TaskCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    var recovered = await recoverProject(
      workspace: workspace,
      snapshot: snapshot,
      onTaskUpdated: onTaskUpdated,
    );
    var project = recovered.project;
    var activeTask = recovered.activeTask;
    if (project.isTerminal ||
        project.pendingQuestion != null ||
        project.blocker?.type == ProjectBlockerType.question) {
      return recovered;
    }

    if (project.blocker?.type == ProjectBlockerType.budget) {
      project = project.copyWith(
        status: ProjectStatus.paused,
        blocker: null,
        updatedAt: DateTime.now(),
      );
      await _storage.saveSnapshot(workspace.rootPath, project);
    }

    final allowedNewTasks = maxNewTasks.clamp(1, 25).toInt();
    var newTasksCreated = 0;

    while (true) {
      cancellationToken?.throwIfCancelled();
      if (project.isTerminal ||
          project.pendingQuestion != null ||
          project.blocker != null && project.status == ProjectStatus.blocked) {
        return ProjectRunResult(project: project, activeTask: activeTask);
      }

      final activeTaskId = project.activeTaskId;
      if (activeTaskId != null) {
        activeTask = await _loadActiveTask(workspace, project);
        if (activeTask == null) {
          project = _blockProject(
            project,
            ProjectBlockerType.error,
            'The active task could not be found: $activeTaskId',
            DateTime.now(),
            taskId: activeTaskId,
          );
          await _storage.saveSnapshot(workspace.rootPath, project);
          onTaskUpdated?.call(null);
          return ProjectRunResult(project: project);
        }

        while (activeTask!.nextRunnableStep != null && !activeTask.isTerminal) {
          cancellationToken?.throwIfCancelled();
          activeTask = await _taskService.runNextStep(
            client: client,
            workspace: workspace,
            snapshot: activeTask,
            baseSystemPrompt: _buildTaskSystemPrompt(
              baseSystemPrompt,
              project,
              activeTask,
            ),
            requirePhaseApproval: requirePhaseApproval,
            compactionSettings: compactionSettings,
            contextLimitTokens: contextLimitTokens,
            onCompactionStatus: onCompactionStatus,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          );
          onTaskUpdated?.call(activeTask);
          project = _syncTaskRef(project, activeTask, DateTime.now());
          await _storage.saveSnapshot(workspace.rootPath, project);

          if (cancellationToken?.isCancelled == true) {
            project = project.copyWith(
              status: ProjectStatus.paused,
              blocker: null,
              updatedAt: DateTime.now(),
            );
            await _storage.saveSnapshot(workspace.rootPath, project);
            return ProjectRunResult(project: project, activeTask: activeTask);
          }

          final taskBlocker = _taskBlocker(activeTask);
          if (taskBlocker != null) {
            project = _blockProject(
              project,
              taskBlocker.$1,
              taskBlocker.$2,
              DateTime.now(),
              taskId: activeTask.id,
            );
            await _storage.saveSnapshot(workspace.rootPath, project);
            return ProjectRunResult(project: project, activeTask: activeTask);
          }
        }

        if (activeTask.isTerminal) {
          project = _syncTaskRef(project, activeTask, DateTime.now());
          if (activeTask.status == TaskStatus.completed) {
            project = project.copyWith(
              activeTaskId: null,
              status: ProjectStatus.paused,
              blocker: null,
              memorySummary: _appendMemory(
                project.memorySummary,
                _taskMemorySummary(activeTask),
              ),
              updatedAt: DateTime.now(),
            );
            await _storage.saveSnapshot(workspace.rootPath, project);
            onTaskUpdated?.call(null);
            activeTask = null;
            continue;
          }

          project = _blockProject(
            project,
            activeTask.status == TaskStatus.failed
                ? ProjectBlockerType.taskFailed
                : ProjectBlockerType.taskBlocked,
            'Task `${activeTask.title}` ended with status `${activeTask.status.wire}`.',
            DateTime.now(),
            taskId: activeTask.id,
          );
          await _storage.saveSnapshot(workspace.rootPath, project);
          return ProjectRunResult(project: project, activeTask: activeTask);
        }
      }

      if (newTasksCreated >= allowedNewTasks) {
        final now = DateTime.now();
        project = _blockProject(
          project,
          ProjectBlockerType.budget,
          'Project run paused after creating $allowedNewTasks task${allowedNewTasks == 1 ? '' : 's'}. Continue the project to create more work.',
          now,
        );
        await _storage.saveSnapshot(workspace.rootPath, project);
        return ProjectRunResult(project: project, activeTask: activeTask);
      }

      final decision = await _superviseProject(
        client: client,
        workspace: workspace,
        project: project,
        baseSystemPrompt: baseSystemPrompt,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      cancellationToken?.throwIfCancelled();

      final now = DateTime.now();
      final record = decision.toRecord(createdAt: now);
      project = project.copyWith(
        status: ProjectStatus.running,
        blocker: null,
        decisions: [...project.decisions, record],
        memorySummary: _appendMemory(
          project.memorySummary,
          decision.memoryUpdate.isEmpty
              ? decision.projectSummary
              : decision.memoryUpdate,
        ),
        updatedAt: now,
      );

      switch (decision.decision) {
        case ProjectDecisionType.complete:
          project = project.copyWith(
            status: ProjectStatus.completed,
            activeTaskId: null,
            completionSummary: decision.completionSummary.isEmpty
                ? decision.projectSummary
                : decision.completionSummary,
            completedAt: now,
            updatedAt: now,
          );
          await _storage.saveSnapshot(workspace.rootPath, project);
          onTaskUpdated?.call(null);
          return ProjectRunResult(project: project);
        case ProjectDecisionType.blocked:
          project = _blockFromDecision(project, decision, now);
          await _storage.saveSnapshot(workspace.rootPath, project);
          return ProjectRunResult(project: project);
        case ProjectDecisionType.createTask:
          final nextTask = decision.nextTask;
          if (nextTask == null || nextTask.prompt.trim().isEmpty) {
            project = _blockProject(
              project,
              ProjectBlockerType.error,
              'Project supervisor requested a new task without a task prompt.',
              now,
            );
            await _storage.saveSnapshot(workspace.rootPath, project);
            return ProjectRunResult(project: project);
          }
          if (_repeatsPreviousTaskPrompt(project, nextTask.prompt)) {
            project = _blockProject(
              project,
              ProjectBlockerType.error,
              'Project supervisor repeated the same next task twice.',
              now,
            );
            await _storage.saveSnapshot(workspace.rootPath, project);
            return ProjectRunResult(project: project);
          }

          activeTask = await _taskService.createTask(
            client: client,
            workspace: workspace,
            userPrompt: _taskPrompt(project, nextTask),
            selectedMode: ExecutionMode.task,
            baseSystemPrompt: _buildTaskSystemPrompt(
              baseSystemPrompt,
              project,
              null,
            ),
            chatSessionId: project.chatSessionId,
            projectId: project.id,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          );
          onTaskUpdated?.call(activeTask);
          final taskRef = ProjectTaskRef.fromTask(
            activeTask,
            summary: 'Created by project supervisor.',
          );
          project = project.copyWith(
            activeTaskId: activeTask.id,
            tasks: [...project.tasks, taskRef],
            decisions: [
              ...project.decisions.take(project.decisions.length - 1),
              record.copyWithTask(
                taskId: activeTask.id,
                taskTitle: activeTask.title,
              ),
            ],
            updatedAt: DateTime.now(),
          );
          await _storage.saveSnapshot(workspace.rootPath, project);
          newTasksCreated++;
      }
    }
  }

  Future<ProjectDocument> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String answer,
  }) async {
    final question = snapshot.pendingQuestion;
    final trimmed = answer.trim();
    if (question == null || trimmed.isEmpty) return snapshot;
    final updated = snapshot.copyWith(
      status: ProjectStatus.paused,
      pendingQuestion: null,
      blocker: null,
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        'User answered: ${question.question}\nAnswer: $trimmed',
      ),
      updatedAt: DateTime.now(),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<ProjectDocument> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final now = DateTime.now();
    final updated = snapshot.copyWith(
      status: ProjectStatus.cancelled,
      activeTaskId: null,
      pendingQuestion: null,
      blocker: null,
      completedAt: now,
      updatedAt: now,
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
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

  Future<_ProjectDecision> _superviseProject({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required String baseSystemPrompt,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    final metadata = await _collectWorkspaceMetadata(workspace, project);
    try {
      final json = await _completeJson(
        client: client,
        label: 'Project Supervisor',
        system: '$baseSystemPrompt\n\n$_supervisorSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user:
            '''
Evaluate this project and choose the next action.

Return only JSON:
{
  "decision": "create_task|complete|blocked",
  "projectSummary": "...",
  "memoryUpdate": "...",
  "nextTask": {
    "title": "...",
    "prompt": "...",
    "successCriteria": ["..."]
  },
  "completionSummary": "...",
  "userQuestion": "..."
}

Workspace metadata:
${_encoder.convert(metadata)}

Project:
${_encoder.convert(project.toJson())}
''',
      );
      return _ProjectDecision.fromJson(json);
    } on TaskCancelledException {
      rethrow;
    } catch (e) {
      return _ProjectDecision(
        decision: ProjectDecisionType.blocked,
        projectSummary: 'Project supervision failed.',
        memoryUpdate: '',
        error: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _collectWorkspaceMetadata(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) async {
    final root = Directory(workspace.rootPath);
    final rootFiles = <String>[];
    if (await root.exists()) {
      await for (final entity in root.list(followLinks: false)) {
        rootFiles.add(path.basename(entity.path));
        if (rootFiles.length >= 80) break;
      }
    }
    rootFiles.sort();
    final projectTasks = await _taskService.listTasks(
      workspace,
      chatSessionId: project.chatSessionId,
      projectId: project.id,
    );
    return {
      'workspaceName': workspace.displayName,
      'rootFiles': rootFiles,
      'gitAvailable': rootFiles.contains('.git'),
      'commandExecutionApproved': workspace.commandExecutionApproved,
      'projectTaskIds': projectTasks.map((task) => task.id).toList(),
    };
  }

  Future<Map<String, dynamic>> _completeJson({
    required ChatClient client,
    required String system,
    required String user,
    required String label,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    _emitProjectModelOutput(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.start, label: label),
    );
    final completion = await client.completeChatStreamed(
      messages: [
        ChatMessage(role: 'system', content: system),
        ChatMessage(role: 'user', content: user),
      ],
      onToken: (token) {
        cancellationToken?.throwIfCancelled();
        final content = token.content;
        if (content != null && content.isNotEmpty) {
          _emitProjectModelOutput(
            onModelOutput,
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
          _emitProjectModelOutput(
            onModelOutput,
            TaskModelOutputEvent(
              type: TaskModelOutputEventType.reasoning,
              label: label,
              text: reasoning,
              token: token,
            ),
          );
        }
      },
    );
    cancellationToken?.throwIfCancelled();
    _emitProjectModelOutput(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.done, label: label),
    );
    final text = completion.content.trim().isNotEmpty
        ? completion.content
        : completion.reasoning;
    return TaskJson.parseObject(text);
  }

  void _emitProjectModelOutput(
    TaskModelOutputSink? sink,
    TaskModelOutputEvent event,
  ) {
    sink?.call(event);
  }

  ProjectDocument _syncTaskRef(
    ProjectDocument project,
    TaskDocument task,
    DateTime now,
  ) {
    final summary = _taskMemorySummary(task);
    final updatedRef = ProjectTaskRef.fromTask(task, summary: summary);
    final refs = [...project.tasks];
    final index = refs.indexWhere((ref) => ref.taskId == task.id);
    if (index >= 0) {
      refs[index] = updatedRef;
    } else {
      refs.add(updatedRef);
    }
    return project.copyWith(tasks: refs, updatedAt: now);
  }

  ProjectDocument _projectStatusFromTask(
    ProjectDocument project,
    TaskDocument task,
    DateTime now,
  ) {
    final taskBlocker = _taskBlocker(task);
    if (taskBlocker != null) {
      return _blockProject(
        project,
        taskBlocker.$1,
        taskBlocker.$2,
        now,
        taskId: task.id,
      );
    }
    return project.copyWith(status: ProjectStatus.paused, updatedAt: now);
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
    if (task.status == TaskStatus.failed) {
      return (ProjectBlockerType.taskFailed, 'Task `${task.title}` failed.');
    }
    return null;
  }

  ProjectDocument _blockFromDecision(
    ProjectDocument project,
    _ProjectDecision decision,
    DateTime now,
  ) {
    final question = decision.userQuestion.trim();
    if (question.isNotEmpty) {
      return project.copyWith(
        status: ProjectStatus.blocked,
        pendingQuestion: PendingProjectQuestion(
          id: 'question_${uuid.v7()}',
          question: question,
          createdAt: now,
        ),
        blocker: ProjectBlocker(
          type: ProjectBlockerType.question,
          message: question,
          createdAt: now,
        ),
        updatedAt: now,
      );
    }
    return _blockProject(
      project,
      ProjectBlockerType.error,
      decision.error?.trim().isNotEmpty == true
          ? decision.error!.trim()
          : decision.projectSummary.trim().isEmpty
          ? 'Project supervisor blocked without a question.'
          : decision.projectSummary.trim(),
      now,
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

  bool _repeatsPreviousTaskPrompt(ProjectDocument project, String prompt) {
    final normalized = _normalisePrompt(prompt);
    for (final decision in project.decisions.reversed.skip(1).take(1)) {
      final previous = decision.taskPrompt;
      if (previous == null) continue;
      if (_normalisePrompt(previous) == normalized) return true;
    }
    return false;
  }

  String _normalisePrompt(String prompt) =>
      prompt.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _taskPrompt(ProjectDocument project, _NextProjectTask nextTask) {
    final buffer = StringBuffer()
      ..writeln('Project goal:')
      ..writeln(project.goal)
      ..writeln()
      ..writeln('Project constraints:')
      ..writeln(_bulletList(project.constraints))
      ..writeln()
      ..writeln('Project success criteria:')
      ..writeln(_bulletList(project.successCriteria))
      ..writeln()
      ..writeln('Project memory:')
      ..writeln(
        project.memorySummary.trim().isEmpty
            ? 'None yet.'
            : project.memorySummary,
      )
      ..writeln()
      ..writeln('Prior project tasks:')
      ..writeln(_priorTaskList(project))
      ..writeln()
      ..writeln('Next task title:')
      ..writeln(nextTask.title)
      ..writeln()
      ..writeln('Next task request:')
      ..writeln(nextTask.prompt);
    if (nextTask.successCriteria.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Next task success criteria:')
        ..writeln(_bulletList(nextTask.successCriteria));
    }
    return buffer.toString().trim();
  }

  String _buildTaskSystemPrompt(
    String baseSystemPrompt,
    ProjectDocument project,
    TaskDocument? task,
  ) {
    final activeTaskLine = task == null
        ? ''
        : '\nActive project task: ${task.title} (${task.id})';
    return '''
$baseSystemPrompt

You are working inside a supervised Project.
Project id: ${project.id}
Project goal: ${project.goal}
Use Tasks as bounded work units. Complete only the active task, and let the Project supervisor decide what comes next.$activeTaskLine
'''
        .trim();
  }

  String _priorTaskList(ProjectDocument project) {
    if (project.tasks.isEmpty) return 'None yet.';
    return project.tasks
        .map(
          (task) =>
              '- ${task.taskId}: ${task.title} (${task.status.wire}) ${task.summary}',
        )
        .join('\n');
  }

  String _bulletList(List<String> items) {
    if (items.isEmpty) return '- None specified.';
    return items.map((item) => '- $item').join('\n');
  }

  String _taskMemorySummary(TaskDocument task) {
    final latestRun = task.runs.isEmpty ? null : task.runs.last;
    return [
      if (latestRun != null) latestRun.summary,
      if (latestRun?.memoryUpdate.trim().isNotEmpty == true)
        latestRun!.memoryUpdate.trim(),
      if (task.memorySummary.trim().isNotEmpty) task.memorySummary.trim(),
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
  }

  String _appendMemory(String current, String update) {
    final trimmed = update.trim();
    if (trimmed.isEmpty) return current;
    final parts = [if (current.trim().isNotEmpty) current.trim(), trimmed];
    return _cap(parts.join('\n\n'), 18000);
  }

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
}

class _ProjectDecision {
  final ProjectDecisionType decision;
  final String projectSummary;
  final String memoryUpdate;
  final _NextProjectTask? nextTask;
  final String completionSummary;
  final String userQuestion;
  final String? error;

  const _ProjectDecision({
    required this.decision,
    required this.projectSummary,
    required this.memoryUpdate,
    this.nextTask,
    this.completionSummary = '',
    this.userQuestion = '',
    this.error,
  });

  factory _ProjectDecision.fromJson(Map<String, dynamic> json) {
    final rawNextTask = json['nextTask'] ?? json['next_task'];
    return _ProjectDecision(
      decision: parseProjectDecisionType(json['decision']),
      projectSummary: jsonString(
        json['projectSummary'] ?? json['project_summary'],
      ),
      memoryUpdate: jsonString(json['memoryUpdate'] ?? json['memory_update']),
      nextTask: rawNextTask is Map
          ? _NextProjectTask.fromJson(Map<String, dynamic>.from(rawNextTask))
          : null,
      completionSummary: jsonString(
        json['completionSummary'] ?? json['completion_summary'],
      ),
      userQuestion: jsonString(json['userQuestion'] ?? json['user_question']),
      error: jsonNullableString(json['error']),
    );
  }

  ProjectDecisionRecord toRecord({required DateTime createdAt}) {
    return ProjectDecisionRecord(
      id: 'decision_${uuid.v7()}',
      decision: decision,
      summary: projectSummary,
      memoryUpdate: memoryUpdate,
      taskTitle: nextTask?.title,
      taskPrompt: nextTask?.prompt,
      error: error,
      createdAt: createdAt,
    );
  }
}

extension on ProjectDecisionRecord {
  ProjectDecisionRecord copyWithTask({String? taskId, String? taskTitle}) {
    return ProjectDecisionRecord(
      id: id,
      decision: decision,
      summary: summary,
      memoryUpdate: memoryUpdate,
      taskId: taskId ?? this.taskId,
      taskTitle: taskTitle ?? this.taskTitle,
      taskPrompt: taskPrompt,
      error: error,
      createdAt: createdAt,
    );
  }
}

class _NextProjectTask {
  final String title;
  final String prompt;
  final List<String> successCriteria;

  const _NextProjectTask({
    required this.title,
    required this.prompt,
    required this.successCriteria,
  });

  factory _NextProjectTask.fromJson(Map<String, dynamic> json) {
    final prompt = jsonString(json['prompt'] ?? json['request']);
    return _NextProjectTask(
      title: jsonString(json['title'], fallback: prompt),
      prompt: prompt,
      successCriteria: jsonStringList(
        json['successCriteria'] ?? json['success_criteria'],
      ),
    );
  }
}

const String _supervisorSystemInstruction = '''
You supervise a long-horizon Project by choosing the next bounded Task.
Do not call tools.
Do not perform workspace work directly.
Use existing project memory and completed task summaries.
Create one concrete next task when more work is needed.
Only mark complete when the project goal and success criteria are satisfied.
If user input is required, return decision "blocked" with userQuestion.
Avoid repeating the same task. If the next useful work is the same as the previous task, explain why blocked instead.
Return only valid JSON.
''';
