part of 'project_execution_state_machine.dart';

/// Owns deterministic project-shell creation at the project application
/// boundary. Planning is deliberately performed by the normal execution
/// state machine after this shell has been persisted.
class ProjectPlanningUseCase {
  ProjectPlanningUseCase(ProjectPlanningCapabilities context)
    : _context = context;

  final ProjectPlanningCapabilities _context;

  Future<ProjectAggregate> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelConversationPort? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    cancellationToken?.throwIfCancelled();
    final now = DateTime.now();
    final project = ProjectAggregate(
      id: _context.newProjectId(userPrompt),
      title: _context.titleFromPrompt(userPrompt),
      originalGoal: userPrompt,
      refinedGoal: userPrompt,
      constraints: const ['Stay within the attached workspace.'],
      criteria: const [],
      tasks: const [],
      artifacts: const [],
      memory: const [],
      milestones: const [],
      planHistory: const [],
      openQuestions: const [],
      status: ProjectStatus.paused,
      iterationCount: 0,
      maxIterations: _context.normaliseOptionalLimit(
        maxIterations,
        fallback: ProjectAggregate.defaultMaxIterations,
      ),
      maxFailedTasks: ProjectAggregate.defaultMaxFailedTasks,
      activeTaskId: null,
      chatSessionId: chatSessionId,
      completionSummary: '',
      blocker: null,
      decisions: const [],
      diagnostics: const ProjectDiagnostics(),
      createdAt: now,
      updatedAt: now,
    );
    return _context.persistProject(
      workspace.rootPath,
      project,
      checkpoint: ProjectPersistenceCheckpoint.initialization,
    );
  }
}
