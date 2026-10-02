part of 'task_execution_coordinator.dart';

/// Owns task-document queries, lifecycle persistence, recovery persistence,
/// and artifact reads exposed by the task application boundary.
class TaskPersistenceUseCase {
  TaskPersistenceUseCase(this._context);

  final TaskUseCaseContext _context;

  TaskPersistenceStore get _persistenceStore => _context.persistenceStore;
  TaskRecoveryService get _recoveryService => _context.recoveryService;
  WorkspaceReadPort get _sandbox => _context.sandbox;
  TaskModelCompletionPort get _modelCompletion => _context.modelCompletion;
  JsonEncoder get _encoder => _context.encoder;

  Future<Task> persist(String workspaceRoot, Task task) async {
    final persisted = await _persistenceStore.save(workspaceRoot, task);
    return persisted.value;
  }

  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) => _persistenceStore.list(
    workspace.rootPath,
    chatSessionId: chatSessionId,
    projectId: projectId,
  );

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
    return persist(
      workspace.rootPath,
      snapshot.copyWith(
        chatSessionId: chatSessionId,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    bool persist = true,
  }) async {
    if (snapshot.status != TaskStatus.running) return snapshot;
    final recovered = _recoveryService.recover(snapshot, now: DateTime.now());
    return persist ? this.persist(workspace.rootPath, recovered) : recovered;
  }

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
    required ModelGenerationPort client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final metadata = workspace == null || workspace.missing
        ? const WorkspaceMetadata()
        : await _context.collectWorkspaceMetadata(workspace);

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
      return _context.normaliseBrief(
        ModelJson.decode<RefinedTaskBrief>(json.toWire()),
        userPrompt,
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return _context.fallbackBrief(userPrompt);
    }
  }
}
