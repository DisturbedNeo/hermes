import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';

/// Result of migrating the embedded project-task representation into the
/// canonical task repository.
class ProjectTaskMigrationResult {
  final ProjectDocument project;
  final bool migrated;

  const ProjectTaskMigrationResult({
    required this.project,
    required this.migrated,
  });
}

/// Converts the pre-Phase 2 project/task snapshots into the canonical model.
///
/// Legacy project snapshots contain project-task definitions inline and point
/// at a second Task record through `taskDocumentId`. The migration
/// keeps the project task ID, folds the executable record into that ID, moves
/// auxiliary task files, and rewrites the project relationship fields. A
/// migrated project has no embedded task definitions, so running this again
/// is a no-op.
class ProjectTaskSnapshotMigration {
  const ProjectTaskSnapshotMigration({required TaskRepository taskRepository})
    : _taskRepository = taskRepository;

  final TaskRepository _taskRepository;

  Future<ProjectTaskMigrationResult> migrate(
    String workspaceRoot,
    ProjectDocument project,
  ) async {
    if (project.tasks.isEmpty) {
      return ProjectTaskMigrationResult(project: project, migrated: false);
    }

    final plannedById = <String, Task>{};
    final legacyToCanonical = <String, String>{};
    for (final task in project.tasks) {
      plannedById.putIfAbsent(task.id, () => task);
      legacyToCanonical[task.id] = task.id;
      final legacyId = task.taskDocumentId;
      if (legacyId != null && legacyId.isNotEmpty) {
        legacyToCanonical[legacyId] = task.id;
      }
    }

    final orderedIds = <String>[];
    void addTaskId(String id) {
      final canonicalId = legacyToCanonical[id] ?? id;
      if (canonicalId.isEmpty || orderedIds.contains(canonicalId)) return;
      orderedIds.add(canonicalId);
    }

    for (final id in project.taskIds) {
      addTaskId(id);
    }
    for (final task in project.tasks) {
      addTaskId(task.id);
    }

    final migratedTasks = <Task>[];
    for (final canonicalId in orderedIds) {
      final planned = plannedById[canonicalId];
      final canonicalExisting = await _taskRepository.loadTask(
        workspaceRoot,
        canonicalId,
      );
      final legacyId = planned?.taskDocumentId;
      final legacyExisting = legacyId == null || legacyId == canonicalId
          ? null
          : await _taskRepository.loadTask(workspaceRoot, legacyId);
      final execution = _mergeExecutionRecords(
        canonicalExisting,
        legacyExisting,
      );

      final migrated = planned == null
          ? execution?.copyWith(
              id: canonicalId,
              schemaVersion: Task.currentSchemaVersion,
              chatSessionId: project.chatSessionId ?? execution.chatSessionId,
              projectId: project.id,
              taskDocumentId: null,
            )
          : _mergeTask(
              planned: planned,
              execution: execution,
              canonicalId: canonicalId,
              project: project,
              legacyToCanonical: legacyToCanonical,
              legacyTaskId: legacyId,
            );
      if (migrated == null) continue;

      await _taskRepository.migrateSnapshot(
        workspaceRoot,
        sourceTaskId: legacyId ?? canonicalId,
        task: migrated,
      );
      migratedTasks.add(migrated);
    }

    final migratedProject = project.copyWith(
      taskIds: orderedIds,
      tasks: migratedTasks,
      activeTaskId: _canonicalNullableId(
        project.activeTaskId,
        legacyToCanonical,
      ),
      artifacts: [
        for (final artifact in project.artifacts)
          _canonicalizeArtifact(
            artifact,
            canonicalId: _canonicalNullableId(
              artifact.taskId,
              legacyToCanonical,
            ),
            legacyTaskId: artifact.taskId,
          ),
      ],
      evidence: [
        for (final evidence in project.evidence)
          evidence.copyWith(
            taskId: _canonicalNullableId(evidence.taskId, legacyToCanonical),
          ),
      ],
      recoveryIncidents: [
        for (final incident in project.recoveryIncidents)
          incident.copyWith(
            sourceTaskIds: [
              for (final id in incident.sourceTaskIds)
                _canonicalId(id, legacyToCanonical),
            ],
            recoveryTaskIds: [
              for (final id in incident.recoveryTaskIds)
                _canonicalId(id, legacyToCanonical),
            ],
          ),
      ],
      decisions: [
        for (final decision in project.decisions)
          decision.copyWith(
            taskId: _canonicalNullableId(decision.taskId, legacyToCanonical),
          ),
      ],
    );

    return ProjectTaskMigrationResult(project: migratedProject, migrated: true);
  }

  Task? _mergeExecutionRecords(Task? canonical, Task? legacy) {
    if (canonical == null) return legacy;
    if (legacy == null) return canonical;

    final primary = _hasExecution(canonical) ? canonical : legacy;
    final secondary = identical(primary, canonical) ? legacy : canonical;
    return primary.copyWith(
      gates: primary.gates.isNotEmpty ? primary.gates : secondary.gates,
      steps: primary.steps.isNotEmpty ? primary.steps : secondary.steps,
      currentStepId: primary.currentStepId ?? secondary.currentStepId,
      memorySummary: primary.memorySummary.isNotEmpty
          ? primary.memorySummary
          : secondary.memorySummary,
      runs: _mergeRuns(primary.runs, secondary.runs),
      pendingApproval: primary.pendingApproval ?? secondary.pendingApproval,
      pendingQuestion: primary.pendingQuestion ?? secondary.pendingQuestion,
      failure: primary.failure ?? secondary.failure,
      completedAt: primary.completedAt ?? secondary.completedAt,
    );
  }

  bool _hasExecution(Task task) {
    return task.steps.isNotEmpty ||
        task.runs.isNotEmpty ||
        task.currentStepId != null ||
        task.status != TaskStatus.queued && task.status != TaskStatus.draft;
  }

  List<TaskRun> _mergeRuns(List<TaskRun> primary, List<TaskRun> secondary) {
    final seen = <String>{};
    return [
      for (final run in [...primary, ...secondary])
        if (seen.add(run.runId)) run,
    ];
  }

  Task _mergeTask({
    required Task planned,
    required Task? execution,
    required String canonicalId,
    required ProjectDocument project,
    required Map<String, String> legacyToCanonical,
    required String? legacyTaskId,
  }) {
    final source = execution ?? planned;
    final steps = (execution?.steps.isNotEmpty ?? false)
        ? execution!.steps
        : planned.steps;
    final canonicalSteps = [
      for (final step in steps)
        step.copyWith(
          artifacts: [
            for (final artifact in step.artifacts)
              _canonicalizeArtifact(
                artifact,
                canonicalId: canonicalId,
                legacyTaskId: legacyTaskId,
              ),
          ],
        ),
    ];
    final expectedArtifacts = planned.expectedArtifacts.isNotEmpty
        ? planned.expectedArtifacts
        : source.expectedArtifacts;
    final status = _mergedStatus(planned, execution);
    final objective = _firstNonEmpty(planned.objective, source.objective);
    final criteria = planned.criterionIds.isNotEmpty
        ? planned.criterionIds
        : source.criterionIds;
    final dependencies = planned.dependsOnTaskIds.isNotEmpty
        ? planned.dependsOnTaskIds
        : source.dependsOnTaskIds;
    final createdAt = planned.createdAt.isBefore(source.createdAt)
        ? planned.createdAt
        : source.createdAt;
    final updatedAt = planned.updatedAt.isAfter(source.updatedAt)
        ? planned.updatedAt
        : source.updatedAt;

    return source.copyWith(
      schemaVersion: Task.currentSchemaVersion,
      id: canonicalId,
      title: _firstNonEmpty(planned.title, source.title),
      originalPrompt: execution == null
          ? planned.originalPrompt
          : _firstNonEmpty(source.originalPrompt, planned.originalPrompt),
      objective: objective,
      constraints: planned.constraints.isNotEmpty
          ? planned.constraints
          : source.constraints,
      successCriteria: planned.successCriteria.isNotEmpty
          ? planned.successCriteria
          : source.successCriteria,
      gates: planned.gates.isNotEmpty ? planned.gates : source.gates,
      steps: canonicalSteps,
      status: status,
      criterionIds: criteria,
      milestoneId: planned.milestoneId ?? source.milestoneId,
      dependsOnTaskIds: [
        for (final id in dependencies) _canonicalId(id, legacyToCanonical),
      ],
      priority:
          planned.priority != TaskPriority.normal ||
              source.priority == TaskPriority.normal
          ? planned.priority
          : source.priority,
      risk: planned.risk != TaskRisk.unknown || source.risk == TaskRisk.unknown
          ? planned.risk
          : source.risk,
      riskReduction:
          planned.riskReduction != ProjectRiskReduction.none ||
              source.riskReduction == ProjectRiskReduction.none
          ? planned.riskReduction
          : source.riskReduction,
      effort:
          planned.effort != TaskEffort.small ||
              source.effort == TaskEffort.small
          ? planned.effort
          : source.effort,
      selectionRationale: _firstNonEmpty(
        planned.selectionRationale,
        source.selectionRationale,
      ),
      revisionIntroduced: planned.revisionIntroduced > 1
          ? planned.revisionIntroduced
          : source.revisionIntroduced,
      revisionUpdated: planned.revisionUpdated > 1
          ? planned.revisionUpdated
          : source.revisionUpdated,
      expectedEvidence: planned.expectedEvidence.isNotEmpty
          ? planned.expectedEvidence
          : source.expectedEvidence,
      readPaths: planned.readPaths.isNotEmpty
          ? planned.readPaths
          : source.readPaths,
      writePaths: planned.writePaths.isNotEmpty
          ? planned.writePaths
          : source.writePaths,
      legacyWriteAccess: planned.legacyWriteAccess || source.legacyWriteAccess,
      doneCriteria: planned.doneCriteria.isNotEmpty
          ? planned.doneCriteria
          : source.doneCriteria,
      outOfScope: planned.outOfScope.isNotEmpty
          ? planned.outOfScope
          : source.outOfScope,
      context: planned.context.isNotEmpty ? planned.context : source.context,
      expectedArtifacts: [
        for (final artifact in expectedArtifacts)
          _canonicalizeArtifact(
            artifact,
            canonicalId: canonicalId,
            legacyTaskId: legacyTaskId,
          ),
      ],
      recoveryIncidentId:
          planned.recoveryIncidentId ?? source.recoveryIncidentId,
      fingerprint: _firstNonEmpty(
        planned.fingerprint,
        source.fingerprint,
      ).ifEmpty(projectTaskFingerprint(objective, criteria)),
      rejectionReason: planned.rejectionReason ?? source.rejectionReason,
      failure: planned.failure ?? source.failure,
      currentStepId: source.currentStepId ?? planned.currentStepId,
      memorySummary: source.memorySummary,
      runs: [
        for (final run in source.runs)
          run.copyWith(
            artifacts: [
              for (final artifact in run.artifacts)
                _canonicalizeArtifact(
                  artifact,
                  canonicalId: canonicalId,
                  legacyTaskId: legacyTaskId,
                ),
            ],
          ),
      ],
      pendingApproval: source.pendingApproval,
      pendingQuestion: source.pendingQuestion,
      chatSessionId:
          project.chatSessionId ??
          source.chatSessionId ??
          planned.chatSessionId,
      projectId: project.id,
      taskDocumentId: null,
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: source.completedAt ?? planned.completedAt,
    );
  }

  TaskStatus _mergedStatus(Task planned, Task? execution) {
    if (_isTerminal(planned.status) || execution == null) return planned.status;
    return _hasExecution(execution) ? execution.status : planned.status;
  }

  bool _isTerminal(TaskStatus status) => switch (status) {
    TaskStatus.completed ||
    TaskStatus.failed ||
    TaskStatus.rejected ||
    TaskStatus.split ||
    TaskStatus.deferred ||
    TaskStatus.obsolete ||
    TaskStatus.cancelled => true,
    _ => false,
  };

  String _firstNonEmpty(String first, String second) {
    return first.trim().isNotEmpty ? first : second;
  }

  String _canonicalId(String id, Map<String, String> mapping) {
    if (id.isEmpty) return id;
    return mapping[id] ?? id;
  }

  String? _canonicalNullableId(String? id, Map<String, String> mapping) {
    if (id == null || id.isEmpty) return id;
    return mapping[id] ?? id;
  }

  TaskArtifact _canonicalizeArtifact(
    TaskArtifact artifact, {
    required String? canonicalId,
    required String? legacyTaskId,
  }) {
    final legacyPrefix = legacyTaskId == null || legacyTaskId.isEmpty
        ? null
        : '${TaskRepository.tasksRoot}/$legacyTaskId/';
    final path = legacyPrefix == null
        ? artifact.path
        : artifact.path.replaceFirst(
            legacyPrefix,
            '${TaskRepository.tasksRoot}/$canonicalId/',
          );
    return artifact.copyWith(
      path: path,
      taskId: canonicalId ?? artifact.taskId,
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
