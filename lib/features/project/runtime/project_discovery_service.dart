import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/project/runtime/project_memory_service.dart';
import 'package:hermes/features/project/runtime/project_planning_gateway.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/workspace/infrastructure/workspace_discovery_service.dart';
import 'package:hermes/features/workspace/application/workspace_change_discovery.dart';

/// Collects bounded, read-only context for initialization and replanning.
class ProjectDiscoveryService {
  const ProjectDiscoveryService({
    required TaskQueryPort taskController,
    required WorkspaceChangeDiscoveryPort changeDiscovery,
    ProjectMemoryService memoryService = const ProjectMemoryService(),
    WorkspaceDiscoveryProfileService profileService =
        const WorkspaceDiscoveryProfileService(),
    ProjectWorkspaceContextService workspaceContextService =
        const ProjectWorkspaceContextService(),
  }) : _taskQueries = taskController,
       _changeDiscovery = changeDiscovery,
       _memoryService = memoryService,
       _profileService = profileService,
       _workspaceContextService = workspaceContextService;

  static const int _maxRootEntries = 80;
  static const int _maxRecentItems = 12;

  final TaskQueryPort _taskQueries;
  final WorkspaceChangeDiscoveryPort _changeDiscovery;
  final ProjectMemoryService _memoryService;
  final WorkspaceDiscoveryProfileService _profileService;
  final ProjectWorkspaceContextService _workspaceContextService;
  static const ProjectScheduler _scheduler = ProjectScheduler();

  Future<ProjectEvidenceSnapshot> collect({
    required WorkspaceAttachment workspace,
    ProjectAggregate? project,
    String goalContext = '',
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final workspaceProfile = await _profileService.collect(
      workspace: workspace,
      goalContext: goalContext,
      cancellationToken: cancellationToken,
    );
    final rootEntries = workspaceProfile.rootEntries
        .take(_maxRootEntries)
        .toList();
    final changeSet = await _changeDiscovery.discover(
      workspace,
      cancellationToken: cancellationToken,
    );

    final taskSummaries = [
      ...await _taskQueries.listTasks(
        workspace,
        chatSessionId: project?.chatSessionId,
        projectId: project?.id,
      ),
    ];
    cancellationToken?.throwIfCancelled();
    taskSummaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final evidence = project?.evidence ?? const <ProjectEvidence>[];
    final verificationCommands = <String>{};
    for (final item in evidence) {
      final command = item.details['command']?.toString().trim();
      if (command != null && command.isNotEmpty) {
        verificationCommands.add(command);
      }
    }

    final memoryContext = project == null
        ? null
        : _memoryService.selectContext(project: project, maxCharacters: 6000);
    final schedule = project == null
        ? null
        : _scheduler.refreshReadiness(project);
    final workspaceContext = project == null
        ? const ProjectWorkspaceContextSelection(
            orientation: '',
            nodes: [],
            edges: [],
            maxCharacters: 0,
            usedCharacters: 0,
            truncated: false,
          )
        : _workspaceContextService.selectContext(project: project);
    return ProjectEvidenceSnapshot(
      workspaceName: workspace.displayName,
      workspaceProfile: workspaceProfile,
      rootEntries: rootEntries,
      gitAvailable: changeSet.isRepository,
      changedFiles: changeSet.changedFiles,
      projectArtifactPaths: [
        for (final artifact in project?.artifacts ?? const <TaskArtifact>[])
          artifact.path,
      ].take(_maxRecentItems).toList(),
      taskArtifactIds: taskSummaries
          .take(_maxRecentItems)
          .map((item) => item.id)
          .toList(),
      recentTaskResults: [
        for (final task
            in (project?.tasks ?? const <ProjectTaskNode>[])
                .where(
                  (task) =>
                      task.status == TaskStatus.completed ||
                      task.status == TaskStatus.failed,
                )
                .toList()
                .reversed
                .take(_maxRecentItems))
          '${task.status.wire}: ${task.title}',
      ],
      recentGateFailures: [
        for (final incident
            in (project?.recoveryIncidents ?? const []).reversed.take(
              _maxRecentItems,
            ))
          '${incident.failedGateId}: ${incident.failureSummary}',
      ],
      criterionSummaries: [
        for (final criterion in project?.criteria ?? const <ProjectCriterion>[])
          '${criterion.id} [${criterion.status.name}]: ${criterion.statement}',
      ],
      milestoneSummaries: [
        for (final milestone
            in project?.milestones ?? const <ProjectMilestone>[])
          '${milestone.id} [${milestone.status.name}]: ${milestone.objective}',
      ],
      activeMemory: [
        for (final item
            in memoryContext?.items ?? const <ProjectMemoryContextItem>[])
          if (item.memoryEntryId != null) item.content,
      ],
      unresolvedQuestions: [
        for (final question
            in project?.openQuestions ?? const <PendingProjectQuestion>[])
          '${question.id}: ${question.question}',
      ],
      readyTasks: [
        for (final task in project?.tasks ?? const <ProjectTaskNode>[])
          if (task.status == TaskStatus.queued &&
              schedule?.readinessFor(task.id) == TaskReadiness.ready)
            '${task.id}: ${task.title}',
      ],
      blockedTasks: [
        for (final task in project?.tasks ?? const <ProjectTaskNode>[])
          if (task.status == TaskStatus.queued &&
              schedule?.readinessFor(task.id) != TaskReadiness.ready)
            '${task.id}: ${schedule?.reasonsFor(task.id).join('; ')}',
      ],
      recentlyCompletedTasks: [
        for (final task
            in (project?.tasks ?? const <ProjectTaskNode>[])
                .where((task) => task.status == TaskStatus.completed)
                .toList()
                .reversed
                .take(_maxRecentItems))
          '${task.id}: ${task.title}',
      ],
      verificationCommands: verificationCommands.toList()..sort(),
      workspaceGraph: project?.workspaceGraph ?? ProjectWorkspaceGraph.empty(),
      workspaceContext: workspaceContext,
      collectedAt: DateTime.now(),
    );
  }
}
