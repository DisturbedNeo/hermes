part of 'project_execution_state_machine.dart';

/// Deterministic recovery policy extracted from project execution orchestration.
class ProjectRecoveryPolicy {
  ProjectRecoveryUpdate recoveryUpdateForFailedTask({
    required ProjectAggregate project,
    required ProjectTaskNode failedTask,
    required ProjectEvaluation evaluation,
    required DateTime now,
  }) {
    final recoveryFailure = _recoveryFailureFor(
      failedTask: failedTask,
      evaluation: evaluation,
    );
    if (recoveryFailure == null) {
      return ProjectRecoveryUpdate(
        failedTask: failedTask,
        recoveryIncidents: project.recoveryIncidents,
      );
    }

    final existing = _matchingRecoveryIncident(
      project.recoveryIncidents,
      recoveryFailure,
      failedTask.recoveryIncidentId,
    );
    final isRecoveryAttempt = failedTask.recoveryIncidentId != null;
    final incidentId = existing?.id ?? 'recovery_${uuid.v7()}';
    final nextAttemptCount =
        (existing?.attemptCount ?? 0) + (isRecoveryAttempt ? 1 : 0);
    final status =
        nextAttemptCount >=
            (existing?.maxAttempts ??
                ProjectRecoveryIncident.defaultMaxAttempts)
        ? ProjectRecoveryIncidentStatus.exhausted
        : ProjectRecoveryIncidentStatus.active;
    final linkedFailedTask = failedTask.copyWith(
      recoveryIncidentId: incidentId,
    );
    final recoveryTask = status == ProjectRecoveryIncidentStatus.active
        ? recoveryTaskForIncident(
            incidentId: incidentId,
            sourceTask: failedTask,
            failure: recoveryFailure,
            attemptNumber: nextAttemptCount + 1,
            now: now,
          )
        : null;
    final incident =
        (existing ??
                ProjectRecoveryIncident(
                  id: incidentId,
                  status: ProjectRecoveryIncidentStatus.active,
                  sourceTaskIds: const [],
                  sourceTaskTitles: const [],
                  failedGateId: recoveryFailure.gateResult.gateId,
                  command: recoveryFailure.command,
                  workingDirectory: recoveryFailure.workingDirectory,
                  failureSummary: recoveryFailure.summary,
                  attemptCount: 0,
                  maxAttempts: ProjectRecoveryIncident.defaultMaxAttempts,
                  recoveryTaskIds: const [],
                  createdAt: now,
                  updatedAt: now,
                ))
            .copyWith(
              status: status,
              sourceTaskIds: _appendUnique(
                existing?.sourceTaskIds ?? const [],
                failedTask.id,
              ),
              sourceTaskTitles: _appendUnique(
                existing?.sourceTaskTitles ?? const [],
                failedTask.title,
              ),
              failedGateId: recoveryFailure.gateResult.gateId,
              command: recoveryFailure.command,
              workingDirectory: recoveryFailure.workingDirectory,
              failureSummary: recoveryFailure.summary,
              attemptCount: nextAttemptCount,
              recoveryTaskIds: recoveryTask == null
                  ? existing?.recoveryTaskIds ?? const []
                  : _appendUnique(
                      existing?.recoveryTaskIds ?? const [],
                      recoveryTask.id,
                    ),
              updatedAt: now,
              resolvedAt: status == ProjectRecoveryIncidentStatus.exhausted
                  ? now
                  : null,
            );
    return ProjectRecoveryUpdate(
      failedTask: linkedFailedTask,
      recoveryIncidents: upsertRecoveryIncident(
        project.recoveryIncidents,
        incident,
      ),
      incident: incident,
      recoveryTask: recoveryTask,
      exhaustedIncident: status == ProjectRecoveryIncidentStatus.exhausted
          ? incident
          : null,
    );
  }

  ProjectRecoveryFailure? _recoveryFailureFor({
    required ProjectTaskNode failedTask,
    required ProjectEvaluation evaluation,
  }) {
    final failedGate = evaluation.gateResults
        .where(
          (result) =>
              result.status == TaskGateStatus.failed &&
              result.details['required'] == true,
        )
        .where(
          (result) =>
              result.failureDisposition ==
                  TaskGateFailureDisposition.repairable ||
              failedTask.recoveryIncidentId != null,
        )
        .firstOrNull;
    if (failedGate == null) return null;
    final command = _gateFailureCommand(failedGate);
    final workingDirectory = jsonNullableString(
      failedGate.details['workingDirectory'] ??
          failedGate.details['working_directory'],
    );
    final summary = [
      failedGate.summary,
      _gateDiagnosticSummary(failedGate),
      if (evaluation.failureReason?.trim().isNotEmpty == true)
        evaluation.failureReason!.trim(),
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
    return ProjectRecoveryFailure(
      gateResult: failedGate,
      command: command,
      workingDirectory: workingDirectory,
      summary: _cap(summary.isEmpty ? 'Required gate failed.' : summary, 2000),
    );
  }

  String _gateDiagnosticSummary(TaskGateResult result) {
    final unresolved = result.details['unresolvedErrors'];
    if (unresolved is! List) return '';
    final lines = unresolved.whereType<Map>().take(10).map((raw) {
      final item = jsonMap(raw);
      final code = jsonString(item['code'], fallback: 'unknown_tool_error');
      final toolName = jsonString(item['toolName'], fallback: 'tool');
      final operation = jsonString(item['operationKey']);
      final message = jsonString(item['message']);
      return '- $code ($toolName${operation.isEmpty ? '' : ', $operation'}): $message';
    }).toList();
    return lines.isEmpty ? '' : 'Unresolved diagnostics:\n${lines.join('\n')}';
  }

  TaskFailure taskFailure(ProjectEvaluation evaluation) {
    final gate = evaluation.gateResults
        .where(
          (result) =>
              result.status == TaskGateStatus.failed &&
              result.details['required'] == true,
        )
        .firstOrNull;
    final unresolved = gate?.details['unresolvedErrors'];
    final advisory = gate?.details['advisoryErrors'];
    final resolved = gate?.details['resolvedErrors'];
    final errorMaps = unresolved is List
        ? unresolved.whereType<Map>().map(jsonMap).toList()
        : const <Map<String, dynamic>>[];
    final errorCodes =
        errorMaps
            .map((item) => jsonString(item['code']))
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final callIds = errorMaps
        .map((item) => jsonString(item['callId']))
        .where((item) => item.isNotEmpty)
        .take(10)
        .toList();
    final operationKeys =
        errorMaps
            .map((item) => jsonString(item['operationKey']))
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final disposition =
        gate?.failureDisposition ?? TaskGateFailureDisposition.blocking;
    final summary = evaluation.failureReason?.trim().isNotEmpty == true
        ? evaluation.failureReason!.trim()
        : gate?.summary ?? 'Task execution failed.';
    final keyParts = [
      gate?.gateId ?? 'execution',
      ...errorCodes,
      ...operationKeys,
      if (errorCodes.isEmpty && operationKeys.isEmpty) _normalise(summary),
    ];
    return TaskFailure(
      gateId: gate?.gateId,
      disposition: disposition,
      failureKey: _cap(keyParts.join('|'), 500),
      summary: _cap(summary, 2000),
      errorCodes: errorCodes,
      toolCallIds: callIds,
      advisoryErrorCount: advisory is List ? advisory.length : 0,
      resolvedErrorCount: resolved is List ? resolved.length : 0,
      unresolvedErrorCount: unresolved is List ? unresolved.length : 0,
    );
  }

  String? _gateFailureCommand(TaskGateResult result) {
    final direct = jsonNullableString(result.details['command']);
    if (direct != null) return direct;
    final failedCommands = result.details['failedCommands'];
    if (failedCommands is List && failedCommands.isNotEmpty) {
      final first = failedCommands.first;
      if (first is Map) return jsonNullableString(first['command']);
    }
    return null;
  }

  ProjectRecoveryIncident? _matchingRecoveryIncident(
    List<ProjectRecoveryIncident> incidents,
    ProjectRecoveryFailure failure,
    String? preferredIncidentId,
  ) {
    if (preferredIncidentId != null) {
      final preferred = incidents
          .where((incident) => incident.id == preferredIncidentId)
          .firstOrNull;
      if (preferred != null) return preferred;
    }
    final key = _recoveryIncidentKey(
      gateId: failure.gateResult.gateId,
      command: failure.command,
      workingDirectory: failure.workingDirectory,
      summary: failure.summary,
    );
    return incidents.where((incident) {
      return incident.status == ProjectRecoveryIncidentStatus.active &&
          _recoveryIncidentKey(
                gateId: incident.failedGateId,
                command: incident.command,
                workingDirectory: incident.workingDirectory,
                summary: incident.failureSummary,
              ) ==
              key;
    }).firstOrNull;
  }

  String _recoveryIncidentKey({
    required String gateId,
    required String? command,
    required String? workingDirectory,
    required String summary,
  }) {
    final commandPart = command?.trim().isNotEmpty == true
        ? command!.trim()
        : _cap(_normalise(summary), 160);
    return [
      _normalise(gateId),
      _normalise(commandPart),
      _normalise(workingDirectory ?? '.'),
    ].join('|');
  }

  List<TaskEvidenceExpectation> replacementExpectedEvidence({
    required Iterable<TaskEvidenceExpectation> source,
    required Iterable<TaskEvidenceExpectation> additions,
    required Iterable<String> criterionIds,
    required String idPrefix,
  }) {
    final validCriteria = criterionIds.toSet();
    final merged = <String, TaskEvidenceExpectation>{};
    for (final expectation in [...source, ...additions]) {
      final linkedCriteria = expectation.criterionIds
          .where(validCriteria.contains)
          .toSet()
          .toList();
      if (linkedCriteria.isEmpty) continue;
      final normalized = TaskEvidenceExpectation(
        id: expectation.id,
        type: expectation.type,
        criterionIds: linkedCriteria,
        description: expectation.description,
        required: expectation.required,
        sourceRef: expectation.sourceRef,
        details: expectation.details,
      );
      final signature = _evidenceExpectationSignature(normalized);
      final existing = merged[signature];
      merged[signature] = existing == null
          ? normalized
          : TaskEvidenceExpectation(
              id: normalized.id,
              type: normalized.type,
              criterionIds: normalized.criterionIds,
              description: normalized.description,
              required: existing.required || normalized.required,
              sourceRef: normalized.sourceRef,
              details: normalized.details,
            );
    }
    return [
      for (final expectation in merged.values)
        TaskEvidenceExpectation(
          id: '${idPrefix}_${uuid.v7()}',
          type: expectation.type,
          criterionIds: expectation.criterionIds,
          description: expectation.description,
          required: expectation.required,
          sourceRef: expectation.sourceRef,
          details: expectation.details,
        ),
    ];
  }

  String _evidenceExpectationSignature(TaskEvidenceExpectation expectation) {
    final criteria = [...expectation.criterionIds]..sort();
    return [
      expectation.type.name,
      _normalise(expectation.sourceRef ?? ''),
      criteria.join(','),
    ].join('|');
  }

  ProjectTaskNode recoveryTaskForIncident({
    required String incidentId,
    required ProjectTaskNode sourceTask,
    required ProjectRecoveryFailure failure,
    required int attemptNumber,
    required DateTime now,
  }) {
    final command = failure.command?.trim();
    final gateTarget = command?.isNotEmpty == true
        ? '${failure.gateResult.gateId}: $command'
        : failure.gateResult.gateId;
    final objective = 'Restore required project health gate: $gateTarget';
    final gateType =
        command?.isNotEmpty == true ||
            failure.gateResult.gateId == 'command_passes'
        ? ProjectEvidenceType.command
        : failure.gateResult.gateId == 'human_approval'
        ? ProjectEvidenceType.userApproval
        : ProjectEvidenceType.gate;
    final gateSourceRef = command?.isNotEmpty == true
        ? command
        : failure.gateResult.gateId;
    final recoveryGateExpectation = TaskEvidenceExpectation(
      id: 'recovery_gate_expectation',
      type: gateType,
      criterionIds: sourceTask.criterionIds,
      description: 'The required recovery gate passes: $gateTarget.',
      required: true,
      sourceRef: gateSourceRef,
      details: failure.gateResult.details,
    );
    return ProjectTaskNode(
      id: 'project_recovery_${uuid.v7()}',
      title: 'Recover project health',
      objective: objective,
      criterionIds: sourceTask.criterionIds,
      doneCriteria: [
        'Diagnose why the required gate is failing.',
        'Make the smallest safe repair needed to restore the gate.',
        if (command?.isNotEmpty == true)
          'Run `$command` successfully before completing this task.'
        else
          'Rerun the failed required gate successfully before completing this task.',
      ],
      outOfScope: const [
        'Do not start unrelated feature work.',
        'Do not expand the original project scope.',
      ],
      context: [
        'Recovery incident: $incidentId',
        'Original task: ${sourceTask.title}',
        'Original objective: ${sourceTask.objective}',
        'Failed gate: ${failure.gateResult.gateId}',
        if (command?.isNotEmpty == true) 'Failed command: $command',
        if (failure.workingDirectory?.trim().isNotEmpty == true)
          'Working directory: ${failure.workingDirectory}',
        'Failure summary:\n${failure.summary}',
        'Recovery attempt: $attemptNumber',
      ],
      readPaths: sourceTask.readPaths,
      writePaths: sourceTask.writePaths,
      expectedEvidence: replacementExpectedEvidence(
        source: sourceTask.expectedEvidence,
        additions: [recoveryGateExpectation],
        criterionIds: sourceTask.criterionIds,
        idPrefix: 'recovery_expectation',
      ),
      expectedArtifacts: const [],
      status: TaskStatus.queued,
      recoveryIncidentId: incidentId,
      fingerprint: projectTaskFingerprint(objective, [
        incidentId,
        'attempt_$attemptNumber',
      ]),
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<ProjectRecoveryIncident> upsertRecoveryIncident(
    List<ProjectRecoveryIncident> incidents,
    ProjectRecoveryIncident incident,
  ) {
    var replaced = false;
    final next = <ProjectRecoveryIncident>[];
    for (final current in incidents) {
      if (current.id == incident.id) {
        next.add(incident);
        replaced = true;
      } else {
        next.add(current);
      }
    }
    if (!replaced) next.add(incident);
    return next;
  }

  List<ProjectRecoveryIncident> resolveRecoveryIncidentForTask(
    List<ProjectRecoveryIncident> incidents,
    ProjectTaskNode completedTask,
    DateTime now,
  ) {
    final incidentId = completedTask.recoveryIncidentId;
    if (incidentId == null) return incidents;
    return [
      for (final incident in incidents)
        incident.id == incidentId &&
                incident.status == ProjectRecoveryIncidentStatus.active
            ? incident.copyWith(
                status: ProjectRecoveryIncidentStatus.resolved,
                updatedAt: now,
                resolvedAt: now,
              )
            : incident,
    ];
  }

  List<TaskGate> requiredGatesForTask(
    ProjectAggregate project,
    ProjectTaskNode task,
  ) {
    final expectedGates = <TaskGate>[
      for (final expectation in task.expectedEvidence)
        if (expectation.required &&
            expectation.type == ProjectEvidenceType.command &&
            expectation.sourceRef?.trim().isNotEmpty == true)
          TaskGate(
            id: 'command_passes',
            required: true,
            scope: 'task',
            params: {
              'command': expectation.sourceRef!.trim(),
              ...expectation.details,
            },
            description: expectation.description,
          )
        else if (expectation.required &&
            expectation.type == ProjectEvidenceType.gate &&
            expectation.sourceRef?.trim().isNotEmpty == true)
          TaskGate(
            id: expectation.sourceRef!.trim(),
            required: true,
            scope: 'task',
            params: expectation.details,
            description: expectation.description,
          )
        else if (expectation.required &&
            expectation.type == ProjectEvidenceType.userApproval)
          TaskGate(
            id: 'human_approval',
            required: true,
            scope: 'task',
            params: expectation.details,
            description: expectation.description,
          ),
    ];
    final incidentId = task.recoveryIncidentId;
    if (incidentId == null) return expectedGates;
    final incident = project.recoveryIncidents
        .where((item) => item.id == incidentId)
        .firstOrNull;
    if (incident == null) return expectedGates;
    return [
      ...expectedGates,
      TaskGate(
        id: incident.failedGateId,
        required: true,
        scope: 'task',
        params: {
          if (incident.command?.trim().isNotEmpty == true)
            'command': incident.command,
          if (incident.workingDirectory?.trim().isNotEmpty == true)
            'working_directory': incident.workingDirectory,
        },
        description: 'Recovery incident ${incident.id} must be resolved.',
      ),
    ];
  }

  int projectFailureBudgetCount(
    List<ProjectTaskNode> failedTasks,
    List<ProjectRecoveryIncident> recoveryIncidents,
  ) {
    final nonRecoveryFailures = failedTasks
        .where(
          (task) =>
              task.status == TaskStatus.failed &&
              task.recoveryIncidentId == null,
        )
        .map(
          (task) =>
              task.failureKey ??
              '${task.fingerprint}|${_normalise(task.rejectionReason ?? '')}',
        )
        .toSet()
        .length;
    final exhaustedIncidents = recoveryIncidents
        .where(
          (incident) =>
              incident.status == ProjectRecoveryIncidentStatus.exhausted,
        )
        .length;
    return nonRecoveryFailures + exhaustedIncidents;
  }

  // Project execution operations
  /// Executes bounded project runs and owns the task execution protocol.

  List<String> _appendUnique(List<String> current, String value) {
    if (value.trim().isEmpty || current.contains(value)) return current;
    return [...current, value];
  }

  String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _cap(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }
}
