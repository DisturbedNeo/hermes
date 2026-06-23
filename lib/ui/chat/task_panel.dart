import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/a11y.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/ui/common/state_display.dart';

class TaskPanel extends StatelessWidget {
  final ChatService chat;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  const TaskPanel({
    super.key,
    required this.chat,
    required this.expanded,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final project = chat.activeProject;
    final task = chat.activeTask;
    if (!expanded) {
      return _CollapsedTaskPanel(
        chat: chat,
        project: project,
        task: task,
        onToggleExpanded: onToggleExpanded,
      );
    }

    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              chat: chat,
              project: project,
              task: task,
              onToggleExpanded: onToggleExpanded,
            ),
            const Divider(height: 1),
            if (project != null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: _ProjectBody(chat: chat, project: project),
                ),
              )
            else if (task != null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: _TaskBody(chat: chat, task: task),
                ),
              )
            else
              Expanded(child: _WorkList(chat: chat)),
          ],
        ),
      ),
    );
  }
}

class _CollapsedTaskPanel extends StatelessWidget {
  final ChatService chat;
  final ProjectDocument? project;
  final TaskDocument? task;
  final VoidCallback onToggleExpanded;

  const _CollapsedTaskPanel({
    required this.chat,
    required this.project,
    required this.task,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onToggleExpanded,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                project == null
                    ? Icons.account_tree_outlined
                    : Icons.rocket_launch_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  project?.title ?? task?.title ?? 'Workspace Work',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (chat.taskBusy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (project != null)
                AccessibleWidget(
                  label: 'Project status: ${project!.status.wire}',
                  child: _StatusChip(label: project!.status.wire),
                )
              else if (task != null)
                AccessibleWidget(
                  label: 'Task status: ${task!.status.wire}',
                  child: _StatusChip(label: task!.status.wire),
                ),
              IconButton(
                tooltip: 'Open task panel',
                icon: const Icon(Icons.expand_less),
                onPressed: onToggleExpanded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ChatService chat;
  final ProjectDocument? project;
  final TaskDocument? task;
  final VoidCallback onToggleExpanded;

  const _Header({
    required this.chat,
    required this.project,
    required this.task,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Icon(
            project == null
                ? Icons.account_tree_outlined
                : Icons.rocket_launch_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              project?.title ?? task?.title ?? 'Workspace Work',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (chat.taskBusy) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          AccessibleWidget(
            label: 'Reload tasks',
            isButton: true,
            enabled: !chat.taskBusy,
            child: IconButton(
              tooltip: 'Reload tasks',
              icon: const Icon(Icons.refresh),
              onPressed: chat.taskBusy
                  ? null
                  : () => unawaited(chat.reloadTasks()),
            ),
          ),
          AccessibleWidget(
            label: 'Collapse task panel',
            isButton: true,
            child: IconButton(
              tooltip: 'Collapse task panel',
              icon: const Icon(Icons.expand_more),
              onPressed: onToggleExpanded,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectBody extends StatelessWidget {
  final ChatService chat;
  final ProjectDocument project;

  const _ProjectBody({required this.chat, required this.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTask = chat.activeTask?.projectId == project.id
        ? chat.activeTask
        : null;
    final totalProjectTasks =
        project.backlog.length +
        project.completedTasks.length +
        project.failedTasks.length +
        (project.currentTask == null ? 0 : 1);

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
              label: 'Project phase: ${project.phase.wire}',
              child: _StatusChip(label: project.phase.wire),
            ),
            AccessibleWidget(
              label:
                  '${project.completedTasks.length} of $totalProjectTasks tasks completed',
              child: _StatusChip(
                label:
                    '${project.completedTasks.length}/$totalProjectTasks tasks',
              ),
            ),
            AccessibleWidget(
              label:
                  'Project iteration ${project.iterationCount} of ${project.maxIterations}',
              child: _StatusChip(
                label:
                    '${project.iterationCount}/${project.maxIterations} iterations',
              ),
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
        if (project.pendingQuestion != null) ...[
          const SizedBox(height: 10),
          _ProjectQuestionCard(chat: chat, project: project),
        ],
        if (project.blocker != null) ...[
          const SizedBox(height: 10),
          _ProjectBlockerCard(project: project),
        ],
        const SizedBox(height: 12),
        _Section(
          title: 'Goal',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(project.refinedGoal, style: theme.textTheme.bodyMedium),
              if (project.originalGoal != project.refinedGoal) ...[
                const SizedBox(height: 6),
                Text(
                  'Original: ${project.originalGoal}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Success Criteria',
          child: _StringList(
            items: project.successCriteria,
            empty: 'No success criteria recorded.',
          ),
        ),
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
        if (project.currentTask != null) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Current Project Task',
            child: _ProjectTaskDetails(task: project.currentTask!),
          ),
        ],
        if (activeTask != null) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Task Executor',
            child: _CurrentProjectTask(chat: chat, task: activeTask),
          ),
        ],
        const SizedBox(height: 10),
        _Section(
          title: 'Backlog',
          child: _ProjectTaskBoardList(
            tasks: project.backlog,
            empty: 'No queued project tasks.',
          ),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Completed Tasks',
          child: _ProjectTaskBoardList(
            tasks: project.completedTasks.reversed.toList(),
            empty: 'No completed project tasks yet.',
          ),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Failed or Rejected Tasks',
          child: _ProjectTaskBoardList(
            tasks: project.failedTasks.reversed.toList(),
            empty: 'No failed project tasks.',
          ),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Open Questions',
          child: _ProjectQuestionList(project: project),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Artifacts',
          child: _ProjectArtifactBoardList(project: project),
        ),
        if (project.knownFacts.isNotEmpty) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Known Facts',
            child: _StringList(items: project.knownFacts.take(12).toList()),
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
  final ChatService chat;
  final ProjectDocument project;

  const _ProjectActions({required this.chat, required this.project});

  @override
  Widget build(BuildContext context) {
    final canRun = !chat.taskBusy && !project.isTerminal;
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
          label: 'Run next project task',
          isButton: true,
          enabled: canRun,
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run Next Task'),
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
        if (project.currentTask?.status == ProjectTaskStatus.proposed)
          AccessibleWidget(
            label: 'Approve next project task',
            isButton: true,
            enabled: !chat.taskBusy,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Approve Next Task'),
              onPressed: chat.taskBusy
                  ? null
                  : () => unawaited(chat.approveNextProjectTask()),
            ),
          ),
        AccessibleWidget(
          label: 'Edit project',
          isButton: true,
          enabled: !chat.taskBusy,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_note),
            label: const Text('Edit Project'),
            onPressed: chat.taskBusy
                ? null
                : () => unawaited(_editProject(context, chat)),
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

  Future<void> _editProject(BuildContext context, ChatService chat) async {
    final initial = chat.activeProjectJson;
    if (initial == null) return;
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Project'),
              content: SizedBox(
                width: 820,
                child: TextField(
                  controller: controller,
                  minLines: 16,
                  maxLines: 22,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            jsonDecode(controller.text);
                            await chat.updateProjectPlan(controller.text);
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (e) {
                            setState(() {
                              saving = false;
                              error = e.toString();
                            });
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project saved')));
    }
  }
}

class _ProjectQuestionCard extends StatefulWidget {
  final ChatService chat;
  final ProjectDocument project;

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
    final question = widget.project.pendingQuestion!;
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
  final ProjectDocument project;

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
  final ChatService chat;
  final TaskDocument task;

  const _CurrentProjectTask({required this.chat, required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

class _TaskBody extends StatelessWidget {
  final ChatService chat;
  final TaskDocument task;

  const _TaskBody({required this.chat, required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = task.nextRunnableStep;
    final completed = task.steps
        .where(
          (step) =>
              step.status == TaskStepStatus.completed ||
              step.status == TaskStepStatus.skipped,
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AccessibleWidget(
              label: 'Task status: ${task.status.wire}',
              child: _StatusChip(label: task.status.wire),
            ),
            AccessibleWidget(
              label: '$completed of ${task.steps.length} steps completed',
              child: _StatusChip(
                label: '$completed/${task.steps.length} steps',
              ),
            ),
            AccessibleWidget(
              label: 'Task ID: .agent/tasks/${task.id}',
              child: _StatusChip(label: '.agent/tasks/${task.id}'),
            ),
          ],
        ),
        if (chat.taskStatusMessage != null) ...[
          const SizedBox(height: 8),
          Text(chat.taskStatusMessage!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 10),
        _Actions(chat: chat, task: task, next: next),
        if (task.pendingApproval != null) ...[
          const SizedBox(height: 10),
          _ApprovalCard(chat: chat, task: task),
        ],
        if (task.pendingQuestion != null) ...[
          const SizedBox(height: 10),
          _QuestionCard(chat: chat, task: task),
        ],
        const SizedBox(height: 12),
        _Section(
          title: 'Goal',
          child: Text(task.goal, style: theme.textTheme.bodyMedium),
        ),
        if (task.memorySummary.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Memory',
            child: Text(task.memorySummary, style: theme.textTheme.bodySmall),
          ),
        ],
        const SizedBox(height: 10),
        _Section(
          title: 'Plan',
          child: _StepList(task: task),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Artifacts',
          child: _ArtifactList(chat: chat, task: task),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Recent Runs',
          child: _RunList(task: task),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final ChatService chat;
  final TaskDocument task;
  final TaskStep? next;

  const _Actions({required this.chat, required this.task, required this.next});

  @override
  Widget build(BuildContext context) {
    final canRun =
        !chat.taskBusy &&
        next != null &&
        task.status != TaskStatus.completed &&
        task.status != TaskStatus.cancelled;
    final canRetry =
        !chat.taskBusy &&
        (task.status == TaskStatus.blocked || task.status == TaskStatus.failed);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (chat.taskBusy)
          AccessibleWidget(
            label: chat.taskCancellationRequested
                ? 'Cancelling task...'
                : 'Cancel task run',
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
          label: 'Run next step',
          isButton: true,
          enabled: canRun,
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run Next'),
            onPressed: canRun ? () => unawaited(chat.runNextTaskPhase()) : null,
          ),
        ),
        AccessibleWidget(
          label: 'Run entire task',
          isButton: true,
          enabled: canRun,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.fast_forward),
            label: const Text('Run Task'),
            onPressed: canRun ? () => unawaited(chat.runTask()) : null,
          ),
        ),
        AccessibleWidget(
          label: 'Approve current phase',
          isButton: true,
          enabled: !chat.taskBusy && task.pendingApproval != null,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Approve Phase'),
            onPressed: !chat.taskBusy && task.pendingApproval != null
                ? () => unawaited(chat.approveTaskStep())
                : null,
          ),
        ),
        AccessibleWidget(
          label: 'Edit task plan',
          isButton: true,
          enabled: !chat.taskBusy,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_note),
            label: const Text('Edit Plan'),
            onPressed: chat.taskBusy
                ? null
                : () => unawaited(_editPlan(context, chat)),
          ),
        ),
        AccessibleWidget(
          label: 'Replan unfinished steps',
          isButton: true,
          enabled: !chat.taskBusy,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.route_outlined),
            label: const Text('Replan Unfinished'),
            onPressed: chat.taskBusy
                ? null
                : () => unawaited(chat.replanRemainingTask()),
          ),
        ),
        if (canRetry)
          AccessibleWidget(
            label: 'Retry failed step',
            isButton: true,
            child: TextButton.icon(
              icon: const Icon(Icons.replay),
              label: const Text('Retry Step'),
              onPressed: () => unawaited(chat.retryTaskPhase()),
            ),
          ),
        AccessibleWidget(
          label: 'Skip current step',
          isButton: true,
          enabled: !chat.taskBusy && next != null,
          child: TextButton.icon(
            icon: const Icon(Icons.skip_next),
            label: const Text('Skip Step'),
            onPressed: !chat.taskBusy && next != null
                ? () => unawaited(chat.skipTaskPhase())
                : null,
          ),
        ),
        AccessibleWidget(
          label: 'Stop task',
          isButton: true,
          enabled: !chat.taskBusy && !task.isTerminal,
          child: TextButton.icon(
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop'),
            onPressed: !chat.taskBusy && !task.isTerminal
                ? () => unawaited(chat.stopTask())
                : null,
          ),
        ),
      ],
    );
  }

  Future<void> _editPlan(BuildContext context, ChatService chat) async {
    final initial = chat.activeTaskJson;
    if (initial == null) return;
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Plan'),
              content: SizedBox(
                width: 820,
                child: TextField(
                  controller: controller,
                  minLines: 16,
                  maxLines: 22,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            jsonDecode(controller.text);
                            await chat.updateTaskPlan(controller.text);
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (e) {
                            setState(() {
                              saving = false;
                              error = e.toString();
                            });
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task plan saved')));
    }
  }
}

class _ApprovalCard extends StatelessWidget {
  final ChatService chat;
  final TaskDocument task;

  const _ApprovalCard({required this.chat, required this.task});

  @override
  Widget build(BuildContext context) {
    final approval = task.pendingApproval!;
    final step = task.stepById(approval.stepId);
    return _Panel(
      icon: Icons.verified_user_outlined,
      title: 'Approval Required',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(approval.reason),
          if (step != null) ...[
            const SizedBox(height: 6),
            Text(step.objective, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Approve Phase'),
              onPressed: chat.taskBusy
                  ? null
                  : () => unawaited(chat.approveTaskStep()),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatefulWidget {
  final ChatService chat;
  final TaskDocument task;

  const _QuestionCard({required this.chat, required this.task});

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.task.pendingQuestion!;
    return _Panel(
      icon: Icons.help_outline,
      title: 'Input Required',
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
                      widget.chat.answerTaskQuestion(_controller.text),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  final TaskDocument task;

  const _StepList({required this.task});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < task.steps.length; i++)
          _StepTile(index: i + 1, step: task.steps[i]),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  final int index;
  final TaskStep step;

  const _StepTile({required this.index, required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _stepIcon(step.status),
            size: 18,
            color: _stepColor(theme, step.status),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '$index. ${step.title}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AccessibleWidget(
                      label: 'Step status: ${step.status.wire}',
                      child: _StatusChip(label: step.status.wire),
                    ),
                    if (step.mayEditFiles)
                      const AccessibleWidget(
                        label: 'This step edits files',
                        child: _StatusChip(label: 'edits files'),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(step.objective, style: theme.textTheme.bodySmall),
                if (step.instructions.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    step.instructions.map((item) => '- $item').join('\n'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactList extends StatelessWidget {
  final ChatService chat;
  final TaskDocument task;

  const _ArtifactList({required this.chat, required this.task});

  @override
  Widget build(BuildContext context) {
    final artifacts = {
      for (final step in task.steps)
        for (final artifact in step.artifacts) artifact.path: artifact,
      for (final run in task.runs)
        for (final artifact in run.artifacts) artifact.path: artifact,
    }.values.toList();

    if (artifacts.isEmpty) {
      return Text(
        'No artifacts yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final artifact in artifacts)
          AccessibleWidget(
            label:
                'Artifact: ${artifact.path}${artifact.description != null ? '. ${artifact.description}' : ''}',
            isButton: true,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(artifact.path),
              subtitle: artifact.description == null
                  ? null
                  : Text(artifact.description!),
              onTap: () => unawaited(_showArtifact(context, artifact.path)),
            ),
          ),
      ],
    );
  }

  Future<void> _showArtifact(BuildContext context, String path) async {
    try {
      final content = await chat.readTaskArtifact(path);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(path),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open artifact: $e')));
    }
  }
}

class _RunList extends StatelessWidget {
  final TaskDocument task;

  const _RunList({required this.task});

  @override
  Widget build(BuildContext context) {
    final runs = task.runs.reversed.take(8).toList();
    if (runs.isEmpty) {
      return Text('No runs yet.', style: Theme.of(context).textTheme.bodySmall);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final run in runs)
          AccessibleWidget(
            label: 'Task run: ${run.stepId}, status ${run.status.wire}',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_runIcon(run.status)),
              title: Text('${run.stepId} - ${run.status.wire}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(run.summary),
                  if (run.gateResults.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final result in run.gateResults.take(6))
                          _StatusChip(
                            label: '${result.gateId}: ${result.status.wire}',
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ProjectTaskDetails extends StatelessWidget {
  final ProjectTask task;

  const _ProjectTaskDetails({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              task.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            _StatusChip(label: task.status.wire),
            if (task.taskDocumentId != null)
              _StatusChip(label: task.taskDocumentId!),
          ],
        ),
        const SizedBox(height: 6),
        Text(task.objective, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        _StringList(
          title: 'Done',
          items: task.doneCriteria,
          empty: 'No done criteria recorded.',
        ),
        const SizedBox(height: 6),
        _StringList(
          title: 'Out of scope',
          items: task.outOfScope,
          empty: 'No out-of-scope items recorded.',
        ),
        if (task.relevantSuccessCriteria.isNotEmpty) ...[
          const SizedBox(height: 6),
          _StringList(title: 'Covers', items: task.relevantSuccessCriteria),
        ],
        if (task.rejectionReason?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(
            task.rejectionReason!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProjectTaskBoardList extends StatelessWidget {
  final List<ProjectTask> tasks;
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
            child: ListTile(
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
          ),
      ],
    );
  }
}

class _ProjectQuestionList extends StatelessWidget {
  final ProjectDocument project;

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
  final ProjectDocument project;

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
                if (artifact.description.trim().isNotEmpty)
                  artifact.description,
                if (artifact.taskDocumentId != null) artifact.taskDocumentId!,
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
  final String empty;

  const _StringList({required this.items, this.title, this.empty = 'None.'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = items.isEmpty
        ? empty
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
  final ProjectDocument project;

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

class _WorkList extends StatelessWidget {
  final ChatService chat;

  const _WorkList({required this.chat});

  @override
  Widget build(BuildContext context) {
    final projects = chat.availableProjects;
    final tasks = chat.availableTasks;
    final hasContent = projects.isNotEmpty || tasks.isNotEmpty;
    return StateDisplay(
      state: hasContent ? DisplayState.content : DisplayState.empty,
      content: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final project in projects)
            ListTile(
              leading: const Icon(Icons.rocket_launch_outlined),
              title: Text(project.title),
              subtitle: Text('${project.status.wire} - ${project.id}'),
              onTap: chat.taskBusy
                  ? null
                  : () => unawaited(chat.loadProject(project.id)),
            ),
          if (projects.isNotEmpty && tasks.isNotEmpty) const Divider(),
          for (final task in tasks)
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(task.title),
              subtitle: Text('${task.status.wire} - ${task.id}'),
              onTap: chat.taskBusy
                  ? null
                  : () => unawaited(chat.loadTask(task.id)),
            ),
        ],
      ),
      emptyMessage: 'No projects or tasks in this workspace.',
      emptyHint: 'Run a project or task from the chat to see it here',
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return _Panel(icon: Icons.chevron_right, title: title, child: child);
  }
}

class _Panel extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _Panel({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;

  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
  }
}

IconData _stepIcon(TaskStepStatus status) => switch (status) {
  TaskStepStatus.completed => Icons.check_circle,
  TaskStepStatus.running => Icons.sync,
  TaskStepStatus.blocked => Icons.block,
  TaskStepStatus.failed => Icons.error_outline,
  TaskStepStatus.skipped => Icons.skip_next,
  TaskStepStatus.approved => Icons.verified_user_outlined,
  TaskStepStatus.pending => Icons.radio_button_unchecked,
};

Color _stepColor(ThemeData theme, TaskStepStatus status) => switch (status) {
  TaskStepStatus.completed => theme.colorScheme.primary,
  TaskStepStatus.running => theme.colorScheme.primary,
  TaskStepStatus.blocked || TaskStepStatus.failed => theme.colorScheme.error,
  TaskStepStatus.approved => theme.colorScheme.tertiary,
  TaskStepStatus.skipped ||
  TaskStepStatus.pending => theme.colorScheme.onSurfaceVariant,
};

IconData _runIcon(TaskRunStatus status) => switch (status) {
  TaskRunStatus.completed => Icons.check_circle_outline,
  TaskRunStatus.running => Icons.sync,
  TaskRunStatus.blocked => Icons.block,
  TaskRunStatus.failed => Icons.error_outline,
  TaskRunStatus.cancelled => Icons.cancel_outlined,
  TaskRunStatus.skipped => Icons.skip_next,
  TaskRunStatus.needsReplan || TaskRunStatus.replanned => Icons.route_outlined,
};

IconData _projectTaskStatusIcon(ProjectTaskStatus status) => switch (status) {
  ProjectTaskStatus.queued => Icons.radio_button_unchecked,
  ProjectTaskStatus.proposed => Icons.pending_actions_outlined,
  ProjectTaskStatus.approved => Icons.verified_user_outlined,
  ProjectTaskStatus.running => Icons.sync,
  ProjectTaskStatus.completed => Icons.check_circle_outline,
  ProjectTaskStatus.failed => Icons.error_outline,
  ProjectTaskStatus.rejected => Icons.cancel_outlined,
  ProjectTaskStatus.split => Icons.call_split_outlined,
  ProjectTaskStatus.cancelled => Icons.stop_circle_outlined,
};

IconData _projectDecisionIcon(ProjectDecisionType decision) =>
    switch (decision) {
      ProjectDecisionType.createTask => Icons.account_tree_outlined,
      ProjectDecisionType.complete => Icons.check_circle_outline,
      ProjectDecisionType.blocked => Icons.block,
      ProjectDecisionType.rejectTask => Icons.cancel_outlined,
      ProjectDecisionType.splitTask => Icons.call_split_outlined,
      ProjectDecisionType.evaluateTask => Icons.fact_check_outlined,
      ProjectDecisionType.refreshBacklog => Icons.playlist_add_check_outlined,
    };
