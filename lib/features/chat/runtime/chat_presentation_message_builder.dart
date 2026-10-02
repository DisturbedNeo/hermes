import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';

/// Builds user-facing chat messages from immutable task and project results.
///
/// The session orchestrator owns lifecycle and persistence; this collaborator
/// owns presentation wording and transport-failure summaries.
class ChatPresentationMessageBuilder {
  const ChatPresentationMessageBuilder();

  String taskBrief(RefinedTaskBrief brief) {
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

  String taskCreated(TaskAggregate snapshot) {
    final buffer = StringBuffer()
      ..writeln('Task created: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${TaskStatusWire(snapshot.status).wire}`')
      ..writeln()
      ..writeln('Steps:');
    for (var i = 0; i < snapshot.steps.length; i++) {
      buffer.writeln('${i + 1}. ${snapshot.steps[i].title}');
    }
    buffer
      ..writeln()
      ..writeln('Task state is stored under `.agent/tasks/${snapshot.id}/`.');
    return buffer.toString().trim();
  }

  String projectCreated(ProjectAggregate snapshot) {
    final buffer = StringBuffer()
      ..writeln('Project created: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${ProjectStatusWire(snapshot.status).wire}`')
      ..writeln()
      ..writeln('Goal:')
      ..writeln(snapshot.refinedGoal)
      ..writeln()
      ..writeln(
        'Project state is stored under `.agent/projects/${snapshot.id}/`.',
      );
    return buffer.toString().trim();
  }

  String projectStatus(ProjectAggregate snapshot, {TaskAggregate? activeTask}) {
    final buffer = StringBuffer()
      ..writeln('Project status: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${ProjectStatusWire(snapshot.status).wire}`');
    if (projectHasTransportFailure(snapshot, activeTask: activeTask)) {
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
        ..writeln('Latest task: `${latest.id}` - ${latest.status.wire}');
    }
    return buffer.toString().trim();
  }

  String stepFinished(TaskAggregate snapshot) {
    final latestRun = snapshot.runs.isEmpty ? null : snapshot.runs.last;
    final buffer = StringBuffer()
      ..writeln('Task step finished: **${latestRun?.stepId ?? 'step'}**')
      ..writeln()
      ..writeln('Task status: `${snapshot.status.wire}`');
    if (taskHasTransportFailure(snapshot)) {
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

  bool taskHasTransportFailure(TaskAggregate? snapshot) {
    if (snapshot == null ||
        snapshot.status != TaskStatus.paused ||
        snapshot.runs.isEmpty) {
      return false;
    }
    final latestRun = snapshot.runs.last;
    return latestRun.status == TaskRunStatus.failed &&
        latestRun.error?.contains('Model transport failed') == true;
  }

  bool projectHasTransportFailure(
    ProjectAggregate snapshot, {
    TaskAggregate? activeTask,
  }) {
    if (snapshot.status != ProjectStatus.paused ||
        snapshot.activeTaskId == null) {
      return false;
    }
    if (activeTask == null ||
        activeTask.id != snapshot.activeTaskId ||
        activeTask.projectId != snapshot.id) {
      return false;
    }
    return taskHasTransportFailure(activeTask);
  }

  bool taskNeedsIntervention(TaskAggregate snapshot) {
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
}
