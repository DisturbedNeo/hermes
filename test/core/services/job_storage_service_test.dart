import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/job_system/job_storage_service.dart';
import 'package:path/path.dart' as path;

void main() {
  group('JobStorageService v2', () {
    late Directory root;
    late JobStorageService storage;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_storage_');
      storage = JobStorageService();
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('saves and loads a single job document', () async {
      final job = _job(id: 'job_test');

      await storage.saveSnapshot(root.path, job);

      final file = File(
        path.join(root.path, '.agent', 'jobs', 'job_test', 'job.json'),
      );
      expect(file.existsSync(), isTrue);

      final loaded = await storage.loadJob(root.path, 'job_test');
      expect(loaded?.id, 'job_test');
      expect(loaded?.steps.single.title, 'Step 1');
      expect(loaded?.status, JobStatus.paused);
    });

    test('lists v2 jobs newest first and ignores legacy folders', () async {
      final oldJobDir = Directory(
        path.join(root.path, '.agent', 'jobs', 'legacy_job'),
      );
      await oldJobDir.create(recursive: true);
      await File(
        path.join(oldJobDir.path, 'job-spec.yaml'),
      ).writeAsString('{}');

      await storage.saveSnapshot(
        root.path,
        _job(id: 'job_old', updatedAt: DateTime(2026, 1, 1)),
      );
      await storage.saveSnapshot(
        root.path,
        _job(id: 'job_new', updatedAt: DateTime(2026, 1, 2)),
      );

      final jobs = await storage.listJobs(root.path);

      expect(jobs.map((job) => job.id), ['job_new', 'job_old']);
    });

    test('filters and deletes by chat session', () async {
      await storage.saveSnapshot(
        root.path,
        _job(id: 'job_a', chatSessionId: 'chat_a'),
      );
      await storage.saveSnapshot(
        root.path,
        _job(id: 'job_b', chatSessionId: 'chat_b'),
      );

      expect(
        (await storage.listJobs(
          root.path,
          chatSessionId: 'chat_a',
        )).map((job) => job.id),
        ['job_a'],
      );

      final deleted = await storage.deleteJobsForChatSession(
        root.path,
        chatSessionId: 'chat_a',
      );

      expect(deleted, 1);
      expect(await storage.loadJob(root.path, 'job_a'), isNull);
      expect(await storage.loadJob(root.path, 'job_b'), isNotNull);
    });

    test('round-trips the raw job json shape', () async {
      final job = _job(id: 'job_json');
      await storage.saveSnapshot(root.path, job);

      final file = File(
        path.join(root.path, '.agent', 'jobs', 'job_json', 'job.json'),
      );
      final decoded = jsonDecode(await file.readAsString());

      expect(decoded['schemaVersion'], 2);
      expect(decoded['steps'], isA<List>());
      expect(decoded['runs'], isA<List>());
    });
  });
}

JobDocument _job({
  required String id,
  DateTime? updatedAt,
  String? chatSessionId,
}) {
  final now = DateTime(2026, 1, 1);
  return JobDocument(
    id: id,
    title: 'Test job',
    originalPrompt: 'Run the job',
    goal: 'Run the job',
    constraints: const ['Stay in workspace'],
    successCriteria: const ['Finish'],
    steps: const [
      JobStep(
        id: 'step_1',
        title: 'Step 1',
        objective: 'Do step 1',
        instructions: ['Work carefully'],
        mayEditFiles: false,
        artifacts: [],
        status: JobStepStatus.pending,
      ),
    ],
    status: JobStatus.paused,
    currentStepId: 'step_1',
    memorySummary: '',
    runs: const [],
    chatSessionId: chatSessionId,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}
