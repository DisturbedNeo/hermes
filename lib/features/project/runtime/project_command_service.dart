import 'dart:async';

import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/shared_kernel/workspace.dart';
import 'package:hermes/shared_kernel/persistence_contracts.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/project/runtime/project_run_loop.dart';
import 'package:hermes/features/project/runtime/project_aggregate_hydrator.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';

abstract interface class ProjectCommandExecutionPort {
  Future<ProjectCommandResult> execute(ProjectExecutionRequest request);
}

abstract interface class ProjectRecoveryPort {
  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request);
}

class CallbackProjectCommandExecutionPort
    implements ProjectCommandExecutionPort {
  const CallbackProjectCommandExecutionPort(this._callback);

  final ProjectExecutionDelegate _callback;

  @override
  Future<ProjectCommandResult> execute(ProjectExecutionRequest request) =>
      _callback(request);
}

class CallbackProjectRecoveryPort implements ProjectRecoveryPort {
  const CallbackProjectRecoveryPort(this._callback);

  final ProjectRecoveryDelegate _callback;

  @override
  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request) =>
      _callback(request);
}

/// Application command boundary for project execution and recovery.
///
/// This service centralises optimistic revision checks, per-project busy
/// protection, automatic continuation, and transition shaping. It has no
/// model or task execution knowledge and can therefore be tested with ports.
class ProjectCommandService {
  ProjectCommandService({
    required ProjectAggregateHydrator stateStore,
    required PersistencePort persistenceCoordinator,
    ProjectRunLoop runLoop = const ProjectRunLoop(),
  }) : _stateStore = stateStore,
       _persistenceCoordinator = persistenceCoordinator,
       _runLoop = runLoop;

  final ProjectAggregateHydrator _stateStore;
  final PersistencePort _persistenceCoordinator;
  final ProjectRunLoop _runLoop;
  final Set<String> _busyProjects = <String>{};
  final Object _zoneKey = Object();

  Future<ProjectCommandResult> execute(
    ProjectExecutionRequest request, {
    required ProjectCommandExecutionPort port,
  }) => _withProjectCommand(request.workspace, request.snapshot, () async {
    final readOnly = await _ensureCurrentSnapshot(
      request.workspace,
      request.snapshot,
    );
    if (readOnly != null) {
      return ProjectCommandResult(
        project: request.snapshot,
        stopReason: ProjectCommandStopReason.readOnly,
        persistenceDiagnostics: readOnly,
      );
    }
    final result = await port.execute(request);
    return ProjectCommandResult.withTransition(
      result: result,
      before: request.snapshot,
      trigger: 'execute',
    );
  });

  Future<ProjectCommandResult> executeUntilStop(
    ProjectExecutionRequest request, {
    required bool boundedRun,
    required ProjectCommandExecutionPort port,
  }) => _withProjectCommand(request.workspace, request.snapshot, () {
    return _runLoop.run(
      request,
      boundedRun: boundedRun,
      iteration: (current) => execute(current, port: port),
    );
  });

  Future<ProjectCommandResult> recover(
    ProjectRecoveryRequest request, {
    required ProjectRecoveryPort port,
  }) => _withProjectCommand(request.workspace, request.snapshot, () async {
    final readOnly = await _ensureCurrentSnapshot(
      request.workspace,
      request.snapshot,
    );
    if (readOnly != null) {
      return ProjectCommandResult(
        project: request.snapshot,
        stopReason: ProjectCommandStopReason.readOnly,
        persistenceDiagnostics: readOnly,
      );
    }
    final result = await port.recover(request);
    return ProjectCommandResult.withTransition(
      result: result,
      before: request.snapshot,
      trigger: 'recover',
    );
  });

  Future<ProjectPersistenceDiagnostics?> _ensureCurrentSnapshot(
    WorkspaceAttachment workspace,
    ProjectAggregate snapshot,
  ) async {
    final checked = await _stateStore.checkRevisions(workspace, snapshot);
    final diagnostics = checked.diagnostics;
    if (diagnostics.isReadOnly) return diagnostics;
    if (checked.projectRevision == null) return null;
    final currentProjectRevision = checked.projectRevision!.revision;
    if (currentProjectRevision != snapshot.persistenceRevision) {
      throw StaleSnapshotException(
        path: '.agent/projects/${snapshot.id}/project.json',
        expectedRevision: snapshot.persistenceRevision,
        actualRevision: currentProjectRevision,
      );
    }
    for (final task in snapshot.tasks) {
      final revision = checked.taskRevisions[task.id]?.revision;
      if (revision == null) {
        throw StaleSnapshotException(
          path: '.agent/tasks/${task.id}/task.json',
          expectedRevision: 0,
          actualRevision: -1,
        );
      }
    }
    return null;
  }

  Future<T> _withProjectCommand<T>(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
    Future<T> Function() operation,
  ) async {
    if (Zone.current[_zoneKey] == true) return operation();
    final key =
        '${_persistenceCoordinator.canonicalWorkspacePath(workspace.rootPath)}'
        ':${project.id}';
    if (!_busyProjects.add(key)) {
      throw ProjectBusyException(
        workspaceRoot: workspace.rootPath,
        projectId: project.id,
      );
    }
    return runZoned(() async {
      try {
        return await operation();
      } finally {
        _busyProjects.remove(key);
      }
    }, zoneValues: {_zoneKey: true});
  }
}
