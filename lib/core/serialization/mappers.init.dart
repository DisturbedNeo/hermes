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
import '../models/project_workspace_graph.dart' as p6;
import '../models/system_prompt.dart' as p7;
import '../models/task.dart' as p8;
import '../services/project_system/project_task_models.dart' as p9;
import '../services/question_policy_service.dart' as p10;
import '../services/task_system/task_service.dart' as p11;
import '../services/workspace_discovery_profile.dart' as p12;
import '../tools/calculator_tool.dart' as p13;

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
  p5.ProjectBoundaryMapper.ensureInitialized();
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
  p5.ProjectControlOutcomeMapper.ensureInitialized();
  p5.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p6.ProjectWorkspaceNodeMapper.ensureInitialized();
  p6.ProjectWorkspaceEdgeMapper.ensureInitialized();
  p6.ProjectWorkspaceGraphMapper.ensureInitialized();
  p6.ProjectWorkspaceSourceTypeMapper.ensureInitialized();
  p6.ProjectWorkspaceConfidenceMapper.ensureInitialized();
  p7.PromptModuleMapper.ensureInitialized();
  p7.PromptPresetMapper.ensureInitialized();
  p7.SystemPromptSnapshotMapper.ensureInitialized();
  p8.TaskProjectCriterionMapper.ensureInitialized();
  p8.TaskEvidenceExpectationMapper.ensureInitialized();
  p8.TaskProjectEvidenceExpectationMapper.ensureInitialized();
  p8.RefinedTaskBriefMapper.ensureInitialized();
  p8.TaskMapper.ensureInitialized();
  p8.TaskStepMapper.ensureInitialized();
  p8.TaskGateMapper.ensureInitialized();
  p8.TaskGateResultMapper.ensureInitialized();
  p8.TaskFailureMapper.ensureInitialized();
  p8.TaskArtifactMapper.ensureInitialized();
  p8.TaskEvidenceClaimMapper.ensureInitialized();
  p8.TaskRunMapper.ensureInitialized();
  p8.TaskToolErrorMapper.ensureInitialized();
  p8.TaskToolCallRecordMapper.ensureInitialized();
  p8.PendingTaskApprovalMapper.ensureInitialized();
  p8.PendingTaskQuestionMapper.ensureInitialized();
  p8.TaskStatusMapper.ensureInitialized();
  p8.TaskPriorityMapper.ensureInitialized();
  p8.TaskRiskMapper.ensureInitialized();
  p8.ProjectRiskReductionMapper.ensureInitialized();
  p8.TaskEffortMapper.ensureInitialized();
  p8.ProjectEvidenceTypeMapper.ensureInitialized();
  p8.TaskStepStatusMapper.ensureInitialized();
  p8.TaskRunStatusMapper.ensureInitialized();
  p8.TaskGateStatusMapper.ensureInitialized();
  p8.TaskToolCallOutcomeMapper.ensureInitialized();
  p8.TaskToolErrorDispositionMapper.ensureInitialized();
  p8.TaskGateFailureDispositionMapper.ensureInitialized();
  p8.TaskEvidenceClaimTypeMapper.ensureInitialized();
  p8.TaskEvidenceClaimStrengthMapper.ensureInitialized();
  p9.ProjectTaskNodeMapper.ensureInitialized();
  p10.AgentQuestionMapper.ensureInitialized();
  p10.QuestionKindMapper.ensureInitialized();
  p11.TaskPlanningContextMapper.ensureInitialized();
  p11.WorkspaceMetadataMapper.ensureInitialized();
  p12.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p12.WorkspaceRequiredContextIssueMapper.ensureInitialized();
  p12.WorkspaceFileExcerptMapper.ensureInitialized();
  p13.CalculatorOperationMapper.ensureInitialized();
}

