import 'dart:async';

import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/services/project_system/orchestration_contracts.dart';
import 'package:hermes/core/services/project_system/project_run_loop.dart';
import 'package:hermes/core/services/project_system/project_state_store.dart';
import 'package:hermes/core/services/workspace_persistence_coordinator.dart';

abstract interface class ProjectExecutionPort {
  Future<ProjectCommandResult> execute(ProjectExecutionRequest request);
}

abstract interface class ProjectRecoveryPort {
  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request);
}

class CallbackProjectExecutionPort implements ProjectExecutionPort {
  const CallbackProjectExecutionPort(this._callback);

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
    required ProjectStateStore stateStore,
    required WorkspacePersistenceCoordinator persistenceCoordinator,
    ProjectRunLoop runLoop = const ProjectRunLoop(),
  }) : _stateStore = stateStore,
       _persistenceCoordinator = persistenceCoordinator,
       _runLoop = runLoop;

  final ProjectStateStore _stateStore;
  final WorkspacePersistenceCoordinator _persistenceCoordinator;
  final ProjectRunLoop _runLoop;
  final Set<String> _busyProjects = <String>{};
  final Object _zoneKey = Object();

  Future<ProjectCommandResult> execute(
    ProjectExecutionRequest request, {
    required ProjectExecutionPort port,
  }) => _withProjectCommand(request.workspace, request.snapshot, () async {
    final readOnly = await _ensureCurrentSnapshot(request);
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
    required ProjectExecutionPort port,
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
      ProjectExecutionRequest(
        client: _NoopChatClient(),
        workspace: request.workspace,
        snapshot: request.snapshot,
        baseSystemPrompt: '',
        maxNewTasks: 0,
      ),
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
    ProjectExecutionRequest request,
  ) async {
    final checked = await _stateStore.checkRevisions(
      request.workspace,
      request.snapshot,
    );
    final diagnostics = checked.diagnostics;
    if (diagnostics.isReadOnly) return diagnostics;
    if (checked.projectRevision == null) return null;
    final currentProjectRevision = checked.projectRevision!.revision;
    if (currentProjectRevision != request.snapshot.persistenceRevision) {
      throw StaleSnapshotException(
        path: '.agent/projects/${request.snapshot.id}/project.json',
        expectedRevision: request.snapshot.persistenceRevision,
        actualRevision: currentProjectRevision,
      );
    }
    for (final task in request.snapshot.tasks) {
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
    ProjectDocument project,
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

class _NoopChatClient implements ChatClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
