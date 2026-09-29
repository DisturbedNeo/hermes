// ignore_for_file: dead_code_on_catch_subtype, unused_element, unused_field
part of 'task_runtime_engine.dart';

extension _TaskStorageOperations on _TaskApplicationContext {
  Future<Task> _persistTask(String workspaceRoot, Task task) async {
    final persisted = await _persistenceStore.save(workspaceRoot, task);
    return persisted.value;
  }

  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) {
    return _persistenceStore.list(
      workspace.rootPath,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
  }

  Future<Task?> loadLatestTask(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) async {
    final snapshot = await _persistenceStore.loadLatest(
      workspace.rootPath,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
    return snapshot?.value;
  }

  Future<Task?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) async {
    final snapshot = await _persistenceStore.load(
      workspace.rootPath,
      taskId,
      chatSessionId: chatSessionId,
      projectId: projectId,
      includeHistory: includeHistory,
    );
    return snapshot?.value;
  }

  Future<int> deleteTasksForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) {
    if (workspace.missing) return Future.value(0);
    return _persistenceStore.deleteForChatSession(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteOrphanedChatTasks(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) {
    if (workspace.missing) return Future.value(0);
    return _persistenceStore.deleteOrphaned(
      workspace.rootPath,
      retainedChatSessionIds: retainedChatSessionIds,
    );
  }

  Future<Task> updateTaskChatSessionId({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String chatSessionId,
  }) async {
    if (snapshot.chatSessionId == chatSessionId) return snapshot;
    final updated = snapshot.copyWith(
      chatSessionId: chatSessionId,
      updatedAt: DateTime.now(),
    );
    return _persistTask(workspace.rootPath, updated);
  }

  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    bool persist = true,
  }) async {
    if (snapshot.status != TaskStatus.running) return snapshot;
    final now = DateTime.now();
    final recovered = _recoveryService.recover(snapshot, now: now);
    return persist ? _persistTask(workspace.rootPath, recovered) : recovered;
  }

  String encodeTask(Task task) =>
      '${_encoder.convert(ModelJson.encode(task))}\n';

  Future<String> readArtifact({
    required WorkspaceAttachment workspace,
    required String artifactPath,
    CancellationToken? cancellationToken,
  }) async {
    try {
      return await _sandbox.readFilePreview(
        workspace.rootPath,
        artifactPath,
        maxChars: 240000,
        cancellationToken: cancellationToken,
      );
    } on WorkspaceSandboxException catch (error) {
      if (error.message.contains('Path not found')) {
        throw StateError('Artifact not found: $artifactPath');
      }
      rethrow;
    }
  }

  Future<RefinedTaskBrief> refineTaskBrief({
    required ModelProvider client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final metadata = workspace == null || workspace.missing
        ? const WorkspaceMetadata()
        : await _collectWorkspaceMetadata(workspace);

    try {
      final json = await _modelCompletion.completeJson(
        client: client,
        system: _refinerSystemInstruction,
        expectedShape:
            '{"title":"...","goal":"...","constraints":[],"successCriteria":[],"assumptions":[],"questions":[]}',
        label: 'Prompt Refiner',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user:
            '''
Refine this request into a concise brief for a long-horizon task planner.

Return only JSON:
{
  "title": "...",
  "goal": "...",
  "constraints": ["..."],
  "successCriteria": ["..."],
  "assumptions": ["..."],
  "questions": ["..."]
}

Selected mode: ${selectedMode.wire}
Workspace metadata:
${_encoder.convert(ModelJson.encode(metadata))}

Request:
$userPrompt
''',
      );
      return _normaliseBrief(
        ModelJson.decode<RefinedTaskBrief>(json),
        userPrompt,
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return _fallbackBrief(userPrompt);
    }
  }
}
