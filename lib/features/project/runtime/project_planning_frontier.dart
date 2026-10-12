import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/runtime/project_planning_gateway.dart';
import 'package:hermes/features/task/domain/task.dart';

/// Builds the compact, model-facing view of a project planning invocation.
///
/// This is deliberately a presentation layer. It must not be used for
/// persistence or for reconstructing a [ProjectAggregate]. Detailed records
/// are available through the project planner's read tool.
class ProjectPlanningFrontierBuilder {
  const ProjectPlanningFrontierBuilder._();

  static Map<String, dynamic> build({
    required ProjectAggregate project,
    ProjectEvidenceSnapshot? evidence,
    Iterable<String> triggers = const [],
    ProjectTaskNode? focusedTask,
  }) {
    int? criterionNumber(String id) => project.criterionAgentNumber(id);
    int? milestoneNumber(String id) => project.milestoneAgentNumber(id);
    int? taskNumber(String id) => project.taskAgentNumber(id);

    final readyTaskIds = _taskNumbersForEvidence(
      project,
      evidence?.readyTasks ?? const [],
    );
    final blockedTaskIds = _taskNumbersForEvidence(
      project,
      evidence?.blockedTasks ?? const [],
    );
    final activeTaskId = project.activeTaskId == null
        ? null
        : taskNumber(project.activeTaskId!);
    final currentBatchTaskIds = [
      for (final id in project.currentBatchTaskIds)
        if (taskNumber(id) != null) taskNumber(id)!,
    ];

    final frontierTaskIds = <int>{
      ...readyTaskIds,
      ...blockedTaskIds,
      ...currentBatchTaskIds,
      ?activeTaskId,
    };
    if (evidence != null) {
      frontierTaskIds.addAll(
        _taskNumbersForEvidence(project, evidence.recentlyCompletedTasks),
      );
    }

    return {
      'schema_version': 1,
      'project': {
        'persistence_revision': project.persistenceRevision,
        'title': project.title,
        'original_goal': project.originalGoal,
        'refined_goal': project.refinedGoal,
        'constraints': project.constraints,
        'status': project.status.wire,
      },
      'criteria': [
        for (final criterion in project.criteria)
          {
            'criterion_id': criterionNumber(criterion.id),
            'statement': criterion.statement,
            'required': criterion.required,
            'status': criterion.status.name,
            'verification_mode': criterion.verificationMode.name,
          },
      ],
      'milestones': [
        for (final milestone in project.milestones)
          {
            'milestone_id': milestoneNumber(milestone.id),
            'title': milestone.title,
            'objective': milestone.objective,
            'criterion_ids': [
              for (final id in milestone.criterionIds) ?criterionNumber(id),
            ],
            'status': milestone.status.name,
            'order': milestone.order,
          },
      ],
      'tasks': [
        for (final task in project.tasks)
          {
            'task_id': taskNumber(task.id),
            'title': task.title,
            'objective': task.objective,
            'status': task.status.wire,
            'dependency_task_ids': [
              for (final id in task.dependsOnTaskIds) ?taskNumber(id),
            ],
            'milestone_id': task.milestoneId == null
                ? null
                : milestoneNumber(task.milestoneId!),
            'priority': task.priority.name,
            'risk': task.risk.name,
            'risk_reduction': task.riskReduction.name,
            'effort': task.effort.name,
            if (task.rejectionReason?.trim().isNotEmpty == true)
              'rejection_reason': task.rejectionReason,
            if (task.failureKey?.trim().isNotEmpty == true)
              'failure_key': task.failureKey,
            if (task.failureGateId?.trim().isNotEmpty == true)
              'failure_gate_id': task.failureGateId,
            if (task.failureErrorCodes.isNotEmpty)
              'failure_error_codes': task.failureErrorCodes,
            if (task.unresolvedErrorCount > 0)
              'unresolved_error_count': task.unresolvedErrorCount,
            if (task.planningError?.trim().isNotEmpty == true)
              'planning_error': task.planningError,
          },
      ],
      'frontier': {
        'active_task_id': activeTaskId,
        'current_batch_task_ids': currentBatchTaskIds,
        'ready_task_ids': readyTaskIds,
        'blocked_task_ids': blockedTaskIds,
        'detail_required_for': frontierTaskIds.toList()..sort(),
      },
      'control': {
        'pending_questions': [
          for (final question in project.openQuestions)
            {'id': question.id, 'question': question.question},
        ],
        if (project.blocker != null)
          'blocker': {
            'type': project.blocker!.type.name,
            'message': project.blocker!.message,
            if (project.blocker!.taskId != null)
              'task_id': taskNumber(project.blocker!.taskId!),
          },
        'pending_replan_triggers': [for (final trigger in triggers) trigger],
      },
      'workspace': _workspaceFrontier(project, evidence),
      if (evidence != null) 'evidence': _evidenceFrontier(evidence),
      if (focusedTask != null) 'focused_task': taskDetail(project, focusedTask),
    };
  }

  static Map<String, dynamic> taskDetail(
    ProjectAggregate project,
    ProjectTaskNode task, {
    TaskAggregate? canonicalTask,
  }) {
    final wire = <String, dynamic>{
      'task_id': project.taskAgentNumber(task.id),
      'title': task.title,
      'objective': task.objective,
      'status': task.status.wire,
      'constraints': task.constraints,
      'out_of_scope': task.outOfScope,
      'read_paths': task.readPaths,
      'write_paths': task.writePaths,
      'context': task.context,
      'dependency_task_ids': [
        for (final id in task.dependsOnTaskIds) ?project.taskAgentNumber(id),
      ],
      'milestone_id': task.milestoneId == null
          ? null
          : project.milestoneAgentNumber(task.milestoneId!),
      'priority': task.priority.name,
      'risk': task.risk.name,
      'risk_reduction': task.riskReduction.name,
      'effort': task.effort.name,
      'selection_rationale': task.selectionRationale,
      'acceptance': [
        for (final item in task.acceptance)
          {
            'ref': item.ref,
            'statement': item.statement,
            'criterion_ids': [
              for (final id in item.criterionIds)
                ?project.criterionAgentNumber(id),
            ],
            'verifiers': [
              for (final verifier in item.verifiers)
                {
                  'kind': verifier.kind.name,
                  'required': verifier.required,
                  if (verifier.command != null) 'command': verifier.command,
                  if (verifier.workingDirectory != '.')
                    'working_directory': verifier.workingDirectory,
                  if (verifier.path != null) 'path': verifier.path,
                  if (verifier.artifactKind != 'file')
                    'artifact_kind': verifier.artifactKind,
                  if (verifier.description != null)
                    'description': verifier.description,
                },
            ],
          },
      ],
    };
    if (canonicalTask != null) {
      wire['steps'] = [
        for (var index = 0; index < canonicalTask.steps.length; index++)
          _stepWire(canonicalTask.steps[index], index),
      ];
    }
    return wire;
  }

  static Map<String, dynamic> criterionDetail(
    ProjectAggregate project,
    ProjectCriterion criterion,
  ) => {
    'criterion_id': project.criterionAgentNumber(criterion.id),
    'statement': criterion.statement,
    'required': criterion.required,
    'status': criterion.status.name,
    'verification_mode': criterion.verificationMode.name,
    'notes': criterion.notes,
  };

  static Map<String, dynamic> milestoneDetail(
    ProjectAggregate project,
    ProjectMilestone milestone,
  ) => {
    'milestone_id': project.milestoneAgentNumber(milestone.id),
    'title': milestone.title,
    'objective': milestone.objective,
    'criterion_ids': [
      for (final id in milestone.criterionIds)
        ?project.criterionAgentNumber(id),
    ],
    'status': milestone.status.name,
    'exit_conditions': milestone.exitConditions,
    'order': milestone.order,
  };

  static Map<String, dynamic> workspaceDetail(
    ProjectWorkspaceGraph graph,
    String? ref,
  ) {
    if (ref == null || ref.trim().isEmpty || ref == 'summary') {
      return _workspaceSummary(graph);
    }
    final node = graph.nodes.where((item) => item.id == ref).firstOrNull;
    if (node != null) return _nodeDetail(node);
    final edge = graph.edges.where((item) => item.id == ref).firstOrNull;
    if (edge != null) return _edgeDetail(edge);
    throw StateError('Unknown workspace graph reference $ref.');
  }

  static Map<String, dynamic> _workspaceFrontier(
    ProjectAggregate project,
    ProjectEvidenceSnapshot? evidence,
  ) {
    final graph = project.workspaceGraph;
    return {
      'orientation': graph.orientation,
      'graph': _workspaceSummary(graph),
      if (evidence != null)
        'selected_context': evidence.workspaceContext.toMap(),
    };
  }

  static Map<String, dynamic> _workspaceSummary(ProjectWorkspaceGraph graph) =>
      {
        'orientation': graph.orientation,
        'nodes': [
          for (final node in graph.nodes)
            {
              'id': node.id,
              'type': node.type,
              'title': node.title,
              'confidence': node.confidence.name,
              'protected': node.protected,
            },
        ],
        'edges': [
          for (final edge in graph.edges)
            {
              'id': edge.id,
              'source_node_id': edge.sourceNodeId,
              'target_node_id': edge.targetNodeId,
              'label': edge.label,
              'confidence': edge.confidence.name,
              'protected': edge.protected,
            },
        ],
      };

  static Map<String, dynamic> _nodeDetail(ProjectWorkspaceNode node) => {
    'resource': 'workspace_node',
    'id': node.id,
    'type': node.type,
    'title': node.title,
    'description': node.description,
    'aliases': node.aliases,
    'tags': node.tags,
    'references': node.references,
    'source_type': node.sourceType.name,
    if (node.sourceId != null) 'source_id': node.sourceId,
    if (node.managedKey != null) 'managed_key': node.managedKey,
    'confidence': node.confidence.name,
    'protected': node.protected,
  };

  static Map<String, dynamic> _edgeDetail(ProjectWorkspaceEdge edge) => {
    'resource': 'workspace_edge',
    'id': edge.id,
    'source_node_id': edge.sourceNodeId,
    'target_node_id': edge.targetNodeId,
    'label': edge.label,
    'description': edge.description,
    'source_type': edge.sourceType.name,
    if (edge.sourceId != null) 'source_id': edge.sourceId,
    if (edge.managedKey != null) 'managed_key': edge.managedKey,
    'confidence': edge.confidence.name,
    'protected': edge.protected,
  };

  static Map<String, dynamic> _evidenceFrontier(
    ProjectEvidenceSnapshot evidence,
  ) => {
    'workspace_name': evidence.workspaceName,
    'root_entries': evidence.rootEntries.take(80).toList(),
    'git_available': evidence.gitAvailable,
    'changed_files': evidence.changedFiles.take(80).toList(),
    'project_artifact_paths': evidence.projectArtifactPaths.take(80).toList(),
    'task_artifact_ids': evidence.taskArtifactIds.take(80).toList(),
    'recent_task_results': evidence.recentTaskResults.take(40).toList(),
    'recent_gate_failures': evidence.recentGateFailures.take(40).toList(),
    'active_memory': evidence.activeMemory.take(40).toList(),
    'verification_commands': evidence.verificationCommands.take(40).toList(),
    'workspace_context': evidence.workspaceContext.toMap(),
  };

  static Set<int> _taskNumbersForEvidence(
    ProjectAggregate project,
    Iterable<String> entries,
  ) {
    final result = <int>{};
    for (final entry in entries) {
      final id = entry.split(':').first.trim();
      final number = project.taskAgentNumber(id);
      if (number != null) result.add(number);
    }
    return result;
  }

  static Map<String, dynamic> _stepWire(TaskStep step, int index) => {
    'ref': step.planningRef.trim().isEmpty
        ? 'step_${index + 1}'
        : step.planningRef,
    'title': step.title,
    'objective': step.objective,
    'instructions': step.instructions,
    'may_edit_files': step.mayEditFiles,
    'acceptance_refs': step.acceptanceRefs,
    'artifacts': [
      for (final artifact in step.artifacts)
        {
          'path': artifact.path,
          'description': artifact.description,
          'kind': artifact.kind,
        },
    ],
  };
}
