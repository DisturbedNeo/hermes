import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_discovery_service.dart';
import 'package:hermes/core/services/project_system/project_planning_gateway.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/workspace_discovery_profile.dart';

typedef ProjectInitialisationValidator =
    List<Map<String, String>> Function({
      required ProjectInitialPlanResult initialPlan,
      required WorkspaceDiscoveryProfile workspaceProfile,
    });

typedef ProjectContextIssuePolicy =
    bool Function(WorkspaceRequiredContextIssue issue);

class ProjectPlanningResult {
  const ProjectPlanningResult({
    required this.discovery,
    required this.initialPlan,
    required this.validationIssues,
    required this.modelCallCount,
    required this.repairAttempts,
    required this.planningMetrics,
  });

  final ProjectEvidenceSnapshot discovery;
  final ProjectInitialPlanResult initialPlan;
  final List<Map<String, String>> validationIssues;
  final int modelCallCount;
  final int repairAttempts;
  final PlanningMetrics planningMetrics;

  ProjectInitialisation get initialisation => initialPlan.toLegacy();
}

/// Coordinates discovery, bounded initial-plan repair, and validation.
///
/// This component owns only the model-planning protocol and its bounded retry
/// policy. The returned patch is later applied once by the planning phase to
/// the real project aggregate.
class ProjectPlanningCoordinator {
  const ProjectPlanningCoordinator({
    required ProjectDiscoveryService discovery,
    required ProjectPlanner planner,
    this.maxAutomaticRepairs = 2,
  }) : _discovery = discovery,
       _planner = planner;

  final ProjectDiscoveryService _discovery;
  final ProjectPlanner _planner;
  final int maxAutomaticRepairs;

  Future<ProjectPlanningResult> initialise({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ChatClient? client,
    required String baseSystemPrompt,
    required ProjectInitialPlanResult Function() fallback,
    required ProjectInitialisationValidator validate,
    required ProjectContextIssuePolicy blocksContextIssue,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final discovery = await _discovery.collect(
      workspace: workspace,
      goalContext: userPrompt,
      cancellationToken: cancellationToken,
    );
    final metadata = {
      ...discovery.toMap(),
      'commandExecutionApproved': workspace.commandExecutionApproved,
    };
    var issues = <Map<String, String>>[
      for (final issue in discovery.workspaceProfile.requiredContextIssues)
        if (blocksContextIssue(issue))
          {'code': issue.code, 'path': issue.path, 'message': issue.message},
    ];
    var modelCallCount = 0;
    var repairAttempts = 0;
    var initialPlan = client == null || issues.isNotEmpty
        ? fallback()
        : _planner is ProjectInitialPlanPlanner
        ? await (_planner as ProjectInitialPlanPlanner).initializePlan(
            client: client,
            baseSystemPrompt: baseSystemPrompt,
            workspace: workspace,
            originalGoal: userPrompt,
            workspaceMetadata: metadata,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          )
        : ProjectInitialPlanResult.fromLegacy(
            await _planner.initializeProject(
              client: client,
              baseSystemPrompt: baseSystemPrompt,
              workspace: workspace,
              originalGoal: userPrompt,
              workspaceMetadata: metadata,
              onModelOutput: onModelOutput,
              cancellationToken: cancellationToken,
            ),
          );
    var planningMetrics = initialPlan.planningMetrics;

    if (client != null && issues.isEmpty) {
      modelCallCount++;
      issues = validate(
        initialPlan: initialPlan,
        workspaceProfile: discovery.workspaceProfile,
      );
      while (issues.isNotEmpty && repairAttempts < maxAutomaticRepairs) {
        repairAttempts++;
        final ProjectInitialPlanResult? repaired;
        if (_planner is ProjectInitialPlanPlanner) {
          repaired = await (_planner as ProjectInitialPlanPlanner)
              .repairInitialPlan(
                client: client,
                baseSystemPrompt: baseSystemPrompt,
                workspace: workspace,
                originalGoal: userPrompt,
                workspaceMetadata: metadata,
                initialPlan: initialPlan,
                validationIssues: issues,
                onModelOutput: onModelOutput,
                cancellationToken: cancellationToken,
              );
        } else {
          final repairedLegacy = await _planner.repairInitialisation(
            client: client,
            baseSystemPrompt: baseSystemPrompt,
            workspace: workspace,
            originalGoal: userPrompt,
            workspaceMetadata: metadata,
            initialisation: initialPlan.toLegacy(),
            validationIssues: issues,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          );
          repaired = repairedLegacy == null
              ? null
              : ProjectInitialPlanResult.fromLegacy(repairedLegacy);
        }
        modelCallCount++;
        if (repaired == null) continue;
        planningMetrics = planningMetrics.add(repaired.planningMetrics);
        initialPlan = repaired;
        issues = validate(
          initialPlan: initialPlan,
          workspaceProfile: discovery.workspaceProfile,
        );
      }
    }
    cancellationToken?.throwIfCancelled();
    return ProjectPlanningResult(
      discovery: discovery,
      initialPlan: initialPlan,
      validationIssues: issues,
      modelCallCount: modelCallCount,
      repairAttempts: repairAttempts,
      planningMetrics: planningMetrics,
    );
  }
}
