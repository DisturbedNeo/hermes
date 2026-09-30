import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/model_output.dart';
import 'package:hermes/shared_kernel/model_completion_port.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';
import 'package:hermes/shared_kernel/workspace.dart';

/// Read-only project queries exposed to chat and presentation.
abstract interface class ProjectQueryPort {
  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  });

  Future<ProjectAggregate?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  });
}

/// Project commands that do not start execution.
abstract interface class ProjectCommandPort {
  Future<ProjectAggregate> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String rawJson,
  });

  Future<ProjectAggregate> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  });
}

/// Project execution and recovery boundary.
abstract interface class ProjectExecutionPort {
  Future<ProjectCommandResult> executeUntilStop(
    ProjectExecutionRequest request, {
    required bool boundedRun,
  });

  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request);
}

/// The chat-facing project use cases. This is intentionally expressed as
/// user operations rather than as a handle to the project runtime or its
/// repositories.
abstract interface class ProjectChatPort
    implements ProjectQueryPort, ProjectCommandPort, ProjectExecutionPort {
  Future<ProjectAggregate?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  });

  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  });

  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  });

  Future<ProjectAggregate> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String chatSessionId,
  });

  String encodeProject(ProjectAggregate project);

  Future<ProjectAggregate> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelCompletionPort? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  });

  Future<ProjectAggregate> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String answer,
  });

  Future<ProjectAggregate> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String text,
  });

  Future<ProjectAggregate> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String context,
  });

  Future<ProjectAggregate> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  });

  Future<ProjectAggregate> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  });

  Future<ProjectAggregate> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  });

  Future<ProjectAggregate> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String incidentId,
  });

  Future<ProjectAggregate> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  });
}
