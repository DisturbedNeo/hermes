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
import '../services/workspace_discovery_profile.dart' as p9;
import '../tools/calculator_tool.dart' as p10;

/// @nodoc
void initializeMappers() {
  p0.ContextSummaryMapper.ensureInitialized();
  p1.ChatMessageMapper.ensureInitialized();
  p2.ModelConfigurationSnapshotMapper.ensureInitialized();
  p3.ModelLoadConfigurationMapper.ensureInitialized();
  p4.ProjectDiagnosticsMapper.ensureInitialized();
  p4.ProjectCriterionMapper.ensureInitialized();
  p4.ProjectEvidenceMapper.ensureInitialized();
  p4.ProjectMilestoneMapper.ensureInitialized();
  p4.ProjectEvidenceExpectationMapper.ensureInitialized();
  p4.ProjectMemoryEntryMapper.ensureInitialized();
  p4.ProjectMemorySupersessionMapper.ensureInitialized();
  p4.ProjectPlanProposalMapper.ensureInitialized();
  p4.ProjectPlanRevisionMapper.ensureInitialized();
  p4.PendingProjectPlanApprovalMapper.ensureInitialized();
  p4.ProjectCompletionReviewCheckpointMapper.ensureInitialized();
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
  p4.ProjectCriterionStatusMapper.ensureInitialized();
  p4.ProjectVerificationModeMapper.ensureInitialized();
  p4.ProjectEvidenceTypeMapper.ensureInitialized();
  p4.ProjectEvidenceStatusMapper.ensureInitialized();
  p4.ProjectEvidenceStrengthMapper.ensureInitialized();
  p4.ProjectMilestoneStatusMapper.ensureInitialized();
  p4.ProjectTaskPriorityMapper.ensureInitialized();
  p4.ProjectTaskRiskMapper.ensureInitialized();
  p4.ProjectRiskReductionMapper.ensureInitialized();
  p4.ProjectTaskEffortMapper.ensureInitialized();
  p4.ProjectTaskReadinessMapper.ensureInitialized();
  p4.ProjectMemoryKindMapper.ensureInitialized();
  p4.ProjectMemorySourceTypeMapper.ensureInitialized();
  p4.ProjectMemoryConfidenceMapper.ensureInitialized();
  p4.ProjectPlanRevisionTriggerMapper.ensureInitialized();
  p4.ProjectCompletionReviewReasonMapper.ensureInitialized();
  p4.ProjectPlanApprovalPolicyMapper.ensureInitialized();
  p4.ProjectPlanRevisionApproverMapper.ensureInitialized();
  p4.ProjectBlockerTypeMapper.ensureInitialized();
  p4.ProjectDecisionTypeMapper.ensureInitialized();
  p4.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p5.PromptModuleMapper.ensureInitialized();
  p5.PromptPresetMapper.ensureInitialized();
  p5.SystemPromptSnapshotMapper.ensureInitialized();
  p6.TaskProjectCriterionMapper.ensureInitialized();
  p6.TaskProjectEvidenceExpectationMapper.ensureInitialized();
  p6.RefinedTaskBriefMapper.ensureInitialized();
  p6.TaskDocumentMapper.ensureInitialized();
  p6.TaskStepMapper.ensureInitialized();
  p6.TaskGateMapper.ensureInitialized();
  p6.TaskGateResultMapper.ensureInitialized();
  p6.TaskArtifactMapper.ensureInitialized();
  p6.TaskEvidenceClaimMapper.ensureInitialized();
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
  p6.TaskEvidenceClaimTypeMapper.ensureInitialized();
  p6.TaskEvidenceClaimStrengthMapper.ensureInitialized();
  p7.AgentQuestionMapper.ensureInitialized();
  p7.QuestionKindMapper.ensureInitialized();
  p8.TaskPlanningContextMapper.ensureInitialized();
  p8.WorkspaceMetadataMapper.ensureInitialized();
  p9.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p9.WorkspaceFileExcerptMapper.ensureInitialized();
  p10.CalculatorOperationMapper.ensureInitialized();
}

