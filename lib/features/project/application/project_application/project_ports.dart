import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/features/model/domain/model_provider.dart';
import 'package:hermes/features/project/application/project_application/orchestration_contracts.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/task_application/task_model_output.dart';
import 'package:hermes/features/task/domain/task_system_settings.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';

/// Application-facing project use cases. Chat depends on this port rather
/// than on the project runtime implementation.
abstract interface class ProjectApplicationPort {
  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  });

  Future<ProjectDocument?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  });

  Future<ProjectDocument?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
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

  Future<ProjectDocument> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String chatSessionId,
  });

  String encodeProject(ProjectDocument project);

  Future<ProjectDocument> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelProvider? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  });

  Future<ProjectCommandResult> executeUntilStop(
    ProjectExecutionRequest request, {
    required bool boundedRun,
  });

  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request);

  Future<ProjectDocument> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String rawJson,
  });

  Future<ProjectDocument> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String answer,
  });

  Future<ProjectDocument> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String text,
  });

  Future<ProjectDocument> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String context,
  });

  Future<ProjectDocument> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  });

  Future<ProjectDocument> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  });

  Future<ProjectDocument> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  });

  Future<ProjectDocument> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  });

  Future<ProjectDocument> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String incidentId,
  });

  Future<ProjectDocument> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  });
}
