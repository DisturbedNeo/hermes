part of 'task_panel.dart';

class _ProjectBody extends StatelessWidget {
  final ChatController chat;
  final ProjectPanelReadModel project;

  const _ProjectBody({required this.chat, required this.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTask = chat.activeTask?.projectId == project.id
        ? chat.activeTask
        : null;
    final totalProjectTasks = project.tasks.length;
    final completedProjectTasks = project.tasks
        .where((task) => task.status == TaskStatus.completed)
        .length;
    final iterationLabel = project.maxIterations == 0
        ? '${project.iterationCount} iterations'
        : '${project.iterationCount}/${project.maxIterations} iterations';
    final iterationAccessibleLabel = project.maxIterations == 0
        ? 'Project has completed ${project.iterationCount} iterations with no total limit'
        : 'Project iteration ${project.iterationCount} of ${project.maxIterations}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AccessibleWidget(
              label: 'Project status: ${project.status.wire}',
              child: _StatusChip(label: project.status.wire),
            ),
            AccessibleWidget(
              label:
                  '$completedProjectTasks of $totalProjectTasks tasks completed',
              child: _StatusChip(
                label: '$completedProjectTasks/$totalProjectTasks tasks',
              ),
            ),
            AccessibleWidget(
              label: iterationAccessibleLabel,
              child: _StatusChip(label: iterationLabel),
            ),
            AccessibleWidget(
              label: 'Project ID: .agent/projects/${project.id}',
              child: _StatusChip(label: '.agent/projects/${project.id}'),
            ),
          ],
        ),
        if (chat.taskStatusMessage != null) ...[
          const SizedBox(height: 8),
          Text(chat.taskStatusMessage!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 10),
        _ProjectActions(chat: chat, project: project),
        if (project.openQuestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ProjectQuestionCard(chat: chat, project: project),
        ],
        if (project.blocker != null) ...[
          const SizedBox(height: 10),
          _ProjectBlockerCard(project: project),
        ],
        const SizedBox(height: 12),
        ProjectOutcomeSection(project: project),
        const SizedBox(height: 10),
        ProjectWorkspaceContextSection(project: project),
        const SizedBox(height: 10),
        ProjectRevisionSection(project: project, chat: chat),
        const SizedBox(height: 10),
        ProjectRoadmapSection(project: project),
        if (activeTask != null) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'TaskPanelReadModel Executor',
            child: _CurrentProjectTask(chat: chat, task: activeTask),
          ),
        ],
        const SizedBox(height: 10),
        ProjectEvidenceSection(project: project, chat: chat),
        if (project.originalGoal != project.refinedGoal) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Original Goal',
            child: Text(project.originalGoal, style: theme.textTheme.bodySmall),
          ),
        ],
        if (project.constraints.isNotEmpty) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Constraints',
            child: _StringList(items: project.constraints),
          ),
        ],
        if (project.completionSummary.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Completion',
            child: Text(
              project.completionSummary,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
        const SizedBox(height: 10),
        _Section(
          title: 'Completed Tasks',
          child: _ProjectTaskBoardList(
            tasks: project.tasks
                .where((task) => task.status == TaskStatus.completed)
                .toList()
                .reversed
                .toList(),
            empty: 'No completed project tasks yet.',
          ),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Failed or Rejected Tasks',
          child: _ProjectTaskBoardList(
            tasks: project.tasks
                .where(
                  (task) =>
                      task.status == TaskStatus.failed ||
                      task.status == TaskStatus.rejected,
                )
                .toList()
                .reversed
                .toList(),
            empty: 'No failed project tasks.',
          ),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Open Questions',
          child: _ProjectQuestionList(project: project),
        ),
        if (project.artifacts.isNotEmpty) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Project Artifacts',
            child: _ProjectArtifactBoardList(project: project),
          ),
        ],
        if (project.memory.where((entry) => entry.active).isNotEmpty) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Known Facts',
            child: _StringList(
              items: project.memory
                  .where((entry) => entry.active)
                  .map((entry) => entry.content)
                  .take(12)
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _Section(
          title: 'Recent Decisions',
          child: _ProjectDecisionList(project: project),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ProjectActions extends StatelessWidget {
  final ChatController chat;
  final ProjectPanelReadModel project;

  const _ProjectActions({required this.chat, required this.project});

  @override
  Widget build(BuildContext context) {
    final hasActiveTask = project.activeTaskId != null;
    final canRun =
        !chat.taskBusy &&
        !project.isTerminal &&
        project.pendingPlanApproval == null;
    final canReplan =
        !chat.taskBusy &&
        !project.isTerminal &&
        !hasActiveTask &&
        project.pendingPlanApproval == null;
    final exhaustedRecovery = project.recoveryIncidents
        .where(
          (incident) =>
              incident.status == ProjectRecoveryIncidentStatus.exhausted,
        )
        .firstOrNull;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (chat.taskBusy)
          AccessibleWidget(
            label: chat.taskCancellationRequested
                ? 'Cancelling project...'
                : 'Cancel project run',
            isButton: true,
            enabled: !chat.taskCancellationRequested,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.stop),
              label: Text(
                chat.taskCancellationRequested ? 'Cancelling...' : 'Cancel Run',
              ),
              onPressed: chat.taskCancellationRequested
                  ? null
                  : () => unawaited(chat.cancelTaskRun()),
            ),
          ),
        AccessibleWidget(
          label: 'Run next ready project task',
          isButton: true,
          enabled: canRun,
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run Next Ready TaskPanelReadModel'),
            onPressed: canRun
                ? () => unawaited(chat.runNextProjectTask())
                : null,
          ),
        ),
        AccessibleWidget(
          label: 'Run project',
          isButton: true,
          enabled: canRun,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.fast_forward),
            label: const Text('Continue Project'),
            onPressed: canRun ? () => unawaited(chat.runProject()) : null,
          ),
        ),
        AccessibleWidget(
          label: 'Replan project',
          isButton: true,
          enabled: canReplan,
          child: OutlinedButton.icon(
            key: const ValueKey('replan-project'),
            icon: const Icon(Icons.route_outlined),
            label: const Text('Replan'),
            onPressed: canReplan
                ? () async {
                    final reason = await ProjectReplanDialog.show(context);
                    if (reason != null && context.mounted) {
                      unawaited(chat.replanProject(reason));
                    }
                  }
                : null,
          ),
        ),
        AccessibleWidget(
          label: 'Pause project',
          isButton: true,
          enabled: !chat.taskBusy && !project.isTerminal,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.pause_circle_outline),
            label: const Text('Pause'),
            onPressed: !chat.taskBusy && !project.isTerminal
                ? () => unawaited(chat.pauseProject())
                : null,
          ),
        ),
        if (exhaustedRecovery != null)
          AccessibleWidget(
            label: 'Retry project recovery',
            isButton: true,
            enabled: !chat.taskBusy,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.replay),
              label: const Text('Retry Recovery'),
              onPressed: chat.taskBusy
                  ? null
                  : () => unawaited(
                      chat.retryProjectRecovery(exhaustedRecovery.id),
                    ),
            ),
          ),
        AccessibleWidget(
          label: 'Edit project JSON',
          isButton: true,
          enabled: !chat.taskBusy,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.data_object),
            label: const Text('Edit Project JSON'),
            onPressed: chat.taskBusy
                ? null
                : () async {
                    final initial = chat.activeProjectJson;
                    if (initial == null) return;
                    final saved = await EditProjectDialog.show(
                      context,
                      initialJson: initial,
                      onSave: (json) => chat.updateProjectPlan(
                        ProjectCommandProtocolAdapter.decode(json),
                      ),
                    );
                    if (saved && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Project saved')),
                      );
                    }
                  },
          ),
        ),
        AccessibleWidget(
          label: 'Stop project',
          isButton: true,
          enabled: !chat.taskBusy && !project.isTerminal,
          child: TextButton.icon(
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop'),
            onPressed: !chat.taskBusy && !project.isTerminal
                ? () => unawaited(chat.stopProject())
                : null,
          ),
        ),
      ],
    );
  }
}

class _ProjectQuestionCard extends StatefulWidget {
  final ChatController chat;
  final ProjectPanelReadModel project;

  const _ProjectQuestionCard({required this.chat, required this.project});

  @override
  State<_ProjectQuestionCard> createState() => _ProjectQuestionCardState();
}

class _ProjectQuestionCardState extends State<_ProjectQuestionCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.project.openQuestions.first;
    return _Panel(
      icon: Icons.help_outline,
      title: 'Project Input Required',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(question.question),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Answer',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              icon: const Icon(Icons.send_outlined),
              label: const Text('Submit Answer'),
              onPressed: widget.chat.taskBusy
                  ? null
                  : () => unawaited(
                      widget.chat.answerProjectQuestion(_controller.text),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectBlockerCard extends StatelessWidget {
  final ProjectPanelReadModel project;

  const _ProjectBlockerCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final blocker = project.blocker!;
    return _Panel(
      icon: Icons.report_problem_outlined,
      title: 'Project Blocked',
      child: Text(
        '${blocker.type.wire}: ${blocker.message}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _CurrentProjectTask extends StatelessWidget {
  final ChatController chat;
  final TaskPanelReadModel task;

  const _CurrentProjectTask({required this.chat, required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = chat.activeProject;
    final projectTask =
        project?.tasks.where((item) => item.id == task.id).firstOrNull ??
        (project?.activeTaskId == null
            ? null
            : project?.taskById(project.activeTaskId!));
    final criterionIds = projectTask?.criterionIds ?? const <String>[];
    final criterionStatements = [
      for (final criterionId in criterionIds)
        project?.criterionStatement(criterionId) ?? criterionId,
    ];
    final evidenceExpectations = [
      for (final expectation
          in projectTask?.expectedEvidence ?? const <TaskEvidenceExpectation>[])
        '${expectation.type.name}: ${expectation.description}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              task.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            _StatusChip(label: task.status.wire),
          ],
        ),
        if (criterionStatements.isNotEmpty ||
            evidenceExpectations.isNotEmpty) ...[
          const SizedBox(height: 8),
          _StringList(title: 'Project criteria', items: criterionStatements),
          if (evidenceExpectations.isNotEmpty) ...[
            const SizedBox(height: 6),
            _StringList(
              title: 'Expected evidence',
              items: evidenceExpectations,
            ),
          ],
        ],
        const SizedBox(height: 8),
        _Actions(chat: chat, task: task, next: task.nextRunnableStep),
        if (task.pendingApproval != null) ...[
          const SizedBox(height: 10),
          _ApprovalCard(chat: chat, task: task),
        ],
        if (task.pendingQuestion != null) ...[
          const SizedBox(height: 10),
          _QuestionCard(chat: chat, task: task),
        ],
        const SizedBox(height: 10),
        _StepList(task: task),
      ],
    );
  }
}

class _ProjectTaskBoardList extends StatelessWidget {
  final List<ProjectTaskNode> tasks;
  final String empty;

  const _ProjectTaskBoardList({required this.tasks, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Text(empty, style: Theme.of(context).textTheme.bodySmall);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final task in tasks)
          AccessibleWidget(
            label: 'Project task: ${task.title}, status ${task.status.wire}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_projectTaskStatusIcon(task.status)),
                  title: Text(task.title),
                  subtitle: Text(
                    [
                      task.status.wire,
                      task.objective,
                      if (task.doneCriteria.isNotEmpty)
                        'Done: ${task.doneCriteria.join('; ')}',
                      if (task.outOfScope.isNotEmpty)
                        'Out: ${task.outOfScope.join('; ')}',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                ),
                if (task.failureKey != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 40, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Failure: ${task.failureKey}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (task.failureKey!.contains('|'))
                          Text(
                            task.failureKey!.split('|').last,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (task.unresolvedErrorCount > 0)
                          Text(
                            'unresolved: ${task.unresolvedErrorCount}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProjectQuestionList extends StatelessWidget {
  final ProjectPanelReadModel project;

  const _ProjectQuestionList({required this.project});

  @override
  Widget build(BuildContext context) {
    if (project.openQuestions.isEmpty) {
      return Text(
        'No open questions.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final question in project.openQuestions)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline),
            title: Text(question.question),
            subtitle: Text(question.id),
          ),
      ],
    );
  }
}

class _ProjectArtifactBoardList extends StatelessWidget {
  final ProjectPanelReadModel project;

  const _ProjectArtifactBoardList({required this.project});

  @override
  Widget build(BuildContext context) {
    if (project.artifacts.isEmpty) {
      return Text(
        'No project artifacts yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final artifact in project.artifacts)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(artifact.path),
            subtitle: Text(
              [
                artifact.kind,
                if (artifact.description?.trim().isNotEmpty == true)
                  artifact.description!,
                if (artifact.taskId != null) artifact.taskId!,
              ].join(' - '),
            ),
          ),
      ],
    );
  }
}

class _StringList extends StatelessWidget {
  final String? title;
  final List<String> items;

  const _StringList({required this.items, this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = items.isEmpty
        ? 'None.'
        : items.map((item) => '- $item').join('\n');
    if (title == null) return Text(text, style: theme.textTheme.bodySmall);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title!,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ProjectDecisionList extends StatelessWidget {
  final ProjectPanelReadModel project;

  const _ProjectDecisionList({required this.project});

  @override
  Widget build(BuildContext context) {
    final decisions = project.decisions.reversed.take(8).toList();
    if (decisions.isEmpty) {
      return Text(
        'No decisions yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final decision in decisions)
          AccessibleWidget(
            label:
                'Project decision: ${decision.decision.wire}${decision.taskTitle == null ? '' : ', ${decision.taskTitle}'}',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_projectDecisionIcon(decision.decision)),
              title: Text(decision.decision.wire),
              subtitle: Text(
                [
                  if (decision.taskTitle != null) decision.taskTitle!,
                  if (decision.summary.trim().isNotEmpty) decision.summary,
                ].join(' - '),
              ),
            ),
          ),
      ],
    );
  }
}
