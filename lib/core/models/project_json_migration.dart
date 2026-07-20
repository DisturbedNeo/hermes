part of 'project.dart';

class ProjectStateJsonHook extends JsonModelHook {
  const ProjectStateJsonHook()
    : super(
        removeKeys: const {
          'originalPrompt',
          'goal',
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
    final isLegacy =
        version < ProjectState.currentSchemaVersion ||
        (!json.containsKey('originalGoal') &&
            json.containsKey('originalPrompt'));
    if (isLegacy) return ProjectJsonMigration.upgradeV1(json);
    json['schemaVersion'] = ProjectState.currentSchemaVersion;
    return json;
  }
}

class ProjectTaskJsonHook extends JsonModelHook {
  const ProjectTaskJsonHook()
    : super(
        aliases: const {
          'objective': ['prompt'],
          'relevantSuccessCriteria': [
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
      fingerprint: projectTaskFingerprint(
        value.objective,
        value.relevantSuccessCriteria,
      ),
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
      'schemaVersion': ProjectState.currentSchemaVersion,
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
