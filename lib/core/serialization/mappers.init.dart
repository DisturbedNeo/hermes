// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import '../helpers/chat/context_summary_prompt.dart' as p0;
import '../models/chat_message.dart' as p1;
import '../models/model_configuration_snapshot.dart' as p2;
import '../models/model_load_configuration.dart' as p3;
import '../models/planning_metrics.dart' as p4;
import '../models/project.dart' as p5;
import '../models/system_prompt.dart' as p6;
import '../models/task.dart' as p7;
import '../services/question_policy_service.dart' as p8;
import '../services/task_system/task_service.dart' as p9;
import '../services/workspace_discovery_profile.dart' as p10;
import '../tools/calculator_tool.dart' as p11;

/// @nodoc
void initializeMappers() {
  p0.ContextSummaryMapper.ensureInitialized();
  p1.ChatMessageMapper.ensureInitialized();
  p2.ModelConfigurationSnapshotMapper.ensureInitialized();
  p3.ModelLoadConfigurationMapper.ensureInitialized();
  p4.PlanningMetricsMapper.ensureInitialized();
  p5.ProjectDiagnosticsMapper.ensureInitialized();
  p5.ProjectCriterionMapper.ensureInitialized();
  p5.ProjectEvidenceMapper.ensureInitialized();
  p5.ProjectMilestoneMapper.ensureInitialized();
  p5.ProjectMemoryEntryMapper.ensureInitialized();
  p5.ProjectMemorySupersessionMapper.ensureInitialized();
  p5.ProjectDesiredPlanMapper.ensureInitialized();
  p5.ProjectPlanRevisionMapper.ensureInitialized();
  p5.PendingProjectPlanApprovalMapper.ensureInitialized();
  p5.ProjectCompletionReviewCheckpointMapper.ensureInitialized();
  p5.ProjectStateMapper.ensureInitialized();
  p5.ProjectRecoveryIncidentMapper.ensureInitialized();
  p5.ProjectDecisionRecordMapper.ensureInitialized();
  p5.ProjectBlockerMapper.ensureInitialized();
  p5.PendingProjectQuestionMapper.ensureInitialized();
  p5.ProjectStatusMapper.ensureInitialized();
  p5.ProjectCriterionStatusMapper.ensureInitialized();
  p5.ProjectVerificationModeMapper.ensureInitialized();
  p5.ProjectEvidenceStatusMapper.ensureInitialized();
  p5.ProjectEvidenceStrengthMapper.ensureInitialized();
  p5.ProjectMilestoneStatusMapper.ensureInitialized();
  p5.TaskReadinessMapper.ensureInitialized();
  p5.ProjectMemoryKindMapper.ensureInitialized();
  p5.ProjectMemorySourceTypeMapper.ensureInitialized();
  p5.ProjectMemoryConfidenceMapper.ensureInitialized();
  p5.ProjectPlanRevisionTriggerMapper.ensureInitialized();
  p5.ProjectCompletionReviewReasonMapper.ensureInitialized();
  p5.ProjectPlanApprovalPolicyMapper.ensureInitialized();
  p5.ProjectPlanRevisionApproverMapper.ensureInitialized();
  p5.ProjectBlockerTypeMapper.ensureInitialized();
  p5.ProjectDecisionTypeMapper.ensureInitialized();
  p5.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p6.PromptModuleMapper.ensureInitialized();
  p6.PromptPresetMapper.ensureInitialized();
  p6.SystemPromptSnapshotMapper.ensureInitialized();
  p7.TaskProjectCriterionMapper.ensureInitialized();
  p7.TaskEvidenceExpectationMapper.ensureInitialized();
  p7.TaskProjectEvidenceExpectationMapper.ensureInitialized();
  p7.RefinedTaskBriefMapper.ensureInitialized();
  p7.TaskMapper.ensureInitialized();
  p7.TaskStepMapper.ensureInitialized();
  p7.TaskGateMapper.ensureInitialized();
  p7.TaskGateResultMapper.ensureInitialized();
  p7.TaskFailureMapper.ensureInitialized();
  p7.TaskArtifactMapper.ensureInitialized();
  p7.TaskEvidenceClaimMapper.ensureInitialized();
  p7.TaskRunMapper.ensureInitialized();
  p7.TaskToolErrorMapper.ensureInitialized();
  p7.TaskToolCallRecordMapper.ensureInitialized();
  p7.PendingTaskApprovalMapper.ensureInitialized();
  p7.PendingTaskQuestionMapper.ensureInitialized();
  p7.TaskStatusMapper.ensureInitialized();
  p7.TaskPriorityMapper.ensureInitialized();
  p7.TaskRiskMapper.ensureInitialized();
  p7.ProjectRiskReductionMapper.ensureInitialized();
  p7.TaskEffortMapper.ensureInitialized();
  p7.ProjectEvidenceTypeMapper.ensureInitialized();
  p7.TaskStepStatusMapper.ensureInitialized();
  p7.TaskRunStatusMapper.ensureInitialized();
  p7.TaskGateStatusMapper.ensureInitialized();
  p7.TaskToolCallOutcomeMapper.ensureInitialized();
  p7.TaskToolErrorDispositionMapper.ensureInitialized();
  p7.TaskGateFailureDispositionMapper.ensureInitialized();
  p7.TaskEvidenceClaimTypeMapper.ensureInitialized();
  p7.TaskEvidenceClaimStrengthMapper.ensureInitialized();
  p8.AgentQuestionMapper.ensureInitialized();
  p8.QuestionKindMapper.ensureInitialized();
  p9.TaskPlanningContextMapper.ensureInitialized();
  p9.WorkspaceMetadataMapper.ensureInitialized();
  p10.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p10.WorkspaceRequiredContextIssueMapper.ensureInitialized();
  p10.WorkspaceFileExcerptMapper.ensureInitialized();
  p11.CalculatorOperationMapper.ensureInitialized();
}

