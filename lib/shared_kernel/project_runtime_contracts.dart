import 'package:hermes/shared_kernel/compaction_settings.dart';
import 'package:hermes/shared_kernel/project.dart';
import 'package:hermes/shared_kernel/task.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';
import 'package:hermes/shared_kernel/workspace.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/model_provider.dart';
import 'package:hermes/shared_kernel/persistence_contracts.dart';
import 'package:hermes/shared_kernel/project_control_state_service.dart';
import 'package:hermes/shared_kernel/model_output.dart';

typedef ProjectTaskSnapshotSink = void Function(Task? task);
typedef ProjectCompactionStatusSink = void Function(String status);

/// Why a project command stopped making progress.
enum ProjectCommandStopReason {
  active,
  paused,
  waitingForUser,
  blocked,
  degradedPlanning,
  completed,
  failed,
  cancelled,
  readOnly,
}

/// A lifecycle transition observed while handling a command.
class ProjectLifecycleTransition {
  final ProjectStatus from;
  final ProjectStatus to;
  final String trigger;
  final String reason;
  final DateTime occurredAt;
  final String? taskId;

  const ProjectLifecycleTransition({
    required this.from,
    required this.to,
    required this.trigger,
    required this.reason,
    required this.occurredAt,
    this.taskId,
  });
}

/// The stable result shape returned by the application-facing orchestrator.
class ProjectCommandResult {
  final ProjectDocument project;
  final Task? activeTask;
  final ProjectCommandStopReason stopReason;
  final List<ProjectLifecycleTransition> transitions;
  final ProjectPersistenceDiagnostics? persistenceDiagnostics;

  const ProjectCommandResult({
    required this.project,
    this.activeTask,
    required this.stopReason,
    this.transitions = const [],
    this.persistenceDiagnostics,
  });

  factory ProjectCommandResult.fromSnapshot({
    required ProjectDocument project,
    Task? activeTask,
    ProjectPersistenceDiagnostics? persistenceDiagnostics,
  }) => ProjectCommandResult(
    project: project,
    activeTask: activeTask,
    stopReason: persistenceDiagnostics?.isReadOnly == true
        ? ProjectCommandStopReason.readOnly
        : ProjectCommandStopReasonFor.project(project),
    persistenceDiagnostics: persistenceDiagnostics,
  );

  factory ProjectCommandResult.withTransition({
    required ProjectCommandResult result,
    ProjectDocument? before,
    String trigger = 'command',
  }) {
    final project = result.project;
    final transitions = <ProjectLifecycleTransition>[];
    if (before != null && before.status != project.status) {
      transitions.add(
        ProjectLifecycleTransition(
          from: before.status,
          to: project.status,
          trigger: trigger,
          reason: project.blocker?.message ?? '',
          occurredAt: project.updatedAt,
          taskId: project.activeTaskId,
        ),
      );
    }
    return ProjectCommandResult(
      project: project,
      activeTask: result.activeTask,
      stopReason: result.stopReason,
      transitions: [...result.transitions, ...transitions],
      persistenceDiagnostics: result.persistenceDiagnostics,
    );
  }
}

class ProjectCommandStopReasonFor {
  const ProjectCommandStopReasonFor._();

  static ProjectCommandStopReason project(ProjectDocument project) =>
      switch (const ProjectControlStateMachine().read(project).outcome) {
        ProjectControlOutcome.degradedPlanning =>
          ProjectCommandStopReason.degradedPlanning,
        ProjectControlOutcome.awaitingUserInput ||
        ProjectControlOutcome.awaitingPlanApproval =>
          ProjectCommandStopReason.waitingForUser,
        ProjectControlOutcome.blockedValidation =>
          ProjectCommandStopReason.blocked,
        ProjectControlOutcome.paused ||
        ProjectControlOutcome.pausedByBudget => ProjectCommandStopReason.paused,
        ProjectControlOutcome.completed => ProjectCommandStopReason.completed,
        ProjectControlOutcome.failed => ProjectCommandStopReason.failed,
        ProjectControlOutcome.cancelled => ProjectCommandStopReason.cancelled,
        ProjectControlOutcome.initializing ||
        ProjectControlOutcome.running => ProjectCommandStopReason.active,
      };
}

/// All inputs required to run one project command.
class ProjectExecutionRequest {
  final ModelProvider client;
  final WorkspaceAttachment workspace;
  final ProjectDocument snapshot;
  final String baseSystemPrompt;
  final int maxNewTasks;
  final int? maxIterations;
  final bool requirePhaseApproval;
  final CompactionSettings? compactionSettings;
  final int? contextLimitTokens;
  final ProjectCompactionStatusSink? onCompactionStatus;
  final TaskModelOutputSink? onModelOutput;
  final ProjectTaskSnapshotSink? onTaskUpdated;
  final CancellationToken? cancellationToken;
  final QuestionAutonomy questionAutonomy;
  final ProjectPlanApprovalPolicy planApprovalPolicy;

  const ProjectExecutionRequest({
    required this.client,
    required this.workspace,
    required this.snapshot,
    required this.baseSystemPrompt,
    required this.maxNewTasks,
    this.maxIterations,
    this.requirePhaseApproval = false,
    this.compactionSettings,
    this.contextLimitTokens,
    this.onCompactionStatus,
    this.onModelOutput,
    this.onTaskUpdated,
    this.cancellationToken,
    this.questionAutonomy = QuestionAutonomy.balanced,
    this.planApprovalPolicy = ProjectPlanApprovalPolicy.highRiskOnly,
  });

  ProjectExecutionRequest copyWith({
    ProjectDocument? snapshot,
    String? baseSystemPrompt,
  }) => ProjectExecutionRequest(
    client: client,
    workspace: workspace,
    snapshot: snapshot ?? this.snapshot,
    baseSystemPrompt: baseSystemPrompt ?? this.baseSystemPrompt,
    maxNewTasks: maxNewTasks,
    maxIterations: maxIterations,
    requirePhaseApproval: requirePhaseApproval,
    compactionSettings: compactionSettings,
    contextLimitTokens: contextLimitTokens,
    onCompactionStatus: onCompactionStatus,
    onModelOutput: onModelOutput,
    onTaskUpdated: onTaskUpdated,
    cancellationToken: cancellationToken,
    questionAutonomy: questionAutonomy,
    planApprovalPolicy: planApprovalPolicy,
  );
}

class ProjectRecoveryRequest {
  final WorkspaceAttachment workspace;
  final ProjectDocument snapshot;
  final ProjectTaskSnapshotSink? onTaskUpdated;

  const ProjectRecoveryRequest({
    required this.workspace,
    required this.snapshot,
    this.onTaskUpdated,
  });
}

class ProjectBusyException implements Exception {
  final String workspaceRoot;
  final String projectId;

  const ProjectBusyException({
    required this.workspaceRoot,
    required this.projectId,
  });

  @override
  String toString() =>
      'ProjectBusyException: project $projectId is already being handled in $workspaceRoot.';
}

class InvalidProjectTransitionException implements Exception {
  final ProjectStatus from;
  final ProjectStatus to;
  final String reason;

  const InvalidProjectTransitionException({
    required this.from,
    required this.to,
    required this.reason,
  });

  @override
  String toString() =>
      'InvalidProjectTransitionException: ${from.name} -> ${to.name}: $reason';
}

class ProjectReadOnlyException implements Exception {
  final ProjectPersistenceDiagnostics diagnostics;

  const ProjectReadOnlyException(this.diagnostics);

  @override
  String toString() =>
      'ProjectReadOnlyException: ${diagnostics.issues.join(' ')}';
}

/// Delegate seams keep the focused execution paths explicit and testable.
typedef ProjectExecutionDelegate =
    Future<ProjectCommandResult> Function(ProjectExecutionRequest request);

typedef ProjectRecoveryDelegate =
    Future<ProjectCommandResult> Function(ProjectRecoveryRequest request);

typedef ProjectLoadDelegate =
    Future<dynamic> Function(
      WorkspaceAttachment workspace,
      String projectId, {
      String? chatSessionId,
    });
