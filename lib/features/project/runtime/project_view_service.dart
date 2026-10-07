import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/domain/project_control_state_service.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/core/view_pagination.dart';

/// A bounded read model for project planning.
///
/// This deliberately does not serialize [ProjectAggregate] or [TaskAggregate]. Runtime
/// execution data such as runs, logs, gate results, and full evidence stays
/// behind the task and execution services.
class ProjectViewService {
  static const viewSections = [
    'constraints',
    'criteria',
    'milestones',
    'tasks',
    'ready_tasks',
    'blocked_tasks',
    'pending_questions',
    'recent_failures',
    'memory',
    'workspace',
  ];

  const ProjectViewService({
    this.defaultMaxItems = 20,
    this.maxTextLength = 600,
    ProjectScheduler scheduler = const ProjectScheduler(),
    ProjectWorkspaceContextService workspaceContextService =
        const ProjectWorkspaceContextService(),
  }) : _scheduler = scheduler,
       _workspaceContextService = workspaceContextService;

  final int defaultMaxItems;
  final int maxTextLength;
  final ProjectScheduler _scheduler;
  final ProjectWorkspaceContextService _workspaceContextService;

  Map<String, dynamic> query(
    ProjectAggregate project, {
    String? taskRef,
    String? criterionRef,
    String? memoryQuery,
    String? workspaceQuery,
    int? maxItems,
    String? section,
    String? cursor,
  }) {
    final limit = _limit(maxItems ?? defaultMaxItems);
    final navigation = _navigation(section: section, cursor: cursor);
    final selectedSection = navigation.selectedSection;
    final schedule = _scheduler.refreshReadiness(project);
    final tasks = _plannerTasks(project);
    final criteria = _page('criteria', project.criteria, limit, navigation);
    final milestones = _page(
      'milestones',
      (project.milestones.toList()..sort((a, b) => a.order.compareTo(b.order))),
      limit,
      navigation,
    );
    final constraints = _page(
      'constraints',
      project.constraints,
      limit,
      navigation,
    );
    final taskPage = _page('tasks', tasks, limit, navigation);
    final readyTasks = _scheduler.orderedReadyTasks(project).toList();
    final readyTaskPage = _page('ready_tasks', readyTasks, limit, navigation);
    final blockedTasks = [
      for (final task in project.tasks)
        if (schedule.readinessFor(task.id) != TaskReadiness.ready &&
            _isPlannerRelevant(task))
          task,
    ];
    final blockedTaskPage = _page(
      'blocked_tasks',
      blockedTasks,
      limit,
      navigation,
    );
    final pendingQuestions = _page(
      'pending_questions',
      project.openQuestions,
      limit,
      navigation,
    );
    final recentFailures = _page(
      'recent_failures',
      _recentFailures(project, limit),
      limit,
      navigation,
    );
    final workspace = _workspaceContextService.selectContext(
      project: project,
      maxCharacters: 6000,
      maxSelectedNodes: limit,
      maxSelectedEdges: limit * 2,
    );
    final result = <String, dynamic>{
      'project': {
        'id': project.id,
        'title': _text(project.title),
        'status': project.status.wire,
        'base_revision': project.nextRevision - 1,
        'active_task_ref': project.activeTaskId,
      },
      'control': controlState(project, maxItems: limit),
      'goal': {
        'original': _text(project.originalGoal),
        'refined': _text(project.refinedGoal),
      },
      'constraints': [for (final item in constraints.items) _text(item)],
      'criteria': [
        for (final criterion in criteria.items) _criterionSummary(criterion),
      ],
      'milestones': [
        for (final milestone in milestones.items)
          _milestoneSummary(milestone, limit),
      ],
      'workspaceGraph': {
        ...workspace.toMap(maxItems: limit),
        'node_count': project.workspaceGraph.nodes.length,
        'edge_count': project.workspaceGraph.edges.length,
      },
      'tasks': [
        for (final task in taskPage.items) _taskSummary(task, schedule, limit),
      ],
      'ready_tasks': [
        for (final task in readyTaskPage.items)
          _taskSummary(task, schedule, limit),
      ],
      'blocked_tasks': [
        for (final task in blockedTaskPage.items)
          {
            'ref': task.id,
            'title': _text(task.title),
            'readiness': _readinessWire(schedule.readinessFor(task.id)),
            'reasons': [
              for (final reason in schedule.reasonsFor(task.id).take(4))
                _text(reason),
            ],
          },
      ].toList(),
      'current_blocker': _blockerSummary(project),
      'pending_questions': [
        for (final question in pendingQuestions.items)
          {'id': question.id, 'question': _text(question.question)},
      ],
      'recent_failures': recentFailures.items,
      'truncated': {
        'constraints': constraints.hasMore,
        'criteria': criteria.hasMore,
        'milestones': milestones.hasMore,
        'tasks': taskPage.hasMore,
        'ready_tasks': readyTaskPage.hasMore,
        'blocked_tasks': blockedTaskPage.hasMore,
        'pending_questions': pendingQuestions.hasMore,
        'recent_failures': recentFailures.hasMore,
      },
      'navigation': {
        'requested_section': selectedSection,
        'pages': {
          'constraints': constraints.toMap(
            cursor: navigation.cursorFor('constraints'),
          ),
          'criteria': criteria.toMap(cursor: navigation.cursorFor('criteria')),
          'milestones': milestones.toMap(
            cursor: navigation.cursorFor('milestones'),
          ),
          'tasks': taskPage.toMap(cursor: navigation.cursorFor('tasks')),
          'ready_tasks': readyTaskPage.toMap(
            cursor: navigation.cursorFor('ready_tasks'),
          ),
          'blocked_tasks': blockedTaskPage.toMap(
            cursor: navigation.cursorFor('blocked_tasks'),
          ),
          'pending_questions': pendingQuestions.toMap(
            cursor: navigation.cursorFor('pending_questions'),
          ),
          'recent_failures': recentFailures.toMap(
            cursor: navigation.cursorFor('recent_failures'),
          ),
        },
      },
    };

    final requestedTask = taskRef?.trim();
    if (requestedTask != null && requestedTask.isNotEmpty) {
      final task = project.taskById(requestedTask);
      if (task == null) {
        throw ProjectViewException(
          code: 'unknown_reference',
          path: 'task',
          message: 'Task reference $requestedTask does not exist.',
        );
      }
      result['task_detail'] = _taskDetail(task, schedule, limit);
    }

    final requestedCriterion = criterionRef?.trim();
    if (requestedCriterion != null && requestedCriterion.isNotEmpty) {
      final criterion = project.criteria
          .where((item) => item.id == requestedCriterion)
          .firstOrNull;
      if (criterion == null) {
        throw ProjectViewException(
          code: 'unknown_reference',
          path: 'criterion',
          message: 'Criterion reference $requestedCriterion does not exist.',
        );
      }
      result['criterion_detail'] = _criterionDetail(project, criterion, limit);
    }

    final memorySearch =
        memoryQuery?.trim() ??
        (navigation.selectedSection == 'memory'
            ? navigation.cursorScope
            : null);
    if (memorySearch != null && memorySearch.isNotEmpty) {
      final normalised = memorySearch.toLowerCase();
      final matches = [
        for (final entry in project.memory)
          if (entry.active &&
              '${entry.content} ${entry.kind.name} ${entry.sourceId ?? ''}'
                  .toLowerCase()
                  .contains(normalised))
            _memorySummary(entry),
      ];
      final page = _page(
        'memory',
        matches,
        limit,
        navigation,
        scope: normalised,
      );
      result['memory_detail'] = page.items;
      (result['navigation']! as Map)['pages']['memory'] = page.toMap(
        cursor: navigation.cursorFor('memory'),
      );
      (result['truncated']! as Map)['memory'] = page.hasMore;
    }

    final workspaceSearch =
        workspaceQuery?.trim() ??
        (navigation.selectedSection == 'workspace'
            ? navigation.cursorScope
            : null);
    if (workspaceSearch != null && workspaceSearch.isNotEmpty) {
      final query = workspaceSearch.toLowerCase();
      final matchingNodes = [
        for (final node in project.workspaceGraph.nodes)
          if ('${node.id} ${node.type} ${node.title} ${node.description} '
                  '${node.aliases.join(' ')} ${node.tags.join(' ')} '
                  '${node.references.join(' ')}'
              .toLowerCase()
              .contains(query))
            node,
      ]..sort((a, b) => a.id.compareTo(b.id));
      final matches = [
        for (final node in matchingNodes)
          {
            ..._workspaceNodeSummary(node, limit),
            'relationships': _workspaceRelationships(project, node.id, limit),
          },
      ];
      final page = _page('workspace', matches, limit, navigation, scope: query);
      result['workspace_detail'] = page.items;
      (result['navigation']! as Map)['pages']['workspace'] = page.toMap(
        cursor: navigation.cursorFor('workspace'),
      );
      (result['truncated']! as Map)['workspace'] = page.hasMore;
    }

    return result;
  }

  List<ProjectTaskNode> _plannerTasks(ProjectAggregate project) {
    final relevant = _plannerRelevantTasks(project);
    final active = relevant.where((task) => !_isTerminal(task)).toList();
    final recent = relevant.toList()
      ..sort((a, b) {
        final updated = b.updatedAt.compareTo(a.updatedAt);
        return updated != 0 ? updated : a.id.compareTo(b.id);
      });
    final selected = <ProjectTaskNode>[];
    for (final task in [...active, ...recent]) {
      if (selected.any((item) => item.id == task.id)) continue;
      selected.add(task);
    }
    return selected;
  }

  _ProjectViewNavigation _navigation({String? section, String? cursor}) {
    final requested = section?.trim();
    final parsed = cursor == null || cursor.trim().isEmpty
        ? null
        : _decodeCursor(cursor);
    final selected = requested == null || requested.isEmpty
        ? parsed?.collection
        : requested;
    if (selected != null && !viewSections.contains(selected)) {
      throw ProjectViewException(
        code: 'unknown_section',
        path: 'section',
        message: 'Unknown project view section $selected.',
      );
    }
    if (parsed != null && selected != parsed.collection) {
      throw ProjectViewException(
        code: 'cursor_section_mismatch',
        path: 'cursor',
        message:
            'Cursor section ${parsed.collection} does not match $selected.',
      );
    }
    return _ProjectViewNavigation(
      section: selected,
      cursor: cursor,
      cursorScope: parsed?.scope,
    );
  }

  ViewCursor? _decodeCursor(String cursor) {
    try {
      final decoded = ViewCursor.decode(cursor);
      if (!viewSections.contains(decoded.collection)) {
        throw const FormatException('Unknown project view cursor collection.');
      }
      return decoded;
    } on FormatException catch (error) {
      throw ProjectViewException(
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
    _ProjectViewNavigation navigation, {
    String? scope,
  }) {
    final cursor = navigation.cursorFor(collection);
    try {
      return paginateView(
        collection: collection,
        values: values,
        limit: limit,
        cursor: cursor,
        scope: scope,
      );
    } on FormatException catch (error) {
      throw ProjectViewException(
        code: 'invalid_cursor',
        path: 'cursor',
        message: error.message,
      );
    }
  }

  List<ProjectTaskNode> _plannerRelevantTasks(ProjectAggregate project) => [
    for (final task in project.tasks)
      if (!_isTerminal(task) || task.status == TaskStatus.completed) task,
  ];

  Map<String, dynamic> _criterionSummary(ProjectCriterion criterion) => {
    'ref': criterion.id,
    'statement': _text(criterion.statement),
    'required': criterion.required,
    'status': criterion.status.name,
    'verification_mode': criterion.verificationMode.name,
  };

  Map<String, dynamic> _workspaceNodeSummary(
    ProjectWorkspaceNode node,
    int limit,
  ) => {
    'id': node.id,
    'type': _text(node.type),
    'title': _text(node.title),
    'description': _text(node.description),
    'aliases': [for (final item in node.aliases.take(limit)) _text(item)],
    'tags': [for (final item in node.tags.take(limit)) _text(item)],
    'references': [for (final item in node.references.take(limit)) _text(item)],
    'source': node.sourceType.name,
    'source_id': node.sourceId == null ? null : _text(node.sourceId!),
    'confidence': node.confidence.name,
    'protected': node.protected,
  };

  Map<String, dynamic> _workspaceEdgeSummary(ProjectWorkspaceEdge edge) => {
    'id': edge.id,
    'source_node_id': edge.sourceNodeId,
    'target_node_id': edge.targetNodeId,
    'label': _text(edge.label),
    'description': _text(edge.description),
    'source': edge.sourceType.name,
    'source_id': edge.sourceId == null ? null : _text(edge.sourceId!),
    'confidence': edge.confidence.name,
    'protected': edge.protected,
  };

  List<Map<String, dynamic>> _workspaceRelationships(
    ProjectAggregate project,
    String nodeId,
    int limit,
  ) {
    final relationships = [
      for (final edge in project.workspaceGraph.edges)
        if (edge.sourceNodeId == nodeId || edge.targetNodeId == nodeId)
          _workspaceEdgeSummary(edge),
    ];
    relationships.sort((a, b) {
      final label = (a['label'] as String).compareTo(b['label'] as String);
      return label != 0
          ? label
          : (a['id'] as String).compareTo(b['id'] as String);
    });
    return relationships.take(limit * 2).toList();
  }

  Map<String, dynamic> _criterionDetail(
    ProjectAggregate project,
    ProjectCriterion criterion,
    int limit,
  ) => {
    ..._criterionSummary(criterion),
    'notes': _text(criterion.notes),
    'linked_task_refs': [
      for (final task in project.tasks)
        if (task.criterionIds.contains(criterion.id)) task.id,
    ].take(limit).toList(),
  };

  Map<String, dynamic> _milestoneSummary(
    ProjectMilestone milestone,
    int limit,
  ) => {
    'ref': milestone.id,
    'title': _text(milestone.title),
    'objective': _text(milestone.objective),
    'status': milestone.status.name,
    'criterion_refs': milestone.criterionIds.take(limit).toList(),
  };

  Map<String, dynamic> _taskSummary(
    ProjectTaskNode task,
    ProjectScheduleResult schedule,
    int limit,
  ) => {
    'ref': task.id,
    'title': _text(task.title),
    'objective': _text(task.objective),
    'status': task.status.wire,
    'readiness': _readinessWire(schedule.readinessFor(task.id)),
    'criterion_refs': task.criterionIds.take(limit).toList(),
    'milestone_ref': task.milestoneId,
    'dependency_refs': task.dependsOnTaskIds.take(limit).toList(),
    'priority': task.priority.name,
    'risk': task.risk.name,
    'risk_reduction': task.riskReduction.name,
    'effort': task.effort.name,
    'updated_at': task.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> _taskDetail(
    ProjectTaskNode task,
    ProjectScheduleResult schedule,
    int limit,
  ) => {
    ..._taskSummary(task, schedule, limit),
    'constraints': [
      for (final item in task.constraints.take(limit)) _text(item),
    ],
    'read_paths': [for (final path in task.readPaths.take(limit)) _text(path)],
    'write_paths': [
      for (final path in task.writePaths.take(limit)) _text(path),
    ],
    'done_criteria': [
      for (final item in task.doneCriteria.take(limit)) _text(item),
    ],
    'out_of_scope': [
      for (final item in task.outOfScope.take(limit)) _text(item),
    ],
    'context': [for (final item in task.context.take(limit)) _text(item)],
    'expected_artifacts': [
      for (final artifact in task.expectedArtifacts.take(limit))
        {
          'path': _text(artifact.path),
          'description': artifact.description == null
              ? null
              : _text(artifact.description!),
          'kind': artifact.kind,
        },
    ],
    'rejection_reason': task.rejectionReason == null
        ? null
        : _text(task.rejectionReason!),
    'failure': task.failureKey == null
        ? null
        : {
            'key': _text(task.failureKey!),
            'gate_ref': task.failureGateId,
            'error_codes': [
              for (final code in task.failureErrorCodes.take(limit))
                _text(code),
            ],
            'unresolved_error_count': task.unresolvedErrorCount,
          },
    'checks': [
      for (final gate in task.gates.take(limit))
        {
          'kind': gate.id,
          'required': gate.required,
          'command': gate.params['command'] == null
              ? null
              : _text(gate.params['command'].toString()),
          'working_directory': gate.params['working_directory'] == null
              ? null
              : _text(gate.params['working_directory'].toString()),
          'description': gate.description == null
              ? null
              : _text(gate.description!),
        },
    ],
    'evidence_intents': [
      for (final expectation in task.expectedEvidence.take(limit))
        {
          'kind': expectation.type.name,
          'criterion_refs': expectation.criterionIds.take(limit).toList(),
          'description': _text(expectation.description),
          'required': expectation.required,
          'source_ref': expectation.sourceRef == null
              ? null
              : _text(expectation.sourceRef!),
        },
    ],
  };

  List<Map<String, dynamic>> _recentFailures(
    ProjectAggregate project,
    int limit,
  ) {
    final failures = <_FailureSummary>[];
    for (final task in project.tasks) {
      final summary = task.failureKey?.trim();
      final rejection = task.rejectionReason?.trim();
      if ((task.status == TaskStatus.failed ||
              task.status == TaskStatus.rejected) &&
          (summary?.isNotEmpty == true || rejection?.isNotEmpty == true)) {
        failures.add(
          _FailureSummary(
            updatedAt: task.updatedAt,
            value: {
              'source': 'task',
              'task_ref': task.id,
              'summary': _text(
                summary?.isNotEmpty == true ? summary! : rejection!,
              ),
              'status': task.status.wire,
            },
          ),
        );
      }
    }
    for (final incident in project.recoveryIncidents) {
      failures.add(
        _FailureSummary(
          updatedAt: incident.updatedAt,
          value: {
            'source': 'recovery',
            'incident_ref': incident.id,
            'task_refs': incident.sourceTaskIds.take(limit).toList(),
            'summary': _text(incident.failureSummary),
            'status': incident.status.name,
            'attempts': incident.attemptCount,
          },
        ),
      );
    }
    failures.sort((a, b) {
      final updated = b.updatedAt.compareTo(a.updatedAt);
      return updated != 0
          ? updated
          : a.value.toString().compareTo(b.value.toString());
    });
    return [for (final item in failures) item.value];
  }

  Map<String, dynamic>? _blockerSummary(ProjectAggregate project) {
    final blocker = project.blocker;
    if (blocker == null) return null;
    return {
      'type': blocker.type.wire,
      'message': _text(blocker.message),
      'task_ref': blocker.taskId,
    };
  }

  /// Returns the bounded, model-facing control state without exposing the
  /// complete project aggregate or the pending desired plan.
  Map<String, dynamic> controlState(ProjectAggregate project, {int? maxItems}) {
    final boundary = const ProjectControlStateMachine().read(project);
    final approval = project.pendingPlanApproval;
    final limit = _limit(maxItems ?? defaultMaxItems);
    return {
      'outcome': boundary.outcome.wire,
      'action': boundary.action,
      'reason_code': boundary.reasonCode,
      'message': _text(boundary.message),
      'task_ref': boundary.taskId,
      'blocker': _blockerSummary(project),
      'pending_plan_approval': approval == null
          ? null
          : {
              'revision': approval.revision,
              'reason': _text(approval.reason),
              'summary': _text(approval.summary),
              'high_risk_changes': [
                for (final item in approval.highRiskChanges.take(limit))
                  _text(item),
              ],
              'high_risk_reason_codes': approval.highRiskReasonCodes
                  .take(limit)
                  .toList(),
              'created_at': approval.createdAt.toUtc().toIso8601String(),
            },
      'open_questions': [
        for (final question in project.openQuestions.take(limit))
          {
            'id': question.id,
            'question': _text(question.question),
            'created_at': question.createdAt.toUtc().toIso8601String(),
          },
      ],
    };
  }

  Map<String, dynamic> _memorySummary(ProjectMemoryEntry entry) => {
    'id': entry.id,
    'kind': entry.kind.name,
    'content': _text(entry.content),
    'source_id': entry.sourceId == null ? null : _text(entry.sourceId!),
    'confidence': entry.confidence.name,
  };

  int _limit(int requested) => requested.clamp(1, 100).toInt();

  String _text(String value) {
    final text = value.trim();
    if (text.length <= maxTextLength) return text;
    return '${text.substring(0, maxTextLength - 1).trimRight()}…';
  }

  static bool _isPlannerRelevant(ProjectTaskNode task) => !_isTerminal(task);

  static bool _isTerminal(ProjectTaskNode task) => switch (task.status) {
    TaskStatus.completed ||
    TaskStatus.failed ||
    TaskStatus.rejected ||
    TaskStatus.split ||
    TaskStatus.cancelled ||
    TaskStatus.deferred ||
    TaskStatus.obsolete => true,
    _ => false,
  };

  static String _readinessWire(TaskReadiness readiness) => switch (readiness) {
    TaskReadiness.waitingDependency => 'waiting_dependency',
    TaskReadiness.waitingInput => 'waiting_input',
    TaskReadiness.notEligible => 'not_eligible',
    TaskReadiness.ready => 'ready',
  };
}

class ProjectViewException implements Exception {
  final String code;
  final String path;
  final String message;

  const ProjectViewException({
    required this.code,
    required this.path,
    required this.message,
  });

  @override
  String toString() => '$code ($path): $message';
}

class _ProjectViewNavigation {
  const _ProjectViewNavigation({this.section, this.cursor, this.cursorScope});

  final String? section;
  final String? cursor;
  final String? cursorScope;

  String? get selectedSection => section;

  String? cursorFor(String collection) => section == collection ? cursor : null;
}

class _FailureSummary {
  final DateTime updatedAt;
  final Map<String, dynamic> value;

  const _FailureSummary({required this.updatedAt, required this.value});
}
