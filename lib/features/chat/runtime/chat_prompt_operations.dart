// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element, unused_field
part of 'chat_runtime_engine.dart';

extension _ChatPromptOperations on _ChatApplicationContext {
  String _buildTaskSystemPrompt(Task snapshot) {
    return _buildSystemPrompt(currentUserRequest: snapshot.originalPrompt);
  }

  String _buildProjectSystemPrompt(ProjectDocument snapshot) {
    return _buildSystemPrompt(currentUserRequest: snapshot.originalGoal);
  }

  List<Bubble> _withCurrentSystemPrompt(
    List<Bubble> messages, {
    String? currentUserRequest,
  }) {
    final promptText = _buildSystemPrompt(
      currentUserRequest: currentUserRequest,
    );
    if (messages.isEmpty) return [systemPrompt.copyWith(text: promptText)];

    final copy = List<Bubble>.of(messages);
    if (copy.first.role == MessageRole.system) {
      copy[0] = copy.first.copyWith(text: promptText);
    } else {
      copy.insert(0, systemPrompt.copyWith(text: promptText));
    }
    return copy;
  }

  void _syncSystemPrompt() {
    messageStore.setMessages(_withCurrentSystemPrompt(messageStore.messages));
  }

  List<Bubble> _payloadMessages({String? currentUserRequest}) {
    return _withCurrentSystemPrompt(
      messageStore.messages,
      currentUserRequest: currentUserRequest,
    );
  }

  List<String> _autoModuleIdsForWorkspace() {
    final currentWorkspace = workspace;
    if (currentWorkspace == null) return const [];
    return currentWorkspace.missing
        ? const [BuiltInPromptIds.workspaceMissingModule]
        : const [BuiltInPromptIds.workspaceRulesModule];
  }

  // ── Slash command parsing ───────────────────────────────────────────────

  _SlashCommand? _parseSlashCommand(String text) {
    final match = RegExp(
      r'^/(continue-project|project|task|plan|refine|continue)\b(.*)$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    return _SlashCommand(
      name: match.group(1)!.toLowerCase(),
      argument: match.group(2)?.trim() ?? '',
      raw: text,
    );
  }

  void _markWorkspaceChanged() {
    _markPersistableChange();
    notifyListeners();
  }

  void _adoptActiveModelIfRestoreDismissed() {
    if (pendingModelRestore != null) return;

    final activeSnapshot = _activeServerSnapshot;
    if (activeSnapshot == null ||
        activeSnapshot.matches(currentModelSnapshot)) {
      return;
    }

    dispatchCurrentModelSnapshot(activeSnapshot);
    _requestContextEstimateUpdate(immediate: true);
    _markPersistableChange();
    notifyListeners();
  }

  // ── Status message builders ─────────────────────────────────────────────

  String _taskBriefMessage(RefinedTaskBrief brief) {
    final buffer = StringBuffer()
      ..writeln('Task brief refined: **${brief.title}**')
      ..writeln()
      ..writeln('Goal:')
      ..writeln(brief.goal)
      ..writeln()
      ..writeln('Success criteria:');
    for (final item in brief.successCriteria) {
      buffer.writeln('- $item');
    }
    if (brief.constraints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Constraints:');
      for (final item in brief.constraints) {
        buffer.writeln('- $item');
      }
    }
    if (brief.assumptions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Assumptions:');
      for (final item in brief.assumptions) {
        buffer.writeln('- $item');
      }
    }
    if (brief.questions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Questions:');
      for (final question in brief.questions.take(3)) {
        buffer.writeln('- $question');
      }
    }
    return buffer.toString().trim();
  }

  String _taskCreatedMessage(Task snapshot) {
    final buffer = StringBuffer()
      ..writeln('Task created: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${snapshot.status.wire}`')
      ..writeln()
      ..writeln('Steps:');
    for (var i = 0; i < snapshot.steps.length; i++) {
      final step = snapshot.steps[i];
      buffer.writeln('${i + 1}. ${step.title}');
    }
    buffer
      ..writeln()
      ..writeln('Task state is stored under `.agent/tasks/${snapshot.id}/`.');
    return buffer.toString().trim();
  }

  String _projectCreatedMessage(ProjectDocument snapshot) {
    final buffer = StringBuffer()
      ..writeln('Project created: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${snapshot.status.wire}`')
      ..writeln()
      ..writeln('Goal:')
      ..writeln(snapshot.refinedGoal)
      ..writeln()
      ..writeln(
        'Project state is stored under `.agent/projects/${snapshot.id}/`.',
      );
    return buffer.toString().trim();
  }

  String _projectStatusMessage(ProjectDocument snapshot) {
    final buffer = StringBuffer()
      ..writeln('Project status: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${snapshot.status.wire}`');
    if (_projectHasTransportFailure(snapshot)) {
      buffer
        ..writeln()
        ..writeln(
          'Model transport was interrupted. Resume the project to retry the current step.',
        );
    } else if (snapshot.completionSummary.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(snapshot.completionSummary.trim());
    } else if (snapshot.blocker != null) {
      buffer
        ..writeln()
        ..writeln('Blocked: ${snapshot.blocker!.message}');
    } else if (snapshot.tasks.isNotEmpty) {
      final latest = snapshot.tasks.last;
      buffer
        ..writeln()
        ..writeln(
          'Latest task: `${latest.id}` - '
          '${latest.status.wire}',
        );
    }
    return buffer.toString().trim();
  }

  String _stepFinishedMessage(Task snapshot) {
    final latestRun = snapshot.runs.isEmpty ? null : snapshot.runs.last;
    final buffer = StringBuffer()
      ..writeln('Task step finished: **${latestRun?.stepId ?? 'step'}**')
      ..writeln()
      ..writeln('Task status: `${snapshot.status.wire}`');
    if (_taskHasTransportFailure(snapshot)) {
      buffer
        ..writeln()
        ..writeln(
          'Model transport was interrupted. Resume the task to retry this step.',
        );
    } else if (latestRun != null) {
      buffer
        ..writeln()
        ..writeln(
          latestRun.summary.trim().isEmpty
              ? 'The task is paused. Resume it when ready.'
              : latestRun.summary,
        );
    }
    final artifacts = latestRun?.artifacts ?? const [];
    if (artifacts.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Artifacts:');
      for (final artifact in artifacts.take(8)) {
        buffer.writeln('- `${artifact.path}`');
      }
    }
    final gateResults = latestRun?.gateResults ?? const [];
    if (gateResults.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Gates:');
      for (final result in gateResults.take(8)) {
        buffer.writeln(
          '- `${result.gateId}` ${result.status.wire}: ${result.summary}',
        );
      }
    }
    return buffer.toString().trim();
  }

  bool _taskHasTransportFailure(Task? snapshot) {
    if (snapshot == null ||
        snapshot.status != TaskStatus.paused ||
        snapshot.runs.isEmpty) {
      return false;
    }
    final latestRun = snapshot.runs.last;
    return latestRun.status == TaskRunStatus.failed &&
        latestRun.error?.contains('Model transport failed') == true;
  }

  bool _projectHasTransportFailure(ProjectDocument snapshot) {
    if (snapshot.status != ProjectStatus.paused ||
        snapshot.activeTaskId == null) {
      return false;
    }
    final task = activeTask;
    if (task == null ||
        task.id != snapshot.activeTaskId ||
        task.projectId != snapshot.id) {
      return false;
    }
    return _taskHasTransportFailure(task);
  }

  bool _taskNeedsInterventionBeforeContinuing(Task snapshot) {
    if (snapshot.status != TaskStatus.paused) return false;
    if (snapshot.pendingApproval != null || snapshot.pendingQuestion != null) {
      return true;
    }
    final latestRun = snapshot.runs.isEmpty ? null : snapshot.runs.last;
    if (latestRun == null) return true;
    return latestRun.status != TaskRunStatus.completed &&
        latestRun.status != TaskRunStatus.replanned &&
        latestRun.status != TaskRunStatus.skipped;
  }

  // ── Disposable ──────────────────────────────────────────────────────────

  Future<void> quiesceForExit({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_disposed) return;
    await _stopActiveWork().timeout(timeout);
    _session.flushPendingTokens();
  }
}
