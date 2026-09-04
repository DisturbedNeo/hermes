import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/project_system/project_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  group('current project migration', () {
    for (final fixtureName in const [
      'active_project.json',
      'completed_project.json',
      'blocked_project.json',
      'question_blocked_project.json',
      'recovery_project.json',
    ]) {
      test('migrates and idempotently round-trips $fixtureName', () async {
        final raw = await _fixture(fixtureName);

        final migrated = ModelJson.decode<ProjectDocument>(raw);
        final firstEncoding = ModelJson.encode(migrated);
        final loadedAgain = ModelJson.decode<ProjectDocument>(firstEncoding);

        expect(migrated.schemaVersion, ProjectState.currentSchemaVersion);
        expect(migrated.criteria, isNotEmpty);
        expect(migrated.currentRevision, 1);
        expect(migrated.diagnostics.taskExecutions, 0);
        expect(
          migrated.planHistory.single.trigger,
          ProjectPlanRevisionTrigger.migration,
        );
        expect(ModelJson.encode(loadedAgain), firstEncoding);
      });
    }

    test(
      'credits completed legacy work with accepted migration evidence',
      () async {
        final migrated = ModelJson.decode<ProjectDocument>(
          await _fixture('completed_project.json'),
        );

        expect(migrated.criteria.single.id, 'criterion_001');
        expect(
          migrated.criteria.single.status,
          ProjectCriterionStatus.satisfied,
        );
        expect(migrated.criteria.single.evidenceIds, hasLength(1));
        expect(migrated.completedTasks.single.criterionIds, ['criterion_001']);
        expect(migrated.evidence.single.type, ProjectEvidenceType.migrated);
        expect(migrated.evidence.single.status, ProjectEvidenceStatus.accepted);
        expect(
          migrated.evidence.single.strength,
          ProjectEvidenceStrength.supporting,
        );
        expect(
          migrated.milestones.single.status,
          ProjectMilestoneStatus.completed,
        );
      },
    );

    test('preserves unmatched legacy criteria in task context', () async {
      final raw = await _fixture('active_project.json');
      final backlog = raw['backlog'] as List<dynamic>;
      (backlog.single as Map<String, dynamic>)['relevantSuccessCriteria'] = [
        'A criterion removed from the project.',
      ];

      final migrated = ModelJson.decode<ProjectDocument>(raw);

      expect(migrated.backlog.single.criterionIds, isEmpty);
      expect(
        migrated.backlog.single.context,
        contains(
          'Legacy unmatched success criterion: '
          'A criterion removed from the project.',
        ),
      );
    });

    test(
      'classifies legacy user answers as protected confirmed memory',
      () async {
        final raw = await _fixture('active_project.json');
        raw['knownFacts'] = [
          'User answered: Which account?\nAnswer: Production',
          'Planner inferred this fact.',
        ];

        final migrated = ModelJson.decode<ProjectDocument>(raw);

        expect(migrated.memory.first.sourceType, ProjectMemorySourceType.user);
        expect(
          migrated.memory.first.confidence,
          ProjectMemoryConfidence.confirmed,
        );
        expect(migrated.memory.first.protected, isTrue);
        expect(
          migrated.memory.last.sourceType,
          ProjectMemorySourceType.migration,
        );
        expect(migrated.knownFacts, hasLength(2));

        final updated = migrated.copyWith(
          knownFacts: [...migrated.knownFacts, 'A later planner fact.'],
          updatedAt: DateTime.utc(2026, 1, 2),
        );
        expect(updated.memory.first.id, migrated.memory.first.id);
        expect(updated.memory.first.protected, isTrue);
        expect(updated.memory.first.sourceType, ProjectMemorySourceType.user);
      },
    );

    test('new projects serialize only current project and task keys', () {
      final timestamp = DateTime.utc(2026, 1, 1);
      final project = ProjectDocument(
        id: 'project_v3',
        title: 'V3 project',
        originalGoal: 'Deliver the outcome',
        refinedGoal: 'Deliver and verify the outcome',
        successCriteria: const ['The outcome is verified.'],
        constraints: const ['Stay in the workspace.'],
        backlog: [
          ProjectTask(
            id: 'project_task_001',
            title: 'Deliver outcome',
            objective: 'Deliver the bounded outcome.',
            relevantSuccessCriteria: const ['The outcome is verified.'],
            doneCriteria: const ['The outcome is delivered.'],
            outOfScope: const ['Do not expand scope.'],
            context: const [],
            expectedArtifacts: const [],
            status: ProjectTaskStatus.queued,
            taskDocumentId: null,
            fingerprint: 'deliver-outcome',
            rejectionReason: null,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ],
        status: ProjectStatus.active,
        activeTaskId: null,
        knownFacts: const ['An active fact.'],
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      final encoded = ModelJson.encode(project);
      final task =
          (encoded['backlog'] as List<dynamic>).single as Map<String, dynamic>;

      expect(encoded['schemaVersion'], ProjectState.currentSchemaVersion);
      expect(encoded['criteria'], isA<List<dynamic>>());
      expect(encoded['memory'], isA<List<dynamic>>());
      expect(encoded['planHistory'], isA<List<dynamic>>());
      expect(encoded.containsKey('successCriteria'), isFalse);
      expect(encoded.containsKey('knownFacts'), isFalse);
      expect(task['criterionIds'], ['criterion_001']);
      expect(task.containsKey('relevantSuccessCriteria'), isFalse);
      expect(
        ModelJson.encode(ModelJson.decode<ProjectDocument>(encoded)),
        encoded,
      );
    });

    test('v3 migration normalizes triggers and preserves write access', () {
      final timestamp = DateTime.utc(2026, 1, 1);
      final raw = ModelJson.encode(
        ProjectDocument(
          id: 'project_v3',
          title: 'V3 project',
          originalGoal: 'Deliver the outcome',
          refinedGoal: 'Deliver the outcome',
          constraints: const [],
          backlog: [
            ProjectTask(
              id: 'small_task',
              title: 'Legacy small task',
              objective: 'Perform legacy work.',
              doneCriteria: const ['Work is complete.'],
              outOfScope: const ['Do not expand scope.'],
              context: const [],
              expectedArtifacts: const [],
              status: ProjectTaskStatus.queued,
              taskDocumentId: null,
              fingerprint: 'legacy-small-task',
              rejectionReason: null,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          ],
          pendingReplanTriggers: const [
            ProjectPlanRevisionTrigger.taskCompleted,
            ProjectPlanRevisionTrigger.taskFailed,
            ProjectPlanRevisionTrigger.newContext,
          ],
          status: ProjectStatus.active,
          activeTaskId: null,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      raw['schemaVersion'] = 3;
      final task = (raw['backlog'] as List).single as Map<String, dynamic>;
      task.remove('legacyWriteAccess');

      final migrated = ModelJson.decode<ProjectDocument>(raw);

      expect(migrated.backlog.single.legacyWriteAccess, isTrue);
      expect(
        migrated.pendingReplanTriggers,
        unorderedEquals([
          ProjectPlanRevisionTrigger.taskFailed,
          ProjectPlanRevisionTrigger.scopeChanged,
        ]),
      );
    });
  });

  group('current repository migration', () {
    late Directory root;
    late ProjectRepository repository;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_project_v3_');
      repository = ProjectRepository();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'writes one v2 backup before replacing the migrated snapshot',
      () async {
        final raw = await _fixture('active_project.json');
        final projectFile = await _seedProject(root, raw);

        final first = await repository.loadProject(
          root.path,
          'project_fixture_active',
        );
        final backup = File(
          path.join(
            projectFile.parent.path,
            ProjectRepository.v2BackupFileName,
          ),
        );
        final firstBackupContent = await backup.readAsString();

        expect(first?.schemaVersion, ProjectState.currentSchemaVersion);
        expect(
          jsonDecode(await projectFile.readAsString())['schemaVersion'],
          ProjectState.currentSchemaVersion,
        );
        expect(jsonDecode(firstBackupContent)['schemaVersion'], 2);

        await projectFile.writeAsString(jsonEncode(raw));
        await repository.loadProject(root.path, 'project_fixture_active');

        expect(await backup.readAsString(), firstBackupContent);
      },
    );

    test('backs up recovered v2 data when the primary is corrupt', () async {
      final raw = await _fixture('active_project.json');
      final projectFile = await _seedProject(root, raw);
      await File('${projectFile.path}.bak').writeAsString(jsonEncode(raw));
      await projectFile.writeAsString('{}');

      final migrated = await repository.loadProject(
        root.path,
        'project_fixture_active',
      );
      final migrationBackup = File(
        path.join(projectFile.parent.path, ProjectRepository.v2BackupFileName),
      );

      expect(migrated?.schemaVersion, ProjectState.currentSchemaVersion);
      expect(
        jsonDecode(await migrationBackup.readAsString())['schemaVersion'],
        2,
      );
    });
  });
}

Future<Map<String, dynamic>> _fixture(String name) async {
  final file = File(path.join('test', 'fixtures', 'projects', 'v2', name));
  return Map<String, dynamic>.from(
    jsonDecode(await file.readAsString()) as Map,
  );
}

Future<File> _seedProject(Directory root, Map<String, dynamic> raw) async {
  final id = raw['id'] as String;
  final directory = Directory(path.join(root.path, '.agent', 'projects', id));
  await directory.create(recursive: true);
  final file = File(path.join(directory.path, 'project.json'));
  await file.writeAsString(jsonEncode(raw));
  return file;
}
