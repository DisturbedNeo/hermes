import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/a11y.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/project_system/project_scheduler.dart';
import 'package:hermes/ui/chat/task_panel_dialogs.dart';

class ProjectOutcomeSection extends StatelessWidget {
  final ProjectDocument project;

  const ProjectOutcomeSection({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final currentTask = project.activeTaskId == null
        ? null
        : project.taskById(project.activeTaskId!);
    final activeRequired = project.criteria
        .where(
          (item) =>
              item.required &&
              item.status != ProjectCriterionStatus.invalidated,
        )
        .toList();
    final satisfied = activeRequired
        .where((item) => item.status == ProjectCriterionStatus.satisfied)
        .length;
    final partial = activeRequired
        .where((item) => item.status == ProjectCriterionStatus.partial)
        .length;
    final invalidated = project.criteria
        .where((item) => item.status == ProjectCriterionStatus.invalidated)
        .length;
    final remaining = activeRequired.length - satisfied - partial;
    final progress = activeRequired.isEmpty
        ? project.criteria.isEmpty
              ? 0.0
              : 1.0
        : satisfied / activeRequired.length;
    final activeMilestone = project.milestones.where((item) {
      return item.status == ProjectMilestoneStatus.active;
    }).firstOrNull;
    final latestRevision = project.planHistory.isEmpty
        ? null
        : project.planHistory.last;

    return _ProjectSectionCard(
      key: const ValueKey('project-outcome-section'),
      icon: Icons.flag_outlined,
      title: 'Outcome Progress',
      semanticLabel: 'Project outcome progress',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(project.refinedGoal),
          const SizedBox(height: 8),
          Semantics(
            label:
                '$satisfied of ${activeRequired.length} active required criteria satisfied',
            value: activeRequired.isEmpty
                ? 'No required criteria'
                : '${(progress * 100).round()} percent',
            child: LinearProgressIndicator(value: progress),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatusPill(label: 'Satisfied $satisfied'),
              _StatusPill(label: 'Partial $partial'),
              _StatusPill(label: 'Invalidated $invalidated'),
              _StatusPill(label: 'Remaining $remaining'),
            ],
          ),
          const SizedBox(height: 10),
          _LabelValue(label: 'Status', value: _humanize(project.status.name)),
          _LabelValue(
            label: 'Active milestone',
            value: activeMilestone?.title ?? 'No active milestone',
          ),
          _LabelValue(
            label: 'Current task',
            value: currentTask?.title ?? 'No task is currently running',
          ),
          if (project.pendingPlanApproval != null)
            _LabelValue(
              label: 'Approval needed',
              value:
                  'Plan revision ${project.pendingPlanApproval!.revision}: '
                  '${project.pendingPlanApproval!.reason}',
            )
          else if (project.blocker != null)
            _LabelValue(
              label: 'Blocked',
              value:
                  '${_humanize(project.blocker!.type.name)}: '
                  '${project.blocker!.message}',
            ),
          if (latestRevision != null)
            _LabelValue(
              label: 'Latest revision',
              value:
                  '${latestRevision.revision}: ${latestRevision.summary} '
                  '(${_humanize(latestRevision.trigger.name)})',
            ),
          _LabelValue(
            label: 'Diagnostics',
            value:
                '${project.diagnostics.taskExecutions} task runs · '
                '${project.diagnostics.planRevisionAttempts} replans · '
                '${project.diagnostics.projectModelCalls} project model calls · '
                '${project.diagnostics.completedTasksWithoutCriterionProgress} '
                'completed without criterion progress',
          ),
          const SizedBox(height: 8),
          if (project.criteria.isEmpty)
            const Text('No outcome criteria have been recorded yet.')
          else
            for (final criterion in project.criteria)
              _CriterionTile(
                criterion: criterion,
                evidenceCount: project.evidence
                    .where((item) => item.criterionIds.contains(criterion.id))
                    .length,
              ),
        ],
      ),
    );
  }
}

class _CriterionTile extends StatelessWidget {
  final ProjectCriterion criterion;
  final int evidenceCount;

  const _CriterionTile({required this.criterion, required this.evidenceCount});

  @override
  Widget build(BuildContext context) {
    return AccessibleWidget(
      label:
          'Criterion ${criterion.statement}, status '
          '${_humanize(criterion.status.name)}, '
          '$evidenceCount evidence items',
      child: ListTile(
        key: ValueKey('criterion-${criterion.id}'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(_criterionIcon(criterion.status)),
        title: Text(criterion.statement),
        subtitle: Text(
          [
            '${_humanize(criterion.status.name)} · '
                '${criterion.required ? 'required' : 'optional'} · '
                '$evidenceCount evidence',
            if (criterion.notes.trim().isNotEmpty) criterion.notes,
          ].join('\n'),
        ),
      ),
    );
  }
}

class ProjectRoadmapSection extends StatelessWidget {
  final ProjectDocument project;

  const ProjectRoadmapSection({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    const scheduler = ProjectScheduler();
    final refreshed = scheduler.refreshReadiness(project);
    final currentTask = project.activeTaskId == null
        ? null
        : project.taskById(project.activeTaskId!);
    final ready = scheduler.orderedReadyTasks(project);
    final readyIds = ready.map((item) => item.id).toSet();
    final waitingDependency = project.tasks.where((item) {
      return refreshed.readinessFor(item.id) == TaskReadiness.waitingDependency;
    }).toList();
    final waitingInput = project.tasks.where((item) {
      return refreshed.readinessFor(item.id) == TaskReadiness.waitingInput;
    }).toList();
    final deferred = project.tasks.where((item) {
      return item.status == TaskStatus.deferred ||
          item.status == TaskStatus.obsolete;
    }).toList();
    final terminalIds = project.tasks
        .where(
          (item) =>
              item.status == TaskStatus.completed ||
              item.status == TaskStatus.failed ||
              item.status == TaskStatus.rejected ||
              item.status == TaskStatus.split ||
              item.status == TaskStatus.cancelled,
        )
        .map((item) => item.id)
        .toSet();
    final other = project.tasks.where((item) {
      return item.id != currentTask?.id &&
          !terminalIds.contains(item.id) &&
          !readyIds.contains(item.id) &&
          !waitingDependency.contains(item) &&
          !waitingInput.contains(item) &&
          !deferred.contains(item);
    }).toList();

    return _ProjectSectionCard(
      key: const ValueKey('project-roadmap-section'),
      icon: Icons.route_outlined,
      title: 'Roadmap & Readiness',
      semanticLabel: 'Project roadmap and task readiness',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Subheading('Milestones'),
          if (project.milestones.isEmpty)
            const Text('No milestones have been planned yet.')
          else
            for (final milestone in [
              ...project.milestones,
            ]..sort((a, b) => a.order.compareTo(b.order)))
              _MilestoneTile(project: project, milestone: milestone),
          if (currentTask != null) ...[
            const SizedBox(height: 10),
            _Subheading('Active Task'),
            _RoadmapTaskTile(
              task: currentTask,
              showRationale: true,
              schedule: refreshed,
            ),
          ],
          const SizedBox(height: 10),
          _TaskGroup(
            title: 'Ready in Scheduler Order',
            tasks: ready,
            schedule: refreshed,
            empty: 'No tasks are ready to run.',
          ),
          const SizedBox(height: 8),
          _TaskGroup(
            title: 'Waiting on Dependencies',
            tasks: waitingDependency,
            schedule: refreshed,
            empty: 'No tasks are waiting on dependencies.',
          ),
          const SizedBox(height: 8),
          _TaskGroup(
            title: 'Waiting on Input',
            tasks: waitingInput,
            schedule: refreshed,
            empty: 'No tasks are waiting on user input or approval.',
          ),
          if (other.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TaskGroup(
              title: 'Other Planned Work',
              tasks: other,
              schedule: refreshed,
            ),
          ],
          const SizedBox(height: 4),
          ExpansionTile(
            key: const ValueKey('deferred-obsolete-tasks'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            initiallyExpanded: false,
            title: Text('Deferred & Obsolete (${deferred.length})'),
            children: [
              if (deferred.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No deferred or obsolete tasks.'),
                )
              else
                for (final task in deferred)
                  _RoadmapTaskTile(task: task, schedule: refreshed),
            ],
          ),
        ],
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  final ProjectDocument project;
  final ProjectMilestone milestone;

  const _MilestoneTile({required this.project, required this.milestone});

  @override
  Widget build(BuildContext context) {
    final milestoneTaskIds = project.tasks
        .where((item) => item.milestoneId == milestone.id)
        .map((item) => item.id)
        .toSet();
    final completedTaskIds = project.tasks
        .where((item) => item.status == TaskStatus.completed)
        .map((item) => item.id)
        .toSet();
    final satisfiedCriterionIds = project.criteria
        .where((item) => item.status == ProjectCriterionStatus.satisfied)
        .map((item) => item.id)
        .toSet();
    final completedChecks =
        milestoneTaskIds.where(completedTaskIds.contains).length +
        milestone.criterionIds.where(satisfiedCriterionIds.contains).length;
    final totalChecks = milestoneTaskIds.length + milestone.criterionIds.length;
    final progress = totalChecks == 0 ? null : completedChecks / totalChecks;

    return ExpansionTile(
      key: ValueKey('milestone-${milestone.id}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 24, bottom: 8),
      initiallyExpanded: milestone.status == ProjectMilestoneStatus.active,
      leading: Icon(_milestoneIcon(milestone.status)),
      title: Text(milestone.title),
      subtitle: Text(
        '${_humanize(milestone.status.name)} · '
        '${progress == null ? 'No linked checks' : '$completedChecks/$totalChecks linked checks'}',
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(milestone.objective),
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            milestone.exitConditions.isEmpty
                ? 'No exit conditions recorded.'
                : 'Exit conditions:\n${milestone.exitConditions.map((item) => '• $item').join('\n')}',
          ),
        ),
      ],
    );
  }
}

class _TaskGroup extends StatelessWidget {
  final String title;
  final List<Task> tasks;
  final ProjectScheduleResult schedule;
  final String empty;

  const _TaskGroup({
    required this.title,
    required this.tasks,
    required this.schedule,
    this.empty = 'No tasks in this group.',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Subheading('$title (${tasks.length})'),
        if (tasks.isEmpty)
          Text(empty, style: Theme.of(context).textTheme.bodySmall)
        else
          for (final task in tasks)
            _RoadmapTaskTile(task: task, schedule: schedule),
      ],
    );
  }
}

class _RoadmapTaskTile extends StatelessWidget {
  final Task task;
  final bool showRationale;
  final ProjectScheduleResult schedule;

  const _RoadmapTaskTile({
    required this.task,
    required this.schedule,
    this.showRationale = false,
  });

  @override
  Widget build(BuildContext context) {
    final readiness = schedule.readinessFor(task.id);
    final reasons = schedule.reasonsFor(task.id);
    return AccessibleWidget(
      label:
          'Project task ${task.title}, ${_humanize(task.status.name)}, '
          '${_humanize(readiness.name)}',
      child: ListTile(
        key: ValueKey('roadmap-task-${task.id}'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(_readinessIcon(readiness)),
        title: Text(task.title),
        subtitle: Text(
          [
            '${_humanize(readiness.name)} · '
                '${_humanize(task.priority.name)} priority · '
                '${_humanize(task.effort.name)} effort',
            task.objective,
            if (reasons.isNotEmpty) 'Why: ${reasons.join(' ')}',
            if ((showRationale || task.selectionRationale.isNotEmpty) &&
                task.selectionRationale.trim().isNotEmpty)
              'Selected because: ${task.selectionRationale}',
          ].join('\n'),
        ),
      ),
    );
  }
}

class ProjectEvidenceSection extends StatelessWidget {
  final ProjectDocument project;
  final ChatService chat;

  const ProjectEvidenceSection({
    super.key,
    required this.project,
    required this.chat,
  });

  @override
  Widget build(BuildContext context) {
    final unmapped = project.evidence
        .where((item) => item.criterionIds.isEmpty)
        .toList();
    return _ProjectSectionCard(
      key: const ValueKey('project-evidence-section'),
      icon: Icons.fact_check_outlined,
      title: 'Evidence',
      semanticLabel: 'Evidence grouped by project outcome criterion',
      child: project.evidence.isEmpty
          ? const Text('No project evidence has been recorded yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final criterion in project.criteria)
                  _EvidenceGroup(
                    title: criterion.statement,
                    criterionId: criterion.id,
                    evidence: project.evidence.where((item) {
                      return item.criterionIds.contains(criterion.id);
                    }).toList(),
                    chat: chat,
                  ),
                if (unmapped.isNotEmpty)
                  _EvidenceGroup(
                    title: 'Unmapped evidence',
                    criterionId: 'unmapped',
                    evidence: unmapped,
                    chat: chat,
                  ),
              ],
            ),
    );
  }
}

class _EvidenceGroup extends StatelessWidget {
  final String title;
  final String criterionId;
  final List<ProjectEvidence> evidence;
  final ChatService chat;

  const _EvidenceGroup({
    required this.title,
    required this.criterionId,
    required this.evidence,
    required this.chat,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: ValueKey('evidence-group-$criterionId'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: evidence.isNotEmpty,
      title: Text(title),
      subtitle: Text(
        '${evidence.length} evidence item${evidence.length == 1 ? '' : 's'}',
      ),
      children: evidence.isEmpty
          ? const [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('No evidence supports this criterion yet.'),
              ),
            ]
          : [
              for (final item in evidence)
                _EvidenceTile(evidence: item, chat: chat),
            ],
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  final ProjectEvidence evidence;
  final ChatService chat;

  const _EvidenceTile({required this.evidence, required this.chat});

  @override
  Widget build(BuildContext context) {
    final artifactPath = _artifactPath(evidence);
    final canOpen =
        evidence.type == ProjectEvidenceType.artifact && artifactPath != null;
    return AccessibleWidget(
      label:
          'Evidence ${evidence.summary}, ${_humanize(evidence.status.name)}, '
          '${_humanize(evidence.strength.name)}',
      isButton: canOpen,
      child: ListTile(
        key: ValueKey('evidence-${evidence.id}'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(_evidenceIcon(evidence.type)),
        title: Text(evidence.summary),
        subtitle: Text(
          '${_humanize(evidence.type.name)} · '
          '${_humanize(evidence.status.name)} · '
          '${_humanize(evidence.strength.name)}\n'
          'Source: ${evidence.sourceRef}',
        ),
        trailing: canOpen ? const Icon(Icons.open_in_new) : null,
        onTap: canOpen
            ? () => ArtifactViewerDialog.show(
                context,
                path: artifactPath,
                chat: chat,
                onError: (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not open artifact: $error'),
                      ),
                    );
                  }
                },
              )
            : null,
      ),
    );
  }

  static String? _artifactPath(ProjectEvidence evidence) {
    final detailPath = evidence.details['path'];
    if (detailPath is String && detailPath.trim().isNotEmpty) {
      return detailPath.trim();
    }
    return evidence.sourceRef.trim().isEmpty ? null : evidence.sourceRef.trim();
  }
}

class ProjectRevisionSection extends StatelessWidget {
  final ProjectDocument project;
  final ChatService chat;

  const ProjectRevisionSection({
    super.key,
    required this.project,
    required this.chat,
  });

  @override
  Widget build(BuildContext context) {
    final pending = project.pendingPlanApproval;
    final latest = project.planHistory.isEmpty
        ? null
        : project.planHistory.last;
    return _ProjectSectionCard(
      key: const ValueKey('project-revision-section'),
      icon: pending == null
          ? Icons.history_outlined
          : Icons.rule_folder_outlined,
      title: pending == null ? 'Plan Revisions' : 'Plan Review Required',
      semanticLabel: pending == null
          ? 'Project plan revision history'
          : 'Project plan revision awaiting approval',
      child: pending != null
          ? _PendingRevision(project: project, pending: pending, chat: chat)
          : latest == null
          ? const Text('No plan revisions have been recorded yet.')
          : _AppliedRevision(revision: latest),
    );
  }
}

class _PendingRevision extends StatelessWidget {
  final ProjectDocument project;
  final PendingProjectPlanApproval pending;
  final ChatService chat;

  const _PendingRevision({
    required this.project,
    required this.pending,
    required this.chat,
  });

  @override
  Widget build(BuildContext context) {
    final proposal = pending.desiredPlan;
    final existingTaskIds = project.tasks.map((item) => item.id).toSet();
    final existingCriterionIds = project.criteria
        .map((item) => item.id)
        .toSet();
    final existingMilestoneIds = project.milestones
        .map((item) => item.id)
        .toSet();
    return Column(
      key: ValueKey('pending-revision-${pending.revision}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Revision ${pending.revision}: ${pending.summary}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(pending.reason),
        if (proposal != null && proposal.rationale.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Rationale: ${proposal.rationale}'),
        ],
        if (pending.highRiskChanges.isNotEmpty) ...[
          const SizedBox(height: 8),
          _DiffList(
            label: 'High-risk changes',
            values: pending.highRiskChanges,
            warning: true,
          ),
        ],
        if (proposal != null) ...[
          const SizedBox(height: 8),
          _DiffList(
            label: 'Added tasks',
            values: proposal.tasks
                .where((item) => !existingTaskIds.contains(item.id))
                .map((item) => '${item.title} (${item.id})')
                .toList(),
          ),
          _DiffList(
            label: 'Changed tasks',
            values: proposal.tasks
                .where((item) => existingTaskIds.contains(item.id))
                .map((item) => '${item.title} (${item.id})')
                .toList(),
          ),
          _DiffList(label: 'Deferred tasks', values: proposal.deferredTaskIds),
          _DiffList(label: 'Obsolete tasks', values: proposal.obsoleteTaskIds),
          _DiffList(
            label: 'Criterion changes',
            values: [
              ...proposal.criteria
                  .where((item) => !existingCriterionIds.contains(item.id))
                  .map((item) => '${item.statement} (${item.id})'),
              ...project.criteria
                  .where(
                    (item) => !proposal.criteria.any(
                      (desired) => desired.id == item.id,
                    ),
                  )
                  .map((item) => 'Remove ${item.id}'),
            ],
          ),
          _DiffList(
            label: 'Milestone changes',
            values: [
              ...proposal.milestones
                  .where((item) => !existingMilestoneIds.contains(item.id))
                  .map((item) => '${item.title} (${item.id})'),
              ...project.milestones
                  .where(
                    (item) => !proposal.milestones.any(
                      (desired) => desired.id == item.id,
                    ),
                  )
                  .map((item) => 'Remove ${item.id}'),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AccessibleWidget(
              label: 'Approve plan revision ${pending.revision}',
              isButton: true,
              enabled: !chat.taskBusy,
              child: FilledButton.icon(
                key: const ValueKey('approve-plan-revision'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Approve Plan Revision'),
                onPressed: chat.taskBusy
                    ? null
                    : () => unawaited(chat.approveProjectPlanRevision()),
              ),
            ),
            AccessibleWidget(
              label: 'Reject plan revision ${pending.revision}',
              isButton: true,
              enabled: !chat.taskBusy,
              child: OutlinedButton.icon(
                key: const ValueKey('reject-plan-revision'),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Reject Revision'),
                onPressed: chat.taskBusy
                    ? null
                    : () => unawaited(chat.rejectProjectPlanRevision()),
              ),
            ),
            AccessibleWidget(
              label: 'Edit project JSON before deciding',
              isButton: true,
              enabled: !chat.taskBusy,
              child: TextButton.icon(
                icon: const Icon(Icons.data_object),
                label: const Text('Edit Project JSON'),
                onPressed: chat.taskBusy
                    ? null
                    : () => _showProjectEditor(context, chat),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AppliedRevision extends StatelessWidget {
  final ProjectPlanRevision revision;

  const _AppliedRevision({required this.revision});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Revision ${revision.revision}: ${revision.summary}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text('Why: ${revision.rationale}'),
        Text('Trigger: ${_humanize(revision.trigger.name)}'),
        const SizedBox(height: 8),
        _DiffList(label: 'Added tasks', values: revision.addedTaskIds),
        _DiffList(label: 'Changed tasks', values: revision.updatedTaskIds),
        _DiffList(label: 'Removed tasks', values: revision.removedTaskIds),
        _DiffList(
          label: 'Criterion changes',
          values: revision.criterionChanges,
        ),
        _DiffList(
          label: 'Milestone changes',
          values: revision.milestoneChanges,
        ),
        _DiffList(
          label: 'Warnings',
          values: revision.validationWarnings,
          warning: true,
        ),
      ],
    );
  }
}

class _DiffList extends StatelessWidget {
  final String label;
  final List<String> values;
  final bool warning;

  const _DiffList({
    required this.label,
    required this.values,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: warning ? theme.colorScheme.error : null,
            ),
          ),
          Text(values.map((item) => '• $item').join('\n')),
        ],
      ),
    );
  }
}

class _ProjectSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String semanticLabel;
  final Widget child;

  const _ProjectSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.semanticLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;

  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;

  const _LabelValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text('$label: $value'),
    );
  }
}

class _Subheading extends StatelessWidget {
  final String text;

  const _Subheading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

Future<void> _showProjectEditor(BuildContext context, ChatService chat) async {
  final initial = chat.activeProjectJson;
  if (initial == null) return;
  final saved = await EditProjectDialog.show(
    context,
    initialJson: initial,
    onSave: chat.updateProjectPlan,
  );
  if (saved && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Project saved')));
  }
}

String _humanize(String value) {
  final spaced = value
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll('_', ' ');
  if (spaced.isEmpty) return spaced;
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

IconData _criterionIcon(ProjectCriterionStatus status) => switch (status) {
  ProjectCriterionStatus.satisfied => Icons.check_circle_outline,
  ProjectCriterionStatus.partial => Icons.timelapse_outlined,
  ProjectCriterionStatus.invalidated => Icons.block_outlined,
  ProjectCriterionStatus.unsatisfied => Icons.radio_button_unchecked,
};

IconData _milestoneIcon(ProjectMilestoneStatus status) => switch (status) {
  ProjectMilestoneStatus.completed => Icons.flag_circle_outlined,
  ProjectMilestoneStatus.active => Icons.flag_outlined,
  ProjectMilestoneStatus.blocked => Icons.report_problem_outlined,
  ProjectMilestoneStatus.cancelled => Icons.cancel_outlined,
  ProjectMilestoneStatus.planned => Icons.outlined_flag,
};

IconData _readinessIcon(TaskReadiness readiness) => switch (readiness) {
  TaskReadiness.ready => Icons.play_circle_outline,
  TaskReadiness.waitingDependency => Icons.account_tree_outlined,
  TaskReadiness.waitingInput => Icons.person_outline,
  TaskReadiness.notEligible => Icons.pause_circle_outline,
};

IconData _evidenceIcon(ProjectEvidenceType type) => switch (type) {
  ProjectEvidenceType.gate => Icons.rule_outlined,
  ProjectEvidenceType.command => Icons.terminal_outlined,
  ProjectEvidenceType.artifact => Icons.insert_drive_file_outlined,
  ProjectEvidenceType.userApproval => Icons.verified_user_outlined,
  ProjectEvidenceType.taskClaim => Icons.task_alt_outlined,
};
