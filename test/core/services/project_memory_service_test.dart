import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/project_system/project_memory_service.dart';

void main() {
  group('ProjectMemoryService writes', () {
    const service = ProjectMemoryService();

    test(
      'persists complete typed entries without applying a context budget',
      () {
        final content = List.filled(5000, 'x').join();

        final result = service.record(
          project: _project(),
          id: 'user_requirement',
          kind: ProjectMemoryKind.requirement,
          content: content,
          sourceType: ProjectMemorySourceType.user,
          confidence: ProjectMemoryConfidence.confirmed,
        );

        expect(result.entry.content, content);
        expect(result.entry.content, hasLength(5000));
        expect(result.entry.protected, isTrue);
        expect(
          result.project.memory.single.sourceType,
          ProjectMemorySourceType.user,
        );
      },
    );

    test(
      'user answer supersedes a matching assumption but retains history',
      () {
        final assumption = _memory(
          'assumption',
          ProjectMemoryKind.assumption,
          'Assumed: SQLite\nOriginal question: Which database?',
        );
        final question = PendingProjectQuestion(
          id: 'question_1',
          question: 'Which database?',
          createdAt: _now,
        );

        final result = service.recordUserAnswer(
          project: _project(memory: [assumption]),
          question: question,
          answer: 'PostgreSQL',
          timestamp: _now.add(const Duration(hours: 1)),
        );

        expect(result.project.memory, hasLength(2));
        expect(result.project.taskById('unused'), isNull);
        expect(
          result.project.memory
              .singleWhere((item) => item.id == 'assumption')
              .active,
          isFalse,
        );
        expect(result.entry.kind, ProjectMemoryKind.requirement);
        expect(result.entry.protected, isTrue);
        expect(result.entry.supersedesId, 'assumption');
        expect(result.entry.coveredEntryIds, ['assumption']);
        expect(
          result.project.memory.map((item) => item.content),
          contains(contains('PostgreSQL')),
        );
      },
    );

    test('planner cannot supersede protected user memory', () {
      final requirement = _memory(
        'protected',
        ProjectMemoryKind.requirement,
        'Never publish automatically.',
        sourceType: ProjectMemorySourceType.user,
        protected: true,
      );

      expect(
        () => service.record(
          project: _project(memory: [requirement]),
          kind: ProjectMemoryKind.decision,
          content: 'Publish automatically.',
          sourceType: ProjectMemorySourceType.planner,
          supersedesEntryIds: const ['protected'],
        ),
        throwsStateError,
      );
    });
  });

  group('ProjectMemoryService compaction', () {
    const service = ProjectMemoryService();

    test(
      'creates an auditable summary and deactivates only covered entries',
      () {
        final first = _memory('fact_1', ProjectMemoryKind.fact, 'Fact one.');
        final second = _memory('fact_2', ProjectMemoryKind.fact, 'Fact two.');
        final retained = _memory(
          'fact_3',
          ProjectMemoryKind.fact,
          'Fact three.',
        );

        final result = service.compact(
          project: _project(memory: [first, second, retained]),
          coveredEntryIds: const ['fact_2', 'fact_1'],
          summary: 'The first two facts describe the completed setup.',
          compactionId: 'compaction_1',
          timestamp: _now.add(const Duration(days: 1)),
        );

        expect(result.project.memory, hasLength(4));
        expect(result.entry.kind, ProjectMemoryKind.summary);
        expect(result.entry.sourceId, 'compaction_1');
        expect(result.entry.coveredEntryIds, ['fact_1', 'fact_2']);
        expect(
          result.project.memory
              .where((item) => ['fact_1', 'fact_2'].contains(item.id))
              .every((item) => !item.active),
          isTrue,
        );
        expect(
          result.project.memory
              .singleWhere((item) => item.id == 'fact_3')
              .active,
          isTrue,
        );

        final roundTrip = ModelJson.decode<ProjectDocument>(
          ModelJson.encode(result.project),
        );
        expect(roundTrip.memory.last.coveredEntryIds, ['fact_1', 'fact_2']);
      },
    );

    test('never compacts a protected requirement or unresolved risk', () {
      final project = _project(
        memory: [
          _memory(
            'requirement',
            ProjectMemoryKind.requirement,
            'Keep compatibility.',
            protected: true,
          ),
          _memory('risk', ProjectMemoryKind.risk, 'Deployment is unsafe.'),
        ],
      );

      expect(
        () => service.compact(
          project: project,
          coveredEntryIds: const ['requirement'],
          summary: 'Requirement summary.',
        ),
        throwsStateError,
      );
      expect(
        () => service.compact(
          project: project,
          coveredEntryIds: const ['risk'],
          summary: 'Risk summary.',
        ),
        throwsStateError,
      );
    });

    test('resolved recovery risk is superseded by an auditable fact', () {
      final risk = _memory(
        'risk',
        ProjectMemoryKind.risk,
        'The verification gate is red.',
        sourceId: 'incident_1',
        protected: true,
      );

      final result = service.resolveRisksForSource(
        project: _project(memory: [risk]),
        sourceId: 'incident_1',
        resolution: 'The verification gate is green.',
      )!;

      expect(result.project.memory.first.active, isFalse);
      expect(result.entry.kind, ProjectMemoryKind.fact);
      expect(result.entry.coveredEntryIds, ['risk']);
    });
  });

  group('ProjectMemoryService context selection', () {
    const service = ProjectMemoryService();

    test('uses stable relevance tiers and excludes superseded assumptions', () {
      final task = _task('selected', dependencies: const ['dependency']);
      final project = _project(
        tasks: [task],
        memory: [
          _memory(
            'requirement',
            ProjectMemoryKind.requirement,
            'The reporting API must remain compatible.',
            sourceType: ProjectMemorySourceType.user,
            protected: true,
          ),
          _memory('risk', ProjectMemoryKind.risk, 'Reporting may be slow.'),
          _memory(
            'dependency_fact',
            ProjectMemoryKind.fact,
            'The dependency exposes reporting data.',
            sourceType: ProjectMemorySourceType.task,
            sourceId: 'dependency',
          ),
          _memory(
            'task_summary',
            ProjectMemoryKind.summary,
            'A recent unrelated task completed.',
            sourceType: ProjectMemorySourceType.task,
            sourceId: 'other_task',
          ),
          _memory('general', ProjectMemoryKind.fact, 'A general old fact.'),
          _memory(
            'superseded',
            ProjectMemoryKind.assumption,
            'Use the old API.',
            active: false,
          ),
        ],
        milestones: [_milestone()],
      );

      final selection = service.selectContext(
        project: project,
        task: task,
        maxCharacters: 10000,
      );

      expect(selection.withinBudget, isTrue);
      expect(
        selection.items.map((item) => item.rank).toList(),
        orderedEquals([...selection.items.map((item) => item.rank)]..sort()),
      );
      expect(selection.selectedMemoryEntryIds.first, 'requirement');
      expect(selection.selectedMemoryEntryIds, isNot(contains('superseded')));
      expect(
        selection.items
            .singleWhere((item) => item.id == 'memory:dependency_fact')
            .rank,
        3,
      );
      expect(
        selection.items,
        contains(
          predicate<ProjectMemoryContextItem>(
            (item) => item.id == 'criterion:criterion_1',
          ),
        ),
      );
      expect(
        selection.items,
        contains(
          predicate<ProjectMemoryContextItem>(
            (item) => item.id == 'milestone:milestone_1',
          ),
        ),
      );
    });

    test('budgeting omits whole entries without deleting persisted facts', () {
      final requirement = _memory(
        'requirement',
        ProjectMemoryKind.requirement,
        'Keep compatibility.',
        sourceType: ProjectMemorySourceType.user,
        protected: true,
      );
      final older = _memory(
        'older',
        ProjectMemoryKind.fact,
        'This older fact is deliberately too large for the remaining budget.',
      );
      final project = _project(memory: [older, requirement]);
      final budget = 'requirement [requirement]: Keep compatibility.'.length;

      final selection = service.selectContext(
        project: project,
        maxCharacters: budget,
      );

      expect(selection.withinBudget, isTrue);
      expect(selection.selectedMemoryEntryIds, ['requirement']);
      expect(
        selection.exclusions.map((item) => item.entryId),
        contains('older'),
      );
      expect(project.memory, hasLength(2));
      expect(project.memory.every((item) => item.active), isTrue);
    });
  });
}

final _now = DateTime.utc(2026, 1, 1);

ProjectDocument _project({
  List<Task> tasks = const [],
  List<ProjectMemoryEntry> memory = const [],
  List<ProjectMilestone> milestones = const [],
}) => ProjectDocument(
  id: 'project',
  title: 'Project',
  originalGoal: 'Deliver reporting.',
  refinedGoal: 'Deliver reporting.',
  criteria: [
    ProjectCriterion(
      id: 'criterion_1',
      statement: 'Reporting works.',
      createdAt: _now,
      updatedAt: _now,
    ),
  ],
  constraints: const [],
  tasks: tasks,
  memory: memory,
  milestones: milestones,
  status: ProjectStatus.active,
  activeTaskId: null,
  createdAt: _now,
  updatedAt: _now,
);

ProjectMemoryEntry _memory(
  String id,
  ProjectMemoryKind kind,
  String content, {
  ProjectMemorySourceType sourceType = ProjectMemorySourceType.planner,
  String? sourceId,
  bool protected = false,
  bool active = true,
}) => ProjectMemoryEntry(
  id: id,
  kind: kind,
  content: content,
  sourceType: sourceType,
  sourceId: sourceId,
  confidence: ProjectMemoryConfidence.inferred,
  protected: protected,
  active: active,
  createdAt: _now,
  updatedAt: _now,
);

Task _task(String id, {List<String> dependencies = const []}) => Task(
  id: id,
  title: 'Reporting task',
  objective: 'Implement reporting.',
  criterionIds: const ['criterion_1'],
  milestoneId: 'milestone_1',
  dependsOnTaskIds: dependencies,
  doneCriteria: const ['Reporting is verified.'],
  outOfScope: const ['Unrelated work.'],
  context: const [],
  expectedArtifacts: const [],
  status: TaskStatus.queued,
  fingerprint: 'fingerprint_$id',
  rejectionReason: null,
  createdAt: _now,
  updatedAt: _now,
);

ProjectMilestone _milestone() => ProjectMilestone(
  id: 'milestone_1',
  title: 'Reporting',
  objective: 'Finish reporting.',
  status: ProjectMilestoneStatus.active,
  order: 1,
  createdAt: _now,
  updatedAt: _now,
);
