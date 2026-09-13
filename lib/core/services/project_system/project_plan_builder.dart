import 'dart:convert';

import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/project_system/project_plan_revision_service.dart';
import 'package:hermes/core/services/project_system/project_plan_validator.dart';

/// A structured error returned by a draft command before commit.
class ProjectPlanBuilderException implements Exception {
  final String code;
  final String path;
  final String message;

  const ProjectPlanBuilderException({
    required this.code,
    required this.path,
    required this.message,
  });

  @override
  String toString() => '$code${path.isEmpty ? '' : ' ($path)'}: $message';
}

/// The model-facing shape of a task creation request.
///
/// IDs, statuses, timestamps, fingerprints, gates, and evidence expectation
/// IDs are intentionally absent. The builder owns those values.
class ProjectPlanTaskSpec {
  final String ref;
  final String title;
  final String objective;
  final List<String> criterionRefs;
  final List<String> dependencyRefs;
  final String? milestoneRef;
  final TaskPriority priority;
  final TaskRisk risk;
  final ProjectRiskReduction riskReduction;
  final TaskEffort effort;
  final String selectionRationale;
  final List<String> constraints;
  final List<String> readPaths;
  final List<String> writePaths;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<String> context;
  final List<TaskArtifact> expectedArtifacts;

  const ProjectPlanTaskSpec({
    this.ref = '',
    this.title = '',
    this.objective = '',
    this.criterionRefs = const [],
    this.dependencyRefs = const [],
    this.milestoneRef,
    this.priority = TaskPriority.normal,
    this.risk = TaskRisk.unknown,
    this.riskReduction = ProjectRiskReduction.none,
    this.effort = TaskEffort.small,
    this.selectionRationale = '',
    this.constraints = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.context = const [],
    this.expectedArtifacts = const [],
  });
}

enum ProjectPlanTaskDisposition { deferred, obsolete }

class ProjectPlanBuilderCommit {
  final ProjectDesiredPlan proposal;
  final ProjectPlanRevisionResult result;

  const ProjectPlanBuilderCommit({
    required this.proposal,
    required this.result,
  });

  ProjectState get project => result.project;
  ProjectPlanValidationResult get validation => result.validation;
}

class ProjectPlanBuilderPreview {
  final ProjectDesiredPlan proposal;
  final ProjectPlanValidationResult validation;

  const ProjectPlanBuilderPreview({
    required this.proposal,
    required this.validation,
  });
}

/// Builds a complete desired plan without exposing persistence fields to the
/// caller. The base project is never mutated; only [commit] produces a plan
/// and sends it through the existing validator and revision service.
class ProjectPlanBuilder {
  ProjectPlanBuilder({
    required ProjectState project,
    DateTime? now,
    Iterable<ProjectPlanRevisionTrigger> triggers = const [],
    String summary = 'Apply the incremental plan update.',
    String rationale = 'Keep the project plan bounded and actionable.',
    bool requiresApproval = false,
    String approvalReason = '',
    ProjectPlanRevisionService revisionService =
        const ProjectPlanRevisionService(),
  }) : _project = project,
       _now = now ?? DateTime.now(),
       _validationRefinedGoal = project.refinedGoal,
       _triggers = triggers.isEmpty
           ? [ProjectPlanRevisionTrigger.manual]
           : [...triggers],
       _summary = _requiredText(summary, 'summary'),
       _rationale = _requiredText(rationale, 'rationale'),
       _requiresApproval = requiresApproval,
       _approvalReason = approvalReason.trim(),
       _revisionService = revisionService {
    for (final criterion in project.criteria) {
      _criteria[criterion.id] = criterion;
      _criterionRefs[criterion.id] = criterion.id;
    }
    for (final milestone in project.milestones) {
      _milestones[milestone.id] = milestone;
      _milestoneRefs[milestone.id] = milestone.id;
    }
    for (final task in project.tasks) {
      _taskCatalog[task.id] = task;
      _taskRefs[task.id] = task.id;
      if (!_isTerminal(task)) _tasks[task.id] = task;
    }
  }

  final ProjectState _project;
  final DateTime _now;
  String _validationRefinedGoal;
  final List<ProjectPlanRevisionTrigger> _triggers;
  final ProjectPlanRevisionService _revisionService;
  final Map<String, ProjectCriterion> _criteria = {};
  final Map<String, ProjectMilestone> _milestones = {};
  final Map<String, Task> _tasks = {};
  final Map<String, Task> _taskCatalog = {};
  final Map<String, String> _criterionRefs = {};
  final Map<String, String> _milestoneRefs = {};
  final Map<String, String> _taskRefs = {};
  final Set<String> _deferredTaskIds = {};
  final Set<String> _obsoleteTaskIds = {};
  final Set<String> _splitTaskIds = {};
  final List<ProjectMemoryEntry> _memoryAdditions = [];
  final List<PendingProjectQuestion> _openQuestions = [];
  final Map<String, _AppliedCommand> _commands = {};
  String _summary;
  String _rationale;
  final bool _requiresApproval;
  final String _approvalReason;

  String get summary => _summary;
  String get rationale => _rationale;
  List<ProjectPlanRevisionTrigger> get triggers => List.unmodifiable(_triggers);
  List<String> get splitTaskIds => List.unmodifiable(_splitTaskIds);

  void setValidationRefinedGoal(String refinedGoal) {
    _validationRefinedGoal = refinedGoal.trim();
  }

  void setSummary(String summary) {
    _summary = _requiredText(summary, 'summary');
  }

  void setRationale(String rationale) {
    _rationale = _requiredText(rationale, 'rationale');
  }

  String criterionIdFor(String reference) => _resolveCriterion(reference);

  String milestoneIdFor(String reference) => _resolveMilestone(reference);

  String taskIdFor(String reference) => _resolveTask(reference);

  /// Runs several draft operations as one atomic command. Batch planning
  /// tools use this so a later invalid item cannot leave earlier items from
  /// the same model call behind.
  T transaction<T>(T Function() action) => _atomic(action);

  String addCriterion({
    required String statement,
    String ref = '',
    bool required = true,
    ProjectVerificationMode verificationMode = ProjectVerificationMode.mixed,
    String? commandId,
  }) {
    final text = statement.trim();
    final fingerprint = _encode({
      'op': 'add_criterion',
      'statement': text,
      'ref': ref.trim(),
      'required': required,
      'verificationMode': verificationMode.name,
    });
    return _idempotent(commandId, fingerprint, () {
      if (text.isEmpty) {
        throw _error(
          'missing_criterion_statement',
          'statement',
          'A criterion statement is required.',
        );
      }
      return _atomic(() {
        final reference = _claimReference(
          ref,
          namespace: 'criterion',
          fallback: 'criterion',
        );
        final id = _newId('criterion', _criteria.keys);
        final criterion = ProjectCriterion(
          id: id,
          statement: text,
          required: required,
          verificationMode: verificationMode,
          createdAt: _now,
          updatedAt: _now,
          verifiedAt: null,
        );
        _criteria[id] = criterion;
        _criterionRefs[reference] = id;
        _criterionRefs[id] = id;
        return id;
      });
    });
  }

  String addMilestone({
    required String title,
    required String objective,
    Iterable<String> criterionRefs = const [],
    Iterable<String> exitConditions = const [],
    String ref = '',
    int? order,
    String? commandId,
  }) {
    final milestoneTitle = title.trim();
    final milestoneObjective = objective.trim();
    final fingerprint = _encode({
      'op': 'add_milestone',
      'title': milestoneTitle,
      'objective': milestoneObjective,
      'criterionRefs': [...criterionRefs],
      'exitConditions': [...exitConditions],
      'ref': ref.trim(),
      'order': order,
    });
    return _idempotent(commandId, fingerprint, () {
      if (milestoneTitle.isEmpty || milestoneObjective.isEmpty) {
        throw _error(
          'invalid_milestone',
          'milestone',
          'A milestone needs a title and objective.',
        );
      }
      return _atomic(() {
        final reference = _claimReference(
          ref,
          namespace: 'milestone',
          fallback: 'milestone',
        );
        final id = _newId('milestone', _milestones.keys);
        final criterionIds = _resolveReferences(
          criterionRefs,
          _resolveCriterion,
          'criterionRefs',
        );
        final conditions = _cleanStrings(exitConditions);
        final milestone = ProjectMilestone(
          id: id,
          title: milestoneTitle,
          objective: milestoneObjective,
          criterionIds: criterionIds,
          exitConditions: conditions.isEmpty
              ? [milestoneObjective]
              : conditions,
          order: order ?? _nextMilestoneOrder(),
          status: ProjectMilestoneStatus.planned,
          createdAt: _now,
          updatedAt: _now,
        );
        _milestones[id] = milestone;
        _milestoneRefs[reference] = id;
        _milestoneRefs[id] = id;
        return id;
      });
    });
  }

  String addTask(ProjectPlanTaskSpec spec, {String? commandId}) {
    return addTasks([spec], commandId: commandId).single;
  }

  List<String> addTasks(
    Iterable<ProjectPlanTaskSpec> specs, {
    String? commandId,
  }) {
    final items = [...specs];
    final fingerprint = _encode({
      'op': 'add_tasks',
      'tasks': [for (final spec in items) _specMap(spec)],
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() => _addTasksInternal(items));
    });
  }

  Task updateTask(
    String taskReference, {
    String? title,
    String? objective,
    Iterable<String>? criterionRefs,
    Iterable<String>? dependencyRefs,
    String? milestoneRef,
    bool clearMilestone = false,
    TaskPriority? priority,
    TaskRisk? risk,
    ProjectRiskReduction? riskReduction,
    TaskEffort? effort,
    String? selectionRationale,
    Iterable<String>? constraints,
    Iterable<String>? readPaths,
    Iterable<String>? writePaths,
    Iterable<String>? doneCriteria,
    Iterable<String>? outOfScope,
    Iterable<String>? context,
    Iterable<TaskArtifact>? expectedArtifacts,
    String? commandId,
  }) {
    final fingerprint = _encode({
      'op': 'update_task',
      'task': taskReference.trim(),
      'title': title,
      'objective': objective,
      'criterionRefs': criterionRefs == null ? null : [...criterionRefs],
      'dependencyRefs': dependencyRefs == null ? null : [...dependencyRefs],
      'milestoneRef': milestoneRef,
      'clearMilestone': clearMilestone,
      'priority': priority?.name,
      'risk': risk?.name,
      'riskReduction': riskReduction?.name,
      'effort': effort?.name,
      'selectionRationale': selectionRationale,
      'constraints': constraints == null ? null : [...constraints],
      'readPaths': readPaths == null ? null : [...readPaths],
      'writePaths': writePaths == null ? null : [...writePaths],
      'doneCriteria': doneCriteria == null ? null : [...doneCriteria],
      'outOfScope': outOfScope == null ? null : [...outOfScope],
      'context': context == null ? null : [...context],
      'expectedArtifacts': expectedArtifacts == null
          ? null
          : [
              for (final artifact in expectedArtifacts)
                {
                  'path': artifact.path,
                  'description': artifact.description,
                  'kind': artifact.kind,
                },
            ],
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final existing = _editableTask(taskId);
        final nextObjective = objective?.trim() ?? existing.objective;
        if (nextObjective.isEmpty) {
          throw _error(
            'missing_objective',
            'objective',
            'A task objective is required.',
          );
        }
        final nextTitle = title == null ? existing.title : title.trim();
        if (nextTitle.isEmpty) {
          throw _error('missing_title', 'title', 'A task title is required.');
        }
        final nextCriterionIds = criterionRefs == null
            ? existing.criterionIds
            : _resolveReferences(
                criterionRefs,
                _resolveCriterion,
                'criterionRefs',
              );
        if (nextCriterionIds.isEmpty) {
          throw _error(
            'missing_criterion_reference',
            'criterionRefs',
            'A task must link to at least one criterion.',
          );
        }
        final nextDependencyIds = dependencyRefs == null
            ? existing.dependsOnTaskIds
            : _resolveReferences(
                dependencyRefs,
                _resolveTask,
                'dependencyRefs',
              );
        for (final dependencyId in nextDependencyIds) {
          _ensureDependencyCanComplete(dependencyId, 'dependencyRefs');
        }
        final nextMilestoneId = clearMilestone
            ? null
            : milestoneRef == null
            ? existing.milestoneId
            : _resolveMilestone(milestoneRef);
        final nextDoneCriteria = doneCriteria == null
            ? existing.doneCriteria
            : _requiredList(doneCriteria, 'doneCriteria');
        final nextOutOfScope = outOfScope == null
            ? existing.outOfScope
            : _requiredList(outOfScope, 'outOfScope');
        final next = existing.copyWith(
          title: nextTitle,
          objective: nextObjective,
          criterionIds: nextCriterionIds,
          dependsOnTaskIds: nextDependencyIds,
          milestoneId: nextMilestoneId,
          priority: priority,
          risk: risk,
          riskReduction: riskReduction,
          effort: effort,
          selectionRationale: selectionRationale,
          constraints: constraints == null ? null : _cleanStrings(constraints),
          readPaths: readPaths == null ? null : _cleanStrings(readPaths),
          writePaths: writePaths == null ? null : _cleanStrings(writePaths),
          doneCriteria: nextDoneCriteria,
          outOfScope: nextOutOfScope,
          context: context == null ? null : _cleanStrings(context),
          expectedArtifacts: expectedArtifacts == null
              ? null
              : _normaliseArtifacts(expectedArtifacts, taskId),
          fingerprint: objective == null && criterionRefs == null
              ? null
              : projectTaskFingerprint(nextObjective, nextCriterionIds),
          updatedAt: _now,
        );
        _tasks[taskId] = next;
        _taskCatalog[taskId] = next;
        _ensureNoCycles();
        return next;
      });
    });
  }

  Task setDependency({
    required String taskReference,
    required String dependencyReference,
    bool enabled = true,
    String? commandId,
  }) {
    final fingerprint = _encode({
      'op': 'set_dependency',
      'task': taskReference.trim(),
      'dependency': dependencyReference.trim(),
      'enabled': enabled,
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final dependencyId = _resolveTask(dependencyReference);
        final existing = _editableTask(taskId);
        if (taskId == dependencyId) {
          throw _error(
            'self_dependency',
            'dependency',
            'A task cannot depend on itself.',
          );
        }
        if (enabled) {
          _ensureDependencyCanComplete(dependencyId, 'dependency');
        }
        final dependencies = [...existing.dependsOnTaskIds];
        if (enabled) {
          if (!dependencies.contains(dependencyId)) {
            dependencies.add(dependencyId);
          }
        } else {
          dependencies.remove(dependencyId);
        }
        final updated = existing.copyWith(
          dependsOnTaskIds: dependencies,
          updatedAt: _now,
        );
        _tasks[taskId] = updated;
        _taskCatalog[taskId] = updated;
        _ensureNoCycles();
        return updated;
      });
    });
  }

  Task setDisposition({
    required String taskReference,
    required ProjectPlanTaskDisposition disposition,
    String? commandId,
  }) {
    final fingerprint = _encode({
      'op': 'set_disposition',
      'task': taskReference.trim(),
      'disposition': disposition.name,
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final existing = _editableTask(taskId);
        _deferredTaskIds.remove(taskId);
        _obsoleteTaskIds.remove(taskId);
        final status = disposition == ProjectPlanTaskDisposition.deferred
            ? TaskStatus.deferred
            : TaskStatus.obsolete;
        final updated = existing.copyWith(status: status, updatedAt: _now);
        _tasks[taskId] = updated;
        _taskCatalog[taskId] = updated;
        if (disposition == ProjectPlanTaskDisposition.deferred) {
          _deferredTaskIds.add(taskId);
        } else {
          _obsoleteTaskIds.add(taskId);
        }
        return updated;
      });
    });
  }

  Task clearDisposition(String taskReference, {String? commandId}) {
    final fingerprint = _encode({
      'op': 'clear_disposition',
      'task': taskReference.trim(),
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final existing = _editableTask(taskId);
        _deferredTaskIds.remove(taskId);
        _obsoleteTaskIds.remove(taskId);
        final updated = existing.copyWith(
          status:
              existing.status == TaskStatus.deferred ||
                  existing.status == TaskStatus.obsolete
              ? TaskStatus.queued
              : null,
          updatedAt: _now,
        );
        _tasks[taskId] = updated;
        _taskCatalog[taskId] = updated;
        return updated;
      });
    });
  }

  /// Adds a command gate and its matching evidence expectation as one unit.
  String addCommandCheck({
    required String taskReference,
    required String command,
    String workingDirectory = '.',
    Iterable<String>? criterionRefs,
    bool required = true,
    String? description,
    String? commandId,
  }) {
    final commandText = command.trim();
    final directory = workingDirectory.trim().isEmpty
        ? '.'
        : workingDirectory.trim();
    final fingerprint = _encode({
      'op': 'add_command_check',
      'task': taskReference.trim(),
      'command': commandText,
      'workingDirectory': directory,
      'criterionRefs': criterionRefs == null ? null : [...criterionRefs],
      'required': required,
      'description': description,
    });
    return _idempotent(commandId, fingerprint, () {
      if (commandText.isEmpty) {
        throw _error(
          'missing_command',
          'command',
          'A command check needs a command.',
        );
      }
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final task = _editableTask(taskId);
        final criterionIds = criterionRefs == null
            ? task.criterionIds
            : _resolveReferences(
                criterionRefs,
                _resolveCriterion,
                'criterionRefs',
              );
        if (criterionIds.isEmpty ||
            criterionIds.any((id) => !task.criterionIds.contains(id))) {
          throw _error(
            'unlinked_criterion',
            'criterionRefs',
            'A check must link to criteria already owned by the task.',
          );
        }

        final gateIndex = task.gates.indexWhere(
          (gate) =>
              gate.id == 'command_passes' &&
              gate.params['command']?.toString() == commandText &&
              _workingDirectory(gate.params) == directory,
        );
        final gates = [...task.gates];
        if (gateIndex < 0) {
          gates.add(
            TaskGate(
              id: 'command_passes',
              required: required,
              scope: 'task',
              params: {'command': commandText, 'working_directory': directory},
              description: description?.trim().isNotEmpty == true
                  ? description!.trim()
                  : 'The verification command passes.',
            ),
          );
        } else if (required && !gates[gateIndex].required) {
          final previous = gates[gateIndex];
          gates[gateIndex] = TaskGate(
            id: previous.id,
            required: true,
            scope: previous.scope,
            params: previous.params,
            description: previous.description,
          );
        }

        final existingExpectation = task.expectedEvidence.where((expectation) {
          return expectation.type == ProjectEvidenceType.command &&
              expectation.sourceRef == commandText &&
              _sameStrings(expectation.criterionIds, criterionIds) &&
              _workingDirectory(expectation.details) == directory;
        }).firstOrNull;
        final expectedEvidence = [...task.expectedEvidence];
        final expectationId = existingExpectation?.id ?? _newExpectationId();
        if (existingExpectation == null) {
          expectedEvidence.add(
            TaskEvidenceExpectation(
              id: expectationId,
              type: ProjectEvidenceType.command,
              criterionIds: criterionIds,
              description: description?.trim().isNotEmpty == true
                  ? description!.trim()
                  : 'The verification command passes.',
              required: required,
              sourceRef: commandText,
              details: {'working_directory': directory},
            ),
          );
        } else if (required && !existingExpectation.required) {
          final expectationIndex = expectedEvidence.indexOf(
            existingExpectation,
          );
          expectedEvidence[expectationIndex] = TaskEvidenceExpectation(
            id: existingExpectation.id,
            type: existingExpectation.type,
            criterionIds: existingExpectation.criterionIds,
            description: existingExpectation.description,
            required: true,
            sourceRef: existingExpectation.sourceRef,
            details: existingExpectation.details,
          );
        }
        final updated = task.copyWith(
          gates: gates,
          expectedEvidence: expectedEvidence,
          updatedAt: _now,
        );
        _tasks[taskId] = updated;
        _taskCatalog[taskId] = updated;
        return expectationId;
      });
    });
  }

  String addNote({
    required ProjectMemoryKind kind,
    required String content,
    String? sourceId,
    String? commandId,
  }) {
    final text = content.trim();
    final fingerprint = _encode({
      'op': 'add_note',
      'kind': kind.name,
      'content': text,
      'sourceId': sourceId,
    });
    return _idempotent(commandId, fingerprint, () {
      if (text.isEmpty) {
        throw _error(
          'empty_note',
          'content',
          'A note needs non-empty content.',
        );
      }
      return _atomic(() {
        final existing = [..._project.memory, ..._memoryAdditions]
            .where((entry) => _normalise(entry.content) == _normalise(text))
            .firstOrNull;
        if (existing != null) return existing.id;
        final entry = ProjectMemoryEntry(
          id: _newId(
            'memory',
            [..._project.memory, ..._memoryAdditions].map((item) => item.id),
          ),
          kind: kind,
          content: text,
          sourceType: ProjectMemorySourceType.planner,
          sourceId: sourceId?.trim().isEmpty == true ? null : sourceId?.trim(),
          confidence: ProjectMemoryConfidence.inferred,
          protected: false,
          active: true,
          createdAt: _now,
          updatedAt: _now,
        );
        _memoryAdditions.add(entry);
        return entry.id;
      });
    });
  }

  /// Adds a blocking question to the draft. The question ID is generated by
  /// Hermes and repeated question text is returned rather than duplicated.
  String requestUserDecision({required String question, String? commandId}) {
    final text = question.trim();
    final fingerprint = _encode({
      'op': 'request_user_decision',
      'question': text,
    });
    return _idempotent(commandId, fingerprint, () {
      if (text.isEmpty) {
        throw _error(
          'empty_question',
          'question',
          'A user decision needs a non-empty question.',
        );
      }
      return _atomic(() {
        final existing = [
          ..._project.openQuestions,
          ..._openQuestions,
        ].where((item) => _normalise(item.question) == _normalise(text));
        final previous = existing.firstOrNull;
        if (previous != null) return previous.id;
        final id = _newId(
          'question',
          [..._project.openQuestions, ..._openQuestions].map((item) => item.id),
        );
        _openQuestions.add(
          PendingProjectQuestion(id: id, question: text, createdAt: _now),
        );
        return id;
      });
    });
  }

  /// Splits one mutable task into fresh child tasks. The parent is marked
  /// split by [ProjectPlanRevisionService] at commit; it is never rewritten
  /// by a model-supplied task record.
  List<String> splitTask({
    required String taskReference,
    required Iterable<ProjectPlanTaskSpec> children,
    String? commandId,
  }) {
    final items = [...children];
    final fingerprint = _encode({
      'op': 'split_task',
      'task': taskReference.trim(),
      'children': [for (final child in items) _specMap(child)],
    });
    return _idempotent(commandId, fingerprint, () {
      if (items.isEmpty) {
        throw _error(
          'missing_split_children',
          'children',
          'A split needs at least one child task.',
        );
      }
      return _atomic(() {
        final sourceId = _resolveTask(taskReference);
        final source = _editableTask(sourceId);
        final sourceContext = [
          ...source.context,
          'Split from task ${source.id}: ${source.title}.',
        ];
        final inheritedCriteria = source.criterionIds;
        final inheritedDependencies = source.dependsOnTaskIds;
        final inheritedDoneCriteria = source.doneCriteria;
        final inheritedOutOfScope = source.outOfScope;
        final inheritedReadPaths = source.readPaths;
        final inheritedWritePaths = source.writePaths;
        final inheritedArtifacts = source.expectedArtifacts;
        final childSpecs = [
          for (var index = 0; index < items.length; index++)
            _splitChildSpec(
              source: source,
              child: items[index],
              sourceContext: sourceContext,
              inheritedCriteria: inheritedCriteria,
              inheritedDependencies: inheritedDependencies,
              inheritedDoneCriteria: inheritedDoneCriteria,
              inheritedOutOfScope: inheritedOutOfScope,
              inheritedReadPaths: inheritedReadPaths,
              inheritedWritePaths: inheritedWritePaths,
              inheritedArtifacts: inheritedArtifacts,
              fieldPath: 'children[$index]',
            ),
        ];
        final ids = _addTasksInternal(childSpecs);
        // A dependent task that waited for the oversized task must now wait
        // for every child. Leaving the old dependency in place would turn a
        // successful split into a permanently dead dependency at commit.
        for (final entry in _tasks.entries.toList()) {
          if (entry.key == sourceId ||
              !entry.value.dependsOnTaskIds.contains(sourceId)) {
            continue;
          }
          final dependencies = <String>[];
          for (final dependencyId in entry.value.dependsOnTaskIds) {
            if (dependencyId == sourceId) {
              for (final childId in ids) {
                if (!dependencies.contains(childId)) dependencies.add(childId);
              }
            } else if (!dependencies.contains(dependencyId)) {
              dependencies.add(dependencyId);
            }
          }
          final updated = entry.value.copyWith(
            dependsOnTaskIds: dependencies,
            updatedAt: _now,
          );
          _tasks[entry.key] = updated;
          _taskCatalog[entry.key] = updated;
        }
        _ensureNoCycles();
        _deferredTaskIds.remove(sourceId);
        _obsoleteTaskIds.remove(sourceId);
        _splitTaskIds.add(sourceId);
        return ids;
      });
    });
  }

  ProjectPlanTaskSpec _splitChildSpec({
    required Task source,
    required ProjectPlanTaskSpec child,
    required List<String> sourceContext,
    required List<String> inheritedCriteria,
    required List<String> inheritedDependencies,
    required List<String> inheritedDoneCriteria,
    required List<String> inheritedOutOfScope,
    required List<String> inheritedReadPaths,
    required List<String> inheritedWritePaths,
    required List<TaskArtifact> inheritedArtifacts,
    required String fieldPath,
  }) {
    for (var index = 0; index < child.dependencyRefs.length; index++) {
      final reference = child.dependencyRefs.elementAt(index);
      if (_taskRefs[reference.trim()] == source.id) {
        throw _error(
          'split_child_dependency',
          '$fieldPath.dependencyRefs[$index]',
          'A split child cannot depend on its parent task ${source.id}. Depend on the parent\'s prerequisites instead.',
        );
      }
    }
    return ProjectPlanTaskSpec(
      ref: child.ref,
      title: child.title,
      objective: child.objective,
      criterionRefs: child.criterionRefs.isEmpty
          ? inheritedCriteria
          : child.criterionRefs,
      dependencyRefs: child.dependencyRefs.isEmpty
          ? inheritedDependencies
          : child.dependencyRefs,
      milestoneRef: child.milestoneRef ?? source.milestoneId,
      priority: child.priority,
      risk: child.risk,
      riskReduction: child.riskReduction,
      effort: child.effort,
      selectionRationale: child.selectionRationale,
      constraints: child.constraints.isEmpty
          ? source.constraints
          : child.constraints,
      readPaths: child.readPaths.isEmpty ? inheritedReadPaths : child.readPaths,
      writePaths: child.writePaths.isEmpty
          ? inheritedWritePaths
          : child.writePaths,
      doneCriteria: child.doneCriteria.isEmpty
          ? inheritedDoneCriteria
          : child.doneCriteria,
      outOfScope: child.outOfScope.isEmpty
          ? inheritedOutOfScope
          : child.outOfScope,
      context: [...sourceContext, ...child.context],
      expectedArtifacts: child.expectedArtifacts.isEmpty
          ? inheritedArtifacts
          : child.expectedArtifacts,
    );
  }

  /// Creates a fresh queued task from a failed task while preserving the
  /// failed task and its execution history.
  String retryTask({
    required String taskReference,
    String ref = '',
    String? title,
    String? objective,
    String? commandId,
  }) {
    final fingerprint = _encode({
      'op': 'retry_task',
      'task': taskReference.trim(),
      'ref': ref.trim(),
      'title': title,
      'objective': objective,
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final sourceId = _resolveTask(taskReference);
        final source = _taskCatalog[sourceId];
        if (source == null ||
            (source.status != TaskStatus.failed &&
                source.status != TaskStatus.rejected)) {
          throw _error(
            'retry_requires_failed_task',
            'task',
            'Retry is only available for failed or rejected tasks.',
          );
        }
        final baseObjective = objective?.trim().isNotEmpty == true
            ? objective!.trim()
            : source.objective;
        final retryObjective =
            'Retry failed task after addressing the previous failure: '
            '$baseObjective';
        final failureContext = source.failure?.summary.trim();
        final spec = ProjectPlanTaskSpec(
          ref: ref,
          title: title?.trim().isNotEmpty == true
              ? title!.trim()
              : 'Retry ${source.title}',
          objective: retryObjective,
          criterionRefs: source.criterionIds,
          dependencyRefs: source.dependsOnTaskIds,
          milestoneRef: source.milestoneId,
          priority: source.priority,
          risk: source.risk,
          riskReduction: source.riskReduction,
          effort: source.effort,
          selectionRationale: 'Created as a fresh retry of ${source.id}.',
          constraints: source.constraints,
          readPaths: source.readPaths,
          writePaths: source.writePaths,
          doneCriteria: source.doneCriteria,
          outOfScope: source.outOfScope,
          context: [
            ...source.context,
            'Retry of failed task ${source.id}.',
            if (failureContext != null && failureContext.isNotEmpty)
              'Previous failure: $failureContext',
            if (source.rejectionReason?.trim().isNotEmpty == true)
              'Previous rejection: ${source.rejectionReason!.trim()}',
          ],
          expectedArtifacts: source.expectedArtifacts,
        );
        return _addTasksInternal([spec]).single;
      });
    });
  }

  /// Materializes and commits the complete desired plan atomically through
  /// the existing revision service.
  Future<ProjectPlanBuilderCommit> commit({
    required String workspaceRoot,
    ProjectPlanApprovalPolicy approvalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
  }) async {
    final proposal = _materialize();
    final result = await _revisionService.prepareAndApply(
      project: _planningProject,
      proposal: proposal,
      workspaceRoot: workspaceRoot,
      approvalPolicy: approvalPolicy,
      splitTaskIds: _splitTaskIds,
    );
    return ProjectPlanBuilderCommit(proposal: proposal, result: result);
  }

  /// Produces a validation result and desired-plan representation without
  /// applying it. This is intentionally separate from [commit].
  ProjectPlanBuilderPreview preview({required String workspaceRoot}) {
    final proposal = _materialize();
    final validation = _revisionService.validate(
      project: _planningProject,
      proposal: proposal,
      workspaceRoot: workspaceRoot,
    );
    return ProjectPlanBuilderPreview(
      proposal: proposal,
      validation: validation,
    );
  }

  ProjectDesiredPlan _materialize() => ProjectDesiredPlan(
    revision: _project.nextRevision,
    triggers: [..._triggers],
    summary: _summary,
    rationale: _rationale,
    hasCompleteCollections: true,
    criteria: _criteria.values.toList(),
    milestones: _milestones.values.toList(),
    tasks: [
      for (final task in _tasks.values)
        if (!_splitTaskIds.contains(task.id)) task,
    ],
    splitTaskIds: _splitTaskIds.toList(),
    deferredTaskIds: _deferredTaskIds.toList(),
    obsoleteTaskIds: _obsoleteTaskIds.toList(),
    memoryAdditions: [..._memoryAdditions],
    openQuestions: [..._project.openQuestions, ..._openQuestions],
    requiresApproval: _requiresApproval,
    approvalReason: _approvalReason,
    createdAt: _now,
  );

  ProjectState get _planningProject =>
      _project.copyWith(refinedGoal: _validationRefinedGoal);

  List<String> _addTasksInternal(List<ProjectPlanTaskSpec> specs) {
    if (specs.isEmpty) {
      throw _error('missing_tasks', 'tasks', 'At least one task is required.');
    }
    final references = <String, String>{};
    final ids = <String>[];
    for (var index = 0; index < specs.length; index++) {
      final spec = specs[index];
      final reference = _claimReference(
        spec.ref,
        namespace: 'task',
        fallback: _slug(spec.title.isEmpty ? spec.objective : spec.title),
        additional: references.keys,
      );
      if (references.containsKey(reference)) {
        throw _error(
          'duplicate_reference',
          'tasks[$index].ref',
          'Task reference $reference already exists in this command.',
        );
      }
      final id = _newId('task', {..._taskCatalog.keys, ...ids});
      references[reference] = id;
      ids.add(id);
    }

    final created = <Task>[];
    final reservedExpectationIds = <String>{};
    final reservedArtifactIds = <String>{};
    for (var index = 0; index < specs.length; index++) {
      final spec = specs[index];
      final id = ids[index];
      final objective = spec.objective.trim().isEmpty
          ? spec.title.trim()
          : spec.objective.trim();
      if (objective.isEmpty) {
        throw _error(
          'missing_objective',
          'tasks[$index].objective',
          'A task needs an objective or title.',
        );
      }
      final title = spec.title.trim().isEmpty ? objective : spec.title.trim();
      final criterionIds = _resolveReferences(
        spec.criterionRefs,
        _resolveCriterion,
        'tasks[$index].criterionRefs',
      );
      if (criterionIds.isEmpty) {
        throw _error(
          'missing_criterion_reference',
          'tasks[$index].criterionRefs',
          'A task must link to at least one criterion.',
        );
      }
      final dependencies = _resolveReferences(
        spec.dependencyRefs,
        (reference) => references[reference.trim()] ?? _resolveTask(reference),
        'tasks[$index].dependencyRefs',
      );
      for (final dependencyId in dependencies) {
        if (!references.values.contains(dependencyId)) {
          _ensureDependencyCanComplete(
            dependencyId,
            'tasks[$index].dependencyRefs',
          );
        }
      }
      final milestoneId =
          spec.milestoneRef == null || spec.milestoneRef!.trim().isEmpty
          ? null
          : _resolveMilestone(spec.milestoneRef!);
      final doneCriteria = _requiredList(
        spec.doneCriteria,
        'tasks[$index].doneCriteria',
      );
      final outOfScope = _requiredList(
        spec.outOfScope,
        'tasks[$index].outOfScope',
      );
      final expectedEvidence = TaskEvidenceExpectation(
        id: _newExpectationId(additional: reservedExpectationIds),
        type: ProjectEvidenceType.taskClaim,
        criterionIds: criterionIds,
        description: doneCriteria.join(' '),
      );
      reservedExpectationIds.add(expectedEvidence.id);
      final expectedArtifacts = _normaliseArtifacts(
        spec.expectedArtifacts,
        id,
        additionalIds: reservedArtifactIds,
      );
      reservedArtifactIds.addAll(
        expectedArtifacts.map((artifact) => artifact.id),
      );
      final task = Task(
        id: id,
        title: title,
        originalPrompt: objective,
        objective: objective,
        constraints: _cleanStrings(spec.constraints),
        status: TaskStatus.queued,
        criterionIds: criterionIds,
        milestoneId: milestoneId,
        dependsOnTaskIds: dependencies,
        priority: spec.priority,
        risk: spec.risk,
        riskReduction: spec.riskReduction,
        effort: spec.effort,
        selectionRationale: spec.selectionRationale.trim(),
        expectedEvidence: [expectedEvidence],
        readPaths: _cleanStrings(spec.readPaths),
        writePaths: _cleanStrings(spec.writePaths),
        doneCriteria: doneCriteria,
        outOfScope: outOfScope,
        context: _cleanStrings(spec.context),
        expectedArtifacts: expectedArtifacts,
        fingerprint: projectTaskFingerprint(objective, criterionIds),
        createdAt: _now,
        updatedAt: _now,
        chatSessionId: _project.chatSessionId,
        projectId: _project.id,
      );
      created.add(task);
    }
    for (var index = 0; index < created.length; index++) {
      final task = created[index];
      _tasks[task.id] = task;
      _taskCatalog[task.id] = task;
      final reference = references.keys.elementAt(index);
      _taskRefs[reference] = task.id;
      _taskRefs[task.id] = task.id;
    }
    _ensureNoCycles();
    return ids;
  }

  Task _editableTask(String id) {
    final task = _tasks[id];
    if (task == null) {
      final known = _taskCatalog[id];
      if (known != null && _isTerminal(known)) {
        throw _error(
          'terminal_task_immutable',
          'task',
          'Terminal task $id cannot be changed by a draft.',
        );
      }
      throw _error('unknown_task', 'task', 'Task $id is not mutable.');
    }
    if (_splitTaskIds.contains(id)) {
      throw _error(
        'split_task_immutable',
        'task',
        'Task $id has already been split in this draft.',
      );
    }
    if (task.status == TaskStatus.running) {
      throw _error(
        'active_task_immutable',
        'task',
        'The running task $id cannot be changed by a draft.',
      );
    }
    if (_isTerminal(task)) {
      throw _error(
        'terminal_task_immutable',
        'task',
        'Terminal task $id cannot be changed by a draft.',
      );
    }
    return task;
  }

  String _resolveTask(String reference) {
    final key = reference.trim();
    final id = _taskRefs[key];
    if (id == null) {
      throw _error(
        'unknown_reference',
        'task',
        'Task reference $reference does not exist.',
      );
    }
    return id;
  }

  String _resolveCriterion(String reference) {
    final key = reference.trim();
    final id = _criterionRefs[key];
    if (id == null) {
      throw _error(
        'unknown_reference',
        'criterion',
        'Criterion reference $reference does not exist.',
      );
    }
    return id;
  }

  String _resolveMilestone(String reference) {
    final key = reference.trim();
    final id = _milestoneRefs[key];
    if (id == null) {
      throw _error(
        'unknown_reference',
        'milestone',
        'Milestone reference $reference does not exist.',
      );
    }
    return id;
  }

  void _ensureDependencyCanComplete(String dependencyId, String field) {
    final dependency = _taskCatalog[dependencyId];
    if (dependency == null) return;
    final dead = switch (dependency.status) {
      TaskStatus.failed ||
      TaskStatus.rejected ||
      TaskStatus.split ||
      TaskStatus.deferred ||
      TaskStatus.obsolete ||
      TaskStatus.cancelled => true,
      _ => false,
    };
    if (dead ||
        _deferredTaskIds.contains(dependencyId) ||
        _obsoleteTaskIds.contains(dependencyId)) {
      throw _error(
        'dead_dependency',
        field,
        'Task $dependencyId cannot be used as a dependency because it is not completable.',
      );
    }
  }

  List<String> _resolveReferences(
    Iterable<String> references,
    String Function(String) resolver,
    String fieldPath,
  ) {
    final resolved = <String>[];
    for (final reference in references) {
      if (reference.trim().isEmpty) {
        throw _error(
          'empty_reference',
          fieldPath,
          'References must not be empty.',
        );
      }
      final id = resolver(reference);
      if (!resolved.contains(id)) resolved.add(id);
    }
    return resolved;
  }

  String _claimReference(
    String reference, {
    required String namespace,
    required String fallback,
    Iterable<String> additional = const [],
  }) {
    final occupied = _referencesFor(namespace);
    var candidate = reference.trim();
    if (candidate.isEmpty) {
      candidate = _uniqueReference(_slug(fallback).ifEmpty(namespace), [
        ...occupied.keys,
        ...additional,
      ]);
    }
    if (occupied.containsKey(candidate) || additional.contains(candidate)) {
      throw _error(
        'duplicate_reference',
        '$namespace.ref',
        '$namespace reference $candidate already exists.',
      );
    }
    return candidate;
  }

  Map<String, String> _referencesFor(String namespace) => switch (namespace) {
    'criterion' => _criterionRefs,
    'milestone' => _milestoneRefs,
    _ => _taskRefs,
  };

  String _uniqueReference(String base, Iterable<String> additional) {
    final occupied = additional.toSet();
    var candidate = base;
    var suffix = 2;
    while (occupied.contains(candidate)) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  int _nextMilestoneOrder() =>
      _milestones.values.fold<int>(0, (highest, item) {
        return item.order > highest ? item.order : highest;
      }) +
      1;

  String _newExpectationId({Iterable<String> additional = const []}) {
    final used = {
      for (final task in _taskCatalog.values)
        for (final expectation in task.expectedEvidence) expectation.id,
      for (final task in _tasks.values)
        for (final expectation in task.expectedEvidence) expectation.id,
      ...additional,
    };
    return _newId('expect', used);
  }

  List<TaskArtifact> _normaliseArtifacts(
    Iterable<TaskArtifact> artifacts,
    String taskId, {
    Iterable<String> additionalIds = const [],
  }) {
    final used = {
      for (final task in _taskCatalog.values)
        for (final artifact in task.expectedArtifacts)
          if (artifact.id.trim().isNotEmpty) artifact.id,
      ...additionalIds,
    };
    final normalized = <TaskArtifact>[];
    for (final artifact in artifacts) {
      final id = _newId('artifact', used);
      used.add(id);
      normalized.add(
        artifact.copyWith(
          id: id,
          taskId: taskId,
          createdAt: artifact.createdAt ?? _now,
        ),
      );
    }
    return normalized;
  }

  void _ensureNoCycles() {
    final graph = {
      for (final task in _tasks.values) task.id: task.dependsOnTaskIds,
    };
    final visiting = <String>{};
    final visited = <String>{};
    bool visit(String id) {
      if (visiting.contains(id)) return true;
      if (!visited.add(id)) return false;
      visiting.add(id);
      for (final dependency in graph[id] ?? const <String>[]) {
        if (visit(dependency)) return true;
      }
      visiting.remove(id);
      return false;
    }

    for (final id in graph.keys) {
      if (visit(id)) {
        throw _error(
          'dependency_cycle',
          'tasks',
          'The draft dependency graph contains a cycle.',
        );
      }
    }
  }

  T _idempotent<T>(String? commandId, String fingerprint, T Function() action) {
    final key = commandId?.trim();
    if (key == null || key.isEmpty) return action();
    final previous = _commands[key];
    if (previous != null) {
      if (previous.fingerprint != fingerprint) {
        throw _error(
          'duplicate_command',
          'commandId',
          'Command $key was already used with different arguments.',
        );
      }
      return previous.result as T;
    }
    final result = action();
    _commands[key] = _AppliedCommand(fingerprint, result);
    return result;
  }

  T _atomic<T>(T Function() action) {
    final criteria = Map<String, ProjectCriterion>.from(_criteria);
    final milestones = Map<String, ProjectMilestone>.from(_milestones);
    final tasks = Map<String, Task>.from(_tasks);
    final catalog = Map<String, Task>.from(_taskCatalog);
    final criterionRefs = Map<String, String>.from(_criterionRefs);
    final milestoneRefs = Map<String, String>.from(_milestoneRefs);
    final taskRefs = Map<String, String>.from(_taskRefs);
    final deferred = {..._deferredTaskIds};
    final obsolete = {..._obsoleteTaskIds};
    final split = {..._splitTaskIds};
    final memories = [..._memoryAdditions];
    final questions = [..._openQuestions];
    final commands = Map<String, _AppliedCommand>.from(_commands);
    try {
      return action();
    } catch (_) {
      _criteria
        ..clear()
        ..addAll(criteria);
      _milestones
        ..clear()
        ..addAll(milestones);
      _tasks
        ..clear()
        ..addAll(tasks);
      _taskCatalog
        ..clear()
        ..addAll(catalog);
      _criterionRefs
        ..clear()
        ..addAll(criterionRefs);
      _milestoneRefs
        ..clear()
        ..addAll(milestoneRefs);
      _taskRefs
        ..clear()
        ..addAll(taskRefs);
      _deferredTaskIds
        ..clear()
        ..addAll(deferred);
      _obsoleteTaskIds
        ..clear()
        ..addAll(obsolete);
      _splitTaskIds
        ..clear()
        ..addAll(split);
      _memoryAdditions
        ..clear()
        ..addAll(memories);
      _openQuestions
        ..clear()
        ..addAll(questions);
      _commands
        ..clear()
        ..addAll(commands);
      rethrow;
    }
  }

  static bool _isTerminal(Task task) => switch (task.status) {
    TaskStatus.completed ||
    TaskStatus.failed ||
    TaskStatus.rejected ||
    TaskStatus.split ||
    TaskStatus.cancelled => true,
    _ => false,
  };

  static List<String> _requiredList(Iterable<String> values, String field) {
    final result = _cleanStrings(values);
    if (result.isEmpty) {
      throw _error('missing_$field', field, 'At least one value is required.');
    }
    return result;
  }

  static List<String> _cleanStrings(Iterable<String> values) => [
    for (final value in values)
      if (value.trim().isNotEmpty) value.trim(),
  ];

  static bool _sameStrings(Iterable<String> first, Iterable<String> second) {
    final left = first.toSet();
    final right = second.toSet();
    return left.length == right.length && left.containsAll(right);
  }

  static String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _slug(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'task' : slug;
  }

  static String _newId(String prefix, Iterable<String> usedValues) {
    final used = usedValues.toSet();
    String id;
    do {
      id = '${prefix}_${uuid.v7()}';
    } while (used.contains(id));
    return id;
  }

  static String _encode(Object value) => jsonEncode(value);

  static String _requiredText(String value, String field) {
    final text = value.trim();
    if (text.isEmpty) {
      throw _error('missing_$field', field, 'A non-empty $field is required.');
    }
    return text;
  }

  static ProjectPlanBuilderException _error(
    String code,
    String path,
    String message,
  ) => ProjectPlanBuilderException(code: code, path: path, message: message);

  static Map<String, dynamic> _specMap(ProjectPlanTaskSpec spec) => {
    'ref': spec.ref,
    'title': spec.title,
    'objective': spec.objective,
    'criterionRefs': spec.criterionRefs,
    'dependencyRefs': spec.dependencyRefs,
    'milestoneRef': spec.milestoneRef,
    'priority': spec.priority.name,
    'risk': spec.risk.name,
    'riskReduction': spec.riskReduction.name,
    'effort': spec.effort.name,
    'selectionRationale': spec.selectionRationale,
    'constraints': spec.constraints,
    'readPaths': spec.readPaths,
    'writePaths': spec.writePaths,
    'doneCriteria': spec.doneCriteria,
    'outOfScope': spec.outOfScope,
    'context': spec.context,
    'expectedArtifacts': [
      for (final artifact in spec.expectedArtifacts)
        {
          'id': artifact.id,
          'path': artifact.path,
          'description': artifact.description,
          'kind': artifact.kind,
        },
    ],
  };

  static String _workingDirectory(Map<String, dynamic> values) {
    final value = values['working_directory'] ?? values['workingDirectory'];
    final directory = value?.toString().trim();
    return directory == null || directory.isEmpty ? '.' : directory;
  }
}

class _AppliedCommand {
  final String fingerprint;
  final Object? result;

  const _AppliedCommand(this.fingerprint, this.result);
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
