import 'package:hermes/core/models/job.dart';

class JobToolPolicyResolver {
  final Set<String> availableToolIds;

  const JobToolPolicyResolver({required this.availableToolIds});

  List<String> normaliseToolIds(List<String> toolIds) {
    return toolIds
        .map(
          (id) => switch (id) {
            'list_files' => 'list_directory',
            'list_dir' => 'list_directory',
            'search' => 'search_files',
            'read' => 'read_file',
            'write' => 'write_file',
            'patch' => 'patch_file',
            _ => id,
          },
        )
        .where(availableToolIds.contains)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> phaseAllowedTools(JobSpec spec, JobPhase phase) {
    var tools = phase.allowedTools.isEmpty
        ? normaliseToolIds(spec.toolPolicy.defaultAllowed).toSet()
        : normaliseToolIds(phase.allowedTools).toSet();
    tools.removeAll(normaliseToolIds(spec.toolPolicy.defaultDisallowed));
    tools.removeAll(normaliseToolIds(phase.disallowedTools));
    if (effectiveTerminalPolicy(spec, phase) == TerminalPolicy.none) {
      tools.remove('run_command');
    }
    return tools.toList()..sort();
  }

  List<String> phaseDisallowedTools(JobSpec spec, JobPhase phase) {
    final disallowed = {
      ...normaliseToolIds(spec.toolPolicy.defaultDisallowed),
      ...normaliseToolIds(phase.disallowedTools),
    };
    if (effectiveTerminalPolicy(spec, phase) == TerminalPolicy.none) {
      disallowed.add('run_command');
    }
    return disallowed.toList()..sort();
  }

  StopPolicy effectiveStopPolicy(JobSpec spec, JobPhase phase) {
    final phasePolicy = phase.stopPolicy;
    if (phasePolicy == null) return spec.stopPolicy;
    return StopPolicy(
      maxTotalPhases: spec.stopPolicy.maxTotalPhases,
      maxPhaseTerminalCommands:
          phasePolicy.maxPhaseTerminalCommands ??
          spec.stopPolicy.maxPhaseTerminalCommands,
      maxPhaseFilesRead:
          phasePolicy.maxPhaseFilesRead ?? spec.stopPolicy.maxPhaseFilesRead,
      maxPhaseRetries:
          phasePolicy.maxPhaseRetries ?? spec.stopPolicy.maxPhaseRetries,
      maxRuntimeSeconds:
          phasePolicy.maxRuntimeSeconds ?? spec.stopPolicy.maxRuntimeSeconds,
      stopOnRequiredQuestion:
          phasePolicy.stopOnRequiredQuestion ??
          spec.stopPolicy.stopOnRequiredQuestion,
      stopOnLowConfidence:
          phasePolicy.stopOnLowConfidence ??
          spec.stopPolicy.stopOnLowConfidence,
    );
  }

  TerminalPolicy effectiveTerminalPolicy(JobSpec spec, JobPhase phase) {
    final terminal = spec.toolPolicy.terminal;
    if (terminal?.allowed == false) return TerminalPolicy.none;
    final global = terminal?.policy ?? phase.terminalPolicy;
    return _stricterTerminalPolicy(global, phase.terminalPolicy);
  }

  bool shouldDetectWorkspaceMutations(JobSpec spec, JobPhase phase) {
    final allowedTools = phaseAllowedTools(spec, phase);
    final writesAllowed =
        allowedTools.contains('write_file') ||
        allowedTools.contains('patch_file') ||
        allowedTools.contains('create_directory') ||
        allowedTools.contains('rename_path') ||
        allowedTools.contains('delete_path');
    return effectiveTerminalPolicy(spec, phase) == TerminalPolicy.readonly ||
        !writesAllowed ||
        (phase.validation?.mustNotModify.isNotEmpty ?? false);
  }

  TerminalPolicy _stricterTerminalPolicy(
    TerminalPolicy left,
    TerminalPolicy right,
  ) {
    return _terminalPolicyRank(left) <= _terminalPolicyRank(right)
        ? left
        : right;
  }

  int _terminalPolicyRank(TerminalPolicy policy) {
    return switch (policy) {
      TerminalPolicy.none => 0,
      TerminalPolicy.readonly => 1,
      TerminalPolicy.workspaceMutating => 2,
      TerminalPolicy.unrestrictedWorkspace => 3,
    };
  }
}
