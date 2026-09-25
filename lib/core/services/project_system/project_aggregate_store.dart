import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/services/project_system/project_aggregate_repository.dart';
import 'package:hermes/core/services/project_system/project_checkpoint.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';

/// Tracks the last task snapshots included in one project command.
///
/// The execution and planning phases can update a hydrated view freely; this
/// context is the write-set used by [ProjectAggregateStore] and is not an
/// orchestration concern.
class ProjectPersistenceContext {
  ProjectPersistenceContext(Iterable<Task> initialTasks, {this.health}) {
    for (final task in initialTasks) {
      _lastPersistedTasks[task.id] = task;
    }
  }

  final ProjectPersistenceDiagnostics? health;
  final Map<String, Task> _lastPersistedTasks = {};

  bool shouldPersistTask(Task task) {
    final previous = _lastPersistedTasks[task.id];
    return previous == null || previous != task;
  }

  void markPersisted(Task task) {
    _lastPersistedTasks[task.id] = task;
  }
}

/// The sole write boundary for a hydrated project aggregate.
///
/// It owns task write-set calculation and canonical task merge rules. Phases
/// submit a project snapshot and receive the committed hydrated snapshot; they
/// do not coordinate task revisions or repository transactions themselves.
class ProjectAggregateStore {
  const ProjectAggregateStore({
    required ProjectAggregateRepository aggregateRepository,
    required TaskRepository taskRepository,
  }) : _aggregateRepository = aggregateRepository,
       _taskRepository = taskRepository;

  final ProjectAggregateRepository _aggregateRepository;
  final TaskRepository _taskRepository;

  Future<ProjectDocument> commit({
    required String workspaceRoot,
    required ProjectDocument project,
    ProjectPersistenceContext? context,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) async {
    final dirtyTasks = <Task>[];
    final taskIdsToLoad = <String>[];
    for (final task in project.tasks) {
      final changed = context == null || context.shouldPersistTask(task);
      // A zero revision means the record has never reached the canonical task
      // store, even if the hydrated object itself is unchanged.
      if (!changed && task.persistenceRevision > 0) continue;
      dirtyTasks.add(task);
      taskIdsToLoad.add(task.id);
    }

    final loadedExisting = taskIdsToLoad.isEmpty
        ? const <String, PersistedSnapshot<Task>?>{}
        : await _taskRepository.loadTaskSnapshots(
            workspaceRoot,
            taskIdsToLoad,
            includeHistory: false,
          );
    final preparedTasks = [
      for (final task in dirtyTasks)
        _mergeTask(
          task,
          loadedExisting[task.id]?.value,
          projectId: project.id,
          chatSessionId: project.chatSessionId,
        ),
    ];
    final committed = await _aggregateRepository.commit(
      workspaceRoot: workspaceRoot,
      project: project,
      tasks: preparedTasks,
      knownHealth: context?.health,
      checkpoint: checkpoint,
    );
    if (context != null) {
      for (final task in preparedTasks) {
        context.markPersisted(committed.tasks[task.id]?.value ?? task);
      }
    }
    return committed.project.value.copyWith(
      tasks: [
        for (final task in project.tasks)
          committed.tasks[task.id]?.value ?? task,
      ],
    );
  }

  Task _mergeTask(
    Task projectTask,
    Task? existing, {
    required String projectId,
    required String? chatSessionId,
  }) {
    if (existing == null || projectTask.steps.isNotEmpty) {
      return projectTask.copyWith(
        persistenceRevision:
            existing?.persistenceRevision ?? projectTask.persistenceRevision,
        projectId: projectId,
        chatSessionId: chatSessionId,
      );
    }
    // Project planning may update metadata for an existing task, but must not
    // erase executable steps, runs, or task history owned by the task system.
    return existing.copyWith(
      id: projectTask.id,
      title: projectTask.title,
      originalPrompt: projectTask.originalPrompt,
      objective: projectTask.objective,
      constraints: projectTask.constraints,
      successCriteria: projectTask.successCriteria,
      gates: projectTask.gates.isEmpty ? existing.gates : projectTask.gates,
      criterionIds: projectTask.criterionIds,
      milestoneId: projectTask.milestoneId,
      dependsOnTaskIds: projectTask.dependsOnTaskIds,
      priority: projectTask.priority,
      risk: projectTask.risk,
      riskReduction: projectTask.riskReduction,
      effort: projectTask.effort,
      selectionRationale: projectTask.selectionRationale,
      revisionIntroduced: projectTask.revisionIntroduced,
      revisionUpdated: projectTask.revisionUpdated,
      expectedEvidence: projectTask.expectedEvidence.isEmpty
          ? existing.expectedEvidence
          : projectTask.expectedEvidence,
      readPaths: projectTask.readPaths,
      writePaths: projectTask.writePaths,
      doneCriteria: projectTask.doneCriteria,
      outOfScope: projectTask.outOfScope,
      context: projectTask.context,
      expectedArtifacts: projectTask.expectedArtifacts.isEmpty
          ? existing.expectedArtifacts
          : projectTask.expectedArtifacts,
      status: projectTask.status,
      recoveryIncidentId: projectTask.recoveryIncidentId,
      fingerprint: projectTask.fingerprint,
      rejectionReason: projectTask.rejectionReason,
      failure: projectTask.failure ?? existing.failure,
      projectId: projectId,
      chatSessionId: chatSessionId,
    );
  }
}
