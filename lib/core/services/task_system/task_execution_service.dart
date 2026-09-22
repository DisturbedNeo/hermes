import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_service.dart';

/// Task execution boundary used by project orchestration.
///
/// The current task runner still owns its standalone persistence lifecycle;
/// this adapter isolates that dependency so the project command boundary can
/// be migrated to a non-persisting runner without changing callers again.
class TaskExecutionService {
  final TaskService _tasks;

  const TaskExecutionService({required TaskService tasks}) : _tasks = tasks;

  Future<Task> executeStep({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    TaskExecutionRequest executionRequest = const TaskExecutionRequest(),
  }) {
    return _tasks.runNextStep(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      requirePhaseApproval: requirePhaseApproval,
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
      questionAutonomy: questionAutonomy,
      executionRequest: executionRequest,
      persist: false,
    );
  }
}
