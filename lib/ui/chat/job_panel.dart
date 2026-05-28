import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/a11y.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/ui/common/state_display.dart';

class JobPanel extends StatelessWidget {
  final ChatService chat;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  const JobPanel({
    super.key,
    required this.chat,
    required this.expanded,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final job = chat.activeJob;
    if (!expanded) {
      return _CollapsedJobPanel(
        chat: chat,
        job: job,
        onToggleExpanded: onToggleExpanded,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(chat: chat, job: job, onToggleExpanded: onToggleExpanded),
          const Divider(height: 1),
          if (job == null)
            Expanded(child: _JobList(chat: chat))
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: _JobBody(chat: chat, job: job),
              ),
            ),
        ],
      ),
    );
  }
}

class _CollapsedJobPanel extends StatelessWidget {
  final ChatService chat;
  final JobDocument? job;
  final VoidCallback onToggleExpanded;

  const _CollapsedJobPanel({
    required this.chat,
    required this.job,
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
                  job?.title ?? 'Workspace Jobs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (chat.jobBusy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (job != null)
                AccessibleWidget(
                  label: 'Job status: ${job!.status.wire}',
                  child: _StatusChip(label: job!.status.wire),
                ),
              IconButton(
                tooltip: 'Open job panel',
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
  final JobDocument? job;
  final VoidCallback onToggleExpanded;

  const _Header({
    required this.chat,
    required this.job,
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
              job?.title ?? 'Workspace Jobs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (chat.jobBusy) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          AccessibleWidget(
            label: 'Reload jobs',
            isButton: true,
            enabled: !chat.jobBusy,
            child: IconButton(
              tooltip: 'Reload jobs',
              icon: const Icon(Icons.refresh),
              onPressed: chat.jobBusy
                  ? null
                  : () => unawaited(chat.reloadJobs()),
            ),
          ),
          AccessibleWidget(
            label: 'Collapse job panel',
            isButton: true,
            child: IconButton(
              tooltip: 'Collapse job panel',
              icon: const Icon(Icons.expand_more),
              onPressed: onToggleExpanded,
            ),
          ),
        ],
      ),
    );
  }
}

class _JobBody extends StatelessWidget {
  final ChatService chat;
  final JobDocument job;

  const _JobBody({required this.chat, required this.job});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = job.nextRunnableStep;
    final completed = job.steps
        .where(
          (step) =>
              step.status == JobStepStatus.completed ||
              step.status == JobStepStatus.skipped,
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
              label: 'Job status: ${job.status.wire}',
              child: _StatusChip(label: job.status.wire),
            ),
            AccessibleWidget(
              label: '$completed of ${job.steps.length} steps completed',
              child: _StatusChip(label: '$completed/${job.steps.length} steps'),
            ),
            AccessibleWidget(
              label: 'Job ID: .agent/jobs/${job.id}',
              child: _StatusChip(label: '.agent/jobs/${job.id}'),
            ),
          ],
        ),
        if (chat.jobStatusMessage != null) ...[
          const SizedBox(height: 8),
          Text(chat.jobStatusMessage!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 10),
        _Actions(chat: chat, job: job, next: next),
        if (job.pendingApproval != null) ...[
          const SizedBox(height: 10),
          _ApprovalCard(chat: chat, job: job),
        ],
        if (job.pendingQuestion != null) ...[
          const SizedBox(height: 10),
          _QuestionCard(chat: chat, job: job),
        ],
        const SizedBox(height: 12),
        _Section(
          title: 'Goal',
          child: Text(job.goal, style: theme.textTheme.bodyMedium),
        ),
        if (job.memorySummary.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _Section(
            title: 'Memory',
            child: Text(job.memorySummary, style: theme.textTheme.bodySmall),
          ),
        ],
        const SizedBox(height: 10),
        _Section(
          title: 'Plan',
          child: _StepList(job: job),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Artifacts',
          child: _ArtifactList(chat: chat, job: job),
        ),
        const SizedBox(height: 10),
        _Section(
          title: 'Recent Runs',
          child: _RunList(job: job),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final ChatService chat;
  final JobDocument job;
  final JobStep? next;

  const _Actions({required this.chat, required this.job, required this.next});

  @override
  Widget build(BuildContext context) {
    final canRun =
        !chat.jobBusy &&
        next != null &&
        job.status != JobStatus.completed &&
        job.status != JobStatus.cancelled;
    final canRetry =
        !chat.jobBusy &&
        (job.status == JobStatus.blocked || job.status == JobStatus.failed);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (chat.jobBusy)
          AccessibleWidget(
            label: chat.jobCancellationRequested
                ? 'Cancelling job...'
                : 'Cancel job run',
            isButton: true,
            enabled: !chat.jobCancellationRequested,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.stop),
              label: Text(
                chat.jobCancellationRequested ? 'Cancelling...' : 'Cancel Run',
              ),
              onPressed: chat.jobCancellationRequested
                  ? null
                  : () => unawaited(chat.cancelJobRun()),
            ),
          ),
        AccessibleWidget(
          label: 'Run next step',
          isButton: true,
          enabled: canRun,
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run Next'),
            onPressed: canRun ? () => unawaited(chat.runNextJobPhase()) : null,
          ),
        ),
        AccessibleWidget(
          label: 'Run entire job',
          isButton: true,
          enabled: canRun,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.fast_forward),
            label: const Text('Run Job'),
            onPressed: canRun ? () => unawaited(chat.runJob()) : null,
          ),
        ),
        AccessibleWidget(
          label: 'Approve current phase',
          isButton: true,
          enabled: !chat.jobBusy && job.pendingApproval != null,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Approve Phase'),
            onPressed: !chat.jobBusy && job.pendingApproval != null
                ? () => unawaited(chat.approveJobStep())
                : null,
          ),
        ),
        AccessibleWidget(
          label: 'Edit job plan',
          isButton: true,
          enabled: !chat.jobBusy,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_note),
            label: const Text('Edit Plan'),
            onPressed: chat.jobBusy
                ? null
                : () => unawaited(_editPlan(context, chat)),
          ),
        ),
        AccessibleWidget(
          label: 'Replan unfinished steps',
          isButton: true,
          enabled: !chat.jobBusy,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.route_outlined),
            label: const Text('Replan Unfinished'),
            onPressed: chat.jobBusy
                ? null
                : () => unawaited(chat.replanRemainingJob()),
          ),
        ),
        if (canRetry)
          AccessibleWidget(
            label: 'Retry failed step',
            isButton: true,
            child: TextButton.icon(
              icon: const Icon(Icons.replay),
              label: const Text('Retry Step'),
              onPressed: () => unawaited(chat.retryJobPhase()),
            ),
          ),
        AccessibleWidget(
          label: 'Skip current step',
          isButton: true,
          enabled: !chat.jobBusy && next != null,
          child: TextButton.icon(
            icon: const Icon(Icons.skip_next),
            label: const Text('Skip Step'),
            onPressed: !chat.jobBusy && next != null
                ? () => unawaited(chat.skipJobPhase())
                : null,
          ),
        ),
        AccessibleWidget(
          label: 'Stop job',
          isButton: true,
          enabled: !chat.jobBusy && !job.isTerminal,
          child: TextButton.icon(
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop'),
            onPressed: !chat.jobBusy && !job.isTerminal
                ? () => unawaited(chat.stopJob())
                : null,
          ),
        ),
      ],
    );
  }

  Future<void> _editPlan(BuildContext context, ChatService chat) async {
    final initial = chat.activeJobJson;
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
                            await chat.updateJobPlan(controller.text);
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
      ).showSnackBar(const SnackBar(content: Text('Job plan saved')));
    }
  }
}

class _ApprovalCard extends StatelessWidget {
  final ChatService chat;
  final JobDocument job;

  const _ApprovalCard({required this.chat, required this.job});

  @override
  Widget build(BuildContext context) {
    final approval = job.pendingApproval!;
    final step = job.stepById(approval.stepId);
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
              onPressed: chat.jobBusy
                  ? null
                  : () => unawaited(chat.approveJobStep()),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatefulWidget {
  final ChatService chat;
  final JobDocument job;

  const _QuestionCard({required this.chat, required this.job});

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
    final question = widget.job.pendingQuestion!;
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
              onPressed: widget.chat.jobBusy
                  ? null
                  : () => unawaited(
                      widget.chat.answerJobQuestion(_controller.text),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  final JobDocument job;

  const _StepList({required this.job});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < job.steps.length; i++)
          _StepTile(index: i + 1, step: job.steps[i]),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  final int index;
  final JobStep step;

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
  final JobDocument job;

  const _ArtifactList({required this.chat, required this.job});

  @override
  Widget build(BuildContext context) {
    final artifacts = {
      for (final step in job.steps)
        for (final artifact in step.artifacts) artifact.path: artifact,
      for (final run in job.runs)
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
      final content = await chat.readJobArtifact(path);
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
  final JobDocument job;

  const _RunList({required this.job});

  @override
  Widget build(BuildContext context) {
    final runs = job.runs.reversed.take(8).toList();
    if (runs.isEmpty) {
      return Text('No runs yet.', style: Theme.of(context).textTheme.bodySmall);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final run in runs)
          AccessibleWidget(
            label: 'Job run: ${run.stepId}, status ${run.status.wire}',
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

class _JobList extends StatelessWidget {
  final ChatService chat;

  const _JobList({required this.chat});

  @override
  Widget build(BuildContext context) {
    return StateDisplay(
      state: chat.availableJobs.isEmpty
          ? DisplayState.empty
          : DisplayState.content,
      content: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: chat.availableJobs.length,
        itemBuilder: (context, index) {
          final job = chat.availableJobs[index];
          return ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(job.title),
            subtitle: Text('${job.status.wire} - ${job.id}'),
            onTap: chat.jobBusy ? null : () => unawaited(chat.loadJob(job.id)),
          );
        },
      ),
      emptyMessage: 'No jobs in this workspace.',
      emptyHint: 'Run a job from the chat to see it here',
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

IconData _stepIcon(JobStepStatus status) => switch (status) {
  JobStepStatus.completed => Icons.check_circle,
  JobStepStatus.running => Icons.sync,
  JobStepStatus.blocked => Icons.block,
  JobStepStatus.failed => Icons.error_outline,
  JobStepStatus.skipped => Icons.skip_next,
  JobStepStatus.approved => Icons.verified_user_outlined,
  JobStepStatus.pending => Icons.radio_button_unchecked,
};

Color _stepColor(ThemeData theme, JobStepStatus status) => switch (status) {
  JobStepStatus.completed => theme.colorScheme.primary,
  JobStepStatus.running => theme.colorScheme.primary,
  JobStepStatus.blocked || JobStepStatus.failed => theme.colorScheme.error,
  JobStepStatus.approved => theme.colorScheme.tertiary,
  JobStepStatus.skipped ||
  JobStepStatus.pending => theme.colorScheme.onSurfaceVariant,
};

IconData _runIcon(JobRunStatus status) => switch (status) {
  JobRunStatus.completed => Icons.check_circle_outline,
  JobRunStatus.running => Icons.sync,
  JobRunStatus.blocked => Icons.block,
  JobRunStatus.failed => Icons.error_outline,
  JobRunStatus.cancelled => Icons.cancel_outlined,
  JobRunStatus.skipped => Icons.skip_next,
  JobRunStatus.needsReplan || JobRunStatus.replanned => Icons.route_outlined,
};
