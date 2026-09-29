import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/project_runtime_contracts.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';

export 'package:hermes/features/project/project_application_port.dart'
    show ProjectApplicationPort;

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
    required ProjectAggregate project,
    required String rawJson,
  });

  Future<ProjectAggregate> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate project,
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
