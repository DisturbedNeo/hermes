import 'package:hermes/core/cancellation.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/model/application/model_capabilities.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Aggregate-free result returned by a project workflow command.
class ProjectWorkflowResult {
  const ProjectWorkflowResult({
    required this.project,
    this.activeTask,
    this.stopReason = ProjectWorkflowStopReason.active,
    this.persistenceDiagnostics,
  });

  final ProjectSummary project;
  final TaskSummary? activeTask;
  final ProjectWorkflowStopReason stopReason;
  final ProjectPersistenceDiagnostics? persistenceDiagnostics;
}

enum ProjectWorkflowStopReason {
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

/// ID-based project execution request. The owning project runtime hydrates the
/// aggregate; callers never hand an aggregate across this boundary.
class ProjectWorkflowExecution {
  const ProjectWorkflowExecution({
    required this.client,
    required this.workspace,
    required this.projectId,
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

  final ModelConversationPort client;
  final WorkspaceAttachment workspace;
  final String projectId;
  final String baseSystemPrompt;
  final int maxNewTasks;
  final int? maxIterations;
  final bool requirePhaseApproval;
  final CompactionSettings? compactionSettings;
  final int? contextLimitTokens;
  final void Function(String status)? onCompactionStatus;
  final ModelOutputSink? onModelOutput;
  final void Function(TaskSummary? task)? onTaskUpdated;
  final CancellationToken? cancellationToken;
  final QuestionAutonomy questionAutonomy;
  final ProjectPlanApprovalPolicy planApprovalPolicy;
}

class ProjectWorkflowRecovery {
  const ProjectWorkflowRecovery({
    required this.workspace,
    required this.projectId,
    this.onTaskUpdated,
  });

  final WorkspaceAttachment workspace;
  final String projectId;
  final void Function(TaskSummary? task)? onTaskUpdated;
}

/// Feature-facing project workflow capability. It uses IDs, commands, and
/// detached summaries; aggregate hydration and mutation remain owner-bound.
abstract interface class ProjectWorkflowPort {
  Future<ProjectWorkflowResult> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelConversationPort? client,
    String baseSystemPrompt,
    int? maxIterations,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy,
  });

  Future<ProjectWorkflowResult> addUserContext({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String text,
  });

  Future<ProjectWorkflowResult> requestScopeChange({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String context,
  });

  Future<ProjectWorkflowResult> updateProject({
    required WorkspaceAttachment workspace,
    required String projectId,
    required ProjectUpdateCommand command,
  });

  Future<ProjectWorkflowResult> pauseProject({
    required WorkspaceAttachment workspace,
    required String projectId,
  });

  Future<ProjectWorkflowResult> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String answer,
  });

  Future<ProjectWorkflowResult> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required String projectId,
  });

  Future<ProjectWorkflowResult> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required String projectId,
  });

  Future<ProjectWorkflowResult> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required String projectId,
  });

  Future<ProjectWorkflowResult> stopProject({
    required WorkspaceAttachment workspace,
    required String projectId,
  });

  Future<ProjectWorkflowResult> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String incidentId,
  });

  Future<ProjectWorkflowResult> executeUntilStop(
    ProjectWorkflowExecution request, {
    required bool boundedRun,
  });

  Future<ProjectWorkflowResult> recover(ProjectWorkflowRecovery request);
}
