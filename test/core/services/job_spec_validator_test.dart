import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/job_system/job_spec_validator.dart';

void main() {
  group('JobSpecValidator', () {
    const validator = JobSpecValidator();

    test('accepts a complete spec with workspace-relative paths', () {
      final issues = validator.validate(
        _spec(
          phases: [
            _phase(
              inputs: const [
                PhaseInput(path: 'inputs/source.md', required: true),
              ],
              expectedOutputs: const [
                PhaseOutput(
                  path: '.agent/jobs/job_test/output.md',
                  required: true,
                ),
              ],
              validation: const PhaseValidation(
                mustExist: ['inputs/source.md'],
                mustNotModify: ['lib/main.dart'],
                requiredPatterns: [r'^# Report'],
              ),
            ),
          ],
        ),
      );

      expect(issues, isEmpty);
    });

    test('reports structural spec and phase issues together', () {
      final issues = validator.validate(
        _spec(
          id: '',
          title: '',
          taskBriefId: '',
          phases: [
            _phase(
              id: 'phase 1',
              title: '',
              objective: '',
              completionCriteria: const [],
              expectedOutputs: const [],
            ),
            _phase(id: 'duplicate'),
            _phase(id: 'duplicate'),
          ],
        ),
      );

      expect(issues, contains('job id is required'));
      expect(issues, contains('taskBriefId is required'));
      expect(issues, contains('job title is required'));
      expect(
        issues,
        contains('phase "phase 1" id must use letters, numbers, _ or -'),
      );
      expect(issues, contains('phase "phase 1" title is required'));
      expect(issues, contains('phase "phase 1" objective is required'));
      expect(issues, contains('phase "phase 1" needs completion criteria'));
      expect(
        issues,
        contains('phase "phase 1" needs at least one expected output'),
      );
      expect(issues, contains('phase id "duplicate" is duplicated'));
    });

    test('rejects unsafe paths and invalid validation regexes', () {
      final issues = validator.validate(
        _spec(
          phases: [
            _phase(
              inputs: const [
                PhaseInput(path: '/etc/passwd', required: true),
                PhaseInput(path: r'C:\Users\Public\input.md', required: true),
              ],
              expectedOutputs: const [
                PhaseOutput(path: '../escape.md', required: true),
              ],
              validation: const PhaseValidation(
                mustExist: ['../source.md'],
                mustNotModify: ['.'],
                requiredPatterns: ['['],
              ),
            ),
          ],
        ),
      );

      expect(
        issues,
        contains('phase "phase_1" input path is unsafe or empty: /etc/passwd'),
      );
      expect(
        issues,
        contains(
          r'phase "phase_1" input path is unsafe or empty: C:\Users\Public\input.md',
        ),
      );
      expect(
        issues,
        contains(
          'phase "phase_1" output path is unsafe or empty: ../escape.md',
        ),
      );
      expect(
        issues,
        contains(
          'phase "phase_1" mustExist path is unsafe or empty: ../source.md',
        ),
      );
      expect(
        issues,
        contains('phase "phase_1" mustNotModify path is unsafe or empty: .'),
      );
      expect(
        issues.any(
          (issue) => issue.startsWith(
            'phase "phase_1" validation regex is invalid: [',
          ),
        ),
        isTrue,
      );
    });
  });
}

JobSpec _spec({
  int version = 1,
  String id = 'job_test',
  String title = 'Test job',
  String taskBriefId = 'task_test',
  List<JobPhase> phases = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return JobSpec(
    version: version,
    id: id,
    title: title,
    createdAt: now,
    updatedAt: now,
    taskBriefId: taskBriefId,
    status: JobStatus.planned,
    domain: JobDomain.general,
    autonomy: AutonomyLevel.checkpointed,
    globalConstraints: const [],
    globalSuccessCriteria: const [],
    toolPolicy: const ToolPolicy(defaultAllowed: ['read_file']),
    stopPolicy: const StopPolicy(),
    phases: phases,
  );
}

JobPhase _phase({
  String id = 'phase_1',
  String title = 'Phase 1',
  String objective = 'Produce output',
  List<PhaseInput> inputs = const [],
  List<PhaseOutput> expectedOutputs = const [
    PhaseOutput(path: 'output.md', required: true),
  ],
  List<String> completionCriteria = const ['Output exists'],
  PhaseValidation? validation,
}) {
  return JobPhase(
    id: id,
    title: title,
    objective: objective,
    status: PhaseStatus.pending,
    inputs: inputs,
    expectedOutputs: expectedOutputs,
    allowedTools: const ['read_file'],
    terminalPolicy: TerminalPolicy.none,
    completionCriteria: completionCriteria,
    validation: validation,
    review: const ReviewPolicy(required: true, reviewer: ReviewerType.hybrid),
    humanCheckpoint: false,
    retryPolicy: const RetryPolicy(),
  );
}
