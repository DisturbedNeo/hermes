import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/a11y.dart';
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
    final task = chat.activeTask;
    if (!expanded) {
      return _CollapsedTaskPanel(
        chat: chat,
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
            _Header(chat: chat, task: task, onToggleExpanded: onToggleExpanded),
            const Divider(height: 1),
            if (task == null)
              Expanded(child: _TaskList(chat: chat))
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: _TaskBody(chat: chat, task: task),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CollapsedTaskPanel extends StatelessWidget {
  final ChatService chat;
  final TaskDocument? task;
  final VoidCallback onToggleExpanded;

  const _CollapsedTaskPanel({
    required this.chat,
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
                Icons.account_tree_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task?.title ?? 'Workspace Tasks',
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
  final TaskDocument? task;
  final VoidCallback onToggleExpanded;

  const _Header({
    required this.chat,
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
          Icon(Icons.account_tree_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task?.title ?? 'Workspace Tasks',
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
              subtitle: Text(run.summary),
            ),
          ),
      ],
    );
  }
}

class _TaskList extends StatelessWidget {
  final ChatService chat;

  const _TaskList({required this.chat});

  @override
  Widget build(BuildContext context) {
    return StateDisplay(
      state: chat.availableTasks.isEmpty
          ? DisplayState.empty
          : DisplayState.content,
      content: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: chat.availableTasks.length,
        itemBuilder: (context, index) {
          final task = chat.availableTasks[index];
          return ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(task.title),
            subtitle: Text('${task.status.wire} - ${task.id}'),
            onTap: chat.taskBusy
                ? null
                : () => unawaited(chat.loadTask(task.id)),
          );
        },
      ),
      emptyMessage: 'No tasks in this workspace.',
      emptyHint: 'Run a task from the chat to see it here',
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
