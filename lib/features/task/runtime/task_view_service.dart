import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/core/view_pagination.dart';

/// A bounded read model used by the task-planning agent.
///
/// Execution runs and raw tool calls are intentionally not part of this
/// view. A planner gets enough state to decide what to add or preserve without
/// being asked to reproduce the task document.
class TaskViewService {
  static const viewSections = [
    'constraints',
    'out_of_scope',
    'read_paths',
    'write_paths',
    'steps',
    'history',
    'acceptance',
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
    List<String> outOfScope = const [],
    List<String> readPaths = const [],
    List<String> writePaths = const [],
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
    final outOfScopePage = _page('out_of_scope', outOfScope, limit, navigation);
    final readPathsPage = _page('read_paths', readPaths, limit, navigation);
    final writePathsPage = _page('write_paths', writePaths, limit, navigation);
    final steps = _page('steps', task.steps, limit, navigation);
    final history = _page('history', task.runs.reversed, limit, navigation);
    final acceptancePage = _page(
      'acceptance',
      task.acceptance,
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
      'acceptance': [
        for (final item in acceptancePage.items) _acceptanceSummary(item, task),
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
              'disposition': task.failure!.disposition.name,
              'summary': _text(task.failure!.summary),
              'error_codes': task.failure!.errorCodes.take(limit).toList(),
              'unresolved_error_count': task.failure!.unresolvedErrorCount,
            },
      'boundaries': {
        'project_goal': projectGoal == null ? null : _text(projectGoal),
        'out_of_scope': [for (final item in outOfScopePage.items) _text(item)],
        'read_paths': [for (final item in readPathsPage.items) _text(item)],
        'write_paths': [for (final item in writePathsPage.items) _text(item)],
      },
      'truncated': task.steps.length > limit || task.runs.length > limit,
      'truncated_sections': {
        'constraints': constraints.hasMore,
        'out_of_scope': outOfScopePage.hasMore,
        'read_paths': readPathsPage.hasMore,
        'write_paths': writePathsPage.hasMore,
        'steps': steps.hasMore,
        'history': history.hasMore,
        'acceptance': acceptancePage.hasMore,
      },
      'navigation': {
        'requested_section': navigation.selectedSection,
        'pages': {
          'constraints': constraints.toMap(
            cursor: navigation.cursorFor('constraints'),
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
          'steps': steps.toMap(cursor: navigation.cursorFor('steps')),
          'history': history.toMap(cursor: navigation.cursorFor('history')),
          'acceptance': acceptancePage.toMap(
            cursor: navigation.cursorFor('acceptance'),
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
        'acceptance': [
          for (final item in task.acceptance)
            if (step.acceptanceRefs.contains(item.ref))
              _acceptanceSummary(item, task),
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
    'acceptance_refs': step.acceptanceRefs,
  };

  Map<String, dynamic> _acceptanceSummary(
    AcceptanceItem item,
    TaskAggregate task,
  ) => {
    'ref': item.ref,
    'statement': _text(item.statement),
    'criterion_refs': item.criterionIds,
    'verifiers': [
      for (var index = 0; index < item.verifiers.length; index++)
        _verifierSummary(item, task, index),
    ],
  };

  Map<String, dynamic> _verifierSummary(
    AcceptanceItem item,
    TaskAggregate task,
    int index,
  ) {
    final verifier = item.verifiers[index];
    final result = _verifierResult(task, item.ref, index);
    return {
      'kind': verifier.kind.name,
      'required': verifier.required,
      'status': result?.status.wire ?? 'pending',
      if (verifier.required &&
          (result == null ||
              result.status == TaskGateStatus.failed ||
              result.status == TaskGateStatus.pending))
        'blocking_explanation': _text(
          result?.summary ?? 'This required verifier has not passed.',
        ),
      if (verifier.command != null) 'command': _text(verifier.command!),
      if (verifier.path != null) 'path': _text(verifier.path!),
      if (verifier.description != null)
        'description': _text(verifier.description!),
    };
  }

  TaskGateResult? _verifierResult(
    TaskAggregate task,
    String acceptanceRef,
    int index,
  ) {
    for (final run in task.runs.reversed) {
      for (final result in run.gateResults.reversed) {
        if (result.details['acceptance_ref']?.toString() == acceptanceRef &&
            result.details['verifier_index'] == index) {
          return result;
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _artifactSummary(TaskArtifact artifact) => {
    'path': _text(artifact.path),
    'description': artifact.description == null
        ? null
        : _text(artifact.description!),
    'kind': artifact.kind,
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
