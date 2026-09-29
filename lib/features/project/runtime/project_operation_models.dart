part of 'project_runtime_engine.dart';

class _ProjectTaskValidation {
  final bool valid;
  final List<String> violations;

  const _ProjectTaskValidation(this.valid, this.violations);
}

sealed class _DuplicateProjectTaskMatch {
  final ProjectTaskNode task;

  const _DuplicateProjectTaskMatch(this.task);
}

class _QueuedDuplicateProjectTask extends _DuplicateProjectTaskMatch {
  const _QueuedDuplicateProjectTask(super.task);
}

class _FailedDuplicateProjectTask extends _DuplicateProjectTaskMatch {
  const _FailedDuplicateProjectTask(super.task);
}

class _ProjectTaskExecution {
  final ProjectDocument project;
  final Task? activeTask;
  final TaskResult? result;

  const _ProjectTaskExecution({
    required this.project,
    this.activeTask,
    this.result,
  });
}

class _RecoveryFailure {
  final TaskGateResult gateResult;
  final String? command;
  final String? workingDirectory;
  final String summary;

  const _RecoveryFailure({
    required this.gateResult,
    required this.command,
    required this.workingDirectory,
    required this.summary,
  });
}

class _RecoveryUpdate {
  final ProjectTaskNode failedTask;
  final List<ProjectRecoveryIncident> recoveryIncidents;
  final ProjectRecoveryIncident? incident;
  final ProjectRecoveryIncident? exhaustedIncident;
  final ProjectTaskNode? recoveryTask;

  const _RecoveryUpdate({
    required this.failedTask,
    required this.recoveryIncidents,
    this.incident,
    this.exhaustedIncident,
    this.recoveryTask,
  });
}

class _FilteredProjectQuestions {
  final List<PendingProjectQuestion> blocking;
  final List<String> assumptions;

  const _FilteredProjectQuestions({
    required this.blocking,
    required this.assumptions,
  });
}
