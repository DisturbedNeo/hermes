import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/job_system/job_tool_policy_resolver.dart';

void main() {
  group('JobToolPolicyResolver', () {
    const resolver = JobToolPolicyResolver(
      availableToolIds: {
        'read_file',
        'write_file',
        'patch_file',
        'search_files',
        'run_command',
      },
    );

    test('normalises aliases and removes unavailable tool ids', () {
      expect(resolver.normaliseToolIds(const ['read', 'search', 'missing']), [
        'read_file',
        'search_files',
      ]);
    });

    test('combines global and phase tool restrictions', () {
      final spec = _spec(
        toolPolicy: const ToolPolicy(
          defaultAllowed: ['read', 'write', 'run_command'],
          defaultDisallowed: ['write_file'],
        ),
      );
      final phase = _phase(
        allowedTools: const ['read_file', 'write_file', 'run_command'],
        disallowedTools: const ['patch_file'],
        terminalPolicy: TerminalPolicy.workspaceMutating,
      );

      expect(resolver.phaseAllowedTools(spec, phase), [
        'read_file',
        'run_command',
      ]);
      expect(resolver.phaseDisallowedTools(spec, phase), [
        'patch_file',
        'write_file',
      ]);
    });

    test(
      'removes terminal tool when the effective terminal policy is none',
      () {
        final spec = _spec(
          toolPolicy: const ToolPolicy(
            defaultAllowed: ['read_file', 'run_command'],
            terminal: TerminalToolPolicy(
              allowed: true,
              policy: TerminalPolicy.workspaceMutating,
            ),
          ),
        );
        final phase = _phase(
          allowedTools: const ['read_file', 'run_command'],
          terminalPolicy: TerminalPolicy.none,
        );

        expect(
          resolver.effectiveTerminalPolicy(spec, phase),
          TerminalPolicy.none,
        );
        expect(resolver.phaseAllowedTools(spec, phase), ['read_file']);
        expect(resolver.phaseDisallowedTools(spec, phase), ['run_command']);
      },
    );

    test('uses the stricter terminal policy and phase stop overrides', () {
      final spec = _spec(
        toolPolicy: const ToolPolicy(
          terminal: TerminalToolPolicy(
            allowed: true,
            policy: TerminalPolicy.readonly,
          ),
        ),
        stopPolicy: const StopPolicy(
          maxTotalPhases: 8,
          maxPhaseFilesRead: 10,
          stopOnLowConfidence: false,
        ),
      );
      final phase = _phase(
        terminalPolicy: TerminalPolicy.unrestrictedWorkspace,
        stopPolicy: const StopPolicy(maxPhaseFilesRead: 2, maxPhaseRetries: 3),
      );

      expect(
        resolver.effectiveTerminalPolicy(spec, phase),
        TerminalPolicy.readonly,
      );

      final stopPolicy = resolver.effectiveStopPolicy(spec, phase);
      expect(stopPolicy.maxTotalPhases, 8);
      expect(stopPolicy.maxPhaseFilesRead, 2);
      expect(stopPolicy.maxPhaseRetries, 3);
      expect(stopPolicy.stopOnLowConfidence, isFalse);
    });

    test('detects mutation-sensitive phases', () {
      final readonlySpec = _spec(
        toolPolicy: const ToolPolicy(
          defaultAllowed: ['read_file', 'run_command'],
          terminal: TerminalToolPolicy(
            allowed: true,
            policy: TerminalPolicy.readonly,
          ),
        ),
      );
      expect(
        resolver.shouldDetectWorkspaceMutations(
          readonlySpec,
          _phase(
            allowedTools: const ['run_command'],
            terminalPolicy: TerminalPolicy.workspaceMutating,
          ),
        ),
        isTrue,
      );

      final writeSpec = _spec(
        toolPolicy: const ToolPolicy(defaultAllowed: ['write_file']),
      );
      expect(
        resolver.shouldDetectWorkspaceMutations(
          writeSpec,
          _phase(allowedTools: const ['write_file']),
        ),
        isFalse,
      );
    });
  });
}

JobSpec _spec({
  ToolPolicy toolPolicy = const ToolPolicy(defaultAllowed: ['read_file']),
  StopPolicy stopPolicy = const StopPolicy(),
}) {
  final now = DateTime(2026, 1, 1);
  return JobSpec(
    version: 1,
    id: 'job_test',
    title: 'Test job',
    createdAt: now,
    updatedAt: now,
    taskBriefId: 'task_test',
    status: JobStatus.planned,
    domain: JobDomain.general,
    autonomy: AutonomyLevel.checkpointed,
    globalConstraints: const [],
    globalSuccessCriteria: const [],
    toolPolicy: toolPolicy,
    stopPolicy: stopPolicy,
    phases: const [],
  );
}

JobPhase _phase({
  List<String> allowedTools = const ['read_file'],
  List<String> disallowedTools = const [],
  TerminalPolicy terminalPolicy = TerminalPolicy.none,
  StopPolicy? stopPolicy,
}) {
  return JobPhase(
    id: 'phase_1',
    title: 'Phase 1',
    objective: 'Produce output',
    status: PhaseStatus.pending,
    inputs: const [],
    expectedOutputs: const [PhaseOutput(path: 'output.md', required: true)],
    allowedTools: allowedTools,
    disallowedTools: disallowedTools,
    terminalPolicy: terminalPolicy,
    completionCriteria: const ['Output exists'],
    review: const ReviewPolicy(required: true, reviewer: ReviewerType.hybrid),
    humanCheckpoint: false,
    stopPolicy: stopPolicy,
    retryPolicy: const RetryPolicy(),
  );
}
