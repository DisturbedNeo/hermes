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

/// Validates a complete desired plan without changing either input.
class ProjectPlanValidator {
  const ProjectPlanValidator({this.planningHorizon = 7});

  final int planningHorizon;

  ProjectPlanValidationResult validate({
    required ProjectState project,
    required ProjectDesiredPlan proposal,
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

    if (proposal.revision != project.nextRevision) {
      issue(
        'revision_mismatch',
        'revision',
        'Expected revision ${project.nextRevision}.',
      );
    }

    if (!proposal.hasCompleteCollections) {
      issue(
        'incomplete_plan',
        'plan',
        'The planner response did not provide complete criteria, milestone, and task collections.',
      );
    }

    _validateUniqueIds(
      proposal.criteria.map((item) => item.id),
      'criteria',
      issues,
    );
    _validateUniqueIds(
      proposal.milestones.map((item) => item.id),
      'milestones',
      issues,
    );
    _validateUniqueIds(proposal.tasks.map((item) => item.id), 'tasks', issues);
    _validateUniqueIds(
      proposal.memoryAdditions.map((item) => item.id),
      'memoryAdditions',
      issues,
    );

    final existingMemory = {
      for (final entry in project.memory) entry.id: entry,
    };
    final additionIds = proposal.memoryAdditions.map((item) => item.id).toSet();
    for (var index = 0; index < proposal.memoryAdditions.length; index++) {
      final entry = proposal.memoryAdditions[index];
      final fieldPath = 'memoryAdditions[$index]';
      if (entry.content.trim().isEmpty) {
        issue(
          'empty_memory_addition',
          '$fieldPath.content',
          'Memory additions must contain non-empty content.',
        );
      }
      if (existingMemory.containsKey(entry.id)) {
        issue(
          'memory_id_collision',
          '$fieldPath.id',
          'Memory ID ${entry.id} already exists in the project.',
        );
      }
    }

    final supersededSources = <String>{};
    for (var index = 0; index < proposal.memorySupersessions.length; index++) {
      final edit = proposal.memorySupersessions[index];
      final fieldPath = 'memorySupersessions[$index]';
      if (edit.entryId.trim().isEmpty) {
        issue(
          'missing_memory_source',
          '$fieldPath.entryId',
          'A memory supersession needs a source entry ID.',
        );
      }
      if (edit.supersededById.trim().isEmpty) {
        issue(
          'missing_memory_replacement',
          '$fieldPath.supersededById',
          'A memory supersession needs a replacement entry ID.',
        );
      }
      if (edit.entryId == edit.supersededById) {
        issue(
          'self_memory_supersession',
          fieldPath,
          'A memory entry cannot supersede itself.',
        );
      }
      if (!supersededSources.add(edit.entryId)) {
        issue(
          'duplicate_memory_supersession',
          '$fieldPath.entryId',
          'Memory entry ${edit.entryId} is superseded more than once.',
        );
      }
      final source = existingMemory[edit.entryId];
      if (source == null) {
        issue(
          'missing_memory_source',
          '$fieldPath.entryId',
          'Memory source ${edit.entryId} does not exist in the project.',
        );
      } else {
        if (!source.active) {
          issue(
            'inactive_memory_source',
            '$fieldPath.entryId',
            'Memory source ${edit.entryId} is already inactive.',
          );
        }
        if (source.protected) {
          issue(
            'protected_memory_source',
            '$fieldPath.entryId',
            'Protected memory ${edit.entryId} cannot be superseded by the planner.',
          );
        }
      }
      if (!existingMemory.containsKey(edit.supersededById) &&
          !additionIds.contains(edit.supersededById)) {
        issue(
          'missing_memory_replacement',
          '$fieldPath.supersededById',
          'Replacement memory ${edit.supersededById} does not exist in the project or additions.',
        );
      }
    }

    final criterionIds = proposal.criteria.map((item) => item.id).toSet();
    for (var index = 0; index < proposal.criteria.length; index++) {
      if (proposal.criteria[index].statement.trim().isEmpty) {
        issue(
          'missing_criterion_statement',
          'criteria[$index].statement',
          'Criterion ${proposal.criteria[index].id} needs a non-empty statement.',
        );
      }
    }
    for (final existing in project.criteria) {
      if (!criterionIds.contains(existing.id) && existing.required) {
        if (!proposal.requiresApproval) {
          issue(
            'required_criterion_removal',
            'criteria',
            'Required criterion ${existing.id} cannot be removed without approval.',
          );
        } else {
          issues.add(
            ProjectPlanValidationIssue(
              code: 'scope_decision_requires_approval',
              path: 'criteria',
              message:
                  'Removing required criterion ${existing.id} remains pending until approval.',
              severity: ProjectPlanValidationSeverity.warning,
            ),
          );
        }
      }
    }

    final milestoneIds = proposal.milestones.map((item) => item.id).toSet();
    for (
      var milestoneIndex = 0;
      milestoneIndex < proposal.milestones.length;
      milestoneIndex++
    ) {
      final milestone = proposal.milestones[milestoneIndex];
      for (
        var criterionIndex = 0;
        criterionIndex < milestone.criterionIds.length;
        criterionIndex++
      ) {
        final criterionId = milestone.criterionIds[criterionIndex];
        if (!criterionIds.contains(criterionId)) {
          issue(
            'unknown_criterion',
            'milestones[$milestoneIndex].criterionIds[$criterionIndex]',
            'Criterion $criterionId does not exist in the desired plan.',
          );
        }
      }
    }

    final existingTasks = {for (final task in project.tasks) task.id: task};
    final desiredTasks = {for (final task in proposal.tasks) task.id: task};
    final mutableTaskIds = {
      for (final task in project.tasks)
        if (task.status == TaskStatus.queued ||
            task.status == TaskStatus.deferred ||
            task.status == TaskStatus.obsolete)
          task.id,
    };
    for (final entry in <(String, List<String>)>[
      ('deferredTaskIds', proposal.deferredTaskIds),
      ('obsoleteTaskIds', proposal.obsoleteTaskIds),
    ]) {
      final seen = <String>{};
      for (var index = 0; index < entry.$2.length; index++) {
        final taskId = entry.$2[index];
        final fieldPath = '${entry.$1}[$index]';
        if (!seen.add(taskId)) {
          issue(
            'duplicate_task_disposition',
            fieldPath,
            'Task $taskId appears more than once in ${entry.$1}.',
          );
        }
        if (!existingTasks.containsKey(taskId) &&
            !desiredTasks.containsKey(taskId)) {
          issue(
            'unknown_task_disposition',
            fieldPath,
            'Task $taskId does not exist in the current or desired plan.',
          );
        } else if (existingTasks.containsKey(taskId) &&
            !mutableTaskIds.contains(taskId)) {
          issue(
            'immutable_task_disposition',
            fieldPath,
            'Task $taskId cannot be deferred or made obsolete from its current runtime status.',
          );
        }
      }
    }
    final conflictingDispositions = proposal.deferredTaskIds
        .toSet()
        .intersection(proposal.obsoleteTaskIds.toSet());
    for (final taskId in conflictingDispositions) {
      issue(
        'conflicting_task_disposition',
        'deferredTaskIds',
        'Task $taskId cannot be both deferred and made obsolete.',
      );
    }
    final existingFingerprints = <String, String>{
      for (final task in project.tasks)
        if (task.recoveryIncidentId == null) task.fingerprint: task.id,
      for (final decision in project.decisions)
        if (decision.taskPrompt?.trim().isNotEmpty == true)
          projectTaskFingerprint(decision.taskPrompt!, const []):
              'previous_decision',
    };
    final desiredFingerprints = <String, String>{};
    final allExpectationIds = <String>{};
    final expectationSignatures = <String, String>{};
    for (var index = 0; index < proposal.tasks.length; index++) {
      final task = proposal.tasks[index];
      final fieldPath = 'tasks[$index]';
      final existing = existingTasks[task.id];
      if (existing != null &&
          (existing.status == TaskStatus.completed ||
              existing.status == TaskStatus.failed ||
              existing.status == TaskStatus.rejected ||
              existing.status == TaskStatus.split ||
              existing.status == TaskStatus.cancelled)) {
        issue(
          'immutable_runtime_task',
          '$fieldPath.id',
          'Terminal task ${task.id} cannot be replaced by a plan.',
        );
      }
      if (task.status != TaskStatus.queued &&
          task.status != TaskStatus.deferred &&
          task.status != TaskStatus.obsolete) {
        issue(
          'invalid_desired_task_status',
          '$fieldPath.status',
          'Desired tasks may only be queued, deferred, or obsolete.',
        );
      }
      if (task.objective.trim().isEmpty) {
        issue(
          'missing_objective',
          '$fieldPath.objective',
          'Objective is required.',
        );
      }
      if (_normalise(task.objective) == _normalise(project.refinedGoal) ||
          RegExp(
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
          'A task must link to at least one project criterion.',
        );
      }
      if (task.recoveryIncidentId == null) {
        final previousOwner = existingFingerprints[task.fingerprint];
        if (previousOwner != null && previousOwner != task.id) {
          issue(
            'duplicate_work',
            '$fieldPath.fingerprint',
            'Task ${task.id} duplicates existing ordinary work${previousOwner == 'previous_decision' ? '' : ' ($previousOwner)'}.',
          );
        }
        final desiredOwner = desiredFingerprints[task.fingerprint];
        if (desiredOwner != null) {
          issue(
            'duplicate_work',
            '$fieldPath.fingerprint',
            'Task ${task.id} duplicates desired task $desiredOwner.',
          );
        } else {
          desiredFingerprints[task.fingerprint] = task.id;
        }
      }
      for (
        var dependencyIndex = 0;
        dependencyIndex < task.dependsOnTaskIds.length;
        dependencyIndex++
      ) {
        final dependencyId = task.dependsOnTaskIds[dependencyIndex];
        if (dependencyId == task.id) {
          issue(
            'self_dependency',
            '$fieldPath.dependsOnTaskIds[$dependencyIndex]',
            'Task ${task.id} cannot depend on itself.',
          );
        } else if (desiredTasks.containsKey(dependencyId)) {
          if (proposal.deferredTaskIds.contains(dependencyId) ||
              proposal.obsoleteTaskIds.contains(dependencyId)) {
            issue(
              'dead_dependency',
              '$fieldPath.dependsOnTaskIds[$dependencyIndex]',
              'Dependency $dependencyId is deferred or obsolete in the effective plan.',
            );
          }
        } else if (existingTasks[dependencyId]?.status ==
            TaskStatus.completed) {
          // Completed historical work is a valid dependency without being
          // repeated in the desired plan.
        } else if (existingTasks.containsKey(dependencyId)) {
          issue(
            'dead_dependency',
            '$fieldPath.dependsOnTaskIds[$dependencyIndex]',
            'Dependency $dependencyId will not be completed by the effective plan.',
          );
        } else {
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
        if (!criterionIds.contains(criterionId)) {
          issue(
            'unknown_criterion',
            '$fieldPath.criterionIds[$criterionIndex]',
            'Criterion $criterionId does not exist in the desired plan.',
          );
        }
      }
      if (task.milestoneId != null &&
          !milestoneIds.contains(task.milestoneId)) {
        issue(
          'unknown_milestone',
          '$fieldPath.milestoneId',
          'Milestone ${task.milestoneId} does not exist in the desired plan.',
        );
      }
      final taskExpectationIds = <String>{};
      for (
        var expectationIndex = 0;
        expectationIndex < task.expectedEvidence.length;
        expectationIndex++
      ) {
        final expectation = task.expectedEvidence[expectationIndex];
        final expectationPath =
            '$fieldPath.expectedEvidence[$expectationIndex]';
        if (!taskExpectationIds.add(expectation.id) ||
            !allExpectationIds.add(expectation.id)) {
          issue(
            'duplicate_evidence_expectation',
            '$expectationPath.id',
            'Evidence expectation ${expectation.id} is duplicated.',
          );
        }
        final expectationSignature =
            '${task.id}|${expectation.type.name}|${_normalise(expectation.sourceRef ?? '')}|'
            '${([...expectation.criterionIds]..sort()).join(',')}';
        final previousExpectation = expectationSignatures[expectationSignature];
        if (previousExpectation != null) {
          issue(
            'ambiguous_evidence_expectation',
            expectationPath,
            'Evidence expectation duplicates the matching signature of $previousExpectation.',
          );
        } else {
          expectationSignatures[expectationSignature] = expectation.id;
        }
        if (expectation.description.trim().isEmpty ||
            expectation.criterionIds.isEmpty) {
          issue(
            'invalid_evidence_expectation',
            expectationPath,
            'Evidence expectations need a description and criterion link.',
          );
        }
        for (final criterionId in expectation.criterionIds) {
          if (!criterionIds.contains(criterionId) ||
              !task.criterionIds.contains(criterionId)) {
            issue(
              'unlinked_evidence_criterion',
              expectationPath,
              'Evidence expectation $criterionId is not linked to task ${task.id}.',
            );
          }
        }
        if (expectation.required &&
            expectation.type == ProjectEvidenceType.command) {
          final command = expectation.sourceRef?.trim() ?? '';
          final workingDirectory = _workingDirectoryForExpectation(expectation);
          final matchingGate =
              [...task.gates, for (final step in task.steps) ...step.gates].any(
                (gate) =>
                    gate.id == 'command_passes' &&
                    gate.params['command']?.toString() == command &&
                    gate.params['working_directory']?.toString() ==
                        workingDirectory,
              );
          if (!matchingGate) {
            issue(
              'missing_command_passes_gate',
              expectationPath,
              'Required command evidence must have a matching command_passes gate with command "$command" and working directory "$workingDirectory".',
            );
          }
        }
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
      if (task.effort == TaskEffort.small &&
          task.expectedArtifacts.isNotEmpty &&
          task.writePaths.isEmpty &&
          !task.legacyWriteAccess) {
        issue(
          'missing_write_paths',
          '$fieldPath.writePaths',
          'Small artifact-producing tasks must declare write paths.',
        );
      }
    }

    for (var index = 0; index < proposal.criteria.length; index++) {
      final criterion = proposal.criteria[index];
      if (criterion.status == ProjectCriterionStatus.satisfied ||
          criterion.verificationMode != ProjectVerificationMode.deterministic) {
        continue;
      }
      final hasConclusiveExpectation = proposal.tasks.any(
        (task) =>
            !proposal.deferredTaskIds.contains(task.id) &&
            !proposal.obsoleteTaskIds.contains(task.id) &&
            task.expectedEvidence.any(
              (expectation) =>
                  expectation.required &&
                  expectation.criterionIds.contains(criterion.id) &&
                  (expectation.type == ProjectEvidenceType.gate ||
                      expectation.type == ProjectEvidenceType.command),
            ),
      );
      if (!hasConclusiveExpectation) {
        issue(
          'impossible_deterministic_verification',
          'criteria[$index]',
          'Deterministic criterion ${criterion.id} needs a required gate or command evidence expectation.',
        );
      }
    }

    final graph = <String, List<String>>{
      for (final entry in existingTasks.entries)
        entry.key:
            desiredTasks[entry.key]?.dependsOnTaskIds ??
            entry.value.dependsOnTaskIds,
      for (final task in proposal.tasks) task.id: task.dependsOnTaskIds,
    };
    if (_hasCycle(graph)) {
      issue(
        'cyclic_dependencies',
        'tasks',
        'The desired task dependency graph contains a cycle.',
      );
    }

    final readyCount = proposal.tasks
        .where(
          (task) =>
              task.status == TaskStatus.queued &&
              !proposal.deferredTaskIds.contains(task.id) &&
              !proposal.obsoleteTaskIds.contains(task.id),
        )
        .length;
    if (readyCount > planningHorizon &&
        !proposal.rationale.toLowerCase().contains('horizon')) {
      issue(
        'planning_horizon_exceeded',
        'tasks',
        '$readyCount queued tasks exceed the horizon of $planningHorizon without justification.',
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

  static bool _isInsideWorkspace(String workspaceRoot, String value) {
    final candidate = path.normalize(path.absolute(workspaceRoot, value));
    final root = path.normalize(path.absolute(workspaceRoot));
    return candidate == root || path.isWithin(root, candidate);
  }

  static bool _hasCycle(Map<String, List<String>> graph) {
    final states = <String, int>{};
    bool visit(String id) {
      final state = states[id] ?? 0;
      if (state == 1) return true;
      if (state == 2) return false;
      states[id] = 1;
      for (final dependency in graph[id] ?? const <String>[]) {
        if (graph.containsKey(dependency) && visit(dependency)) return true;
      }
      states[id] = 2;
      return false;
    }

    for (final id in graph.keys) {
      if (visit(id)) return true;
    }
    return false;
  }

  static String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _workingDirectoryForExpectation(
    TaskEvidenceExpectation expectation,
  ) {
    final value = expectation.details['working_directory']?.toString().trim();
    return value == null || value.isEmpty ? '.' : value;
  }
}
