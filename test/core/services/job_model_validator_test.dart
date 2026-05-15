import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/job_system/job_model_validator.dart';

void main() {
  group('BuiltInModelValidators', () {
    test(
      'selects audit evidence and severity calibration for audit phases',
      () {
        final phase = _phase(
          id: 'risk_scan',
          title: 'Scan severity findings',
          objective: 'Produce audit findings with severity labels.',
        );

        final profile = BuiltInModelValidators.select(
          taskBrief: _brief(
            domain: JobDomain.development,
            objective: 'Audit this codebase for major issues.',
          ),
          jobSpec: _spec(domain: JobDomain.development, phase: phase),
          phase: phase,
        );

        expect(profile.validatorIds, contains('AuditEvidenceReview'));
        expect(profile.validatorIds, contains('SeverityCalibrationReview'));
        expect(
          profile.criteria,
          contains(
            contains('Critical severity is used only for plausible data loss'),
          ),
        );
      },
    );

    test('selects implementation review for mutating development phases', () {
      final phase = _phase(
        title: 'Implement feature',
        objective: 'Patch files to implement the feature.',
        allowedTools: const ['read_file', 'patch_file'],
      );

      final profile = BuiltInModelValidators.select(
        taskBrief: _brief(
          domain: JobDomain.development,
          objective: 'Design and implement feature X.',
        ),
        jobSpec: _spec(domain: JobDomain.development, phase: phase),
        phase: phase,
      );

      expect(profile.validatorIds, ['ImplementationPlanReview']);
      expect(profile.criteria, contains(contains('Verification steps')));
    });

    test('selects continuity and style review for creative outline phases', () {
      final phase = _phase(
        id: 'chapter_outline',
        title: 'Create chapter outline',
        objective: 'Create a chapter outline with continuity notes.',
      );

      final profile = BuiltInModelValidators.select(
        taskBrief: _brief(
          domain: JobDomain.creativeWriting,
          objective: 'Create a novel planning pack.',
        ),
        jobSpec: _spec(domain: JobDomain.creativeWriting, phase: phase),
        phase: phase,
      );

      expect(profile.validatorIds, contains('FictionContinuityReview'));
      expect(profile.validatorIds, contains('StyleQualityReview'));
    });
  });
}

TaskBrief _brief({required JobDomain domain, required String objective}) {
  final now = DateTime(2026, 1, 1);
  return TaskBrief(
    id: 'task_test',
    createdAt: now,
    updatedAt: now,
    title: 'Test task',
    originalPrompt: objective,
    objective: objective,
    successCriteria: const ['Produce a useful artifact.'],
    constraints: const [],
    nonGoals: const [],
    assumptions: const [],
    clarifyingQuestions: const [],
    recommendedMode: ExecutionMode.job,
    recommendedAutonomy: AutonomyLevel.checkpointed,
    requiredOutputs: const [],
    domain: domain,
    riskLevel: RiskLevel.medium,
  );
}

JobSpec _spec({required JobDomain domain, required JobPhase phase}) {
  final now = DateTime(2026, 1, 1);
  return JobSpec(
    version: 1,
    id: 'job_test',
    title: 'Test job',
    createdAt: now,
    updatedAt: now,
    taskBriefId: 'task_test',
    status: JobStatus.planned,
    domain: domain,
    autonomy: AutonomyLevel.checkpointed,
    globalConstraints: const [],
    globalSuccessCriteria: const [],
    toolPolicy: const ToolPolicy(defaultAllowed: ['read_file', 'patch_file']),
    stopPolicy: const StopPolicy(),
    phases: [phase],
  );
}

JobPhase _phase({
  String id = 'phase_1',
  String title = 'Phase 1',
  String objective = 'Produce output.',
  List<String> allowedTools = const ['read_file'],
}) {
  return JobPhase(
    id: id,
    title: title,
    objective: objective,
    status: PhaseStatus.pending,
    inputs: const [],
    expectedOutputs: const [PhaseOutput(path: 'output.md', required: true)],
    allowedTools: allowedTools,
    terminalPolicy: TerminalPolicy.none,
    completionCriteria: const ['Output exists.'],
    review: const ReviewPolicy(required: true, reviewer: ReviewerType.model),
    humanCheckpoint: false,
  );
}
