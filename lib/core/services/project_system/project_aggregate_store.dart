import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/services/project_system/project_aggregate_repository.dart';
import 'package:hermes/core/services/project_system/project_checkpoint.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/services/task_system/task_plan_materializer.dart';

/// Tracks the last task snapshots included in one project command.
///
/// The execution and planning phases can update a hydrated view freely; this
/// context is the write-set used by [ProjectAggregateStore] and is not an
/// orchestration concern.
class ProjectPersistenceContext {
  ProjectPersistenceContext(Iterable<Task> initialTasks, {this.health}) {
    for (final task in initialTasks) {
      _lastPersistedTasks[task.id] = task;
      _expectedTaskRevisions[task.id] = task.persistenceRevision;
    }
  }

  final ProjectPersistenceDiagnostics? health;
  final Map<String, Task> _lastPersistedTasks = {};
  final Map<String, int> _expectedTaskRevisions = {};
  final Map<String, Task> _stagedTasks = {};

  void stageTask(Task task) {
    final expected = _expectedTaskRevisions[task.id];
    final effective = expected != null && task.persistenceRevision < expected
        ? task.copyWith(persistenceRevision: expected)
        : task;
    _stagedTasks[task.id] = effective;
    // Task-system services may persist a task while carrying out the same
    // command (for example, when recovering a run).  Staging the returned
    // canonical document advances this command's expected revision; a later
    // unrelated writer still fails the commit check.
    if (expected == null || effective.persistenceRevision >= expected) {
      _expectedTaskRevisions[task.id] = effective.persistenceRevision;
    }
  }

  Iterable<Task> get stagedTasks => _stagedTasks.values;

  int? expectedTaskRevision(String taskId) => _expectedTaskRevisions[taskId];

  void observeTaskRevision(String taskId, int revision) {
    _expectedTaskRevisions[taskId] = revision;
  }

  bool shouldPersistTask(Task task) {
    final previous = _lastPersistedTasks[task.id];
    return previous == null || previous != task;
  }

  void markPersisted(Task task) {
    _lastPersistedTasks[task.id] = task;
    _expectedTaskRevisions[task.id] = task.persistenceRevision;
    _stagedTasks[task.id] = task;
  }
}

/// Explicit command-level unit of work for one project checkpoint.
///
/// Handlers produce this intent; the aggregate store is the only component
/// that turns it into repository writes, transaction manifests, and
/// optimistic-revision checks.
class ProjectCommitIntent {
  const ProjectCommitIntent({
    required this.workspaceRoot,
    required this.project,
    this.context,
    this.checkpoint = ProjectPersistenceCheckpoint.runtime,
  });

  final String workspaceRoot;
  final ProjectDocument project;
  final ProjectPersistenceContext? context;
  final ProjectPersistenceCheckpoint checkpoint;
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
  final TaskPlanMaterializer _materializer = const TaskPlanMaterializer();

  Future<ProjectDocument> commit(ProjectCommitIntent intent) async {
    final workspaceRoot = intent.workspaceRoot;
    final project = intent.project;
    final context = intent.context;
    final checkpoint = intent.checkpoint;
    final dirtyTasks = <Task>[...(context?.stagedTasks ?? const <Task>[])];
    final taskIdsToLoad = <String>{
      ...dirtyTasks.map((task) => task.id),
      ...project.tasks.map((task) => task.id),
    }.toList();

    final loadedExisting = taskIdsToLoad.isEmpty
        ? const <String, PersistedSnapshot<Task>?>{}
        : await _taskRepository.loadTaskSnapshots(
            workspaceRoot,
            taskIdsToLoad,
            includeHistory: false,
          );
    final stagedById = <String, Task>{
      for (final task in dirtyTasks) task.id: task,
    };
    for (final taskId in taskIdsToLoad) {
      final expected = context?.expectedTaskRevision(taskId);
      final actual = loadedExisting[taskId]?.revision;
      if (expected != null && (actual == null || expected != actual)) {
        final staged = stagedById[taskId];
        if (staged != null &&
            actual != null &&
            staged.persistenceRevision == actual) {
          // A task-system operation performed by this same command may have
          // committed a newer canonical revision before the aggregate
          // checkpoint. Its returned snapshot is authoritative for this
          // write-set; an unrelated writer still fails below when the staged
          // revision no longer matches the loaded envelope.
          context?.observeTaskRevision(taskId, actual);
          continue;
        }
        throw StaleSnapshotException(
          path: _taskRepository.taskRelativePath(
            taskId,
            TaskRepository.documentFileName,
          ),
          expectedRevision: expected,
          actualRevision: actual ?? 0,
        );
      }
    }
    final preparedById = <String, Task>{
      for (final task in dirtyTasks)
        task.id: task.copyWith(
          projectId: project.id,
          chatSessionId: project.chatSessionId,
        ),
    };
    // A new plan node is materialized exactly once. Existing executable
    // records are updated through the task-system materializer, never by
    // merging a second Task copy stored on the project.
    for (final node in project.tasks) {
      final existing = loadedExisting[node.id]?.value;
      if (existing == null) {
        preparedById[node.id] = _materializer.create(
          node,
          projectId: project.id,
          chatSessionId: project.chatSessionId,
        );
      } else if (!_materializer.matches(node, existing) &&
          !preparedById.containsKey(node.id)) {
        preparedById[node.id] = _materializer.apply(
          node,
          existing,
          projectId: project.id,
          chatSessionId: project.chatSessionId,
        );
      }
    }
    final preparedTasks = preparedById.values.toList();
    final committed = await _aggregateRepository.commit(
      workspaceRoot: workspaceRoot,
      project: project,
      tasks: preparedTasks,
      knownHealth: context?.health,
      checkpoint: checkpoint,
    );
    if (context != null) {
      for (final task in preparedTasks) {
        final persisted = committed.tasks[task.id];
        context.markPersisted(
          persisted == null
              ? task
              : persisted.value.copyWith(
                  persistenceRevision: persisted.revision,
                ),
        );
      }
    }
    return committed.project.value.copyWith(tasks: project.tasks);
  }
}
