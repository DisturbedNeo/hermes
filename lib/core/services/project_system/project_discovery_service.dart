import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/project_system/project_memory_service.dart';
import 'package:hermes/core/services/project_system/project_planning_gateway.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:path/path.dart' as path;

/// Collects bounded, read-only context for initialization and replanning.
class ProjectDiscoveryService {
  const ProjectDiscoveryService({
    required TaskService taskService,
    ProjectMemoryService memoryService = const ProjectMemoryService(),
  }) : _taskService = taskService,
       _memoryService = memoryService;

  static const int _maxRootEntries = 80;
  static const int _maxRecentItems = 12;

  final TaskService _taskService;
  final ProjectMemoryService _memoryService;

  Future<ProjectEvidenceSnapshot> collect({
    required WorkspaceAttachment workspace,
    ProjectState? project,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final rootEntries = <String>[];
    final root = Directory(workspace.rootPath);
    try {
      if (await root.exists()) {
        await for (final entity in root.list(followLinks: false)) {
          cancellationToken?.throwIfCancelled();
          rootEntries.add(path.basename(entity.path));
          if (rootEntries.length >= _maxRootEntries) break;
        }
      }
    } on FileSystemException {
      // A partial snapshot remains useful when a directory is unreadable.
    }
    rootEntries.sort();
    var gitAvailable = false;
    var changedFiles = const <String>[];
    try {
      gitAvailable =
          await FileSystemEntity.type(
            path.join(workspace.rootPath, '.git'),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound;
      if (gitAvailable) {
        changedFiles = await _gitChangedFiles(
          workspace.rootPath,
          cancellationToken,
        );
      }
    } on FileSystemException {
      // Git discovery is optional.
    }

    final taskSummaries = [
      ...await _taskService.listTasks(
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
    return ProjectEvidenceSnapshot(
      workspaceName: workspace.displayName,
      rootEntries: rootEntries,
      gitAvailable: gitAvailable,
      changedFiles: changedFiles,
      projectArtifactPaths: [
        for (final artifact in project?.artifacts ?? const <ProjectArtifact>[])
          artifact.path,
      ].take(_maxRecentItems).toList(),
      taskArtifactIds: taskSummaries
          .take(_maxRecentItems)
          .map((item) => item.id)
          .toList(),
      recentTaskResults: [
        for (final task in [
          ...?project?.completedTasks.reversed,
          ...?project?.failedTasks.reversed,
        ].take(_maxRecentItems))
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
        for (final task in project?.backlog ?? const <ProjectTask>[])
          if (task.status == ProjectTaskStatus.queued &&
              task.readiness == ProjectTaskReadiness.ready)
            '${task.id}: ${task.title}',
      ],
      blockedTasks: [
        for (final task in project?.backlog ?? const <ProjectTask>[])
          if (task.readiness != ProjectTaskReadiness.ready)
            '${task.id}: ${task.readinessReasons.join('; ')}',
      ],
      recentlyCompletedTasks: [
        for (final task
            in (project?.completedTasks ?? const <ProjectTask>[]).reversed.take(
              _maxRecentItems,
            ))
          '${task.id}: ${task.title}',
      ],
      verificationCommands: verificationCommands.toList()..sort(),
      collectedAt: DateTime.now(),
    );
  }

  Future<List<String>> _gitChangedFiles(
    String workspaceRoot,
    CancellationToken? cancellationToken,
  ) async {
    Process? process;
    try {
      cancellationToken?.throwIfCancelled();
      process = await Process.start('git', [
        '-C',
        workspaceRoot,
        'status',
        '--porcelain=v1',
        '--untracked-files=no',
      ]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errorDrain = process.stderr.drain<void>();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill();
          return -1;
        },
      );
      final text = await output;
      await errorDrain;
      cancellationToken?.throwIfCancelled();
      if (exitCode != 0) return const [];
      return text
          .split('\n')
          .map((line) => line.length > 3 ? line.substring(3).trim() : '')
          .where((line) => line.isNotEmpty)
          .take(_maxRootEntries)
          .toList();
    } on OperationCancelledException {
      process?.kill();
      rethrow;
    } on Object {
      process?.kill();
      return const [];
    }
  }
}
