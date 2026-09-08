import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/serialization/model_json.dart';

void main() {
  group('clean-slate project lifecycle', () {
    test('keeps every task in one canonical collection', () {
      final project = _project([
        _task('queued', ProjectTaskStatus.queued),
        _task('active', ProjectTaskStatus.running, taskDocumentId: 'doc_1'),
        _task('done', ProjectTaskStatus.completed),
        _task('failed', ProjectTaskStatus.failed),
        _task('deferred', ProjectTaskStatus.deferred),
        _task('obsolete', ProjectTaskStatus.obsolete),
        _task('cancelled', ProjectTaskStatus.cancelled),
      ], activeTaskId: 'active');

      expect(project.tasks.map((task) => task.id).toSet(), hasLength(7));
      expect(project.taskById(project.activeTaskId!), same(project.tasks[1]));
      expect(project.tasks.where((task) => task.status == ProjectTaskStatus.completed), hasLength(1));
      expect(project.tasks.where((task) => task.status == ProjectTaskStatus.failed), hasLength(1));
      expect(project.tasks.singleWhere((task) => task.status == ProjectTaskStatus.running).taskDocumentId, 'doc_1');
    });

    test('round-trips terminal history and active task identity', () {
      final project = _project([
        _task('done', ProjectTaskStatus.completed),
        _task('active', ProjectTaskStatus.running, taskDocumentId: 'doc_1'),
      ], activeTaskId: 'active');
      final decoded = ModelJson.decode<ProjectDocument>(ModelJson.encode(project));

      expect(decoded.tasks.map((task) => task.id), ['done', 'active']);
      expect(decoded.activeTaskId, 'active');
      expect(decoded.taskById('active')?.taskDocumentId, 'doc_1');
    });

    test('waiting and blocked states retain a durable explanation', () {
      final now = DateTime(2026, 1, 1);
      final question = PendingProjectQuestion(
        id: 'question_1',
        question: 'Which account should be used?',
        createdAt: now,
      );
      final project = _project(
        const [],
        status: ProjectStatus.waitingForUser,
        openQuestions: [question],
        blocker: ProjectBlocker(
          type: ProjectBlockerType.question,
          message: question.question,
          createdAt: now,
        ),
      );
      expect(project.openQuestions, hasLength(1));
      expect(project.blocker, isNotNull);
    });
  });
}

ProjectDocument _project(
  List<ProjectTask> tasks, {
  String? activeTaskId,
  ProjectStatus status = ProjectStatus.active,
  List<PendingProjectQuestion> openQuestions = const [],
  ProjectBlocker? blocker,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectDocument(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Build it',
    refinedGoal: 'Build it safely',
    criteria: [
      ProjectCriterion(
        id: 'criterion_1',
        statement: 'It works',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    constraints: const [],
    tasks: tasks,
    status: status,
    activeTaskId: activeTaskId,
    openQuestions: openQuestions,
    blocker: blocker,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectTask _task(
  String id,
  ProjectTaskStatus status, {
  String? taskDocumentId,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectTask(
    id: id,
    title: id,
    objective: 'Do $id',
    criterionIds: const ['criterion_1'],
    doneCriteria: const ['Done.'],
    outOfScope: const ['Everything else.'],
    context: const [],
    expectedArtifacts: const [],
    status: status,
    taskDocumentId: taskDocumentId,
    fingerprint: id,
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}
