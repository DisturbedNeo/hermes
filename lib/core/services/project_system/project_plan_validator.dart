import 'package:hermes/core/models/project.dart';
import 'package:path/path.dart' as path;

enum ProjectPlanValidationSeverity { warning, error }

class ProjectPlanValidationIssue {
  final String code;
  final String path;
  final String message;
  final ProjectPlanValidationSeverity severity;

  const ProjectPlanValidationIssue({
    required this.code,
    required this.path,
    required this.message,
    this.severity = ProjectPlanValidationSeverity.error,
  });

  Map<String, String> toMap() => {
    'code': code,
    'path': path,
    'message': message,
    'severity': severity.name,
  };
}

class ProjectPlanValidationResult {
  final List<ProjectPlanValidationIssue> issues;

  const ProjectPlanValidationResult(this.issues);

  bool get valid => issues.every(
    (issue) => issue.severity != ProjectPlanValidationSeverity.error,
  );

  List<ProjectPlanValidationIssue> get errors => issues
      .where((issue) => issue.severity == ProjectPlanValidationSeverity.error)
      .toList();

  List<ProjectPlanValidationIssue> get warnings => issues
      .where((issue) => issue.severity == ProjectPlanValidationSeverity.warning)
      .toList();
}

/// Validates a proposal without changing either the proposal or project.
class ProjectPlanValidator {
  const ProjectPlanValidator({this.planningHorizon = 7});

  final int planningHorizon;

  ProjectPlanValidationResult validate({
    required ProjectState project,
    required ProjectPlanProposal proposal,
    required String workspaceRoot,
  }) {
    final issues = <ProjectPlanValidationIssue>[];
    void issue(String code, String fieldPath, String message) {
      issues.add(
        ProjectPlanValidationIssue(
          code: code,
          path: fieldPath,
          message: message,
        ),
      );
    }

    if (proposal.revision != project.currentRevision + 1) {
      issue(
        'revision_mismatch',
        'revision',
        'Expected revision ${project.currentRevision + 1}.',
      );
    }

    _validateUniqueIds(
      proposal.criterionUpserts.map((item) => item.id),
      'criterionUpserts',
      issues,
    );
    _validateUniqueIds(
      proposal.milestoneUpserts.map((item) => item.id),
      'milestoneUpserts',
      issues,
    );
    _validateUniqueIds(
      proposal.taskAdditions.map((item) => item.id),
      'taskAdditions',
      issues,
    );
    _validateUniqueIds(
      proposal.taskUpdates.map((item) => item.id),
      'taskUpdates',
      issues,
    );
    _validateUniqueIds(
      proposal.memoryAdditions.map((item) => item.id),
      'memoryAdditions',
      issues,
    );
    _validateUniqueIds(
      proposal.removedCriterionIds,
      'removedCriterionIds',
      issues,
    );
    _validateUniqueIds(
      proposal.removedMilestoneIds,
      'removedMilestoneIds',
      issues,
    );

    final upsertedCriterionIds = proposal.criterionUpserts
        .map((item) => item.id)
        .toSet();
    for (var index = 0; index < proposal.criterionUpserts.length; index++) {
      final criterion = proposal.criterionUpserts[index];
      if (criterion.statement.trim().isEmpty) {
        issue(
          'missing_criterion_statement',
          'criterionUpserts[$index].statement',
          'Criterion ${criterion.id} needs a non-empty statement.',
        );
      }
    }
    for (var index = 0; index < proposal.removedCriterionIds.length; index++) {
      final id = proposal.removedCriterionIds[index];
      if (upsertedCriterionIds.contains(id)) {
        issue(
          'conflicting_criterion_edit',
          'removedCriterionIds[$index]',
          'Criterion $id cannot be updated and removed in one revision.',
        );
      }
    }

    final existingCriterionIds = project.criteria
        .map((item) => item.id)
        .toSet();
    final proposedCriterionIds = {
      ...existingCriterionIds,
      ...proposal.criterionUpserts.map((item) => item.id),
    }..removeAll(proposal.removedCriterionIds);
    for (var index = 0; index < proposal.removedCriterionIds.length; index++) {
      final id = proposal.removedCriterionIds[index];
      final criterion = project.criteria
          .where((item) => item.id == id)
          .firstOrNull;
      if (criterion == null) {
        issue(
          'unknown_criterion',
          'removedCriterionIds[$index]',
          'Criterion $id does not exist.',
        );
      } else if (criterion.required) {
        if (!proposal.requiresApproval) {
          issue(
            'required_criterion_removal',
            'removedCriterionIds[$index]',
            'Required criterion $id needs an approved scope decision.',
          );
        } else {
          issues.add(
            ProjectPlanValidationIssue(
              code: 'scope_decision_requires_approval',
              path: 'removedCriterionIds[$index]',
              message:
                  'Removing required criterion $id must remain pending until user approval.',
              severity: ProjectPlanValidationSeverity.warning,
            ),
          );
        }
      }
    }

    final existingMilestoneIds = project.milestones
        .map((item) => item.id)
        .toSet();
    final proposedMilestoneIds = {
      ...existingMilestoneIds,
      ...proposal.milestoneUpserts.map((item) => item.id),
    }..removeAll(proposal.removedMilestoneIds);
    for (var index = 0; index < proposal.removedMilestoneIds.length; index++) {
      final id = proposal.removedMilestoneIds[index];
      if (!existingMilestoneIds.contains(id)) {
        issue(
          'unknown_milestone',
          'removedMilestoneIds[$index]',
          'Milestone $id does not exist.',
        );
      }
      if (proposal.milestoneUpserts.any((item) => item.id == id)) {
        issue(
          'conflicting_milestone_edit',
          'removedMilestoneIds[$index]',
          'Milestone $id cannot be updated and removed in one revision.',
        );
      }
    }
    for (
      var milestoneIndex = 0;
      milestoneIndex < proposal.milestoneUpserts.length;
      milestoneIndex++
    ) {
      final milestone = proposal.milestoneUpserts[milestoneIndex];
      for (
        var criterionIndex = 0;
        criterionIndex < milestone.criterionIds.length;
        criterionIndex++
      ) {
        final criterionId = milestone.criterionIds[criterionIndex];
        if (!proposedCriterionIds.contains(criterionId)) {
          issue(
            'unknown_criterion',
            'milestoneUpserts[$milestoneIndex].criterionIds[$criterionIndex]',
            'Criterion $criterionId does not exist in the proposed plan.',
          );
        }
      }
    }

    final existingBacklogById = {
      for (final task in project.backlog) task.id: task,
    };
    for (var index = 0; index < proposal.taskUpdates.length; index++) {
      final task = proposal.taskUpdates[index];
      if (!existingBacklogById.containsKey(task.id)) {
        issue(
          'immutable_or_unknown_task',
          'taskUpdates[$index].id',
          'Only an existing backlog task may be updated.',
        );
      }
    }
    final existingTaskIds = {
      ...project.backlog.map((item) => item.id),
      ...project.completedTasks.map((item) => item.id),
      ...project.failedTasks.map((item) => item.id),
      if (project.currentTask != null) project.currentTask!.id,
    };
    for (var index = 0; index < proposal.taskAdditions.length; index++) {
      final task = proposal.taskAdditions[index];
      if (existingTaskIds.contains(task.id)) {
        issue(
          'duplicate_task_id',
          'taskAdditions[$index].id',
          'Task ID ${task.id} already exists.',
        );
      }
    }
    final additionIds = proposal.taskAdditions.map((item) => item.id).toSet();
    for (var index = 0; index < proposal.taskUpdates.length; index++) {
      if (additionIds.contains(proposal.taskUpdates[index].id)) {
        issue(
          'duplicate_id',
          'taskUpdates[$index].id',
          'A task cannot be both added and updated in one revision.',
        );
      }
    }
    for (final entry in <(String, List<String>)>[
      ('deferredTaskIds', proposal.deferredTaskIds),
      ('obsoleteTaskIds', proposal.obsoleteTaskIds),
    ]) {
      for (var index = 0; index < entry.$2.length; index++) {
        if (!existingBacklogById.containsKey(entry.$2[index])) {
          issue(
            'immutable_or_unknown_task',
            '${entry.$1}[$index]',
            'Only an existing backlog task may be ${entry.$1 == 'deferredTaskIds' ? 'deferred' : 'made obsolete'}.',
          );
        }
      }
    }

    final changedTasks = [...proposal.taskAdditions, ...proposal.taskUpdates];
    final changedTaskPaths = <String>[
      for (var i = 0; i < proposal.taskAdditions.length; i++)
        'taskAdditions[$i]',
      for (var i = 0; i < proposal.taskUpdates.length; i++) 'taskUpdates[$i]',
    ];
    final knownTaskIds = {
      ...existingTaskIds,
      ...proposal.taskAdditions.map((item) => item.id),
    };
    final existingFingerprintOwners = <String, ProjectTask>{
      for (final task in [
        ...project.backlog,
        ...project.completedTasks,
        ...project.failedTasks,
        ?project.currentTask,
      ])
        task.fingerprint: task,
    };
    final proposalFingerprints = <String, String>{};
    for (var index = 0; index < changedTasks.length; index++) {
      final task = changedTasks[index];
      final fieldPath = changedTaskPaths[index];
      if (task.id.trim().isEmpty) {
        issue('missing_id', '$fieldPath.id', 'Task ID is required.');
      }
      if (task.objective.trim().isEmpty) {
        issue(
          'missing_objective',
          '$fieldPath.objective',
          'Objective is required.',
        );
      }
      if (_normalise(task.objective) == _normalise(project.refinedGoal)) {
        issue(
          'task_equals_project_goal',
          '$fieldPath.objective',
          'A task cannot be equivalent to the entire project goal.',
        );
      }
      if (RegExp(
        r'\b(entire project|whole project|complete the project|finish the project|implement all|end[ -]to[ -]end)\b',
        caseSensitive: false,
      ).hasMatch(task.objective)) {
        issue(
          'task_equals_project_goal',
          '$fieldPath.objective',
          'A task cannot represent the entire project scope.',
        );
      }
      if (task.doneCriteria.isEmpty) {
        issue(
          'missing_done_criteria',
          '$fieldPath.doneCriteria',
          'At least one done criterion is required.',
        );
      }
      if (task.outOfScope.isEmpty) {
        issue(
          'missing_boundary',
          '$fieldPath.outOfScope',
          'At least one explicit out-of-scope boundary is required.',
        );
      }
      if (task.expectedEvidence.isEmpty && task.expectedArtifacts.isEmpty) {
        issue(
          'missing_expected_verification',
          '$fieldPath.expectedEvidence',
          'Expected evidence or a verifiable artifact is required.',
        );
      }
      if (task.recoveryIncidentId == null && task.criterionIds.isEmpty) {
        issue(
          'missing_criterion_link',
          '$fieldPath.criterionIds',
          'A project task must link to at least one project criterion.',
        );
      }
      if (task.dependsOnTaskIds.contains(task.id)) {
        issue(
          'self_dependency',
          '$fieldPath.dependsOnTaskIds',
          'Task ${task.id} cannot depend on itself.',
        );
      }
      for (
        var dependencyIndex = 0;
        dependencyIndex < task.dependsOnTaskIds.length;
        dependencyIndex++
      ) {
        final dependencyId = task.dependsOnTaskIds[dependencyIndex];
        if (!knownTaskIds.contains(dependencyId)) {
          issue(
            'missing_dependency',
            '$fieldPath.dependsOnTaskIds[$dependencyIndex]',
            'Dependency $dependencyId does not exist.',
          );
        }
      }
      for (
        var criterionIndex = 0;
        criterionIndex < task.criterionIds.length;
        criterionIndex++
      ) {
        final criterionId = task.criterionIds[criterionIndex];
        if (!proposedCriterionIds.contains(criterionId)) {
          issue(
            'unknown_criterion',
            '$fieldPath.criterionIds[$criterionIndex]',
            'Criterion $criterionId does not exist in the proposed plan.',
          );
        }
      }
      final expectationIds = <String>{};
      for (
        var expectationIndex = 0;
        expectationIndex < task.expectedEvidence.length;
        expectationIndex++
      ) {
        final expectation = task.expectedEvidence[expectationIndex];
        final expectationPath =
            '$fieldPath.expectedEvidence[$expectationIndex]';
        if (!expectationIds.add(expectation.id)) {
          issue(
            'duplicate_evidence_expectation',
            '$expectationPath.id',
            'Evidence expectation ID ${expectation.id} is duplicated in task ${task.id}.',
          );
        }
        if (expectation.description.trim().isEmpty) {
          issue(
            'missing_evidence_description',
            '$expectationPath.description',
            'Evidence expectation ${expectation.id} needs a description.',
          );
        }
        if (expectation.criterionIds.isEmpty) {
          issue(
            'missing_evidence_criterion',
            '$expectationPath.criterionIds',
            'Evidence expectation ${expectation.id} must link to a task criterion.',
          );
        }
        for (
          var criterionIndex = 0;
          criterionIndex < expectation.criterionIds.length;
          criterionIndex++
        ) {
          final criterionId = expectation.criterionIds[criterionIndex];
          if (!proposedCriterionIds.contains(criterionId)) {
            issue(
              'unknown_evidence_criterion',
              '$expectationPath.criterionIds[$criterionIndex]',
              'Evidence expectation ${expectation.id} references unknown criterion $criterionId.',
            );
          } else if (!task.criterionIds.contains(criterionId)) {
            issue(
              'unlinked_evidence_criterion',
              '$expectationPath.criterionIds[$criterionIndex]',
              'Evidence expectation ${expectation.id} references criterion $criterionId outside task ${task.id}.',
            );
          }
        }
      }
      if (task.milestoneId != null &&
          !proposedMilestoneIds.contains(task.milestoneId)) {
        issue(
          'unknown_milestone',
          '$fieldPath.milestoneId',
          'Milestone ${task.milestoneId} does not exist in the proposed plan.',
        );
      }
      for (final entry in [...task.readPaths, ...task.writePaths]) {
        if (!_isInsideWorkspace(workspaceRoot, entry)) {
          issue(
            'path_outside_workspace',
            fieldPath,
            'Path "$entry" resolves outside the attached workspace.',
          );
        }
      }
      if (task.effort == ProjectTaskEffort.small &&
          task.expectedArtifacts.isNotEmpty &&
          task.writePaths.isEmpty &&
          !task.legacyWriteAccess) {
        issue(
          'missing_write_paths',
          '$fieldPath.writePaths',
          'Small tasks that produce workspace artifacts must declare write paths.',
        );
      }

      final existing = existingFingerprintOwners[task.fingerprint];
      if (existing != null && existing.id != task.id) {
        final retryContext = task.context.any(
          (item) => RegExp(
            r'\b(retry|recovery|follow-up)\b',
            caseSensitive: false,
          ).hasMatch(item),
        );
        if (existing.status != ProjectTaskStatus.failed || !retryContext) {
          issue(
            'duplicate_work',
            '$fieldPath.fingerprint',
            'Equivalent work already exists as ${existing.id}.',
          );
        }
      }
      final proposalOwner = proposalFingerprints[task.fingerprint];
      if (proposalOwner != null && proposalOwner != task.id) {
        issue(
          'duplicate_work',
          '$fieldPath.fingerprint',
          'Equivalent work is already proposed as $proposalOwner.',
        );
      }
      proposalFingerprints[task.fingerprint] = task.id;
    }

    final updatedTasksById = {
      for (final task in proposal.taskUpdates) task.id: task,
    };
    for (final existing in project.backlog) {
      if (proposal.obsoleteTaskIds.contains(existing.id)) continue;
      final effective = updatedTasksById[existing.id] ?? existing;
      for (final removedId in proposal.removedCriterionIds) {
        if (effective.criterionIds.contains(removedId)) {
          issue(
            'removed_criterion_still_in_use',
            'removedCriterionIds',
            'Criterion $removedId is still linked by queued task ${existing.id}; update or obsolete that task in the same revision.',
          );
        }
      }
      final removedMilestoneId = effective.milestoneId;
      if (removedMilestoneId != null &&
          proposal.removedMilestoneIds.contains(removedMilestoneId)) {
        issue(
          'removed_milestone_still_in_use',
          'removedMilestoneIds',
          'Milestone $removedMilestoneId is still linked by queued task ${existing.id}; update or obsolete that task in the same revision.',
        );
      }
    }

    final taskGraph = <String, List<String>>{
      for (final task in project.backlog) task.id: task.dependsOnTaskIds,
      for (final task in proposal.taskUpdates) task.id: task.dependsOnTaskIds,
      for (final task in proposal.taskAdditions) task.id: task.dependsOnTaskIds,
    };
    if (_hasCycle(taskGraph)) {
      issue(
        'cyclic_dependencies',
        'taskAdditions',
        'The proposed task dependency graph contains a cycle.',
      );
    }

    final existingMemoryIds = project.memory.map((item) => item.id).toSet();
    final additionMemoryIds = proposal.memoryAdditions
        .map((item) => item.id)
        .toSet();
    for (var index = 0; index < proposal.memoryAdditions.length; index++) {
      if (existingMemoryIds.contains(proposal.memoryAdditions[index].id)) {
        issue(
          'duplicate_id',
          'memoryAdditions[$index].id',
          'Memory ID ${proposal.memoryAdditions[index].id} already exists.',
        );
      }
    }
    for (var index = 0; index < proposal.memorySupersessions.length; index++) {
      final edit = proposal.memorySupersessions[index];
      final target = project.memory
          .where((item) => item.id == edit.entryId)
          .firstOrNull;
      if (target == null) {
        issue(
          'unknown_memory',
          'memorySupersessions[$index].entryId',
          'Memory ${edit.entryId} does not exist.',
        );
      } else if (target.protected) {
        issue(
          'protected_memory_mutation',
          'memorySupersessions[$index].entryId',
          'Protected user memory ${edit.entryId} cannot be superseded by the planner.',
        );
      }
      if (!existingMemoryIds.contains(edit.supersededById) &&
          !additionMemoryIds.contains(edit.supersededById)) {
        issue(
          'unknown_memory',
          'memorySupersessions[$index].supersededById',
          'Replacement memory ${edit.supersededById} does not exist.',
        );
      }
    }

    final readyAfterProposal =
        [
          ...project.backlog.where(
            (task) =>
                !proposal.deferredTaskIds.contains(task.id) &&
                !proposal.obsoleteTaskIds.contains(task.id),
          ),
          ...proposal.taskAdditions,
        ].where((task) {
          return task.status == ProjectTaskStatus.queued &&
              task.readiness == ProjectTaskReadiness.ready;
        }).length;
    if (readyAfterProposal > planningHorizon &&
        !proposal.rationale.toLowerCase().contains('horizon')) {
      issue(
        'planning_horizon_exceeded',
        'taskAdditions',
        '$readyAfterProposal ready tasks exceed the horizon of $planningHorizon without justification.',
      );
    }

    return ProjectPlanValidationResult(issues);
  }

  static void _validateUniqueIds(
    Iterable<String> ids,
    String fieldPath,
    List<ProjectPlanValidationIssue> issues,
  ) {
    final seen = <String>{};
    var index = 0;
    for (final id in ids) {
      if (id.trim().isEmpty) {
        issues.add(
          ProjectPlanValidationIssue(
            code: 'missing_id',
            path: '$fieldPath[$index].id',
            message: 'A stable ID is required.',
          ),
        );
      } else if (!seen.add(id)) {
        issues.add(
          ProjectPlanValidationIssue(
            code: 'duplicate_id',
            path: '$fieldPath[$index].id',
            message: 'Stable ID $id appears more than once.',
          ),
        );
      }
      index++;
    }
  }

  static bool _isInsideWorkspace(String workspaceRoot, String candidate) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) return true;
    final root = path.normalize(path.absolute(workspaceRoot));
    final resolved = path.normalize(
      path.isAbsolute(trimmed) ? trimmed : path.join(root, trimmed),
    );
    return resolved == root || path.isWithin(root, resolved);
  }

  static bool _hasCycle(Map<String, List<String>> graph) {
    final visiting = <String>{};
    final visited = <String>{};
    bool visit(String id) {
      if (visiting.contains(id)) return true;
      if (!visited.add(id)) return false;
      visiting.add(id);
      for (final dependency in graph[id] ?? const <String>[]) {
        if (graph.containsKey(dependency) && visit(dependency)) return true;
      }
      visiting.remove(id);
      return false;
    }

    return graph.keys.any(visit);
  }

  static String _normalise(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}
