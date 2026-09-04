part of 'project.dart';

class ProjectStateJsonHook extends JsonModelHook {
  const ProjectStateJsonHook()
    : super(
        removeKeys: const {
          'originalPrompt',
          'goal',
          'successCriteria',
          'knownFacts',
          'memorySummary',
          'tasks',
          'pendingQuestion',
        },
        outputOverrides: const {
          'schemaVersion': ProjectState.currentSchemaVersion,
        },
      );

  @override
  Object? beforeDecode(Object? value) {
    final normalized = super.beforeDecode(value);
    if (normalized is! Map) return normalized;
    final json = Map<String, dynamic>.from(normalized);
    json['refinedGoal'] ??= json['goal'] ?? json['objective'];
    final questions = jsonMapList(json['openQuestions']);
    final pendingQuestion = json['pendingQuestion'];
    if (questions.isEmpty && pendingQuestion is Map) {
      json['openQuestions'] = [Map<String, dynamic>.from(pendingQuestion)];
    }
    final version = jsonInt(json['schemaVersion']);
    if (version > ProjectState.currentSchemaVersion) {
      throw FormatException(
        'Unsupported project schema version $version; maximum supported '
        'version is ${ProjectState.currentSchemaVersion}.',
      );
    }
    final isV1 =
        version < 2 ||
        (!json.containsKey('originalGoal') &&
            json.containsKey('originalPrompt'));
    var migrated = isV1 ? ProjectJsonMigration.upgradeV1(json) : json;
    if (jsonInt(migrated['schemaVersion']) < 3) {
      migrated = ProjectJsonMigration.upgradeV2(migrated);
    }
    if (jsonInt(migrated['schemaVersion']) < 4) {
      migrated = ProjectJsonMigration.upgradeV3(migrated);
    }
    migrated['schemaVersion'] = ProjectState.currentSchemaVersion;
    return migrated;
  }
}

class ProjectTaskJsonHook extends JsonModelHook {
  const ProjectTaskJsonHook()
    : super(
        removeKeys: const {'relevantSuccessCriteria'},
        aliases: const {
          'objective': ['prompt'],
          'criterionIds': [
            'relevantSuccessCriteria',
            'relevant_success_criteria',
            'successCriteria',
            'success_criteria',
          ],
        },
      );

  @override
  Object? afterDecode(Object? value) {
    if (value is! ProjectTask || value.fingerprint.isNotEmpty) return value;
    return value.copyWith(
      fingerprint: projectTaskFingerprint(value.objective, value.criterionIds),
    );
  }
}

class ProjectArtifactJsonHook extends JsonModelHook {
  const ProjectArtifactJsonHook();

  @override
  Object? afterDecode(Object? value) {
    if (value is! ProjectArtifact || value.id.isNotEmpty) return value;
    return value.copyWith(id: value.path);
  }
}

abstract final class ProjectJsonMigration {
  static Map<String, dynamic> upgradeV1(Map<String, dynamic> json) {
    final now = DateTime.now();
    final originalGoal = jsonString(json['originalPrompt']);
    final refinedGoal = jsonString(
      json['goal'] ?? json['objective'],
      fallback: originalGoal,
    );
    final activeTaskId = jsonNullableString(json['activeTaskId']);
    final backlog = <Map<String, dynamic>>[];
    final completedTasks = <Map<String, dynamic>>[];
    final failedTasks = <Map<String, dynamic>>[];
    Map<String, dynamic>? currentTask;

    for (final raw in jsonMapList(json['tasks'])) {
      final taskId = jsonString(raw['taskId'] ?? raw['task_id']);
      final taskStatus = parseTaskStatus(raw['status']);
      final task = _legacyTask(raw, taskId, taskStatus, now);
      if (taskId == activeTaskId && !taskStatus.isTerminal) {
        task['status'] = ProjectTaskStatus.running.wire;
        currentTask = task;
      } else if (taskStatus == TaskStatus.completed) {
        task['status'] = ProjectTaskStatus.completed.wire;
        completedTasks.add(task);
      } else if (taskStatus == TaskStatus.failed ||
          taskStatus == TaskStatus.cancelled ||
          taskStatus == TaskStatus.blocked) {
        task['status'] = ProjectTaskStatus.failed.wire;
        failedTasks.add(task);
      } else {
        backlog.add(task);
      }
    }

    final pendingQuestion = json['pendingQuestion'];
    final openQuestions = pendingQuestion is Map
        ? [Map<String, dynamic>.from(pendingQuestion)]
        : const <Map<String, dynamic>>[];
    final rawStatus = (json['status'] ?? '').toString().trim().toLowerCase();
    final status = switch (rawStatus.replaceAll('-', '_')) {
      'paused' => ProjectStatus.active,
      'running' => ProjectStatus.runningTask,
      'blocked' =>
        openQuestions.isNotEmpty
            ? ProjectStatus.waitingForUser
            : ProjectStatus.blocked,
      'completed' => ProjectStatus.completed,
      'failed' => ProjectStatus.failed,
      'cancelled' => ProjectStatus.cancelled,
      _ => parseProjectStatus(json['status']),
    };
    final memorySummary = jsonString(json['memorySummary']);

    return {
      'schemaVersion': 2,
      'id': jsonString(json['id']),
      'title': jsonString(json['title'], fallback: 'Untitled project'),
      'originalGoal': originalGoal,
      'refinedGoal': refinedGoal,
      'successCriteria': jsonStringList(json['successCriteria']),
      'constraints': jsonStringList(json['constraints']),
      'backlog': backlog,
      'currentTask': ?currentTask,
      'completedTasks': completedTasks,
      'failedTasks': failedTasks,
      'artifacts': const <Map<String, dynamic>>[],
      'recoveryIncidents': const <Map<String, dynamic>>[],
      'knownFacts': [if (memorySummary.isNotEmpty) memorySummary.trim()],
      'openQuestions': openQuestions,
      'status': status.wire,
      'phase': status == ProjectStatus.completed
          ? ProjectPhase.finalization.wire
          : currentTask != null
          ? ProjectPhase.execution.wire
          : ProjectPhase.planning.wire,
      'iterationCount': completedTasks.length + failedTasks.length,
      'maxIterations': ProjectState.defaultMaxIterations,
      'maxFailedTasks': ProjectState.defaultMaxFailedTasks,
      'activeTaskId': ?activeTaskId,
      'chatSessionId': ?jsonNullableString(json['chatSessionId']),
      'completionSummary': jsonString(json['completionSummary']),
      'blocker': ?json['blocker'],
      'decisions': jsonMapList(json['decisions']),
      'createdAt': jsonNullableDate(json['createdAt']) ?? now,
      'updatedAt': jsonNullableDate(json['updatedAt']) ?? now,
      'completedAt': ?jsonNullableDate(json['completedAt']),
    };
  }

  static Map<String, dynamic> upgradeV2(Map<String, dynamic> json) {
    final createdAt = jsonNullableDate(json['createdAt']) ?? DateTime.now();
    final updatedAt = jsonNullableDate(json['updatedAt']) ?? createdAt;
    final statements = jsonStringList(json['successCriteria']);
    final criteria = <Map<String, dynamic>>[
      for (var index = 0; index < statements.length; index++)
        {
          'id': _numberedId('criterion', index),
          'statement': statements[index],
          'required': true,
          'status': ProjectCriterionStatus.unsatisfied.name,
          'verificationMode': 'mixed',
          'evidenceIds': <String>[],
          'notes': '',
          'createdAt': createdAt,
          'updatedAt': updatedAt,
        },
    ];
    final criterionIdByStatement = <String, String>{
      for (final criterion in criteria)
        _normalise(jsonString(criterion['statement'])): jsonString(
          criterion['id'],
        ),
    };
    final evidence = <Map<String, dynamic>>[];

    List<Map<String, dynamic>> migrateTasks(
      Object? rawTasks, {
      required bool completed,
    }) {
      final tasks = <Map<String, dynamic>>[];
      for (final raw in jsonMapList(rawTasks)) {
        final task = Map<String, dynamic>.from(raw);
        final legacyCriteria = jsonStringList(
          task['relevantSuccessCriteria'] ?? task['criterionIds'],
        );
        final criterionIds = <String>[];
        final unmatched = <String>[];
        for (final statement in legacyCriteria) {
          final id = criterionIdByStatement[_normalise(statement)];
          if (id == null) {
            unmatched.add(statement);
          } else if (!criterionIds.contains(id)) {
            criterionIds.add(id);
          }
        }
        final taskStatus = jsonString(
          task['status'],
          fallback: ProjectTaskStatus.queued.wire,
        );
        final migrationReadiness = switch (taskStatus) {
          'queued' || 'approved' => ProjectTaskReadiness.ready,
          'proposed' => ProjectTaskReadiness.waitingInput,
          _ => ProjectTaskReadiness.notEligible,
        };
        task
          ..remove('relevantSuccessCriteria')
          ..remove('relevant_success_criteria')
          ..['criterionIds'] = criterionIds
          ..['context'] = [
            ...jsonStringList(task['context']),
            for (final statement in unmatched)
              'Legacy unmatched success criterion: $statement',
          ]
          ..putIfAbsent('dependsOnTaskIds', () => <String>[])
          ..putIfAbsent('priority', () => ProjectTaskPriority.normal.name)
          ..putIfAbsent('risk', () => ProjectTaskRisk.unknown.name)
          ..putIfAbsent('riskReduction', () => ProjectRiskReduction.none.name)
          ..putIfAbsent('effort', () => ProjectTaskEffort.small.name)
          ..putIfAbsent(
            'readiness',
            () => completed
                ? 'not_eligible'
                : switch (migrationReadiness) {
                    ProjectTaskReadiness.waitingInput => 'waiting_input',
                    ProjectTaskReadiness.notEligible => 'not_eligible',
                    _ => migrationReadiness.name,
                  },
          )
          ..putIfAbsent(
            'readinessReasons',
            () => migrationReadiness == ProjectTaskReadiness.waitingInput
                ? <String>['Legacy proposed task awaits approval.']
                : <String>[],
          )
          ..putIfAbsent('selectionRationale', () => '')
          ..putIfAbsent('revisionIntroduced', () => 1)
          ..putIfAbsent('revisionUpdated', () => 1)
          ..putIfAbsent('expectedEvidence', () => <Map<String, dynamic>>[])
          ..putIfAbsent('readPaths', () => <String>[])
          ..putIfAbsent('writePaths', () => <String>[]);
        tasks.add(task);

        if (completed) {
          for (final criterionId in criterionIds) {
            final evidenceId =
                'evidence_migrated_${jsonString(task['id'])}_$criterionId';
            evidence.add({
              'id': evidenceId,
              'type': ProjectEvidenceType.migrated.name,
              'criterionIds': [criterionId],
              'projectTaskId': jsonNullableString(task['id']),
              'taskDocumentId': jsonNullableString(task['taskDocumentId']),
              'sourceRef': jsonString(
                task['taskDocumentId'] ?? task['id'],
                fallback: evidenceId,
              ),
              'summary': 'Legacy completed task credited this criterion.',
              'status': ProjectEvidenceStatus.accepted.name,
              'strength': ProjectEvidenceStrength.supporting.name,
              'details': {'migration': 'v2_to_v3'},
              'createdAt': jsonNullableDate(task['updatedAt']) ?? updatedAt,
              'evaluatedAt': jsonNullableDate(task['updatedAt']) ?? updatedAt,
            });
            final criterion = criteria.firstWhere(
              (item) => item['id'] == criterionId,
            );
            (criterion['evidenceIds'] as List<String>).add(evidenceId);
            criterion['status'] = ProjectCriterionStatus.satisfied.name;
            criterion['notes'] =
                'Satisfied by migrated completed-task history.';
            criterion['verifiedAt'] =
                jsonNullableDate(task['updatedAt']) ?? updatedAt;
          }
        }
      }
      return tasks;
    }

    final backlog = migrateTasks(json['backlog'], completed: false);
    final completedTasks = migrateTasks(
      json['completedTasks'],
      completed: true,
    );
    final failedTasks = migrateTasks(json['failedTasks'], completed: false);
    final currentTaskList = migrateTasks(
      json['currentTask'] == null ? const [] : [json['currentTask']],
      completed: false,
    );
    final currentTask = currentTaskList.firstOrNull;
    final allTasks = [
      ...completedTasks,
      ...failedTasks,
      ...currentTaskList,
      ...backlog,
    ];
    final hasHistory =
        allTasks.isNotEmpty || jsonMapList(json['decisions']).isNotEmpty;
    final projectStatus = parseProjectStatus(json['status']);
    final milestoneStatus = switch (projectStatus) {
      ProjectStatus.completed => ProjectMilestoneStatus.completed,
      ProjectStatus.cancelled => ProjectMilestoneStatus.cancelled,
      ProjectStatus.blocked ||
      ProjectStatus.failed ||
      ProjectStatus.waitingForUser => ProjectMilestoneStatus.blocked,
      _ => ProjectMilestoneStatus.active,
    };
    final memory = <Map<String, dynamic>>[
      for (
        var index = 0;
        index < jsonStringList(json['knownFacts']).length;
        index++
      )
        _migratedMemory(
          jsonStringList(json['knownFacts'])[index],
          index,
          createdAt,
          updatedAt,
        ),
    ];

    return {
        ...json,
        'schemaVersion': 3,
        'criteria': criteria,
        'evidence': evidence,
        'milestones': [
          if (hasHistory)
            {
              'id': 'milestone_001',
              'title': 'Legacy project work',
              'objective': jsonString(
                json['refinedGoal'],
                fallback: 'Preserve migrated project history.',
              ),
              'criterionIds': [for (final item in criteria) item['id']],
              'status': milestoneStatus.name,
              'exitConditions': statements,
              'taskIds': [for (final task in allTasks) task['id']],
              'order': 0,
              'createdAt': createdAt,
              'updatedAt': updatedAt,
              if (projectStatus == ProjectStatus.completed)
                'completedAt':
                    jsonNullableDate(json['completedAt']) ?? updatedAt,
            },
        ],
        'memory': memory,
        'currentRevision': 1,
        'planHistory': [
          {
            'revision': 1,
            'trigger': ProjectPlanRevisionTrigger.migration.name,
            'summary': 'Migrated the project plan to schema v3.',
            'rationale': 'Preserved schema-v2 project state and history.',
            'addedTaskIds': <String>[],
            'updatedTaskIds': <String>[],
            'removedTaskIds': <String>[],
            'criterionChanges': <String>[],
            'milestoneChanges': <String>[],
            'validationWarnings': <String>[],
            'createdAt': updatedAt,
            'approvedAt': updatedAt,
            'approvedBy': ProjectPlanRevisionApprover.automatic.name,
          },
        ],
        'backlog': backlog,
        'currentTask': ?currentTask,
        'completedTasks': completedTasks,
        'failedTasks': failedTasks,
      }
      ..remove('successCriteria')
      ..remove('knownFacts');
  }

  static Map<String, dynamic> upgradeV3(Map<String, dynamic> json) {
    Map<String, dynamic> markLegacyTask(Map<String, dynamic> raw) {
      final task = Map<String, dynamic>.from(raw);
      final effort = jsonString(task['effort'], fallback: 'small');
      if (effort == ProjectTaskEffort.small.name &&
          jsonStringList(task['writePaths']).isEmpty) {
        task['legacyWriteAccess'] = true;
      }
      return task;
    }

    List<Map<String, dynamic>> migrateTaskList(Object? value) => [
      for (final task in jsonMapList(value)) markLegacyTask(task),
    ];

    final pending = <String>{};
    for (final raw in jsonStringList(json['pendingReplanTriggers'])) {
      switch (raw.replaceAll('-', '_')) {
        case 'task_failed':
          pending.add('task_failed');
        case 'evidence_rejected':
          pending.add('evidence_rejected');
        case 'no_ready_task':
          pending.add('no_ready_task');
        case 'new_context':
        case 'manual':
          pending.add('scope_changed');
        case 'milestone_completed':
          pending.add('milestone_roadmap_changed');
      }
    }

    return {
      ...json,
      'schemaVersion': 4,
      'backlog': migrateTaskList(json['backlog']),
      'completedTasks': migrateTaskList(json['completedTasks']),
      'failedTasks': migrateTaskList(json['failedTasks']),
      if (json['currentTask'] is Map)
        'currentTask': markLegacyTask(
          Map<String, dynamic>.from(json['currentTask'] as Map),
        ),
      'pendingReplanTriggers': pending.toList()..sort(),
      'completionReviewCheckpoint': null,
    };
  }

  static Map<String, dynamic> _migratedMemory(
    String content,
    int index,
    DateTime createdAt,
    DateTime updatedAt,
  ) {
    final fromUser =
        content.startsWith('User answered:') ||
        content.startsWith('User added project context:');
    return {
      'id': _numberedId('memory', index),
      'kind': fromUser
          ? ProjectMemoryKind.requirement.name
          : ProjectMemoryKind.fact.name,
      'content': content,
      'sourceType': fromUser
          ? ProjectMemorySourceType.user.name
          : ProjectMemorySourceType.migration.name,
      'confidence': fromUser
          ? ProjectMemoryConfidence.confirmed.name
          : ProjectMemoryConfidence.inferred.name,
      'protected': fromUser,
      'active': true,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  static String _numberedId(String prefix, int index) =>
      '${prefix}_${(index + 1).toString().padLeft(3, '0')}';

  static String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static Map<String, dynamic> _legacyTask(
    Map<String, dynamic> json,
    String taskId,
    TaskStatus status,
    DateTime now,
  ) {
    final title = jsonString(json['title'], fallback: 'Untitled task');
    final summary = jsonString(json['summary']);
    final objective = summary.isEmpty ? title : summary;
    final criteria = summary.isEmpty ? <String>[] : [summary];
    final createdAt =
        jsonNullableDate(json['createdAt'] ?? json['created_at']) ?? now;
    final updatedAt =
        jsonNullableDate(json['updatedAt'] ?? json['updated_at']) ?? now;
    return {
      'id': 'project_task_$taskId',
      'title': title,
      'objective': objective,
      'relevantSuccessCriteria': criteria,
      'doneCriteria': criteria.isEmpty ? ['Finish $title.'] : criteria,
      'outOfScope': const ['Do not expand this task into the full project.'],
      'context': const <String>[],
      'expectedArtifacts': const <Map<String, dynamic>>[],
      'status': switch (status) {
        TaskStatus.completed => ProjectTaskStatus.completed.wire,
        TaskStatus.failed ||
        TaskStatus.cancelled => ProjectTaskStatus.failed.wire,
        _ => ProjectTaskStatus.queued.wire,
      },
      'taskDocumentId': taskId,
      'fingerprint': projectTaskFingerprint(objective, criteria),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
