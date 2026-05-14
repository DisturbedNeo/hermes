import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/job_storage_service.dart';
import 'package:path/path.dart' as path;

void main() {
  group('JobStorageService', () {
    late Directory root;
    late JobStorageService storage;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_jobs_');
      storage = JobStorageService();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('saves and loads canonical job artifacts', () async {
      final snapshot = _snapshot();

      await storage.saveSnapshot(root.path, snapshot);

      expect(
        File(
          path.join(
            root.path,
            '.agent',
            'jobs',
            snapshot.spec.id,
            'task-brief.yaml',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          path.join(
            root.path,
            '.agent',
            'jobs',
            snapshot.spec.id,
            'job-spec.yaml',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          path.join(
            root.path,
            '.agent',
            'jobs',
            snapshot.spec.id,
            'job-state.yaml',
          ),
        ).existsSync(),
        isTrue,
      );

      final loaded = await storage.loadJob(root.path, snapshot.spec.id);

      expect(loaded?.taskBrief.title, snapshot.taskBrief.title);
      expect(loaded?.spec.phases.single.id, 'phase_1');
      expect(loaded?.state.status, JobStatus.planned);
    });

    test('lists jobs newest first', () async {
      final old = _snapshot(id: 'job_old', updatedAt: DateTime(2026, 1, 1));
      final recent = _snapshot(
        id: 'job_recent',
        updatedAt: DateTime(2026, 1, 2),
      );

      await storage.saveSnapshot(root.path, old);
      await storage.saveSnapshot(root.path, recent);

      final jobs = await storage.listJobs(root.path);

      expect(jobs.map((job) => job.id), ['job_recent', 'job_old']);
    });

    test('filters jobs by chat session', () async {
      final chatAOld = _snapshot(
        id: 'job_a_old',
        updatedAt: DateTime(2026, 1, 1),
        chatSessionId: 'chat_a',
      );
      final chatARecent = _snapshot(
        id: 'job_a_recent',
        updatedAt: DateTime(2026, 1, 3),
        chatSessionId: 'chat_a',
      );
      final chatB = _snapshot(
        id: 'job_b',
        updatedAt: DateTime(2026, 1, 2),
        chatSessionId: 'chat_b',
      );

      await storage.saveSnapshot(root.path, chatAOld);
      await storage.saveSnapshot(root.path, chatARecent);
      await storage.saveSnapshot(root.path, chatB);

      final chatAJobs = await storage.listJobs(
        root.path,
        chatSessionId: 'chat_a',
      );
      final latestChatA = await storage.loadLatestJob(
        root.path,
        chatSessionId: 'chat_a',
      );
      final crossScopedJob = await storage.loadJob(
        root.path,
        'job_b',
        chatSessionId: 'chat_a',
      );

      expect(chatAJobs.map((job) => job.id), ['job_a_recent', 'job_a_old']);
      expect(chatAJobs.every((job) => job.chatSessionId == 'chat_a'), isTrue);
      expect(latestChatA?.spec.id, 'job_a_recent');
      expect(crossScopedJob, isNull);
    });

    test('deletes jobs for one chat session only', () async {
      final chatA = _snapshot(id: 'job_a', chatSessionId: 'chat_a');
      final chatB = _snapshot(id: 'job_b', chatSessionId: 'chat_b');

      await storage.saveSnapshot(root.path, chatA);
      await storage.saveSnapshot(root.path, chatB);

      final deleted = await storage.deleteJobsForChatSession(
        root.path,
        chatSessionId: 'chat_a',
      );

      expect(deleted, 1);
      expect(await storage.loadJob(root.path, 'job_a'), isNull);
      expect(await storage.loadJob(root.path, 'job_b'), isNotNull);
    });

    test('deletes orphaned chat-scoped jobs', () async {
      final retained = _snapshot(id: 'job_saved', chatSessionId: 'chat_saved');
      final orphaned = _snapshot(
        id: 'job_orphaned',
        chatSessionId: 'chat_deleted',
      );
      final unscoped = _snapshot(id: 'job_unscoped');

      await storage.saveSnapshot(root.path, retained);
      await storage.saveSnapshot(root.path, orphaned);
      await storage.saveSnapshot(root.path, unscoped);

      final deleted = await storage.deleteOrphanedChatJobs(
        root.path,
        retainedChatSessionIds: {'chat_saved'},
      );

      expect(deleted, 1);
      expect(await storage.loadJob(root.path, 'job_saved'), isNotNull);
      expect(await storage.loadJob(root.path, 'job_orphaned'), isNull);
      expect(await storage.loadJob(root.path, 'job_unscoped'), isNotNull);
    });
  });
}

JobSnapshot _snapshot({
  String id = 'job_test',
  DateTime? updatedAt,
  String? chatSessionId,
}) {
  final now = updatedAt ?? DateTime(2026, 1, 1);
  final brief = TaskBrief(
    id: 'task_$id',
    createdAt: now,
    updatedAt: now,
    title: 'Test job',
    originalPrompt: 'Do the thing',
    objective: 'Do the thing',
    successCriteria: const ['Produces output'],
    constraints: const ['Stay inside workspace'],
    nonGoals: const [],
    assumptions: const [],
    clarifyingQuestions: const [],
    recommendedMode: ExecutionMode.job,
    recommendedAutonomy: AutonomyLevel.checkpointed,
    requiredOutputs: const [RequiredOutput(path: 'output.md', required: true)],
    domain: JobDomain.general,
    riskLevel: RiskLevel.low,
  );
  final spec = JobSpec(
    version: 1,
    id: id,
    title: 'Test job',
    createdAt: now,
    updatedAt: now,
    taskBriefId: brief.id,
    status: JobStatus.planned,
    domain: JobDomain.general,
    autonomy: AutonomyLevel.checkpointed,
    globalConstraints: brief.constraints,
    globalSuccessCriteria: brief.successCriteria,
    toolPolicy: const ToolPolicy(defaultAllowed: ['read_file']),
    stopPolicy: const StopPolicy(),
    phases: const [
      JobPhase(
        id: 'phase_1',
        title: 'Phase 1',
        objective: 'Produce output',
        status: PhaseStatus.pending,
        inputs: [],
        expectedOutputs: [PhaseOutput(path: 'output.md', required: true)],
        allowedTools: ['read_file'],
        terminalPolicy: TerminalPolicy.none,
        completionCriteria: ['Output exists'],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.hybrid),
        humanCheckpoint: false,
      ),
    ],
  );
  final state = JobState(
    jobId: id,
    chatSessionId: chatSessionId,
    status: JobStatus.planned,
    updatedAt: now,
    completedPhases: const [],
    failedPhases: const [],
    skippedPhases: const [],
    artifacts: const [],
    openQuestions: const [],
    assumptions: const [],
    risks: const [],
    phaseRuns: const [],
    latestSummary: 'Planned',
  );
  return JobSnapshot(taskBrief: brief, spec: spec, state: state);
}
