part of 'task_execution_coordinator.dart';

/// Builds the single model-facing payload used by task planning and replanning.
///
/// The selected task remains editable in full, but project context and
/// completed-step history are represented only once and only at the detail
/// needed by the current planning pass.
class TaskPlanningFrontierBuilder {
  const TaskPlanningFrontierBuilder._();

  static Map<String, dynamic> build({
    required TaskAggregate task,
    required int taskNumber,
    required WorkspaceMetadata metadata,
    TaskPlanningContext? planningContext,
    List<AcceptanceItem> inheritedAcceptance = const [],
    Map<String, int> criterionAgentNumbers = const {},
    Map<String, int> taskAgentNumbers = const {},
    Map<String, int> milestoneAgentNumbers = const {},
  }) {
    int? criterionNumber(String id) =>
        criterionAgentNumbers[id] ?? int.tryParse(id);
    int? taskAgentNumber(String id) => taskAgentNumbers[id] ?? int.tryParse(id);
    int? milestoneNumber(String id) =>
        milestoneAgentNumbers[id] ?? int.tryParse(id);

    final inheritedRefs = {for (final item in inheritedAcceptance) item.ref};
    final outOfScope = task.outOfScope.isNotEmpty
        ? task.outOfScope
        : planningContext?.outOfScope ?? const <String>[];
    final readPaths = task.readPaths.isNotEmpty
        ? task.readPaths
        : planningContext?.readPaths ?? const <String>[];
    final writePaths = task.writePaths.isNotEmpty
        ? task.writePaths
        : planningContext?.writePaths ?? const <String>[];
    final effectiveAcceptance = [
      for (final item in task.acceptance)
        _acceptanceWire(item, criterionNumber),
    ];
    final compactTask = <String, dynamic>{
      'task_id': taskNumber,
      'title': task.title,
      'objective': task.objective,
      'constraints': task.constraints,
      'out_of_scope': outOfScope,
      'read_paths': readPaths,
      'write_paths': writePaths,
      'context': task.context,
      'dependency_task_ids': [
        for (final id in task.dependsOnTaskIds) ?taskAgentNumber(id),
      ],
      'milestone_id': task.milestoneId == null
          ? null
          : milestoneNumber(task.milestoneId!),
      'priority': task.priority.name,
      'risk': task.risk.name,
      'risk_reduction': task.riskReduction.name,
      'effort': task.effort.name,
      'selection_rationale': task.selectionRationale,
      'status': task.status.wire,
      'acceptance': effectiveAcceptance,
      'inherited_acceptance_refs': inheritedRefs.toList()..sort(),
      'local_acceptance_refs': [
        for (final item in task.acceptance)
          if (!inheritedRefs.contains(item.ref)) item.ref,
      ]..sort(),
      'steps': [
        for (var index = 0; index < task.steps.length; index++)
          _stepWire(task.steps[index], index),
      ],
    };

    return {
      'schema_version': 1,
      'task': compactTask,
      'project': {
        if (planningContext != null) ...{
          'goal': planningContext.projectGoal,
          'criteria': [
            for (final criterion in planningContext.criteria)
              {
                'criterion_id': criterionNumber(criterion.id),
                'statement': criterion.statement,
                'required': criterion.required,
                'verification_mode': criterion.verificationMode,
              },
          ],
          'known_facts': planningContext.knownFacts,
          'workspace_orientation': planningContext.workspaceOrientation,
          'workspace_context': planningContext.workspaceContext,
          'max_steps': planningContext.maxSteps.clamp(1, 6),
        },
      },
      'workspace': _compactWorkspaceMetadata(metadata),
    };
  }

  static Map<String, dynamic> _acceptanceWire(
    AcceptanceItem item,
    int? Function(String) criterionNumber,
  ) => {
    'ref': item.ref,
    'statement': item.statement,
    'criterion_ids': [
      for (final id in item.criterionIds)
        if (criterionNumber(id) != null) criterionNumber(id)!,
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
          if (verifier.description != null) 'description': verifier.description,
        },
    ],
  };

  static Map<String, dynamic> _stepWire(TaskStep step, int index) {
    final compact = <String, dynamic>{
      'ref': step.planningRef.trim().isEmpty
          ? 'step_${index + 1}'
          : step.planningRef,
      'title': step.title,
      'status': step.status.wire,
    };
    final isCompleted =
        step.status == TaskStepStatus.completed ||
        step.status == TaskStepStatus.skipped;
    if (!isCompleted) {
      compact.addAll({
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
      });
    }
    return compact;
  }

  static Map<String, dynamic> _compactWorkspaceMetadata(
    WorkspaceMetadata metadata,
  ) {
    final raw = snakeCaseMap(ModelJson.encode(metadata));
    final profile = raw['workspace_profile'];
    final profileMap = profile is Map
        ? Map<String, dynamic>.from(profile)
        : const <String, dynamic>{};
    List<String> strings(Object? value, {int limit = 80}) => [
      if (value is List)
        for (final item in value)
          if (item is String) item,
    ].take(limit).toList();
    final highSignalFiles = <Map<String, dynamic>>[];
    final rawHighSignalFiles = profileMap['high_signal_files'];
    if (rawHighSignalFiles is List) {
      for (final rawFile in rawHighSignalFiles.take(6)) {
        if (rawFile is! Map) continue;
        final file = Map<String, dynamic>.from(rawFile);
        final content = file['content']?.toString() ?? '';
        highSignalFiles.add({
          'path': file['path']?.toString() ?? '',
          'content': content.length <= 2200
              ? content
              : '${content.substring(0, 2199).trimRight()}…',
          'truncated': file['truncated'] == true || content.length > 2200,
        });
      }
    }
    return {
      'workspace_name': raw['workspace_name'],
      'command_execution_approved': raw['command_execution_approved'],
      'root_files': strings(raw['root_files']),
      'git_available': raw['git_available'] == true,
      'tree_paths': strings(profileMap['tree_paths'], limit: 160),
      'high_signal_files': highSignalFiles,
      'package_name': profileMap['package_name'],
      'scripts': profileMap['scripts'],
      'dependencies': strings(profileMap['dependencies']),
      'languages': strings(profileMap['languages']),
      'frameworks': strings(profileMap['frameworks']),
      'tree_truncated': profileMap['tree_truncated'] == true,
    };
  }
}
