import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/runtime/project_discovery_service.dart';
import 'package:hermes/features/project/runtime/project_planning_gateway.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/workspace/application/workspace_discovery_profile.dart';

/// Typed input for one incremental project-plan revision.
class ProjectPlanRevisionRequest {
  const ProjectPlanRevisionRequest({
    required this.client,
    required this.workspace,
    required this.project,
    required this.triggers,
    required this.baseSystemPrompt,
    required this.approvalPolicy,
    this.onModelOutput,
    this.cancellationToken,
  });

  final ModelCompletionPort client;
  final WorkspaceAttachment workspace;
  final ProjectAggregate project;
  final List<ProjectPlanRevisionTrigger> triggers;
  final String baseSystemPrompt;
  final ProjectPlanApprovalPolicy approvalPolicy;
  final ModelOutputSink? onModelOutput;
  final CancellationToken? cancellationToken;
}

/// Typed result separating bounded context collection from model-backed
/// planning. The state machine decides how to transition the aggregate.
class ProjectPlanRevisionResult {
  const ProjectPlanRevisionResult({
    this.incremental,
    this.contextIssues = const [],
  });

  final ProjectIncrementalPlanResult? incremental;
  final List<WorkspaceRequiredContextIssue> contextIssues;

  bool get hasContextIssues => contextIssues.isNotEmpty;
}

class ProjectPlanRevisionCoordinator {
  const ProjectPlanRevisionCoordinator({
    required ProjectDiscoveryService discovery,
    required ProjectPlanner planner,
  }) : _discovery = discovery,
       _planner = planner;

  final ProjectDiscoveryService _discovery;
  final ProjectPlanner _planner;

  Future<ProjectPlanRevisionResult> revise(
    ProjectPlanRevisionRequest request,
  ) async {
    final snapshot = await _discovery.collect(
      workspace: request.workspace,
      project: request.project,
      goalContext:
          'Original goal:\n${request.project.originalGoal}\n\nRefined goal:\n${request.project.refinedGoal}',
      cancellationToken: request.cancellationToken,
    );
    final issues = snapshot.workspaceProfile.requiredContextIssues;
    if (issues.isNotEmpty) {
      return ProjectPlanRevisionResult(contextIssues: issues);
    }

    return ProjectPlanRevisionResult(
      incremental: await _planner.revisePlanWithCommands(
        client: request.client,
        baseSystemPrompt: request.baseSystemPrompt,
        workspace: request.workspace,
        project: request.project,
        evidenceSnapshot: snapshot,
        triggers: request.triggers.toSet().toList(),
        approvalPolicy: request.approvalPolicy,
        onModelOutput: request.onModelOutput,
        cancellationToken: request.cancellationToken,
      ),
    );
  }
}
