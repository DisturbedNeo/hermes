import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/services/project_system/project_aggregate_repository.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';

/// Why a project command stopped making progress.
enum ProjectCommandStopReason {
  active,
  paused,
  waitingForUser,
  blocked,
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

  factory ProjectCommandResult.fromRun({
    required ProjectRunResult result,
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
      stopReason: ProjectCommandStopReasonFor.project(project),
      transitions: transitions,
      persistenceDiagnostics: result.persistenceDiagnostics,
    );
  }

  ProjectRunResult asRunResult() => ProjectRunResult(
    project: project,
    activeTask: activeTask,
    persistenceDiagnostics: persistenceDiagnostics,
  );
}

class ProjectCommandStopReasonFor {
  const ProjectCommandStopReasonFor._();

  static ProjectCommandStopReason project(ProjectDocument project) =>
      switch (project.status) {
        ProjectStatus.active ||
        ProjectStatus.initializing ||
        ProjectStatus.runningTask ||
        ProjectStatus.reviewingTask => ProjectCommandStopReason.active,
        ProjectStatus.paused => ProjectCommandStopReason.paused,
        ProjectStatus.waitingForUser => ProjectCommandStopReason.waitingForUser,
        ProjectStatus.blocked => ProjectCommandStopReason.blocked,
        ProjectStatus.completed => ProjectCommandStopReason.completed,
        ProjectStatus.failed => ProjectCommandStopReason.failed,
        ProjectStatus.cancelled => ProjectCommandStopReason.cancelled,
      };
}

/// All inputs required to run one project command.
class ProjectExecutionRequest {
  final ChatClient client;
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

class InvalidTaskTransitionException implements Exception {
  final TaskStatus from;
  final TaskStatus to;
  final String reason;

  const InvalidTaskTransitionException({
    required this.from,
    required this.to,
    required this.reason,
  });

  @override
  String toString() =>
      'InvalidTaskTransitionException: ${from.name} -> ${to.name}: $reason';
}

class ProjectReadOnlyException implements Exception {
  final ProjectPersistenceDiagnostics diagnostics;

  const ProjectReadOnlyException(this.diagnostics);

  @override
  String toString() =>
      'ProjectReadOnlyException: ${diagnostics.issues.join(' ')}';
}

/// A small adapter used by the focused services while the legacy service is
/// being decomposed. It keeps their dependencies explicit and testable.
typedef ProjectRunDelegate =
    Future<ProjectRunResult> Function(ProjectExecutionRequest request);

typedef ProjectRecoveryDelegate =
    Future<ProjectRunResult> Function(ProjectRecoveryRequest request);

typedef ProjectLoadDelegate =
    Future<ProjectLoadResult> Function(
      WorkspaceAttachment workspace,
      String projectId, {
      String? chatSessionId,
    });
