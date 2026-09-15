import 'package:hermes/core/models/task.dart';

/// A bounded read model used by the task-planning agent.
///
/// Execution runs and raw tool calls are intentionally not part of this
/// view. A planner gets enough state to decide what to add or preserve without
/// being asked to reproduce the task document.
class TaskViewService {
  const TaskViewService({this.defaultMaxItems = 12, this.maxTextLength = 600});

  final int defaultMaxItems;
  final int maxTextLength;

  Map<String, dynamic> query(
    Task task, {
    String? stepRef,
    int? maxItems,
    int? maxSteps,
    String? projectGoal,
    List<String> doneCriteria = const [],
    List<String> outOfScope = const [],
    List<String> readPaths = const [],
    List<String> writePaths = const [],
    List<TaskArtifact> requiredArtifacts = const [],
    List<TaskGate> requiredGates = const [],
    List<TaskProjectEvidenceExpectation> requiredEvidence = const [],
  }) {
    final limit = _limit(maxItems ?? defaultMaxItems);
    final result = <String, dynamic>{
      'task': {
        'id': task.id,
        'title': _text(task.title),
        'objective': _text(task.objective),
        'status': task.status.wire,
        'current_step_ref': task.currentStepId,
        'step_count': task.steps.length,
        'max_steps': maxSteps,
      },
      'constraints': [
        for (final item in task.constraints.take(limit)) _text(item),
      ],
      'success_criteria': [
        for (final item in task.successCriteria.take(limit)) _text(item),
      ],
      'steps': [for (final step in task.steps.take(limit)) _stepSummary(step)],
      'history': [
        for (final run in task.runs.reversed.take(limit))
          {
            'step_ref': run.stepId,
            'status': run.status.wire,
            'summary': _text(run.summary),
          },
      ],
      'memory': _text(task.memorySummary),
      'failure': task.failure == null
          ? null
          : {
              'gate_ref': task.failure!.gateId,
              'disposition': task.failure!.disposition.name,
              'summary': _text(task.failure!.summary),
              'error_codes': task.failure!.errorCodes.take(limit).toList(),
              'unresolved_error_count': task.failure!.unresolvedErrorCount,
            },
      'boundaries': {
        'project_goal': projectGoal == null ? null : _text(projectGoal),
        'done_criteria': [
          for (final item in doneCriteria.take(limit)) _text(item),
        ],
        'out_of_scope': [
          for (final item in outOfScope.take(limit)) _text(item),
        ],
        'read_paths': [for (final item in readPaths.take(limit)) _text(item)],
        'write_paths': [for (final item in writePaths.take(limit)) _text(item)],
        'expected_artifacts': [
          for (final artifact in requiredArtifacts.take(limit))
            {
              'path': _text(artifact.path),
              'description': artifact.description == null
                  ? null
                  : _text(artifact.description!),
              'kind': artifact.kind,
            },
        ],
      },
      'required_checks': [
        for (final gate in requiredGates.take(limit)) _gateSummary(gate),
      ],
      'required_project_evidence': [
        for (final item in requiredEvidence.take(limit))
          {
            'type': item.type,
            'description': _text(item.description),
            'required': item.required,
            'source_ref': item.sourceRef,
            'details': item.details,
          },
      ],
      'truncated': task.steps.length > limit || task.runs.length > limit,
    };

    final requested = stepRef?.trim();
    if (requested != null && requested.isNotEmpty) {
      final step = task.steps.where((item) => item.id == requested).firstOrNull;
      if (step == null) {
        throw TaskViewException(
          code: 'unknown_reference',
          path: 'step',
          message: 'Step reference $requested does not exist.',
        );
      }
      result['step_detail'] = {
        ..._stepSummary(step),
        'instructions': [
          for (final instruction in step.instructions.take(limit))
            _text(instruction),
        ],
        'artifacts': [
          for (final artifact in step.artifacts.take(limit))
            {
              'path': _text(artifact.path),
              'description': artifact.description == null
                  ? null
                  : _text(artifact.description!),
              'kind': artifact.kind,
            },
        ],
        'checks': [
          for (final gate in step.gates.take(limit)) _gateSummary(gate),
        ],
      };
    }
    return result;
  }

  Map<String, dynamic> _stepSummary(TaskStep step) => {
    'ref': step.id,
    'title': _text(step.title),
    'objective': _text(step.objective),
    'status': step.status.wire,
    'may_edit_files': step.mayEditFiles,
    'artifact_paths': [
      for (final artifact in step.artifacts) _text(artifact.path),
    ],
    'check_kinds': [for (final gate in step.gates) gate.id],
  };

  Map<String, dynamic> _gateSummary(TaskGate gate) => {
    'kind': gate.id,
    'scope': gate.scope,
    'required': gate.required,
    if (gate.params['command'] != null)
      'command': _text(gate.params['command'].toString()),
    if (gate.params['working_directory'] != null)
      'working_directory': _text(gate.params['working_directory'].toString()),
    'description': gate.description == null ? null : _text(gate.description!),
  };

  int _limit(int value) => value.clamp(1, defaultMaxItems * 4).toInt();

  String _text(String value) {
    final text = value.trim();
    if (text.length <= maxTextLength) return text;
    return '${text.substring(0, maxTextLength - 1).trimRight()}…';
  }
}

class TaskViewException implements Exception {
  final String code;
  final String path;
  final String message;

  const TaskViewException({
    required this.code,
    required this.path,
    required this.message,
  });

  @override
  String toString() => '$code ($path): $message';
}
