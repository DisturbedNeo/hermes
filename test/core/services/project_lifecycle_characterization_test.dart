import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/project_system/project_repository.dart';
import 'package:path/path.dart' as path;

const _fixtureRoot = 'test/fixtures/projects/v2';

void main() {
  group('schema-v2 project lifecycle fixtures', () {
    test('active project preserves a queued bounded task', () async {
      final project = await _loadFixture('active_project.json');

      expect(project.status, ProjectStatus.active);
      expect(project.phase, ProjectPhase.planning);
      expect(project.backlog, hasLength(1));
      expect(project.backlog.single.status, ProjectTaskStatus.queued);
      expect(project.currentTask, isNull);
      expect(project.activeTaskId, isNull);
      _expectLifecycleInvariants(project);
    });

    test(
      'completed project has terminal evidence and no active work',
      () async {
        final project = await _loadFixture('completed_project.json');

        expect(project.status, ProjectStatus.completed);
        expect(project.phase, ProjectPhase.finalization);
        expect(project.completedTasks, hasLength(1));
        expect(project.artifacts.single.path, 'docs/summary.md');
        expect(project.completedAt, isNotNull);
        _expectLifecycleInvariants(project);
      },
    );

    test('blocked project retains the failure and blocker', () async {
      final project = await _loadFixture('blocked_project.json');

      expect(project.status, ProjectStatus.blocked);
      expect(project.blocker?.type, ProjectBlockerType.taskFailed);
      expect(project.failedTasks.single.failure?.gateId, 'command_passes');
      _expectLifecycleInvariants(project);
    });

    test('question-blocked project retains required user input', () async {
      final project = await _loadFixture('question_blocked_project.json');

      expect(project.status, ProjectStatus.waitingForUser);
      expect(project.blocker?.type, ProjectBlockerType.question);
      expect(project.pendingQuestion?.id, 'question_fixture_account');
      _expectLifecycleInvariants(project);
    });

    test('recovery project retains active recovery and normal work', () async {
      final project = await _loadFixture('recovery_project.json');

      expect(
        project.recoveryIncidents.single.status,
        ProjectRecoveryIncidentStatus.active,
      );
      expect(project.backlog, hasLength(2));
      expect(project.backlog.first.recoveryIncidentId, isNull);
      expect(
        project.backlog.last.recoveryIncidentId,
        project.recoveryIncidents.single.id,
      );
      _expectLifecycleInvariants(project);
    });

    test('all healthy fixtures round-trip without semantic drift', () async {
      for (final name in const [
        'active_project.json',
        'completed_project.json',
        'blocked_project.json',
        'question_blocked_project.json',
        'recovery_project.json',
      ]) {
        final project = await _loadFixture(name);
        final encoded = ModelJson.encode(project);
        final decoded = ModelJson.decode<ProjectDocument>(encoded);

        expect(
          ModelJson.encode(decoded),
          encoded,
          reason: '$name changed after a model round-trip.',
        );
      }
    });

    test('repository excludes a semantically corrupt snapshot', () async {
      final root = await Directory.systemTemp.createTemp(
        'hermes_corrupt_project_fixture_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final projectDirectory = Directory(
        path.join(
          root.path,
          ProjectRepository.projectsRoot,
          'project_fixture_corrupt',
        ),
      );
      await projectDirectory.create(recursive: true);
      await File(
        path.join(projectDirectory.path, ProjectRepository.documentFileName),
      ).writeAsString(
        await File(
          path.join(_fixtureRoot, 'corrupt_missing_id.json'),
        ).readAsString(),
      );

      final projects = await ProjectRepository().listProjects(root.path);

      expect(projects, isEmpty);
    });
  });
}

Future<ProjectDocument> _loadFixture(String name) async {
  final raw = jsonDecode(
    await File(path.join(_fixtureRoot, name)).readAsString(),
  );
  return ModelJson.decode<ProjectDocument>(raw);
}

/// Characterizes the state-machine rules relied on by the current runner.
///
/// These are deliberately test-side assertions in Milestone 0: they document
/// behavior without introducing a new runtime validation or transition policy.
void _expectLifecycleInvariants(ProjectDocument project) {
  final allTasks = [
    ...project.backlog,
    ...project.completedTasks,
    ...project.failedTasks,
    if (project.currentTask != null) project.currentTask!,
  ];

  // A project task occupies exactly one lifecycle bucket.
  expect(
    allTasks.map((task) => task.id).toSet(),
    hasLength(allTasks.length),
    reason: '${project.id} contains a task in multiple lifecycle buckets.',
  );
  expect(
    project.completedTasks.every(
      (task) => task.status == ProjectTaskStatus.completed,
    ),
    isTrue,
  );
  expect(
    project.failedTasks.every(
      (task) => const {
        ProjectTaskStatus.failed,
        ProjectTaskStatus.rejected,
        ProjectTaskStatus.split,
        ProjectTaskStatus.cancelled,
      }.contains(task.status),
    ),
    isTrue,
  );

  // Active execution always has both the project task and its TaskDocument ID.
  if (project.status == ProjectStatus.runningTask ||
      project.status == ProjectStatus.reviewingTask) {
    expect(project.currentTask, isNotNull);
    expect(project.activeTaskId, isNotNull);
  }
  if (project.activeTaskId != null) {
    expect(project.currentTask, isNotNull);
    expect(project.currentTask?.taskDocumentId, project.activeTaskId);
  }

  // Waiting and blocked states retain a durable explanation.
  if (project.status == ProjectStatus.waitingForUser) {
    expect(project.openQuestions.isNotEmpty || project.blocker != null, isTrue);
  }
  if (project.status == ProjectStatus.blocked) {
    expect(project.blocker, isNotNull);
  }

  // A completed project has no work or input still in flight.
  if (project.status == ProjectStatus.completed) {
    expect(project.currentTask, isNull);
    expect(project.activeTaskId, isNull);
    expect(project.openQuestions, isEmpty);
    expect(project.blocker, isNull);
    expect(project.completedAt, isNotNull);
  }

  // Every active recovery incident retains at least one identifiable recovery task.
  for (final incident in project.recoveryIncidents.where(
    (item) => item.status == ProjectRecoveryIncidentStatus.active,
  )) {
    final incidentTasks = allTasks.where(
      (task) => task.recoveryIncidentId == incident.id,
    );
    expect(incidentTasks, isNotEmpty);
    expect(
      incidentTasks.any((task) => incident.recoveryTaskIds.contains(task.id)),
      isTrue,
    );
  }

  expect(project.iterationCount, greaterThanOrEqualTo(0));
  expect(
    project.iterationCount,
    greaterThanOrEqualTo(project.completedTasks.length),
  );
}
