import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/features/project/application/project_application/project_control_state_service.dart';

void main() {
  group('clean-slate project lifecycle', () {
    test('keeps every task in one canonical collection', () {
      final project = _project([
        _task('queued', TaskStatus.queued),
        _task('active', TaskStatus.running),
        _task('done', TaskStatus.completed),
        _task('failed', TaskStatus.failed),
        _task('deferred', TaskStatus.deferred),
        _task('obsolete', TaskStatus.obsolete),
        _task('cancelled', TaskStatus.cancelled),
      ], activeTaskId: 'active');

      expect(project.tasks.map((task) => task.id).toSet(), hasLength(7));
      expect(project.taskById(project.activeTaskId!), same(project.tasks[1]));
      expect(
        project.tasks.where((task) => task.status == TaskStatus.completed),
        hasLength(1),
      );
      expect(
        project.tasks.where((task) => task.status == TaskStatus.failed),
        hasLength(1),
      );
    });

    test('round-trips terminal history and active task identity', () {
      final project = _project([
        _task('done', TaskStatus.completed),
        _task('active', TaskStatus.running),
      ], activeTaskId: 'active');
      final decoded = ModelJson.decode<ProjectDocument>(
        ModelJson.encode(project),
      );

      expect(decoded.taskIds, ['done', 'active']);
      expect(decoded.tasks, isEmpty);
      expect(decoded.activeTaskId, 'active');
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

    test('derives the new control boundary for older snapshots', () {
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

      final synced = const ProjectControlStateService().synchronise(project);

      expect(synced.boundary?.outcome, ProjectControlOutcome.awaitingUserInput);
      expect(synced.boundary?.action, 'answer_question');
      expect(synced.boundary?.message, question.question);
    });

    test(
      'persists explicit planning degradation alongside compatibility state',
      () {
        final project = const ProjectControlStateService().withOutcome(
          _project(const []),
          outcome: ProjectControlOutcome.degradedPlanning,
          message: 'Planner unavailable.',
          action: 'retry_planning',
          reasonCode: 'model_unavailable',
        );

        final decoded = ModelJson.decode<ProjectDocument>(
          ModelJson.encode(project),
        );

        expect(
          decoded.boundary?.outcome,
          ProjectControlOutcome.degradedPlanning,
        );
        expect(decoded.boundary?.reasonCode, 'model_unavailable');
      },
    );

    test('preserves the canonical boundary across compatibility drift', () {
      final service = const ProjectControlStateService();
      final reduced = service.withOutcome(
        _project(const []),
        outcome: ProjectControlOutcome.degradedPlanning,
        message: 'Planner unavailable.',
        action: 'retry_planning',
        reasonCode: 'model_unavailable',
      );
      final drifted = reduced.copyWith(
        status: ProjectStatus.active,
        blocker: null,
        openQuestions: const [],
      );

      final synchronized = service.synchronise(drifted);

      expect(
        synchronized.boundary?.outcome,
        ProjectControlOutcome.degradedPlanning,
      );
      expect(synchronized.boundary?.reasonCode, 'model_unavailable');
    });
  });
}

ProjectDocument _project(
  List<Task> tasks, {
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
    tasks: [for (final task in tasks) ProjectTaskNode.fromTask(task)],
    status: status,
    activeTaskId: activeTaskId,
    openQuestions: openQuestions,
    blocker: blocker,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(String id, TaskStatus status) {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: id,
    title: id,
    objective: 'Do $id',
    criterionIds: const ['criterion_1'],
    doneCriteria: const ['Done.'],
    outOfScope: const ['Everything else.'],
    context: const [],
    expectedArtifacts: const [],
    status: status,
    fingerprint: id,
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}
