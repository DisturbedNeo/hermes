// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import '../helpers/chat/context_summary_prompt.dart' as p0;
import '../models/chat_message.dart' as p1;
import '../models/model_configuration_snapshot.dart' as p2;
import '../models/model_load_configuration.dart' as p3;
import '../models/project.dart' as p4;
import '../models/system_prompt.dart' as p5;
import '../models/task.dart' as p6;
import '../services/question_policy_service.dart' as p7;
import '../services/task_system/task_service.dart' as p8;
import '../tools/calculator_tool.dart' as p9;

/// @nodoc
void initializeMappers() {
  p0.ContextSummaryMapper.ensureInitialized();
  p1.ChatMessageMapper.ensureInitialized();
  p2.ModelConfigurationSnapshotMapper.ensureInitialized();
  p3.ModelLoadConfigurationMapper.ensureInitialized();
  p4.ProjectStateMapper.ensureInitialized();
  p4.ProjectRecoveryIncidentMapper.ensureInitialized();
  p4.ProjectTaskMapper.ensureInitialized();
  p4.ProjectTaskFailureMapper.ensureInitialized();
  p4.ProjectArtifactMapper.ensureInitialized();
  p4.ProjectTaskRefMapper.ensureInitialized();
  p4.ProjectDecisionRecordMapper.ensureInitialized();
  p4.ProjectBlockerMapper.ensureInitialized();
  p4.PendingProjectQuestionMapper.ensureInitialized();
  p4.ProjectStatusMapper.ensureInitialized();
  p4.ProjectPhaseMapper.ensureInitialized();
  p4.ProjectTaskStatusMapper.ensureInitialized();
  p4.ProjectBlockerTypeMapper.ensureInitialized();
  p4.ProjectDecisionTypeMapper.ensureInitialized();
  p4.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p5.PromptModuleMapper.ensureInitialized();
  p5.PromptPresetMapper.ensureInitialized();
  p5.SystemPromptSnapshotMapper.ensureInitialized();
  p6.RefinedTaskBriefMapper.ensureInitialized();
  p6.TaskDocumentMapper.ensureInitialized();
  p6.TaskStepMapper.ensureInitialized();
  p6.TaskGateMapper.ensureInitialized();
  p6.TaskGateResultMapper.ensureInitialized();
  p6.TaskArtifactMapper.ensureInitialized();
  p6.TaskRunMapper.ensureInitialized();
  p6.TaskToolErrorMapper.ensureInitialized();
  p6.TaskToolCallRecordMapper.ensureInitialized();
  p6.PendingTaskApprovalMapper.ensureInitialized();
  p6.PendingTaskQuestionMapper.ensureInitialized();
  p6.TaskStatusMapper.ensureInitialized();
  p6.TaskStepStatusMapper.ensureInitialized();
  p6.TaskRunStatusMapper.ensureInitialized();
  p6.TaskGateStatusMapper.ensureInitialized();
  p6.TaskToolCallOutcomeMapper.ensureInitialized();
  p6.TaskToolErrorDispositionMapper.ensureInitialized();
  p6.TaskGateFailureDispositionMapper.ensureInitialized();
  p7.AgentQuestionMapper.ensureInitialized();
  p7.QuestionKindMapper.ensureInitialized();
  p8.TaskPlanningContextMapper.ensureInitialized();
  p8.WorkspaceMetadataMapper.ensureInitialized();
  p9.CalculatorOperationMapper.ensureInitialized();
}

