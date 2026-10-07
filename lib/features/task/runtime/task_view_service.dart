import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/view_pagination.dart';

/// A bounded read model used by the task-planning agent.
///
/// Execution runs and raw tool calls are intentionally not part of this
/// view. A planner gets enough state to decide what to add or preserve without
/// being asked to reproduce the task document.
class TaskViewService {
  static const viewSections = [
    'constraints',
    'success_criteria',
    'done_criteria',
    'out_of_scope',
    'read_paths',
    'write_paths',
    'expected_artifacts',
    'steps',
    'history',
    'required_checks',
    'required_project_evidence',
  ];

  const TaskViewService({this.defaultMaxItems = 12, this.maxTextLength = 600});

  final int defaultMaxItems;
  final int maxTextLength;

  Map<String, dynamic> query(
    TaskAggregate task, {
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
    String? section,
    String? cursor,
  }) {
    final limit = _limit(maxItems ?? defaultMaxItems);
    final navigation = _navigation(section: section, cursor: cursor);
    final constraints = _page(
      'constraints',
      task.constraints,
      limit,
      navigation,
    );
    final successCriteria = _page(
      'success_criteria',
      task.successCriteria,
      limit,
      navigation,
    );
    final doneCriteriaPage = _page(
      'done_criteria',
      doneCriteria,
      limit,
      navigation,
    );
    final outOfScopePage = _page('out_of_scope', outOfScope, limit, navigation);
    final readPathsPage = _page('read_paths', readPaths, limit, navigation);
    final writePathsPage = _page('write_paths', writePaths, limit, navigation);
    final expectedArtifactsPage = _page(
      'expected_artifacts',
      requiredArtifacts,
      limit,
      navigation,
    );
    final steps = _page('steps', task.steps, limit, navigation);
    final history = _page('history', task.runs.reversed, limit, navigation);
    final requiredChecks = _page(
      'required_checks',
      requiredGates,
      limit,
      navigation,
    );
    final requiredEvidencePage = _page(
      'required_project_evidence',
      requiredEvidence,
      limit,
      navigation,
    );
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
      'control': _controlState(task),
      'constraints': [for (final item in constraints.items) _text(item)],
      'success_criteria': [
        for (final item in successCriteria.items) _text(item),
      ],
      'steps': [for (final step in steps.items) _stepSummary(step)],
      'history': [
        for (final run in history.items)
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
          for (final item in doneCriteriaPage.items) _text(item),
        ],
        'out_of_scope': [for (final item in outOfScopePage.items) _text(item)],
        'read_paths': [for (final item in readPathsPage.items) _text(item)],
        'write_paths': [for (final item in writePathsPage.items) _text(item)],
        'expected_artifacts': [
          for (final artifact in expectedArtifactsPage.items)
            _artifactSummary(artifact),
        ],
      },
      'required_checks': [
        for (final gate in requiredChecks.items) _gateSummary(gate),
      ],
      'required_project_evidence': [
        for (final item in requiredEvidencePage.items)
          _evidenceSummary(item, limit),
      ],
      'truncated': task.steps.length > limit || task.runs.length > limit,
      'truncated_sections': {
        'constraints': constraints.hasMore,
        'success_criteria': successCriteria.hasMore,
        'done_criteria': doneCriteriaPage.hasMore,
        'out_of_scope': outOfScopePage.hasMore,
        'read_paths': readPathsPage.hasMore,
        'write_paths': writePathsPage.hasMore,
        'expected_artifacts': expectedArtifactsPage.hasMore,
        'steps': steps.hasMore,
        'history': history.hasMore,
        'required_checks': requiredChecks.hasMore,
        'required_project_evidence': requiredEvidencePage.hasMore,
      },
      'navigation': {
        'requested_section': navigation.selectedSection,
        'pages': {
          'constraints': constraints.toMap(
            cursor: navigation.cursorFor('constraints'),
          ),
          'success_criteria': successCriteria.toMap(
            cursor: navigation.cursorFor('success_criteria'),
          ),
          'done_criteria': doneCriteriaPage.toMap(
            cursor: navigation.cursorFor('done_criteria'),
          ),
          'out_of_scope': outOfScopePage.toMap(
            cursor: navigation.cursorFor('out_of_scope'),
          ),
          'read_paths': readPathsPage.toMap(
            cursor: navigation.cursorFor('read_paths'),
          ),
          'write_paths': writePathsPage.toMap(
            cursor: navigation.cursorFor('write_paths'),
          ),
          'expected_artifacts': expectedArtifactsPage.toMap(
            cursor: navigation.cursorFor('expected_artifacts'),
          ),
          'steps': steps.toMap(cursor: navigation.cursorFor('steps')),
          'history': history.toMap(cursor: navigation.cursorFor('history')),
          'required_checks': requiredChecks.toMap(
            cursor: navigation.cursorFor('required_checks'),
          ),
          'required_project_evidence': requiredEvidencePage.toMap(
            cursor: navigation.cursorFor('required_project_evidence'),
          ),
        },
      },
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
            _artifactSummary(artifact),
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

  Map<String, dynamic> _artifactSummary(TaskArtifact artifact) => {
    'path': _text(artifact.path),
    'description': artifact.description == null
        ? null
        : _text(artifact.description!),
    'kind': artifact.kind,
  };

  Map<String, dynamic> _evidenceSummary(
    TaskProjectEvidenceExpectation item,
    int limit,
  ) => {
    'type': item.type,
    'criterion_refs': item.criterionIds.take(limit).toList(),
    'description': _text(item.description),
    'required': item.required,
    'source_ref': item.sourceRef,
    'details': item.details,
  };

  Map<String, dynamic> _controlState(TaskAggregate task) => {
    'outcome': task.pendingApproval != null
        ? 'awaiting_approval'
        : task.pendingQuestion != null
        ? 'awaiting_user_input'
        : task.status.wire,
    'action': task.pendingApproval != null
        ? 'approve_or_reject_step'
        : task.pendingQuestion != null
        ? 'answer_question'
        : null,
    'pending_approval': task.pendingApproval == null
        ? null
        : {
            'step_ref': task.pendingApproval!.stepId,
            'reason': _text(task.pendingApproval!.reason),
            'created_at': task.pendingApproval!.createdAt
                .toUtc()
                .toIso8601String(),
          },
    'pending_question': task.pendingQuestion == null
        ? null
        : {
            'id': task.pendingQuestion!.id,
            'step_ref': task.pendingQuestion!.stepId,
            'question': _text(task.pendingQuestion!.question),
            'created_at': task.pendingQuestion!.createdAt
                .toUtc()
                .toIso8601String(),
          },
    'open_questions': task.pendingQuestion == null
        ? const []
        : [
            {
              'id': task.pendingQuestion!.id,
              'step_ref': task.pendingQuestion!.stepId,
              'question': _text(task.pendingQuestion!.question),
            },
          ],
    'current_step_ref': task.currentStepId,
    'planning_error': task.planningError == null
        ? null
        : _text(task.planningError!),
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

  _TaskViewNavigation _navigation({String? section, String? cursor}) {
    final requested = section?.trim();
    final parsed = cursor == null || cursor.trim().isEmpty
        ? null
        : _decodeCursor(cursor);
    final selected = requested == null || requested.isEmpty
        ? parsed?.collection
        : requested;
    if (selected != null && !viewSections.contains(selected)) {
      throw TaskViewException(
        code: 'unknown_section',
        path: 'section',
        message: 'Unknown task view section $selected.',
      );
    }
    if (parsed != null && selected != parsed.collection) {
      throw TaskViewException(
        code: 'cursor_section_mismatch',
        path: 'cursor',
        message:
            'Cursor section ${parsed.collection} does not match $selected.',
      );
    }
    return _TaskViewNavigation(section: selected, cursor: cursor);
  }

  ViewCursor? _decodeCursor(String cursor) {
    try {
      final decoded = ViewCursor.decode(cursor);
      if (!viewSections.contains(decoded.collection)) {
        throw const FormatException('Unknown task view cursor collection.');
      }
      return decoded;
    } on FormatException catch (error) {
      throw TaskViewException(
        code: 'invalid_cursor',
        path: 'cursor',
        message: error.message,
      );
    }
  }

  ViewPage<T> _page<T>(
    String collection,
    Iterable<T> values,
    int limit,
    _TaskViewNavigation navigation,
  ) {
    final cursor = navigation.cursorFor(collection);
    try {
      return paginateView(
        collection: collection,
        values: values,
        limit: limit,
        cursor: cursor,
      );
    } on FormatException catch (error) {
      throw TaskViewException(
        code: 'invalid_cursor',
        path: 'cursor',
        message: error.message,
      );
    }
  }

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

class _TaskViewNavigation {
  const _TaskViewNavigation({this.section, this.cursor});

  final String? section;
  final String? cursor;

  String? get selectedSection => section;

  String? cursorFor(String collection) => section == collection ? cursor : null;
}
