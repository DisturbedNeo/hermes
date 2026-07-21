// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import '../helpers/chat/context_summary_prompt.dart' as p0;
import '../models/chat_message.dart' as p1;
import '../models/model_configuration_snapshot.dart' as p2;
import '../models/project.dart' as p3;
import '../models/system_prompt.dart' as p4;
import '../models/task.dart' as p5;
import '../services/question_policy_service.dart' as p6;
import '../services/task_system/task_service.dart' as p7;
import '../tools/calculator_tool.dart' as p8;

/// @nodoc
void initializeMappers() {
  p0.ContextSummaryMapper.ensureInitialized();
  p1.ChatMessageMapper.ensureInitialized();
  p2.ModelConfigurationSnapshotMapper.ensureInitialized();
  p3.ProjectStateMapper.ensureInitialized();
  p3.ProjectRecoveryIncidentMapper.ensureInitialized();
  p3.ProjectTaskMapper.ensureInitialized();
  p3.ProjectTaskFailureMapper.ensureInitialized();
  p3.ProjectArtifactMapper.ensureInitialized();
  p3.ProjectTaskRefMapper.ensureInitialized();
  p3.ProjectDecisionRecordMapper.ensureInitialized();
  p3.ProjectBlockerMapper.ensureInitialized();
  p3.PendingProjectQuestionMapper.ensureInitialized();
  p3.ProjectStatusMapper.ensureInitialized();
  p3.ProjectPhaseMapper.ensureInitialized();
  p3.ProjectTaskStatusMapper.ensureInitialized();
  p3.ProjectBlockerTypeMapper.ensureInitialized();
  p3.ProjectDecisionTypeMapper.ensureInitialized();
  p3.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p4.PromptModuleMapper.ensureInitialized();
  p4.PromptPresetMapper.ensureInitialized();
  p4.SystemPromptSnapshotMapper.ensureInitialized();
  p5.RefinedTaskBriefMapper.ensureInitialized();
  p5.TaskDocumentMapper.ensureInitialized();
  p5.TaskStepMapper.ensureInitialized();
  p5.TaskGateMapper.ensureInitialized();
  p5.TaskGateResultMapper.ensureInitialized();
  p5.TaskArtifactMapper.ensureInitialized();
  p5.TaskRunMapper.ensureInitialized();
  p5.TaskToolErrorMapper.ensureInitialized();
  p5.TaskToolCallRecordMapper.ensureInitialized();
  p5.PendingTaskApprovalMapper.ensureInitialized();
  p5.PendingTaskQuestionMapper.ensureInitialized();
  p5.TaskStatusMapper.ensureInitialized();
  p5.TaskStepStatusMapper.ensureInitialized();
  p5.TaskRunStatusMapper.ensureInitialized();
  p5.TaskGateStatusMapper.ensureInitialized();
  p5.TaskToolCallOutcomeMapper.ensureInitialized();
  p5.TaskToolErrorDispositionMapper.ensureInitialized();
  p5.TaskGateFailureDispositionMapper.ensureInitialized();
  p6.AgentQuestionMapper.ensureInitialized();
  p6.QuestionKindMapper.ensureInitialized();
  p7.TaskPlanningContextMapper.ensureInitialized();
  p7.WorkspaceMetadataMapper.ensureInitialized();
  p8.CalculatorOperationMapper.ensureInitialized();
}

