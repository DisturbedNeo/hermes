import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';

abstract interface class ProjectQueryPort {
  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  });

  Future<ProjectAggregate?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  });

  Future<ProjectAggregate?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  });
}

abstract interface class ProjectSessionPort {
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
}

abstract interface class ProjectPlanningPort {
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
}

abstract interface class ProjectCommandPort {
  Future<ProjectAggregate> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required ProjectUpdateCommand command,
  });

  Future<ProjectAggregate> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  });

  Future<ProjectAggregate> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String answer,
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

  Future<ProjectAggregate> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  });
}

abstract interface class ProjectRecoveryCommandsPort {
  Future<ProjectAggregate> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String incidentId,
  });
}

abstract interface class ProjectExecutionPort {
  Future<ProjectCommandResult> executeUntilStop(
    ProjectExecutionRequest request, {
    required bool boundedRun,
  });

  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request);
}
