import 'dart:convert';

import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/project/application/contracts/project_task_models.dart'
    show ProjectTaskCheckSpec;
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';
import 'package:hermes/features/project/runtime/project_plan_validator.dart';
import 'package:hermes/features/project/runtime/project_plan_patch.dart';
import 'package:hermes/features/project/runtime/project_planning_policy.dart';

/// A structured error returned by a draft command before commit.
part 'project_plan_builder_workspace.dart';
part 'project_plan_builder_commands.dart';
part 'project_plan_builder_support.dart';

class ProjectPlanBuilderException implements Exception {
  final String code;
  final String path;
  final String message;
  final Map<String, dynamic> details;

  const ProjectPlanBuilderException({
    required this.code,
    required this.path,
    required this.message,
    this.details = const {},
  });

  @override
  String toString() => '$code${path.isEmpty ? '' : ' ($path)'}: $message';
}

enum ProjectPlanTaskDisposition { deferred, obsolete }

class ProjectPlanBuilderCommit {
  final ProjectDesiredPlan proposal;
  final ProjectPlanRevisionResult result;

  const ProjectPlanBuilderCommit({
    required this.proposal,
    required this.result,
  });

  ProjectAggregate get project => result.project;
  ProjectPlanValidationResult get validation => result.validation;

  ProjectPlanPatch get patch => ProjectPlanPatch.incremental(proposal);
}

class ProjectPlanBuilderPreview {
  final ProjectDesiredPlan proposal;
  final ProjectPlanValidationResult validation;

  const ProjectPlanBuilderPreview({
    required this.proposal,
    required this.validation,
  });
}

String _requiredBuilderText(String value, String field) {
  final text = value.trim();
  if (text.isEmpty) {
    throw ProjectPlanBuilderException(
      code: 'missing_$field',
      path: field,
      message: 'A non-empty $field is required.',
    );
  }
  return text;
}

/// Builds a complete desired plan without exposing persistence fields to the
/// caller. The base project is never mutated; only [commit] produces a plan
/// and sends it through the existing validator and revision service.
class ProjectPlanBuilder {
  ProjectPlanBuilder({
    required ProjectAggregate project,
    DateTime? now,
    Iterable<ProjectPlanRevisionTrigger> triggers = const [],
    String summary = 'Apply the incremental plan update.',
    String rationale = 'Keep the project plan bounded and actionable.',
    bool requiresApproval = false,
    String approvalReason = '',
    this.planningLimits = ProjectPlanningLimits.maintenance,
    ProjectPlanRevisionService revisionService =
        const ProjectPlanRevisionService(),
  }) : _project = project,
       _now = now ?? DateTime.now(),
       _validationRefinedGoal = project.refinedGoal,
       _triggers = triggers.isEmpty
           ? [ProjectPlanRevisionTrigger.manual]
           : [...triggers],
       _summary = _requiredBuilderText(summary, 'summary'),
       _rationale = _requiredBuilderText(rationale, 'rationale'),
       _workspaceOrientation = project.workspaceGraph.orientation,
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
    for (final node in project.workspaceGraph.nodes) {
      _workspaceNodes[node.id] = node;
      _workspaceNodeRefs[node.id] = node.id;
    }
    for (final edge in project.workspaceGraph.edges) {
      _workspaceEdges[edge.id] = edge;
      _workspaceEdgeRefs[edge.id] = edge.id;
    }
  }

  final ProjectAggregate _project;
  final DateTime _now;
  String _validationRefinedGoal;
  final List<ProjectPlanRevisionTrigger> _triggers;
  final ProjectPlanRevisionService _revisionService;
  final Map<String, ProjectCriterion> _criteria = {};
  final Map<String, ProjectMilestone> _milestones = {};
  final Map<String, ProjectTaskNode> _tasks = {};
  final Map<String, ProjectTaskNode> _taskCatalog = {};
  final Map<String, ProjectWorkspaceNode> _workspaceNodes = {};
  final Map<String, ProjectWorkspaceEdge> _workspaceEdges = {};
  final Map<String, String> _criterionRefs = {};
  final Map<String, String> _milestoneRefs = {};
  final Map<String, String> _taskRefs = {};
  final Map<String, String> _workspaceNodeRefs = {};
  final Map<String, String> _workspaceEdgeRefs = {};
  final Set<String> _deferredTaskIds = {};
  final Set<String> _obsoleteTaskIds = {};
  final Set<String> _splitTaskIds = {};
  final List<ProjectMemoryEntry> _memoryAdditions = [];
  final List<PendingProjectQuestion> _openQuestions = [];
  final Map<String, _AppliedCommand> _commands = {};
  String _workspaceOrientation;
  String _summary;
  String _rationale;
  final bool _requiresApproval;
  final String _approvalReason;
  final ProjectPlanningLimits planningLimits;
  final Set<String> _newTaskIds = {};

  String get summary => _summary;
  String get rationale => _rationale;
  List<ProjectPlanRevisionTrigger> get triggers => List.unmodifiable(_triggers);
  List<String> get splitTaskIds => List.unmodifiable(_splitTaskIds);

  Future<ProjectPlanBuilderCommit> commit({
    required String workspaceRoot,
    ProjectPlanApprovalPolicy approvalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
  }) async {
    final proposal = _materialize();
    final result = await _revisionService.prepareAndApplyPatch(
      project: _planningProject,
      patch: ProjectPlanPatch.incremental(proposal),
      workspaceRoot: workspaceRoot,
      approvalPolicy: approvalPolicy,
      planningLimits: planningLimits,
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
      planningLimits: planningLimits,
    );
    return ProjectPlanBuilderPreview(
      proposal: proposal,
      validation: validation,
    );
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
