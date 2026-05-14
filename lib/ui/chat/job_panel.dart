import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/models/job_system_settings.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/terminal_command_classifier.dart';
import 'package:hermes/ui/chat/message/message_bubble.dart';

class JobPanel extends StatefulWidget {
  final ChatService chat;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  const JobPanel({
    super.key,
    required this.chat,
    this.expanded = true,
    this.onToggleExpanded,
  });

  @override
  State<JobPanel> createState() => _JobPanelState();
}

class _JobPanelState extends State<JobPanel> {
  final _scroll = ScrollController();
  final _planScroll = ScrollController();
  final _modelOutputScroll = ScrollController();

  ChatService get chat => widget.chat;

  @override
  void dispose() {
    _scroll.dispose();
    _planScroll.dispose();
    _modelOutputScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = chat.activeJob;
    if (job == null && chat.availableJobs.isEmpty && !chat.jobBusy) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final status = job?.state.status;
    final currentPhase = job?.spec.phases
        .where((phase) => phase.id == job.state.currentPhaseId)
        .firstOrNull;
    final pendingPhase = job?.spec.phases
        .where(
          (phase) =>
              phase.status == PhaseStatus.pending ||
              phase.status == PhaseStatus.failed ||
              phase.status == PhaseStatus.blocked,
        )
        .firstOrNull;
    final isDraftJob = job?.spec.status == JobStatus.draft;
    final hasRequiredOpenQuestions =
        job?.state.openQuestions.any(
          (question) =>
              question.required && question.status == OpenQuestionStatus.open,
        ) ??
        false;
    final canPlanDraft =
        job != null && !chat.jobBusy && isDraftJob && !hasRequiredOpenQuestions;
    final canRun =
        job != null &&
        !chat.jobBusy &&
        status != JobStatus.completed &&
        status != JobStatus.running &&
        status != JobStatus.cancelled &&
        pendingPhase != null;
    final canRunJob =
        job != null &&
        !chat.jobBusy &&
        status != JobStatus.completed &&
        status != JobStatus.cancelled &&
        pendingPhase != null;
    final canRetry =
        job != null &&
        !chat.jobBusy &&
        (status == JobStatus.blocked || status == JobStatus.failed) &&
        pendingPhase != null;
    final canSkip =
        job != null &&
        !chat.jobBusy &&
        status != JobStatus.completed &&
        status != JobStatus.cancelled &&
        pendingPhase != null;
    final canStop =
        job != null &&
        !chat.jobBusy &&
        status != JobStatus.completed &&
        status != JobStatus.cancelled;
    final canManage =
        job != null && !chat.jobBusy && status != JobStatus.running;

    final header = _buildHeader(
      context: context,
      job: job,
      status: status,
      canManage: canManage,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.7)),
        ),
      ),
      child: widget.expanded
          ? Column(
              children: [
                header,
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.55),
                ),
                Expanded(
                  child: chat.jobModelOutputTitle == null
                      ? _buildScrollableBody(
                          context: context,
                          job: job,
                          status: status,
                          currentPhase: currentPhase,
                          pendingPhase: pendingPhase,
                          isDraftJob: isDraftJob,
                          canPlanDraft: canPlanDraft,
                          canRun: canRun,
                          canRunJob: canRunJob,
                          canRetry: canRetry,
                          canSkip: canSkip,
                          canStop: canStop,
                        )
                      : job == null
                      ? _buildModelOutputOnlyBody(context)
                      : _buildSplitBody(
                          context: context,
                          job: job,
                          status: status,
                          currentPhase: currentPhase,
                          pendingPhase: pendingPhase,
                          isDraftJob: isDraftJob,
                          canPlanDraft: canPlanDraft,
                          canRun: canRun,
                          canRunJob: canRunJob,
                          canRetry: canRetry,
                          canSkip: canSkip,
                          canStop: canStop,
                        ),
                ),
              ],
            )
          : header,
    );
  }

  Widget _buildModelOutputOnlyBody(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chat.jobStatusMessage != null) ...[
            Text(chat.jobStatusMessage!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: _JobModelOutputPanel(
              chat: chat,
              fill: true,
              scrollController: _modelOutputScroll,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableBody({
    required BuildContext context,
    required JobSnapshot? job,
    required JobStatus? status,
    required JobPhase? currentPhase,
    required JobPhase? pendingPhase,
    required bool isDraftJob,
    required bool canPlanDraft,
    required bool canRun,
    required bool canRunJob,
    required bool canRetry,
    required bool canSkip,
    required bool canStop,
  }) {
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        primary: false,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: _buildBody(
          context: context,
          job: job,
          status: status,
          currentPhase: currentPhase,
          pendingPhase: pendingPhase,
          isDraftJob: isDraftJob,
          canPlanDraft: canPlanDraft,
          canRun: canRun,
          canRunJob: canRunJob,
          canRetry: canRetry,
          canSkip: canSkip,
          canStop: canStop,
        ),
      ),
    );
  }

  Widget _buildSplitBody({
    required BuildContext context,
    required JobSnapshot? job,
    required JobStatus? status,
    required JobPhase? currentPhase,
    required JobPhase? pendingPhase,
    required bool isDraftJob,
    required bool canPlanDraft,
    required bool canRun,
    required bool canRunJob,
    required bool canRetry,
    required bool canSkip,
    required bool canStop,
  }) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 640.0;
        final outputMinHeight = math.min(
          180.0,
          math.max(96.0, availableHeight * 0.32),
        );
        final desiredPlanHeight = availableHeight * 0.44;
        final minimumPlanHeight = math.min(
          180.0,
          math.max(96.0, availableHeight * 0.32),
        );
        final maxPlanHeight = math.max(80.0, availableHeight - outputMinHeight);
        final planHeight = math.min(
          maxPlanHeight,
          math.min(360.0, math.max(minimumPlanHeight, desiredPlanHeight)),
        );

        return Column(
          children: [
            SizedBox(
              height: planHeight,
              child: _PinnedPlanPane(
                scrollController: _planScroll,
                job: job,
                child: _buildBody(
                  context: context,
                  job: job,
                  status: status,
                  currentPhase: currentPhase,
                  pendingPhase: pendingPhase,
                  isDraftJob: isDraftJob,
                  canPlanDraft: canPlanDraft,
                  canRun: canRun,
                  canRunJob: canRunJob,
                  canRetry: canRetry,
                  canSkip: canSkip,
                  canStop: canStop,
                ),
              ),
            ),
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.55),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: _JobModelOutputPanel(
                  chat: chat,
                  fill: true,
                  scrollController: _modelOutputScroll,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required JobSnapshot? job,
    required JobStatus? status,
    required bool canManage,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: widget.expanded ? 'Collapse job panel' : 'Open job panel',
            icon: Icon(
              widget.expanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
            ),
            onPressed: widget.onToggleExpanded,
          ),
          Icon(
            Icons.account_tree_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              job?.spec.title ?? 'Workspace Jobs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (chat.jobBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            _StatusChip(status: status),
          const SizedBox(width: 6),
          PopupMenuButton<_JobPanelAction>(
            tooltip: 'Job actions',
            enabled: canManage,
            icon: const Icon(Icons.more_vert),
            onSelected: (action) => unawaited(_handleAction(context, action)),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _JobPanelAction.editBrief,
                child: ListTile(
                  leading: Icon(Icons.description_outlined),
                  title: Text('Edit Task Brief'),
                ),
              ),
              PopupMenuItem(
                value: _JobPanelAction.editPlan,
                child: ListTile(
                  leading: Icon(Icons.view_list_outlined),
                  title: Text('Edit Plan'),
                ),
              ),
              PopupMenuItem(
                value: _JobPanelAction.editSpec,
                child: ListTile(
                  leading: Icon(Icons.fact_check_outlined),
                  title: Text('Edit Raw Spec'),
                ),
              ),
              PopupMenuItem(
                value: _JobPanelAction.replanCurrent,
                child: ListTile(
                  leading: Icon(Icons.low_priority_outlined),
                  title: Text('Replan Current Phase'),
                ),
              ),
              PopupMenuItem(
                value: _JobPanelAction.replanRemaining,
                child: ListTile(
                  leading: Icon(Icons.route_outlined),
                  title: Text('Replan Remaining'),
                ),
              ),
              PopupMenuItem(
                value: _JobPanelAction.replanEntire,
                child: ListTile(
                  leading: Icon(Icons.restart_alt),
                  title: Text('Replan Entire Job'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Reload jobs',
            icon: const Icon(Icons.refresh),
            onPressed: chat.jobBusy ? null : () => unawaited(chat.reloadJobs()),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required JobSnapshot? job,
    required JobStatus? status,
    required JobPhase? currentPhase,
    required JobPhase? pendingPhase,
    required bool isDraftJob,
    required bool canPlanDraft,
    required bool canRun,
    required bool canRunJob,
    required bool canRetry,
    required bool canSkip,
    required bool canStop,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (job != null) ...[
          _JobActionBar(
            showPlan: isDraftJob,
            showRun:
                !isDraftJob &&
                status != JobStatus.completed &&
                status != JobStatus.cancelled,
            onPlan: canPlanDraft ? () => unawaited(chat.planActiveJob()) : null,
            onRunNext: canRun
                ? () => unawaited(_runNextPhaseWithApproval(context))
                : null,
            onRunJob: canRunJob ? () => unawaited(chat.runJob()) : null,
            onRetry: canRetry ? () => unawaited(chat.retryJobPhase()) : null,
            onSkip: canSkip ? () => unawaited(chat.skipJobPhase()) : null,
            onStop: canStop ? () => unawaited(chat.stopJob()) : null,
          ),
        ],
        if (chat.jobStatusMessage != null) ...[
          const SizedBox(height: 6),
          Text(chat.jobStatusMessage!, style: theme.textTheme.bodySmall),
        ],
        if (job != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetaChip(icon: Icons.tune, label: job.spec.autonomy.wire),
              if (currentPhase != null)
                _MetaChip(
                  icon: Icons.radio_button_checked,
                  label: currentPhase.title,
                )
              else if (pendingPhase != null)
                _MetaChip(
                  icon: Icons.radio_button_unchecked,
                  label: pendingPhase.title,
                ),
              _MetaChip(
                icon: Icons.folder_copy_outlined,
                label: '.agent/jobs/${job.spec.id}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TaskBriefSummary(job: job),
          if (isDraftJob) ...[
            const SizedBox(height: 8),
            _DraftPlanPanel(chat: chat, job: job, canPlan: canPlanDraft),
          ],
          if (job.spec.phases.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PhaseTimeline(job: job),
          ],
          if (pendingPhase != null &&
              canRun &&
              _phaseNeedsHumanApproval(
                chat.jobSystemSettings,
                job,
                pendingPhase,
              )) ...[
            const SizedBox(height: 8),
            _PhaseApprovalPanel(
              settings: chat.jobSystemSettings,
              job: job,
              phase: pendingPhase,
              onApprove: () => _runNextPhaseWithApproval(context),
            ),
          ],
          if (job.state.pendingApprovals.any(
            (approval) => approval.status == 'pending',
          )) ...[
            const SizedBox(height: 8),
            _PendingFileApprovals(chat: chat, job: job),
          ],
          if (_RecoveryDashboard.shouldShow(job)) ...[
            const SizedBox(height: 8),
            _RecoveryDashboard(
              chat: chat,
              job: job,
              pendingPhase: pendingPhase,
              canRun: canRun,
              canRetry: canRetry,
              canSkip: canSkip,
              onRunNext: () => _runNextPhaseWithApproval(context),
              onReplanCurrent: () =>
                  _confirmReplan(context, ReplanScope.currentPhase),
              onReplanRemaining: () =>
                  _confirmReplan(context, ReplanScope.remainingPhases),
            ),
          ],
          const SizedBox(height: 8),
          _Artifacts(chat: chat, job: job),
          if (job.state.phaseRuns.isNotEmpty || job.state.risks.isNotEmpty) ...[
            const SizedBox(height: 8),
            _RecentActivity(job: job),
          ],
          if (job.state.openQuestions.any(
            (question) => question.status == OpenQuestionStatus.open,
          )) ...[
            const SizedBox(height: 8),
            _OpenQuestions(chat: chat, job: job),
          ],
        ],
      ],
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    _JobPanelAction action,
  ) async {
    switch (action) {
      case _JobPanelAction.editBrief:
        final initial = chat.activeTaskBriefJson;
        if (initial == null) return;
        await _editJson(
          context: context,
          title: 'Edit Task Brief',
          initial: initial,
          save: chat.updateJobTaskBrief,
        );
        break;
      case _JobPanelAction.editPlan:
        await _editPlan(context);
        break;
      case _JobPanelAction.editSpec:
        final initial = chat.activeJobSpecJson;
        if (initial == null) return;
        await _editJson(
          context: context,
          title: 'Edit Raw Spec',
          initial: initial,
          save: chat.updateJobSpec,
        );
        break;
      case _JobPanelAction.replanCurrent:
        await _confirmReplan(context, ReplanScope.currentPhase);
        break;
      case _JobPanelAction.replanRemaining:
        await _confirmReplan(context, ReplanScope.remainingPhases);
        break;
      case _JobPanelAction.replanEntire:
        await _confirmReplan(context, ReplanScope.entireJob);
        break;
    }
  }

  Future<void> _runNextPhaseWithApproval(BuildContext context) async {
    final job = chat.activeJob;
    if (job == null || chat.jobBusy) return;
    final phase = _nextRunnablePhase(job);
    if (phase == null) return;

    if (_phaseNeedsHumanApproval(chat.jobSystemSettings, job, phase)) {
      final approved = await _confirmPhaseApproval(context, job, phase);
      if (approved != true) return;
    }

    await chat.runNextJobPhase();
  }

  Future<bool?> _confirmPhaseApproval(
    BuildContext context,
    JobSnapshot job,
    JobPhase phase,
  ) {
    final reasons = _approvalReasons(chat.jobSystemSettings, job, phase);
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text('Approve ${phase.title}'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(phase.objective, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MiniChip(
                      icon: Icons.terminal,
                      label: _effectiveTerminalPolicy(job.spec, phase).wire,
                    ),
                    if (phase.humanCheckpoint)
                      const _MiniChip(
                        icon: Icons.verified_user_outlined,
                        label: 'checkpoint',
                      ),
                    for (final tool in _mutatingTools(phase).take(4))
                      _MiniChip(icon: Icons.edit_outlined, label: tool),
                  ],
                ),
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final reason in reasons)
                    Text('- $reason', style: theme.textTheme.bodySmall),
                ],
                if (phase.expectedOutputs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Expected outputs',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final output in phase.expectedOutputs.take(5))
                    Text('- ${output.path}', style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Approve & Run'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editPlan(BuildContext context) async {
    final job = chat.activeJob;
    if (job == null) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _PlanEditorDialog(
          initial: job.spec,
          save: (spec) {
            final rawJson =
                '${const JsonEncoder.withIndent('  ').convert(spec.toJson())}\n';
            return chat.updateJobSpec(rawJson);
          },
        );
      },
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Job plan saved')));
    }
  }

  Future<void> _editJson({
    required BuildContext context,
    required String title,
    required String initial,
    required Future<void> Function(String rawJson) save,
  }) async {
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 820,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      minLines: 16,
                      maxLines: 22,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        helperText: 'Edit the saved JSON job artifact.',
                        errorText: error,
                      ),
                    ),
                  ],
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
                            await save(controller.text);
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (e) {
                            if (!context.mounted) return;
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
      ).showSnackBar(SnackBar(content: Text('$title saved')));
    }
  }

  Future<void> _confirmReplan(BuildContext context, ReplanScope scope) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Preview ${scope.label} Replan'),
          content: Text(_replanDescription(scope)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Generate Preview'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final original = chat.activeJob;
    if (original == null) return;

    JobSnapshot? proposal;
    try {
      proposal = await chat.proposeReplanJob(scope);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Replan preview failed: $e')));
      return;
    }
    if (proposal == null || !context.mounted) return;

    final approved = await _showReplanPreview(
      context: context,
      scope: scope,
      original: original,
      proposal: proposal,
    );
    if (approved != true) return;

    try {
      await chat.applyReplanProposal(proposal, scope);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${scope.label} replan applied')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Apply replan failed: $e')));
    }
  }

  Future<bool?> _showReplanPreview({
    required BuildContext context,
    required ReplanScope scope,
    required JobSnapshot original,
    required JobSnapshot proposal,
  }) {
    final diff = _PlanDiff.fromSpecs(original.spec, proposal.spec);
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text('${scope.label} Replan Preview'),
          content: SizedBox(
            width: 880,
            height: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nothing has been saved yet. Review the proposed plan changes before applying them.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MiniChip(
                      icon: Icons.add_circle_outline,
                      label: '${diff.addedCount} added',
                    ),
                    _MiniChip(
                      icon: Icons.edit_outlined,
                      label: '${diff.changedCount} changed',
                    ),
                    _MiniChip(
                      icon: Icons.remove_circle_outline,
                      label: '${diff.removedCount} removed',
                    ),
                    _MiniChip(
                      icon: Icons.check_circle_outline,
                      label: '${diff.unchangedCount} unchanged',
                    ),
                    _MiniChip(
                      icon: Icons.radio_button_checked,
                      label: 'next ${proposal.state.currentPhaseId ?? 'none'}',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: diff.changes.isEmpty
                      ? Center(
                          child: Text(
                            'No phase changes proposed.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : ListView.separated(
                          itemCount: diff.changes.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            return _PlanDiffRow(change: diff.changes[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Apply Replan'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  String _replanDescription(ReplanScope scope) {
    final scopeText = switch (scope) {
      ReplanScope.currentPhase =>
        'Only the current pending, failed, or blocked phase can be replaced. Other phases are preserved.',
      ReplanScope.remainingPhases =>
        'Completed and skipped phases are preserved. Pending, failed, or blocked phases may be replaced.',
      ReplanScope.entireJob =>
        'The executable phase plan can be replaced from the beginning. Existing runs and artifacts remain in job history.',
    };
    return '$scopeText Nothing is saved until you approve the preview.';
  }
}

enum _JobPanelAction {
  editBrief,
  editPlan,
  editSpec,
  replanCurrent,
  replanRemaining,
  replanEntire,
}

class _JobActionBar extends StatelessWidget {
  final bool showPlan;
  final bool showRun;
  final VoidCallback? onPlan;
  final VoidCallback? onRunNext;
  final VoidCallback? onRunJob;
  final VoidCallback? onRetry;
  final VoidCallback? onSkip;
  final VoidCallback? onStop;

  const _JobActionBar({
    required this.showPlan,
    required this.showRun,
    required this.onPlan,
    required this.onRunNext,
    required this.onRunJob,
    required this.onRetry,
    required this.onSkip,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showPlan)
          FilledButton.icon(
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Generate Plan'),
            onPressed: onPlan,
          ),
        if (showRun) ...[
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run Next'),
            onPressed: onRunNext,
          ),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.fast_forward),
            label: const Text('Run Job'),
            onPressed: onRunJob,
          ),
        ],
        if (onRetry != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.replay),
            label: const Text('Retry'),
            onPressed: onRetry,
          ),
        if (onSkip != null)
          TextButton.icon(
            icon: const Icon(Icons.skip_next),
            label: const Text('Skip'),
            onPressed: onSkip,
          ),
        if (onStop != null)
          TextButton.icon(
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop'),
            onPressed: onStop,
          ),
      ],
    );
  }
}

class _PinnedPlanPane extends StatelessWidget {
  final ScrollController scrollController;
  final JobSnapshot? job;
  final Widget child;

  const _PinnedPlanPane({
    required this.scrollController,
    required this.job,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phases = job?.spec.phases ?? const <JobPhase>[];
    final completed = phases
        .where((phase) => phase.status == PhaseStatus.completed)
        .length;

    return ColoredBox(
      color: theme.colorScheme.surface.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
            child: Row(
              children: [
                Icon(
                  Icons.view_list_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    job == null ? 'Plan' : 'Plan: ${job!.spec.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (phases.isNotEmpty)
                  _MiniChip(
                    icon: Icons.check_circle_outline,
                    label: '$completed/${phases.length} complete',
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.45)),
          Expanded(
            child: Scrollbar(
              controller: scrollController,
              child: SingleChildScrollView(
                controller: scrollController,
                primary: false,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobModelOutputPanel extends StatelessWidget {
  final ChatService chat;
  final bool fill;
  final ScrollController? scrollController;

  const _JobModelOutputPanel({
    required this.chat,
    this.fill = false,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = chat.jobModelOutputTitle ?? 'Model Output';
    final text = chat.jobModelOutputText.trim().isEmpty
        ? '_Waiting for model output..._'
        : chat.jobModelOutputText.trimLeft();
    final bubble = Bubble(
      id: 'job_model_output',
      role: MessageRole.assistant,
      text: text,
      reasoning: chat.jobModelOutputReasoning.trimLeft(),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  chat.jobModelOutputActive
                      ? Icons.stream
                      : Icons.article_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (chat.jobModelOutputActive)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (fill)
              Expanded(
                child: Scrollbar(
                  controller: scrollController,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    primary: false,
                    child: MessageBubble(b: bubble, editable: false),
                  ),
                ),
              )
            else
              MessageBubble(b: bubble, editable: false),
          ],
        ),
      ),
    );
  }
}

JobPhase? _nextRunnablePhase(JobSnapshot job) {
  return job.spec.phases
      .where(
        (phase) =>
            phase.status == PhaseStatus.pending ||
            phase.status == PhaseStatus.failed ||
            phase.status == PhaseStatus.blocked,
      )
      .firstOrNull;
}

bool _phaseNeedsHumanApproval(
  JobSystemSettings settings,
  JobSnapshot job,
  JobPhase phase,
) {
  if (phase.humanCheckpoint || job.spec.autonomy == AutonomyLevel.manual) {
    return true;
  }
  final terminalPolicy = _effectiveTerminalPolicy(job.spec, phase);
  if (settings.requireApprovalBeforeTerminal &&
      (terminalPolicy == TerminalPolicy.workspaceMutating ||
          terminalPolicy == TerminalPolicy.unrestrictedWorkspace)) {
    return true;
  }
  return settings.requireApprovalBeforeFileEdits &&
      _mutatingTools(phase).isNotEmpty;
}

List<String> _approvalReasons(
  JobSystemSettings settings,
  JobSnapshot job,
  JobPhase phase,
) {
  final reasons = <String>[];
  if (job.spec.autonomy == AutonomyLevel.manual) {
    reasons.add('The job is using manual autonomy.');
  }
  if (phase.humanCheckpoint) {
    reasons.add('This phase is marked as a human checkpoint.');
  }
  final terminalPolicy = _effectiveTerminalPolicy(job.spec, phase);
  if (settings.requireApprovalBeforeTerminal &&
      (terminalPolicy == TerminalPolicy.workspaceMutating ||
          terminalPolicy == TerminalPolicy.unrestrictedWorkspace)) {
    reasons.add('Terminal policy allows workspace mutation.');
  }
  final mutatingTools = _mutatingTools(phase);
  if (settings.requireApprovalBeforeFileEdits && mutatingTools.isNotEmpty) {
    reasons.add('Allowed tools can modify workspace files.');
  }
  return reasons;
}

TerminalPolicy _effectiveTerminalPolicy(JobSpec spec, JobPhase phase) {
  final terminal = spec.toolPolicy.terminal;
  if (terminal?.allowed == false) return TerminalPolicy.none;
  final global = terminal?.policy ?? phase.terminalPolicy;
  return _terminalPolicyRank(global) <=
          _terminalPolicyRank(phase.terminalPolicy)
      ? global
      : phase.terminalPolicy;
}

int _terminalPolicyRank(TerminalPolicy policy) {
  return switch (policy) {
    TerminalPolicy.none => 0,
    TerminalPolicy.readonly => 1,
    TerminalPolicy.workspaceMutating => 2,
    TerminalPolicy.unrestrictedWorkspace => 3,
  };
}

List<String> _mutatingTools(JobPhase phase) {
  const mutating = {
    'write_file',
    'patch_file',
    'create_directory',
    'rename_path',
    'delete_path',
  };
  return phase.allowedTools.where(mutating.contains).toList()..sort();
}

enum _PlanPhaseDiffKind { added, removed, changed, unchanged }

class _PlanDiff {
  final List<_PlanPhaseDiff> changes;
  final int addedCount;
  final int changedCount;
  final int removedCount;
  final int unchangedCount;

  const _PlanDiff({
    required this.changes,
    required this.addedCount,
    required this.changedCount,
    required this.removedCount,
    required this.unchangedCount,
  });

  factory _PlanDiff.fromSpecs(JobSpec original, JobSpec proposal) {
    final originalById = {for (final phase in original.phases) phase.id: phase};
    final originalIndexById = {
      for (var i = 0; i < original.phases.length; i++) original.phases[i].id: i,
    };
    final proposalIds = proposal.phases.map((phase) => phase.id).toSet();
    final changes = <_PlanPhaseDiff>[];
    var added = 0;
    var changed = 0;
    var unchanged = 0;

    for (var i = 0; i < proposal.phases.length; i++) {
      final next = proposal.phases[i];
      final previous = originalById[next.id];
      if (previous == null) {
        added += 1;
        changes.add(
          _PlanPhaseDiff(
            kind: _PlanPhaseDiffKind.added,
            phaseId: next.id,
            title: next.title,
            previousIndex: null,
            nextIndex: i,
            details: [
              'Added at position ${i + 1}',
              'Outputs: ${_outputsSummary(next.expectedOutputs)}',
            ],
          ),
        );
        continue;
      }

      final details = _phaseDetails(
        previous: previous,
        next: next,
        previousIndex: originalIndexById[next.id]!,
        nextIndex: i,
      );
      if (details.isEmpty) {
        unchanged += 1;
        changes.add(
          _PlanPhaseDiff(
            kind: _PlanPhaseDiffKind.unchanged,
            phaseId: next.id,
            title: next.title,
            previousIndex: originalIndexById[next.id],
            nextIndex: i,
            details: const ['No material changes'],
          ),
        );
      } else {
        changed += 1;
        changes.add(
          _PlanPhaseDiff(
            kind: _PlanPhaseDiffKind.changed,
            phaseId: next.id,
            title: next.title,
            previousIndex: originalIndexById[next.id],
            nextIndex: i,
            details: details,
          ),
        );
      }
    }

    var removed = 0;
    for (var i = 0; i < original.phases.length; i++) {
      final phase = original.phases[i];
      if (proposalIds.contains(phase.id)) continue;
      removed += 1;
      changes.add(
        _PlanPhaseDiff(
          kind: _PlanPhaseDiffKind.removed,
          phaseId: phase.id,
          title: phase.title,
          previousIndex: i,
          nextIndex: null,
          details: ['Removed from position ${i + 1}'],
        ),
      );
    }

    return _PlanDiff(
      changes: changes,
      addedCount: added,
      changedCount: changed,
      removedCount: removed,
      unchangedCount: unchanged,
    );
  }

  static List<String> _phaseDetails({
    required JobPhase previous,
    required JobPhase next,
    required int previousIndex,
    required int nextIndex,
  }) {
    final details = <String>[];
    if (previousIndex != nextIndex) {
      details.add('Moved from ${previousIndex + 1} to ${nextIndex + 1}');
    }
    if (previous.title != next.title) {
      details.add('Title: "${previous.title}" -> "${next.title}"');
    }
    if (previous.objective != next.objective) {
      details.add('Objective changed');
    }
    if (previous.terminalPolicy != next.terminalPolicy) {
      details.add(
        'Terminal policy: ${previous.terminalPolicy.wire} -> ${next.terminalPolicy.wire}',
      );
    }
    if (previous.humanCheckpoint != next.humanCheckpoint) {
      details.add(
        'Human checkpoint: ${previous.humanCheckpoint ? 'yes' : 'no'} -> ${next.humanCheckpoint ? 'yes' : 'no'}',
      );
    }
    if (previous.review.required != next.review.required ||
        previous.review.reviewer != next.review.reviewer) {
      details.add(
        'Review: ${_reviewSummary(previous.review)} -> ${_reviewSummary(next.review)}',
      );
    }
    if (!_sameList(previous.allowedTools, next.allowedTools)) {
      details.add('Allowed tools changed');
    }
    if (!_sameList(previous.disallowedTools, next.disallowedTools)) {
      details.add('Disallowed tools changed');
    }
    if (!_sameList(previous.completionCriteria, next.completionCriteria)) {
      details.add('Completion criteria changed');
    }
    if (!_sameList(
      previous.inputs.map(_inputKey),
      next.inputs.map(_inputKey),
    )) {
      details.add('Inputs changed');
    }
    if (!_sameList(
      previous.expectedOutputs.map(_outputKey),
      next.expectedOutputs.map(_outputKey),
    )) {
      details.add(
        'Outputs changed: ${_outputsSummary(previous.expectedOutputs)} -> ${_outputsSummary(next.expectedOutputs)}',
      );
    }
    return details;
  }

  static bool _sameList(Iterable<String> left, Iterable<String> right) {
    final leftList = left.toList();
    final rightList = right.toList();
    if (leftList.length != rightList.length) return false;
    for (var i = 0; i < leftList.length; i++) {
      if (leftList[i] != rightList[i]) return false;
    }
    return true;
  }

  static String _inputKey(PhaseInput input) {
    return '${input.path}|${input.required}|${input.description ?? ''}';
  }

  static String _outputKey(PhaseOutput output) {
    return '${output.path}|${output.required}|${output.format?.wire ?? ''}|${output.description ?? ''}';
  }

  static String _outputsSummary(List<PhaseOutput> outputs) {
    if (outputs.isEmpty) return 'none';
    if (outputs.length == 1) return outputs.single.path;
    return '${outputs.length} outputs';
  }

  static String _reviewSummary(ReviewPolicy review) {
    return review.required ? review.reviewer.wire : 'not required';
  }
}

class _PlanPhaseDiff {
  final _PlanPhaseDiffKind kind;
  final String phaseId;
  final String title;
  final int? previousIndex;
  final int? nextIndex;
  final List<String> details;

  const _PlanPhaseDiff({
    required this.kind,
    required this.phaseId,
    required this.title,
    required this.previousIndex,
    required this.nextIndex,
    required this.details,
  });
}

class _PlanDiffRow extends StatelessWidget {
  final _PlanPhaseDiff change;

  const _PlanDiffRow({required this.change});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color(theme);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(), color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        change.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MiniChip(icon: _icon(), label: _label()),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  change.phaseId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                for (final detail in change.details.take(5))
                  Text('- $detail', style: theme.textTheme.bodySmall),
                if (change.details.length > 5)
                  Text(
                    '- ${change.details.length - 5} more changes',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon() {
    return switch (change.kind) {
      _PlanPhaseDiffKind.added => Icons.add_circle_outline,
      _PlanPhaseDiffKind.removed => Icons.remove_circle_outline,
      _PlanPhaseDiffKind.changed => Icons.edit_outlined,
      _PlanPhaseDiffKind.unchanged => Icons.check_circle_outline,
    };
  }

  String _label() {
    return switch (change.kind) {
      _PlanPhaseDiffKind.added => 'added',
      _PlanPhaseDiffKind.removed => 'removed',
      _PlanPhaseDiffKind.changed => 'changed',
      _PlanPhaseDiffKind.unchanged => 'unchanged',
    };
  }

  Color _color(ThemeData theme) {
    return switch (change.kind) {
      _PlanPhaseDiffKind.added => theme.colorScheme.primary,
      _PlanPhaseDiffKind.removed => theme.colorScheme.error,
      _PlanPhaseDiffKind.changed => theme.colorScheme.tertiary,
      _PlanPhaseDiffKind.unchanged => theme.colorScheme.onSurfaceVariant,
    };
  }
}

class _PlanEditorDialog extends StatefulWidget {
  final JobSpec initial;
  final Future<void> Function(JobSpec spec) save;

  const _PlanEditorDialog({required this.initial, required this.save});

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  late JobSpec _spec = widget.initial;
  var _selectedIndex = 0;
  var _saving = false;
  String? _error;

  JobPhase? get _selectedPhase {
    if (_spec.phases.isEmpty) return null;
    if (_selectedIndex < 0) return _spec.phases.first;
    if (_selectedIndex >= _spec.phases.length) return _spec.phases.last;
    return _spec.phases[_selectedIndex];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = (media.width - 48).clamp(360.0, 1080.0);
    final height = (media.height - 150).clamp(420.0, 720.0);

    return AlertDialog(
      title: const Text('Edit Plan'),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              _ErrorBanner(message: _error!),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [
                        SizedBox(height: 190, child: _buildPhaseList(context)),
                        const SizedBox(height: 10),
                        Expanded(child: _buildEditor(context)),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 310, child: _buildPhaseList(context)),
                      const VerticalDivider(width: 24),
                      Expanded(child: _buildEditor(context)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save'),
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _buildPhaseList(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Phases',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add phase',
                  icon: const Icon(Icons.add),
                  onPressed: _saving ? null : _addPhase,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _spec.phases.isEmpty
                ? Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Phase'),
                      onPressed: _saving ? null : _addPhase,
                    ),
                  )
                : ListView.separated(
                    itemCount: _spec.phases.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final phase = _spec.phases[index];
                      return ListTile(
                        dense: true,
                        selected: index == _selectedIndex,
                        leading: CircleAvatar(
                          radius: 13,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(
                          phase.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          phase.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: _saving
                            ? null
                            : () => setState(() => _selectedIndex = index),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Move up',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: !_saving && _selectedIndex > 0
                      ? () => _movePhase(-1)
                      : null,
                ),
                IconButton(
                  tooltip: 'Move down',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed:
                      !_saving && _selectedIndex < _spec.phases.length - 1
                      ? () => _movePhase(1)
                      : null,
                ),
                IconButton(
                  tooltip: 'Duplicate phase',
                  icon: const Icon(Icons.content_copy_outlined),
                  onPressed: !_saving && _selectedPhase != null
                      ? _duplicatePhase
                      : null,
                ),
                IconButton(
                  tooltip: 'Remove phase',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: !_saving && _selectedPhase != null
                      ? _removeSelectedPhase
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final phase = _selectedPhase;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildJobFields(context),
          const SizedBox(height: 18),
          if (phase == null)
            const SizedBox.shrink()
          else
            _buildPhaseFields(context, phase),
        ],
      ),
    );
  }

  Widget _buildJobFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(icon: Icons.account_tree_outlined, label: 'Job'),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey('plan-title'),
          initialValue: _spec.title,
          decoration: _fieldDecoration('Title'),
          enabled: !_saving,
          onChanged: (value) {
            _setSpec(_spec.copyWith(title: value));
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<AutonomyLevel>(
                initialValue: _spec.autonomy,
                decoration: _fieldDecoration('Autonomy'),
                items: [
                  for (final autonomy in AutonomyLevel.values)
                    DropdownMenuItem(
                      value: autonomy,
                      child: Text(autonomy.wire),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        _setSpec(_spec.copyWith(autonomy: value));
                      },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                key: const ValueKey('plan-modules'),
                initialValue: _linesText(_spec.promptModules),
                decoration: _fieldDecoration('Prompt modules'),
                enabled: !_saving,
                minLines: 1,
                maxLines: 2,
                onChanged: (value) {
                  _setSpec(_spec.copyWith(promptModules: _splitList(value)));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey('plan-constraints'),
          initialValue: _linesText(_spec.globalConstraints),
          decoration: _fieldDecoration('Global constraints'),
          enabled: !_saving,
          minLines: 2,
          maxLines: 5,
          onChanged: (value) {
            _setSpec(_spec.copyWith(globalConstraints: _splitLines(value)));
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey('plan-success-criteria'),
          initialValue: _linesText(_spec.globalSuccessCriteria),
          decoration: _fieldDecoration('Global success criteria'),
          enabled: !_saving,
          minLines: 2,
          maxLines: 5,
          onChanged: (value) {
            _setSpec(_spec.copyWith(globalSuccessCriteria: _splitLines(value)));
          },
        ),
      ],
    );
  }

  Widget _buildPhaseFields(BuildContext context, JobPhase phase) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(icon: Icons.adjust_outlined, label: 'Selected Phase'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('phase-id-$_selectedIndex'),
                initialValue: phase.id,
                decoration: _fieldDecoration('ID'),
                enabled: !_saving,
                onChanged: (value) {
                  _updateSelectedPhase((phase) => phase.copyWith(id: value));
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextFormField(
                key: ValueKey('phase-title-$_selectedIndex'),
                initialValue: phase.title,
                decoration: _fieldDecoration('Title'),
                enabled: !_saving,
                onChanged: (value) {
                  _updateSelectedPhase((phase) => phase.copyWith(title: value));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('phase-objective-$_selectedIndex'),
          initialValue: phase.objective,
          decoration: _fieldDecoration('Objective'),
          enabled: !_saving,
          minLines: 2,
          maxLines: 5,
          onChanged: (value) {
            _updateSelectedPhase((phase) => phase.copyWith(objective: value));
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<TerminalPolicy>(
                key: ValueKey('phase-terminal-$_selectedIndex'),
                initialValue: phase.terminalPolicy,
                decoration: _fieldDecoration('Terminal policy'),
                items: [
                  for (final policy in TerminalPolicy.values)
                    DropdownMenuItem(value: policy, child: Text(policy.wire)),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        _updateSelectedPhase(
                          (phase) => phase.copyWith(terminalPolicy: value),
                        );
                      },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<ReviewerType>(
                key: ValueKey('phase-reviewer-$_selectedIndex'),
                initialValue: phase.review.reviewer,
                decoration: _fieldDecoration('Reviewer'),
                items: [
                  for (final reviewer in ReviewerType.values)
                    DropdownMenuItem(
                      value: reviewer,
                      child: Text(reviewer.wire),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        _updateSelectedPhase(
                          (phase) => phase.copyWith(
                            review: ReviewPolicy(
                              required: phase.review.required,
                              reviewer: value,
                              criteria: phase.review.criteria,
                            ),
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            SizedBox(
              width: 260,
              child: SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Human checkpoint'),
                value: phase.humanCheckpoint,
                onChanged: _saving
                    ? null
                    : (value) {
                        _updateSelectedPhase(
                          (phase) => phase.copyWith(humanCheckpoint: value),
                        );
                      },
              ),
            ),
            SizedBox(
              width: 230,
              child: SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Review required'),
                value: phase.review.required,
                onChanged: _saving
                    ? null
                    : (value) {
                        _updateSelectedPhase(
                          (phase) => phase.copyWith(
                            review: ReviewPolicy(
                              required: value,
                              reviewer: phase.review.reviewer,
                              criteria: phase.review.criteria,
                            ),
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('phase-allowed-tools-$_selectedIndex'),
                initialValue: _linesText(phase.allowedTools),
                decoration: _fieldDecoration('Allowed tools'),
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                onChanged: (value) {
                  _updateSelectedPhase(
                    (phase) => phase.copyWith(allowedTools: _splitList(value)),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                key: ValueKey('phase-disallowed-tools-$_selectedIndex'),
                initialValue: _linesText(phase.disallowedTools),
                decoration: _fieldDecoration('Disallowed tools'),
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                onChanged: (value) {
                  _updateSelectedPhase(
                    (phase) =>
                        phase.copyWith(disallowedTools: _splitList(value)),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('phase-inputs-$_selectedIndex'),
          initialValue: _inputsText(phase.inputs),
          decoration: _fieldDecoration('Inputs: path | required | description'),
          enabled: !_saving,
          minLines: 2,
          maxLines: 5,
          onChanged: (value) {
            _updateSelectedPhase(
              (phase) => phase.copyWith(inputs: _parseInputs(value)),
            );
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('phase-outputs-$_selectedIndex'),
          initialValue: _outputsText(phase.expectedOutputs),
          decoration: _fieldDecoration(
            'Expected outputs: path | required | format | description',
          ),
          enabled: !_saving,
          minLines: 2,
          maxLines: 5,
          onChanged: (value) {
            _updateSelectedPhase(
              (phase) => phase.copyWith(expectedOutputs: _parseOutputs(value)),
            );
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('phase-criteria-$_selectedIndex'),
          initialValue: _linesText(phase.completionCriteria),
          decoration: _fieldDecoration('Completion criteria'),
          enabled: !_saving,
          minLines: 2,
          maxLines: 5,
          onChanged: (value) {
            _updateSelectedPhase(
              (phase) => phase.copyWith(completionCriteria: _splitLines(value)),
            );
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('phase-review-criteria-$_selectedIndex'),
          initialValue: _linesText(phase.review.criteria),
          decoration: _fieldDecoration('Review criteria'),
          enabled: !_saving,
          minLines: 1,
          maxLines: 4,
          onChanged: (value) {
            _updateSelectedPhase(
              (phase) => phase.copyWith(
                review: ReviewPolicy(
                  required: phase.review.required,
                  reviewer: phase.review.reviewer,
                  criteria: _splitLines(value),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _setSpec(JobSpec spec) {
    setState(() {
      _spec = spec;
      _error = null;
      _clampSelectedIndex();
    });
  }

  void _setPhases(List<JobPhase> phases) {
    _setSpec(_spec.copyWith(phases: phases));
  }

  void _updateSelectedPhase(JobPhase Function(JobPhase phase) update) {
    final phase = _selectedPhase;
    if (phase == null) return;
    final phases = [..._spec.phases];
    phases[_selectedIndex] = update(phase);
    _setPhases(phases);
  }

  void _addPhase() {
    final id = _uniquePhaseId('phase_${_spec.phases.length + 1}');
    final newPhase = JobPhase(
      id: id,
      title: 'New phase',
      objective: 'Define the objective for this phase.',
      status: PhaseStatus.pending,
      inputs: const [],
      expectedOutputs: [
        PhaseOutput(
          path: '.agent/jobs/${_spec.id}/$id.md',
          required: true,
          format: ArtifactFormat.markdown,
        ),
      ],
      allowedTools: _spec.toolPolicy.defaultAllowed,
      terminalPolicy: TerminalPolicy.none,
      completionCriteria: const ['Produces the expected output artifact.'],
      review: const ReviewPolicy(required: true, reviewer: ReviewerType.hybrid),
      humanCheckpoint: false,
    );
    final phases = [..._spec.phases, newPhase];
    setState(() {
      _spec = _spec.copyWith(phases: phases);
      _selectedIndex = phases.length - 1;
      _error = null;
    });
  }

  void _duplicatePhase() {
    final phase = _selectedPhase;
    if (phase == null) return;
    final id = _uniquePhaseId('${phase.id}_copy');
    final clone = phase.copyWith(
      id: id,
      title: '${phase.title} Copy',
      status: PhaseStatus.pending,
      expectedOutputs: phase.expectedOutputs
          .map(
            (output) => PhaseOutput(
              path: _duplicateOutputPath(output.path, id),
              required: output.required,
              description: output.description,
              format: output.format,
            ),
          )
          .toList(),
    );
    final phases = [..._spec.phases]..insert(_selectedIndex + 1, clone);
    setState(() {
      _spec = _spec.copyWith(phases: phases);
      _selectedIndex += 1;
      _error = null;
    });
  }

  void _removeSelectedPhase() {
    if (_spec.phases.isEmpty) return;
    final phases = [..._spec.phases]..removeAt(_selectedIndex);
    setState(() {
      _spec = _spec.copyWith(phases: phases);
      _clampSelectedIndex();
      _error = null;
    });
  }

  void _movePhase(int delta) {
    final target = _selectedIndex + delta;
    if (target < 0 || target >= _spec.phases.length) return;
    final phases = [..._spec.phases];
    final phase = phases.removeAt(_selectedIndex);
    phases.insert(target, phase);
    setState(() {
      _spec = _spec.copyWith(phases: phases);
      _selectedIndex = target;
      _error = null;
    });
  }

  Future<void> _save() async {
    final issues = _validationIssues();
    if (issues.isNotEmpty) {
      setState(() => _error = issues.join('\n'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(_spec.copyWith(updatedAt: DateTime.now()));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  List<String> _validationIssues() {
    final issues = <String>[];
    if (_spec.title.trim().isEmpty) {
      issues.add('Job title is required.');
    }
    if (_spec.phases.isEmpty) {
      issues.add('At least one phase is required.');
    }

    final ids = <String>{};
    for (final phase in _spec.phases) {
      final id = phase.id.trim();
      final label = id.isEmpty ? '<empty>' : id;
      if (id.isEmpty) {
        issues.add('Phase ID is required.');
      } else if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
        issues.add('Phase "$label" ID must use letters, numbers, _ or -.');
      } else if (!ids.add(id)) {
        issues.add('Phase "$label" is duplicated.');
      }
      if (phase.title.trim().isEmpty) {
        issues.add('Phase "$label" title is required.');
      }
      if (phase.objective.trim().isEmpty) {
        issues.add('Phase "$label" objective is required.');
      }
      if (phase.expectedOutputs.isEmpty) {
        issues.add('Phase "$label" needs at least one expected output.');
      }
      if (phase.completionCriteria.isEmpty) {
        issues.add('Phase "$label" needs completion criteria.');
      }
    }
    return issues;
  }

  void _clampSelectedIndex() {
    if (_spec.phases.isEmpty) {
      _selectedIndex = 0;
      return;
    }
    if (_selectedIndex < 0) _selectedIndex = 0;
    if (_selectedIndex >= _spec.phases.length) {
      _selectedIndex = _spec.phases.length - 1;
    }
  }

  String _uniquePhaseId(String base) {
    final clean = base
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = clean.isEmpty ? 'phase' : clean;
    final existing = _spec.phases.map((phase) => phase.id).toSet();
    if (!existing.contains(prefix)) return prefix;
    var counter = 2;
    while (existing.contains('${prefix}_$counter')) {
      counter += 1;
    }
    return '${prefix}_$counter';
  }

  String _duplicateOutputPath(String original, String phaseId) {
    final slash = original.lastIndexOf('/');
    final directory = slash == -1 ? '' : original.substring(0, slash + 1);
    final name = slash == -1 ? original : original.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    final extension = dot == -1 ? '.md' : name.substring(dot);
    return '$directory$phaseId$extension';
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    );
  }

  static String _linesText(List<String> values) => values.join('\n');

  static String _inputsText(List<PhaseInput> inputs) {
    return inputs
        .map((input) {
          final required = input.required ? 'required' : 'optional';
          final description = input.description?.trim();
          if (description == null || description.isEmpty) {
            return '${input.path} | $required';
          }
          return '${input.path} | $required | $description';
        })
        .join('\n');
  }

  static String _outputsText(List<PhaseOutput> outputs) {
    return outputs
        .map((output) {
          final required = output.required ? 'required' : 'optional';
          final format = output.format?.wire ?? '';
          final description = output.description?.trim();
          return [
            output.path,
            required,
            format,
            if (description != null && description.isNotEmpty) description,
          ].join(' | ');
        })
        .join('\n');
  }

  static List<String> _splitLines(String value) {
    return value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static List<String> _splitList(String value) {
    return value
        .split(RegExp(r'[\n,]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<PhaseInput> _parseInputs(String value) {
    final inputs = <PhaseInput>[];
    for (final line in _splitLines(value)) {
      final parts = line.split('|').map((part) => part.trim()).toList();
      final path = parts.firstOrNull ?? '';
      if (path.isEmpty) continue;
      inputs.add(
        PhaseInput(
          path: path,
          required: _parseRequired(parts.elementAtOrNull(1), fallback: true),
          description: _optionalText(parts.skip(2).join(' | ')),
        ),
      );
    }
    return inputs;
  }

  static List<PhaseOutput> _parseOutputs(String value) {
    final outputs = <PhaseOutput>[];
    for (final line in _splitLines(value)) {
      final parts = line.split('|').map((part) => part.trim()).toList();
      final path = parts.firstOrNull ?? '';
      if (path.isEmpty) continue;
      outputs.add(
        PhaseOutput(
          path: path,
          required: _parseRequired(parts.elementAtOrNull(1), fallback: true),
          format: parseArtifactFormat(parts.elementAtOrNull(2)),
          description: _optionalText(parts.skip(3).join(' | ')),
        ),
      );
    }
    return outputs;
  }

  static bool _parseRequired(String? value, {required bool fallback}) {
    final normalised = value?.trim().toLowerCase();
    if (normalised == null || normalised.isEmpty) return fallback;
    return switch (normalised) {
      'required' || 'true' || 'yes' || 'y' || '1' => true,
      'optional' || 'false' || 'no' || 'n' || '0' => false,
      _ => fallback,
    };
  }

  static String? _optionalText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _PhaseApprovalPanel extends StatelessWidget {
  final JobSystemSettings settings;
  final JobSnapshot job;
  final JobPhase phase;
  final Future<void> Function() onApprove;

  const _PhaseApprovalPanel({
    required this.settings,
    required this.job,
    required this.phase,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reasons = _approvalReasons(settings, job, phase);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Approval Required',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _MiniChip(icon: Icons.adjust_outlined, label: phase.id),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              phase.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              reasons.isEmpty
                  ? 'This phase is waiting for explicit approval.'
                  : reasons.join(' '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MiniChip(
                  icon: Icons.terminal,
                  label: _effectiveTerminalPolicy(job.spec, phase).wire,
                ),
                if (phase.expectedOutputs.isNotEmpty)
                  _MiniChip(
                    icon: Icons.inventory_2_outlined,
                    label: '${phase.expectedOutputs.length} outputs',
                  ),
                for (final tool in _mutatingTools(phase).take(3))
                  _MiniChip(icon: Icons.edit_outlined, label: tool),
                FilledButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Approve & Run'),
                  onPressed: () => unawaited(onApprove()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftPlanPanel extends StatelessWidget {
  final ChatService chat;
  final JobSnapshot job;
  final bool canPlan;

  const _DraftPlanPanel({
    required this.chat,
    required this.job,
    required this.canPlan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requiredQuestions = job.state.openQuestions
        .where(
          (question) =>
              question.required && question.status == OpenQuestionStatus.open,
        )
        .toList();
    final ready = requiredQuestions.isEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.28),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rule_outlined,
                  size: 18,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Clarification Gate',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Generate Plan'),
                  onPressed: canPlan
                      ? () => unawaited(chat.planActiveJob())
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ready
                  ? 'Required questions are answered. Generate the app-readable JobSpec to continue.'
                  : '${requiredQuestions.length} required question${requiredQuestions.length == 1 ? '' : 's'} must be answered before planning.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ready
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryDashboard extends StatelessWidget {
  final ChatService chat;
  final JobSnapshot job;
  final JobPhase? pendingPhase;
  final bool canRun;
  final bool canRetry;
  final bool canSkip;
  final Future<void> Function() onRunNext;
  final Future<void> Function() onReplanCurrent;
  final Future<void> Function() onReplanRemaining;

  const _RecoveryDashboard({
    required this.chat,
    required this.job,
    required this.pendingPhase,
    required this.canRun,
    required this.canRetry,
    required this.canSkip,
    required this.onRunNext,
    required this.onReplanCurrent,
    required this.onReplanRemaining,
  });

  static bool shouldShow(JobSnapshot job) {
    final hasProblemStatus =
        job.state.status == JobStatus.blocked ||
        job.state.status == JobStatus.failed ||
        job.spec.status == JobStatus.blocked ||
        job.spec.status == JobStatus.failed;
    final hasProblemPhase = job.spec.phases.any(
      (phase) =>
          phase.status == PhaseStatus.blocked ||
          phase.status == PhaseStatus.failed,
    );
    final hasOpenRequiredQuestion = job.state.openQuestions.any(
      (question) =>
          question.required && question.status == OpenQuestionStatus.open,
    );
    final hasProblemRun = _latestProblemRun(job) != null;
    return hasProblemStatus ||
        hasProblemPhase ||
        hasOpenRequiredQuestion ||
        job.state.risks.isNotEmpty ||
        hasProblemRun;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items();
    final recommendation = _recommendation();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.28),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.build_circle_outlined,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recovery',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                _MiniChip(
                  icon: Icons.flag_outlined,
                  label: job.state.status.wire,
                ),
                if (pendingPhase != null) ...[
                  const SizedBox(width: 6),
                  _MiniChip(
                    icon: Icons.adjust_outlined,
                    label: pendingPhase!.id,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              recommendation,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final item in items.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _RecoveryItemRow(item: item),
                ),
              if (items.length > 6)
                Text(
                  '${items.length - 6} more recovery note${items.length == 7 ? '' : 's'} in job state.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.replay),
                  label: const Text('Retry Phase'),
                  onPressed: canRetry
                      ? () => unawaited(chat.retryJobPhase())
                      : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.low_priority_outlined),
                  label: const Text('Replan Current'),
                  onPressed: chat.jobBusy || pendingPhase == null
                      ? null
                      : () => unawaited(onReplanCurrent()),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('Replan Remaining'),
                  onPressed: chat.jobBusy || pendingPhase == null
                      ? null
                      : () => unawaited(onReplanRemaining()),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run Next'),
                  onPressed: canRun ? () => unawaited(onRunNext()) : null,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Skip Phase'),
                  onPressed: canSkip
                      ? () => unawaited(chat.skipJobPhase())
                      : null,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload State'),
                  onPressed: chat.jobBusy
                      ? null
                      : () => unawaited(chat.reloadJobs()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _recommendation() {
    final requiredQuestions = job.state.openQuestions
        .where(
          (question) =>
              question.required && question.status == OpenQuestionStatus.open,
        )
        .toList();
    if (requiredQuestions.isNotEmpty) {
      return 'Answer the required question${requiredQuestions.length == 1 ? '' : 's'} before execution can continue.';
    }

    final latestRun = _latestProblemRun(job);
    final review = latestRun?.reviewResult;
    if (review != null) {
      return switch (review.recommendation) {
        ReviewRecommendation.retryPhase =>
          'The latest review recommends retrying the current phase.',
        ReviewRecommendation.askUser =>
          'The latest review needs user input before this job can continue.',
        ReviewRecommendation.revisePlan =>
          'The latest review recommends replanning before continuing.',
        ReviewRecommendation.stopJob =>
          'The latest review recommends stopping this job.',
        ReviewRecommendation.continueJob =>
          'Review passed with warnings. Inspect the notes before continuing.',
      };
    }

    final summary = job.state.latestSummary.trim();
    if (summary.contains('missing') || summary.contains('empty')) {
      return 'A required artifact or input is missing. Retry the producing phase, or replan if the artifact is no longer needed.';
    }
    if (summary.contains('interrupted') || summary.contains('Recovered')) {
      return 'The job was recovered from an interrupted state. Retry the current phase to continue.';
    }
    if (job.state.status == JobStatus.failed) {
      return 'The job failed. Retry the current phase, replan, or stop the job.';
    }
    return 'The job is blocked. Review the notes and choose a recovery action.';
  }

  List<_RecoveryItem> _items() {
    final seen = <String>{};
    final items = <_RecoveryItem>[];
    void add(_RecoverySeverity severity, String title, String? detail) {
      final normalized = '$title\n${detail ?? ''}'.trim();
      if (normalized.isEmpty || !seen.add(normalized)) return;
      items.add(
        _RecoveryItem(severity: severity, title: title, detail: detail),
      );
    }

    final summary = job.state.latestSummary.trim();
    if (summary.isNotEmpty) {
      add(_RecoverySeverity.warning, 'Current state', summary);
    }

    for (final question in job.state.openQuestions.where(
      (question) => question.status == OpenQuestionStatus.open,
    )) {
      add(
        question.required ? _RecoverySeverity.error : _RecoverySeverity.info,
        question.required ? 'Required question' : 'Optional question',
        question.question,
      );
    }

    for (final risk in job.state.risks) {
      add(_RecoverySeverity.warning, 'Recovery note', risk);
    }

    final blockedPhases = job.spec.phases.where(
      (phase) =>
          phase.status == PhaseStatus.blocked ||
          phase.status == PhaseStatus.failed,
    );
    for (final phase in blockedPhases) {
      add(
        _RecoverySeverity.error,
        'Phase ${phase.status.wire}',
        '${phase.id}: ${phase.title}',
      );
    }

    final latestRun = _latestProblemRun(job);
    if (latestRun != null) {
      add(
        _RecoverySeverity.error,
        'Latest run ${latestRun.status.wire}',
        latestRun.error ?? latestRun.summary,
      );
      final review = latestRun.reviewResult;
      if (review != null) {
        add(
          review.status == ReviewStatus.warning
              ? _RecoverySeverity.warning
              : _RecoverySeverity.error,
          'Review ${review.status.wire}',
          review.summary,
        );
        for (final issue in review.issues.take(4)) {
          add(
            issue.severity == 'info'
                ? _RecoverySeverity.info
                : issue.severity == 'warning'
                ? _RecoverySeverity.warning
                : _RecoverySeverity.error,
            'Review issue',
            issue.suggestedAction == null
                ? issue.message
                : '${issue.message} Suggested: ${issue.suggestedAction}',
          );
        }
      }
    }

    return items;
  }

  static PhaseRun? _latestProblemRun(JobSnapshot job) {
    for (final run in job.state.phaseRuns.reversed) {
      final reviewStatus = run.reviewResult?.status;
      if (run.status == PhaseRunStatus.failed ||
          run.status == PhaseRunStatus.blocked ||
          run.status == PhaseRunStatus.reviewFailed ||
          reviewStatus == ReviewStatus.failed ||
          reviewStatus == ReviewStatus.blocked ||
          reviewStatus == ReviewStatus.warning) {
        return run;
      }
    }
    return null;
  }
}

enum _RecoverySeverity { info, warning, error }

class _RecoveryItem {
  final _RecoverySeverity severity;
  final String title;
  final String? detail;

  const _RecoveryItem({
    required this.severity,
    required this.title,
    this.detail,
  });
}

class _RecoveryItemRow extends StatelessWidget {
  final _RecoveryItem item;

  const _RecoveryItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color(theme);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(_icon(), size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.title,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              if (item.detail != null && item.detail!.trim().isNotEmpty)
                Text(
                  item.detail!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _icon() {
    return switch (item.severity) {
      _RecoverySeverity.info => Icons.info_outline,
      _RecoverySeverity.warning => Icons.warning_amber_outlined,
      _RecoverySeverity.error => Icons.error_outline,
    };
  }

  Color _color(ThemeData theme) {
    return switch (item.severity) {
      _RecoverySeverity.info => theme.colorScheme.primary,
      _RecoverySeverity.warning => theme.colorScheme.tertiary,
      _RecoverySeverity.error => theme.colorScheme.error,
    };
  }
}

class _PendingFileApprovals extends StatelessWidget {
  final ChatService chat;
  final JobSnapshot job;

  const _PendingFileApprovals({required this.chat, required this.job});

  @override
  Widget build(BuildContext context) {
    final approvals = job.state.pendingApprovals
        .where((approval) => approval.status == 'pending')
        .toList();
    if (approvals.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.28),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.difference_outlined,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'File Change Approval',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _MiniChip(
                  icon: Icons.pending_actions_outlined,
                  label: '${approvals.length} pending',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'The phase proposed file edits. Select hunks to apply, or reject the proposal.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final approval in approvals)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PendingFileApprovalCard(chat: chat, approval: approval),
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingFileApprovalCard extends StatefulWidget {
  final ChatService chat;
  final PendingFileApproval approval;

  const _PendingFileApprovalCard({required this.chat, required this.approval});

  @override
  State<_PendingFileApprovalCard> createState() =>
      _PendingFileApprovalCardState();
}

class _PendingFileApprovalCardState extends State<_PendingFileApprovalCard> {
  late Set<String> _selectedHunks = {
    for (final hunk in widget.approval.hunks) hunk.id,
  };

  @override
  void didUpdateWidget(covariant _PendingFileApprovalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.approval.id != widget.approval.id) {
      _selectedHunks = {for (final hunk in widget.approval.hunks) hunk.id};
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approval = widget.approval;
    final selectedCount = _selectedHunks.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              approval.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MiniChip(
                  icon: Icons.checklist_outlined,
                  label: '$selectedCount/${approval.hunks.length} selected',
                ),
                _MiniChip(icon: Icons.build_outlined, label: approval.toolName),
                _MiniChip(icon: Icons.edit_note, label: approval.changeType),
              ],
            ),
            if (approval.summary != null) ...[
              const SizedBox(height: 4),
              Text(approval.summary!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            for (final hunk in approval.hunks)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ExpansionTile(
                    dense: true,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    leading: Checkbox(
                      value: _selectedHunks.contains(hunk.id),
                      onChanged: widget.chat.jobBusy
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedHunks.add(hunk.id);
                                } else {
                                  _selectedHunks.remove(hunk.id);
                                }
                              });
                            },
                    ),
                    title: Text(
                      hunk.summary ??
                          '+${hunk.newLines.length}/-${hunk.oldLines.length} lines',
                      style: theme.textTheme.labelSmall,
                    ),
                    subtitle: Text(
                      '@@ -${hunk.oldStart + 1} +${hunk.newStart + 1} @@',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    children: [_DiffPreview(diff: hunk.diff)],
                  ),
                ),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('Reject All'),
                  onPressed: widget.chat.jobBusy
                      ? null
                      : () => unawaited(
                          widget.chat.resolveFileApproval(
                            approval.id,
                            const <String>{},
                          ),
                        ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.select_all),
                  label: const Text('Select All'),
                  onPressed: widget.chat.jobBusy
                      ? null
                      : () {
                          setState(() {
                            _selectedHunks = {
                              for (final hunk in approval.hunks) hunk.id,
                            };
                          });
                        },
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Apply Selected'),
                  onPressed: widget.chat.jobBusy || _selectedHunks.isEmpty
                      ? null
                      : () => unawaited(
                          widget.chat.resolveFileApproval(
                            approval.id,
                            _selectedHunks,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffPreview extends StatelessWidget {
  final String diff;

  const _DiffPreview({required this.diff});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.35,
      color: theme.colorScheme.onSurface,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SelectableText.rich(
            TextSpan(
              style: baseStyle,
              children: [
                for (final line in diff.split('\n'))
                  TextSpan(text: '$line\n', style: _lineStyle(theme, line)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle? _lineStyle(ThemeData theme, String line) {
    if (line.startsWith('@@')) {
      return TextStyle(
        color: theme.colorScheme.tertiary,
        fontWeight: FontWeight.w700,
      );
    }
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return TextStyle(color: theme.colorScheme.primary);
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return TextStyle(color: theme.colorScheme.error);
    }
    return null;
  }
}

class _ArtifactEntry {
  final String path;
  final bool internal;
  final bool produced;
  final bool required;
  final String? phaseId;
  final String? description;
  final ArtifactFormat? format;

  const _ArtifactEntry({
    required this.path,
    required this.internal,
    required this.produced,
    required this.required,
    this.phaseId,
    this.description,
    this.format,
  });

  bool get canOpen => internal || produced;
}

class _Artifacts extends StatelessWidget {
  final ChatService chat;
  final JobSnapshot job;

  const _Artifacts({required this.chat, required this.job});

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    if (entries.isEmpty) return const SizedBox.shrink();

    final outputs = entries.where((entry) => !entry.internal).toList();
    final metadata = entries.where((entry) => entry.internal).toList();
    final producedOutputs = outputs.where((entry) => entry.produced).length;
    final requiredPending = outputs
        .where((entry) => entry.required && !entry.produced)
        .length;
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
                Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Artifacts',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _MiniChip(
                  icon: Icons.check_circle_outline,
                  label: '$producedOutputs/${outputs.length} outputs',
                ),
                if (requiredPending > 0) ...[
                  const SizedBox(width: 6),
                  _MiniChip(
                    icon: Icons.pending_actions_outlined,
                    label: '$requiredPending required pending',
                  ),
                ],
              ],
            ),
            if (outputs.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ArtifactGroup(
                chat: chat,
                title: 'Phase Outputs',
                entries: outputs,
              ),
            ],
            if (metadata.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ArtifactGroup(
                chat: chat,
                title: 'Job Metadata',
                entries: metadata,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_ArtifactEntry> _entries() {
    final producedByPath = {
      for (final artifact in job.state.artifacts) artifact.path: artifact,
    };
    final entries = <_ArtifactEntry>[];
    final expectedPaths = <String>{};

    for (final phase in job.spec.phases) {
      for (final output in phase.expectedOutputs) {
        expectedPaths.add(output.path);
        final produced = producedByPath[output.path];
        entries.add(
          _ArtifactEntry(
            path: output.path,
            internal: false,
            produced: produced != null,
            required: output.required,
            phaseId: produced?.producedByPhaseId ?? phase.id,
            description: output.description ?? produced?.description,
            format: output.format,
          ),
        );
      }
    }

    for (final artifact in job.state.artifacts) {
      if (expectedPaths.contains(artifact.path)) continue;
      entries.add(
        _ArtifactEntry(
          path: artifact.path,
          internal: false,
          produced: true,
          required: false,
          phaseId: artifact.producedByPhaseId,
          description: artifact.description,
        ),
      );
    }

    entries.sort((a, b) => a.path.compareTo(b.path));
    return [
      ...entries,
      _ArtifactEntry(
        path: '.agent/jobs/${job.spec.id}/task-brief.yaml',
        internal: true,
        produced: true,
        required: true,
        description: 'Task brief',
        format: ArtifactFormat.yaml,
      ),
      _ArtifactEntry(
        path: '.agent/jobs/${job.spec.id}/job-spec.yaml',
        internal: true,
        produced: true,
        required: true,
        description: 'Executable job spec',
        format: ArtifactFormat.yaml,
      ),
      _ArtifactEntry(
        path: '.agent/jobs/${job.spec.id}/job-state.yaml',
        internal: true,
        produced: true,
        required: true,
        description: 'Current job state',
        format: ArtifactFormat.yaml,
      ),
      _ArtifactEntry(
        path: '.agent/jobs/${job.spec.id}/refined-prompt.md',
        internal: true,
        produced: true,
        required: false,
        description: 'Rendered task brief',
        format: ArtifactFormat.markdown,
      ),
    ];
  }
}

class _ArtifactGroup extends StatelessWidget {
  final ChatService chat;
  final String title;
  final List<_ArtifactEntry> entries;

  const _ArtifactGroup({
    required this.chat,
    required this.title,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) Divider(height: 1, color: theme.dividerColor),
          _ArtifactRow(chat: chat, entry: entries[index]),
        ],
      ],
    );
  }
}

class _ArtifactRow extends StatelessWidget {
  final ChatService chat;
  final _ArtifactEntry entry;

  const _ArtifactRow({required this.chat, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.produced
        ? theme.colorScheme.primary
        : entry.required
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_icon(), size: 18, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  entry.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _MiniChip(
            icon: entry.produced
                ? Icons.check_circle_outline
                : Icons.schedule_outlined,
            label: entry.produced ? 'produced' : 'pending',
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open'),
            onPressed: chat.jobBusy || !entry.canOpen
                ? null
                : () => unawaited(_openArtifact(context)),
          ),
        ],
      ),
    );
  }

  IconData _icon() {
    if (entry.internal) return Icons.settings_suggest_outlined;
    if (entry.produced) return Icons.insert_drive_file_outlined;
    return Icons.description_outlined;
  }

  String _subtitle() {
    final parts = <String>[
      entry.internal
          ? 'job metadata'
          : entry.phaseId == null
          ? 'phase output'
          : 'phase ${entry.phaseId}',
      entry.required ? 'required' : 'optional',
      if (entry.format != null) entry.format!.wire,
      if (entry.description != null && entry.description!.trim().isNotEmpty)
        entry.description!.trim(),
    ];
    return parts.join(' - ');
  }

  Future<void> _openArtifact(BuildContext context) async {
    try {
      final content = await chat.readJobArtifact(entry.path);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(
              entry.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860, maxHeight: 560),
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
          );
        },
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open artifact: $e')));
    }
  }
}

class _RecentActivity extends StatelessWidget {
  final JobSnapshot job;

  const _RecentActivity({required this.job});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runs = job.state.phaseRuns.reversed.take(5).toList();

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
                Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recent Activity',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (job.state.risks.isNotEmpty) ...[
              const SizedBox(height: 8),
              _RiskList(risks: job.state.risks.take(3).toList()),
            ],
            if (runs.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final run in runs) _PhaseRunRow(job: job, run: run),
            ],
          ],
        ),
      ),
    );
  }
}

class _RiskList extends StatelessWidget {
  final List<String> risks;

  const _RiskList({required this.risks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recovery Notes',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 4),
            for (final risk in risks)
              Text(
                '- $risk',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhaseRunRow extends StatelessWidget {
  final JobSnapshot job;
  final PhaseRun run;

  const _PhaseRunRow({required this.job, required this.run});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phaseTitle = job.spec.phases
        .where((phase) => phase.id == run.phaseId)
        .map((phase) => phase.title)
        .firstOrNull;
    final review = run.reviewResult;
    final toolErrors = run.toolCalls
        .where((call) => call.error != null)
        .toList();
    final failedChecks =
        review?.deterministicChecks.where((check) => !check.passed).length ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: _statusColor(theme, run.status, review?.status),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _statusIcon(run.status, review?.status),
                    size: 18,
                    color: _statusColor(theme, run.status, review?.status),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          phaseTitle == null
                              ? run.phaseId
                              : '${run.phaseId} - $phaseTitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (run.summary.trim().isNotEmpty)
                          Text(
                            run.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        if (toolErrors.isNotEmpty)
                          Text(
                            '${toolErrors.length} tool error${toolErrors.length == 1 ? '' : 's'}: ${toolErrors.first.toolName} - ${toolErrors.first.error}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.article_outlined, size: 16),
                    label: const Text('Details'),
                    onPressed: () => _showDetails(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MiniChip(
                    icon: Icons.build_outlined,
                    label: '${run.toolCalls.length} tools',
                  ),
                  if (toolErrors.isNotEmpty)
                    _AlertMiniChip(
                      icon: Icons.report_problem_outlined,
                      label:
                          '${toolErrors.length} error${toolErrors.length == 1 ? '' : 's'}',
                    ),
                  _MiniChip(
                    icon: Icons.menu_book_outlined,
                    label: '${run.filesRead.length} read',
                  ),
                  _MiniChip(
                    icon: Icons.edit_note,
                    label:
                        '${run.filesWritten.length + run.filesPatched.length} changed',
                  ),
                  _MiniChip(
                    icon: Icons.terminal,
                    label: '${run.terminalCommands.length} commands',
                  ),
                  if (review != null)
                    _MiniChip(
                      icon: Icons.rate_review_outlined,
                      label: 'review ${review.status.wire}',
                    ),
                  if (failedChecks > 0)
                    _AlertMiniChip(
                      icon: Icons.rule_folder_outlined,
                      label:
                          '$failedChecks failed check${failedChecks == 1 ? '' : 's'}',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Phase Run: ${run.phaseId}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 560),
            child: SingleChildScrollView(
              child: SelectableText(
                _detailsText(),
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
        );
      },
    );
  }

  String _detailsText() {
    final buffer = StringBuffer()
      ..writeln('Phase: ${run.phaseId}')
      ..writeln('Run: ${run.runId}')
      ..writeln('Status: ${run.status.wire}')
      ..writeln('Started: ${run.startedAt.toLocal().toIso8601String()}');
    if (run.completedAt != null) {
      buffer.writeln(
        'Completed: ${run.completedAt!.toLocal().toIso8601String()}',
      );
    }
    if (run.error != null) {
      buffer.writeln('Error: ${run.error}');
    }
    if (run.summary.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Summary:')
        ..writeln(run.summary);
    }

    _writeList(buffer, 'Files read', run.filesRead);
    _writeList(buffer, 'Files written', run.filesWritten);
    _writeList(buffer, 'Files patched', run.filesPatched);
    _writeFileChanges(buffer, run.fileChanges);
    _writeTerminalCommands(buffer, run.terminalCommands);
    _writeToolCallErrors(buffer, run.toolCalls);

    if (run.toolCalls.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Tool calls:');
      for (final call in run.toolCalls) {
        buffer.writeln('- ${call.toolName} (${call.id})');
        if (call.arguments != null) {
          buffer.writeln('  args: ${_formatToolValue(call.arguments)}');
        }
        if (call.error != null) buffer.writeln('  error: ${call.error}');
        if (call.resultSummary != null) {
          buffer.writeln('  result: ${call.resultSummary}');
        }
      }
    }

    final review = run.reviewResult;
    if (review != null) {
      buffer
        ..writeln()
        ..writeln('Review:')
        ..writeln('Status: ${review.status.wire}')
        ..writeln('Recommendation: ${review.recommendation.wire}')
        ..writeln('Summary: ${review.summary}');
      if (review.deterministicChecks.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('Deterministic checks:');
        for (final check in review.deterministicChecks) {
          buffer.writeln('- ${check.passed ? 'pass' : 'fail'} ${check.id}');
          buffer.writeln('  ${check.message}');
        }
      }
      if (review.issues.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('Issues:');
        for (final issue in review.issues) {
          buffer.writeln('- ${issue.severity}: ${issue.message}');
          if (issue.suggestedAction != null) {
            buffer.writeln('  suggested: ${issue.suggestedAction}');
          }
        }
      }
    }

    return buffer.toString().trim();
  }

  void _writeList(StringBuffer buffer, String title, List<String> values) {
    if (values.isEmpty) return;
    buffer
      ..writeln()
      ..writeln('$title:');
    for (final value in values) {
      buffer.writeln('- $value');
    }
  }

  void _writeTerminalCommands(StringBuffer buffer, List<String> commands) {
    if (commands.isEmpty) return;
    buffer
      ..writeln()
      ..writeln('Terminal commands:');
    for (final command in commands) {
      final commandClass = TerminalCommandClassifier.classify(command);
      buffer.writeln('- [${commandClass.wire}] $command');
    }
  }

  void _writeToolCallErrors(
    StringBuffer buffer,
    List<ToolCallRecord> toolCalls,
  ) {
    final errors = toolCalls.where((call) => call.error != null).toList();
    if (errors.isEmpty) return;
    buffer
      ..writeln()
      ..writeln('Tool call errors:');
    for (final call in errors) {
      buffer.writeln('- ${call.toolName} (${call.id})');
      if (call.arguments != null) {
        buffer.writeln('  args: ${_formatToolValue(call.arguments)}');
      }
      buffer.writeln('  error: ${call.error}');
      if (call.resultSummary != null) {
        buffer.writeln('  result: ${call.resultSummary}');
      }
    }
  }

  void _writeFileChanges(StringBuffer buffer, List<FileChangeSummary> changes) {
    if (changes.isEmpty) return;
    buffer
      ..writeln()
      ..writeln('File change previews:');
    for (final change in changes) {
      buffer.writeln(
        '- [${change.changeType}] ${change.path} via ${change.toolName} (+${change.addedLines}/-${change.removedLines})',
      );
      if (change.summary != null) buffer.writeln('  ${change.summary}');
      if (change.diff != null && change.diff!.trim().isNotEmpty) {
        buffer
          ..writeln('  diff:')
          ..writeln(
            change.diff!.split('\n').map((line) => '    $line').join('\n'),
          );
      }
    }
  }

  Color _statusColor(
    ThemeData theme,
    PhaseRunStatus status,
    ReviewStatus? reviewStatus,
  ) {
    if (reviewStatus == ReviewStatus.failed ||
        reviewStatus == ReviewStatus.blocked ||
        status == PhaseRunStatus.failed ||
        status == PhaseRunStatus.reviewFailed) {
      return theme.colorScheme.error;
    }
    if (reviewStatus == ReviewStatus.warning ||
        status == PhaseRunStatus.blocked) {
      return theme.colorScheme.tertiary;
    }
    if (status == PhaseRunStatus.completed) return theme.colorScheme.primary;
    return theme.colorScheme.onSurfaceVariant;
  }

  IconData _statusIcon(PhaseRunStatus status, ReviewStatus? reviewStatus) {
    if (reviewStatus == ReviewStatus.failed ||
        reviewStatus == ReviewStatus.blocked ||
        status == PhaseRunStatus.failed ||
        status == PhaseRunStatus.reviewFailed) {
      return Icons.error_outline;
    }
    if (reviewStatus == ReviewStatus.warning ||
        status == PhaseRunStatus.blocked) {
      return Icons.warning_amber_outlined;
    }
    if (status == PhaseRunStatus.completed) return Icons.check_circle_outline;
    return Icons.sync;
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _TaskBriefSummary extends StatelessWidget {
  final JobSnapshot job;

  const _TaskBriefSummary({required this.job});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assumptions = {
      ...job.taskBrief.assumptions,
      ...job.state.assumptions,
    }.where((assumption) => assumption.trim().isNotEmpty).toList();

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
                Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Task Brief',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(job.taskBrief.objective, style: theme.textTheme.bodySmall),
            if (assumptions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final assumption in assumptions.take(4))
                    _MetaChip(
                      icon: Icons.psychology_alt_outlined,
                      label: assumption,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OpenQuestions extends StatelessWidget {
  final ChatService chat;
  final JobSnapshot job;

  const _OpenQuestions({required this.chat, required this.job});

  @override
  Widget build(BuildContext context) {
    final questions = job.state.openQuestions
        .where((question) => question.status == OpenQuestionStatus.open)
        .toList();
    final requiredQuestions = questions
        .where((question) => question.required)
        .toList();
    final optionalQuestions = questions
        .where((question) => !question.required)
        .toList();
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
                Icon(
                  Icons.help_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Clarification Gate',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (optionalQuestions.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Proceed With Assumptions'),
                    onPressed: chat.jobBusy
                        ? null
                        : () => unawaited(chat.dismissOptionalJobQuestions()),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (job.taskBrief.assumptions.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final assumption in job.taskBrief.assumptions.take(3))
                    _MetaChip(
                      icon: Icons.psychology_alt_outlined,
                      label: assumption,
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (requiredQuestions.isNotEmpty)
              Text(
                '${requiredQuestions.length} required question${requiredQuestions.length == 1 ? '' : 's'} must be answered before planning or execution continues.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (optionalQuestions.isNotEmpty)
              Text(
                'Optional questions can be answered or dismissed using their default assumptions.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (questions.isNotEmpty) const SizedBox(height: 8),
            for (final question in questions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _QuestionRow(
                  chat: chat,
                  question: question,
                  briefQuestion: _briefQuestion(question.id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  ClarifyingQuestion? _briefQuestion(String questionId) {
    for (final question in job.taskBrief.clarifyingQuestions) {
      if (question.id == questionId) return question;
    }
    return null;
  }
}

class _QuestionRow extends StatelessWidget {
  final ChatService chat;
  final OpenQuestion question;
  final ClarifyingQuestion? briefQuestion;

  const _QuestionRow({
    required this.chat,
    required this.question,
    required this.briefQuestion,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultAssumption = briefQuestion?.defaultAssumption?.trim();
    final impact = briefQuestion?.impactIfUnanswered ?? question.reason;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            question.required ? Icons.priority_high : Icons.info_outline,
            size: 16,
            color: question.required
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(question.question, style: theme.textTheme.bodySmall),
              if (defaultAssumption != null &&
                  defaultAssumption.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  'Default: $defaultAssumption',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (impact != null && impact.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  impact,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Answer'),
              onPressed: chat.jobBusy
                  ? null
                  : () => unawaited(_answer(context, question)),
            ),
            if (!question.required)
              TextButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  defaultAssumption == null || defaultAssumption.isEmpty
                      ? 'Dismiss'
                      : 'Use Assumption',
                ),
                onPressed: chat.jobBusy
                    ? null
                    : () => unawaited(chat.dismissJobQuestion(question.id)),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _answer(BuildContext context, OpenQuestion question) async {
    final controller = TextEditingController(text: question.answer ?? '');
    final answer = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Answer Question'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: question.required ? 'Required answer' : 'Answer',
              helperText: question.reason,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Save'),
              onPressed: () => Navigator.of(context).pop(controller.text),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (answer == null || answer.trim().isEmpty) return;
    await chat.answerJobQuestion(question.id, answer);
  }
}

class _PhaseTimeline extends StatelessWidget {
  final JobSnapshot job;

  const _PhaseTimeline({required this.job});

  @override
  Widget build(BuildContext context) {
    final phases = job.spec.phases;
    final completed = phases
        .where((phase) => phase.status == PhaseStatus.completed)
        .length;
    final blocked = phases
        .where(
          (phase) =>
              phase.status == PhaseStatus.blocked ||
              phase.status == PhaseStatus.failed,
        )
        .length;
    final currentPhaseId = job.state.currentPhaseId;
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
                Icon(
                  Icons.route_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Phase Timeline',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _MiniChip(
                  icon: Icons.check_circle_outline,
                  label: '$completed/${phases.length} complete',
                ),
                if (blocked > 0) ...[
                  const SizedBox(width: 6),
                  _MiniChip(
                    icon: Icons.warning_amber_outlined,
                    label: '$blocked blocked',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: phases.isEmpty ? 0 : completed / phases.length,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 142,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: phases.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final phase = phases[index];
                  final lastRun = job.state.phaseRuns.reversed
                      .where((run) => run.phaseId == phase.id)
                      .firstOrNull;
                  return _PhaseTimelineTile(
                    index: index,
                    phase: phase,
                    lastRun: lastRun,
                    current: phase.id == currentPhaseId,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseTimelineTile extends StatelessWidget {
  final int index;
  final JobPhase phase;
  final PhaseRun? lastRun;
  final bool current;

  const _PhaseTimelineTile({
    required this.index,
    required this.phase,
    required this.lastRun,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color(theme);
    final outputCount = phase.expectedOutputs.length;
    final toolCount = phase.allowedTools.length;
    final runStatus =
        lastRun?.reviewResult?.status.wire ?? lastRun?.status.wire;

    return SizedBox(
      width: 286,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: current
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
          border: Border.all(
            color: current ? color : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(_icon(), size: 18, color: color),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${index + 1}. ${phase.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _PhaseStatusPill(label: phase.status.wire, color: color),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                phase.objective,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  _MiniChip(
                    icon: Icons.inventory_2_outlined,
                    label: '$outputCount output${outputCount == 1 ? '' : 's'}',
                  ),
                  _MiniChip(
                    icon: Icons.build_outlined,
                    label: '$toolCount tool${toolCount == 1 ? '' : 's'}',
                  ),
                  _MiniChip(
                    icon: Icons.terminal,
                    label: phase.terminalPolicy.wire,
                  ),
                  _MiniChip(
                    icon: Icons.rate_review_outlined,
                    label: phase.review.reviewer.wire,
                  ),
                  if (runStatus != null)
                    _MiniChip(icon: Icons.history, label: 'last $runStatus'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _icon() => switch (phase.status) {
    PhaseStatus.completed => Icons.check_circle,
    PhaseStatus.running => Icons.sync,
    PhaseStatus.reviewing => Icons.rate_review_outlined,
    PhaseStatus.failed => Icons.error_outline,
    PhaseStatus.blocked => Icons.block,
    PhaseStatus.skipped => Icons.skip_next,
    PhaseStatus.pending => Icons.radio_button_unchecked,
  };

  Color _color(ThemeData theme) => switch (phase.status) {
    PhaseStatus.completed => theme.colorScheme.primary,
    PhaseStatus.running => theme.colorScheme.primary,
    PhaseStatus.reviewing => theme.colorScheme.tertiary,
    PhaseStatus.failed => theme.colorScheme.error,
    PhaseStatus.blocked => theme.colorScheme.error,
    PhaseStatus.skipped => theme.colorScheme.onSurfaceVariant,
    PhaseStatus.pending => theme.colorScheme.onSurfaceVariant,
  };
}

class _PhaseStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _PhaseStatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AlertMiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AlertMiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.42),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.38),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.error),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatToolValue(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}

class _StatusChip extends StatelessWidget {
  final JobStatus? status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = _color(theme);
    return Chip(
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.45)),
      backgroundColor: color.withValues(alpha: 0.12),
      label: Text(
        status!.wire,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _color(ThemeData theme) => switch (status) {
    JobStatus.completed => theme.colorScheme.primary,
    JobStatus.running => theme.colorScheme.primary,
    JobStatus.paused ||
    JobStatus.planned ||
    JobStatus.draft => theme.colorScheme.onSurfaceVariant,
    JobStatus.blocked || JobStatus.failed => theme.colorScheme.error,
    JobStatus.cancelled => theme.colorScheme.onSurfaceVariant,
    null => theme.colorScheme.onSurfaceVariant,
  };
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}
