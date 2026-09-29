// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import '../../features/project/domain/project.dart' as p4;
import '../../features/project/domain/project_task_models.dart' as p5;
import '../../features/task/domain/task.dart' as p6;
import '../../features/task/domain/task_planning_models.dart' as p7;
import '../../shared_kernel/chat_message.dart' as p8;
import '../../shared_kernel/model_configuration.dart' as p9;
import '../../shared_kernel/planning_metrics.dart' as p10;
import '../../shared_kernel/project_planning_contracts.dart' as p11;
import '../../shared_kernel/project_workspace_graph.dart' as p12;
import '../../shared_kernel/system_prompt.dart' as p13;
import '../../shared_kernel/task_execution_contracts.dart' as p14;
import '../../shared_kernel/task_planning_types.dart' as p15;
import '../../shared_kernel/task_tool_contracts.dart' as p16;
import '../../shared_kernel/workspace_discovery_profile.dart' as p17;
import '../helpers/chat/context_summary_prompt.dart' as p0;
import '../models/model_load_configuration.dart' as p1;
import '../services/question_policy_service.dart' as p2;
import '../tools/calculator_tool.dart' as p3;

/// @nodoc
void initializeMappers() {
  p0.ContextSummaryMapper.ensureInitialized();
  p1.ModelLoadConfigurationMapper.ensureInitialized();
  p2.AgentQuestionMapper.ensureInitialized();
  p2.QuestionKindMapper.ensureInitialized();
  p3.CalculatorOperationMapper.ensureInitialized();
  p4.ProjectDiagnosticsMapper.ensureInitialized();
  p4.ProjectCriterionMapper.ensureInitialized();
  p4.ProjectEvidenceMapper.ensureInitialized();
  p4.ProjectMilestoneMapper.ensureInitialized();
  p4.ProjectMemoryEntryMapper.ensureInitialized();
  p4.ProjectMemorySupersessionMapper.ensureInitialized();
  p4.ProjectDesiredPlanMapper.ensureInitialized();
  p4.ProjectPlanRevisionMapper.ensureInitialized();
  p4.PendingProjectPlanApprovalMapper.ensureInitialized();
  p4.ProjectCompletionReviewCheckpointMapper.ensureInitialized();
  p4.ProjectBoundaryMapper.ensureInitialized();
  p4.ProjectAggregateMapper.ensureInitialized();
  p4.ProjectRecoveryIncidentMapper.ensureInitialized();
  p4.ProjectDecisionRecordMapper.ensureInitialized();
  p4.ProjectBlockerMapper.ensureInitialized();
  p4.PendingProjectQuestionMapper.ensureInitialized();
  p4.ProjectStatusMapper.ensureInitialized();
  p4.ProjectCriterionStatusMapper.ensureInitialized();
  p4.ProjectVerificationModeMapper.ensureInitialized();
  p4.ProjectEvidenceStatusMapper.ensureInitialized();
  p4.ProjectEvidenceStrengthMapper.ensureInitialized();
  p4.ProjectMilestoneStatusMapper.ensureInitialized();
  p4.TaskReadinessMapper.ensureInitialized();
  p4.ProjectMemoryKindMapper.ensureInitialized();
  p4.ProjectMemorySourceTypeMapper.ensureInitialized();
  p4.ProjectMemoryConfidenceMapper.ensureInitialized();
  p4.ProjectPlanRevisionTriggerMapper.ensureInitialized();
  p4.ProjectCompletionReviewReasonMapper.ensureInitialized();
  p4.ProjectPlanRevisionApproverMapper.ensureInitialized();
  p4.ProjectBlockerTypeMapper.ensureInitialized();
  p4.ProjectDecisionTypeMapper.ensureInitialized();
  p4.ProjectControlOutcomeMapper.ensureInitialized();
  p4.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p5.ProjectTaskNodeMapper.ensureInitialized();
  p6.TaskProjectCriterionMapper.ensureInitialized();
  p6.TaskProjectEvidenceExpectationMapper.ensureInitialized();
  p6.RefinedTaskBriefMapper.ensureInitialized();
  p6.TaskAggregateMapper.ensureInitialized();
  p6.TaskStepMapper.ensureInitialized();
  p6.TaskRunMapper.ensureInitialized();
  p6.TaskToolCallRecordMapper.ensureInitialized();
  p6.PendingTaskApprovalMapper.ensureInitialized();
  p6.PendingTaskQuestionMapper.ensureInitialized();
  p6.TaskStepStatusMapper.ensureInitialized();
  p6.TaskRunStatusMapper.ensureInitialized();
  p6.TaskToolCallOutcomeMapper.ensureInitialized();
  p7.TaskPlanningContextMapper.ensureInitialized();
  p7.WorkspaceMetadataMapper.ensureInitialized();
  p8.ChatMessageMapper.ensureInitialized();
  p9.ModelConfigurationSnapshotMapper.ensureInitialized();
  p10.PlanningMetricsMapper.ensureInitialized();
  p11.ProjectPlanApprovalPolicyMapper.ensureInitialized();
  p12.ProjectWorkspaceNodeMapper.ensureInitialized();
  p12.ProjectWorkspaceEdgeMapper.ensureInitialized();
  p12.ProjectWorkspaceGraphMapper.ensureInitialized();
  p12.ProjectWorkspaceSourceTypeMapper.ensureInitialized();
  p12.ProjectWorkspaceConfidenceMapper.ensureInitialized();
  p13.PromptModuleMapper.ensureInitialized();
  p13.PromptPresetMapper.ensureInitialized();
  p13.SystemPromptSnapshotMapper.ensureInitialized();
  p14.TaskGateMapper.ensureInitialized();
  p14.TaskEvidenceExpectationMapper.ensureInitialized();
  p14.TaskArtifactMapper.ensureInitialized();
  p14.TaskGateResultMapper.ensureInitialized();
  p14.TaskFailureMapper.ensureInitialized();
  p14.TaskEvidenceClaimMapper.ensureInitialized();
  p14.TaskGateStatusMapper.ensureInitialized();
  p14.TaskGateFailureDispositionMapper.ensureInitialized();
  p14.TaskEvidenceClaimTypeMapper.ensureInitialized();
  p14.TaskEvidenceClaimStrengthMapper.ensureInitialized();
  p15.TaskStatusMapper.ensureInitialized();
  p15.TaskPriorityMapper.ensureInitialized();
  p15.TaskRiskMapper.ensureInitialized();
  p15.ProjectRiskReductionMapper.ensureInitialized();
  p15.TaskEffortMapper.ensureInitialized();
  p15.ProjectEvidenceTypeMapper.ensureInitialized();
  p16.TaskToolErrorMapper.ensureInitialized();
  p16.TaskToolErrorDispositionMapper.ensureInitialized();
  p17.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p17.WorkspaceRequiredContextIssueMapper.ensureInitialized();
  p17.WorkspaceFileExcerptMapper.ensureInitialized();
}

