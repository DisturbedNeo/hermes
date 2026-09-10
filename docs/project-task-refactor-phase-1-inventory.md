# Project and Task Refactor: Phase 1 Inventory

This inventory records the pre-refactor behavior before changing the domain
models. It is intentionally limited to the current `ProjectTask`/
`TaskDocument` split and the execution paths that must remain covered during
later phases.

## Current model and persistence split

| Concern | Current owner | Persistence path | Main callers |
| --- | --- | --- | --- |
| Project planning, ordered project work, task lifecycle, dependencies, risk, milestones, evidence references, recovery references | `ProjectTask` embedded in `ProjectState.tasks` | `.agent/projects/<project-id>/project.json` through `ProjectRepository` | `ProjectService`, `ProjectScheduler`, `ProjectPlanValidator`, `ProjectPlanRevisionService`, `ProjectModelCalls`, project UI |
| Executable task plan, step cursor, approvals/questions, task status, task runs, tool records, artifacts, gate results, evidence claims, task memory | `TaskDocument` (`TaskSnapshot` typedef) | `.agent/tasks/<task-id>/task.json` through `TaskRepository` | `TaskService`, `ProjectService`, `ChatService`, task UI |
| Link between the two records | `ProjectTask.taskDocumentId`; project identity remains `ProjectTask.id` | Project snapshot stores the link; task snapshot stores `projectId` | `ProjectService._loadActiveTask`, `ChatService._taskForActiveProject`, recovery and evidence services |
| Task execution history and logs | `TaskDocument.runs` plus task tool records and log files | Task snapshot and `.agent/tasks/<task-id>/logs/` | `TaskService`, `TaskRepository`, `ChatService`, project evidence/progress code |

The current code therefore has two task identifiers in normal project
execution: the project-task ID and the task-document ID. The latter is used to
load execution state, while the former is used for scheduling, dependencies,
plan revisions, and project history.

## Read and write inventory

### Project-side reads and writes

- `lib/core/models/project.dart`
  - Defines `ProjectTaskStatus`, `ProjectPlanRevisionTrigger`, `ProjectState`,
    `ProjectTask`, project evidence, milestones, recovery incidents, decisions,
    and diagnostics.
  - `ProjectState.tasks`, `activeTaskId`, and `taskById` are the project-side
    task collection and cursor.
  - `ProjectTask` contains planning fields and the nullable
    `taskDocumentId` link, but no executable steps or task runs.
- `lib/core/services/project_system/project_repository.dart`
  - Reads and writes complete project snapshots at
    `.agent/projects/<project-id>/project.json`.
  - Lists project summaries using `activeTaskId`; it does not load task
    documents while listing.
- `lib/core/services/project_system/project_service.dart`
  - Reads `ProjectState.tasks` for scheduling, dependency validation,
    duplicate detection, plan revision, completion, failure/recovery, and
    project UI status.
  - Writes project task status and `taskDocumentId` while selecting, running,
    evaluating, cancelling, and recovering work.
  - Loads the active executable task through `activeTaskDocumentId`, then
    copies executable status back into the matching `ProjectTask`.
  - Records project decisions, evidence, artifacts, recovery incidents,
    completion state, diagnostics, and pending replan triggers in the project
    snapshot.
- `lib/core/services/project_system/project_scheduler.dart`
  - Reads project task IDs, statuses, priorities, milestones, and dependency
    IDs to derive readiness and select the next task.
  - Returns a refreshed project with scheduling rationale; readiness is
    derived and does not itself persist a separate task record.
- `lib/core/services/project_system/project_plan_validator.dart`
  - Reads task IDs, dependencies, statuses, paths, effort, gates/evidence,
    criteria, and milestone membership to validate proposed complete plans.
- `lib/core/services/project_system/project_plan_revision_service.dart`
  - Reads and reconciles existing `ProjectTask` records by canonical project
    task ID, preserving terminal history and applying mutable updates.
  - Writes project tasks, plan history, status/blockers, and pending approval
    state through the returned `ProjectState`.
- `lib/core/services/project_system/project_model_calls.dart`
  - Reads planner JSON into `ProjectTask` records and emits complete desired
    plans containing project task IDs, dependencies, status, and planning
    metadata.
- `lib/core/services/project_system/project_evidence_service.dart` and
  `project_progress_monitor.dart`
  - Read project task identity and the task result/history projection to
    attribute evidence and progress to project tasks.

### Task-side reads and writes

- `lib/core/models/task.dart`
  - Defines `TaskStatus`, step/run statuses, gates, artifacts, evidence
    claims, tool records, and `TaskDocument`.
  - `TaskDocument.runs` is the existing execution history. `currentStepId`
    is the executable cursor; `projectId` links the document back to a
    project.
- `lib/core/services/task_system/task_repository.dart`
  - Reads and writes task snapshots at `.agent/tasks/<task-id>/task.json`.
  - Performs the existing task schema migration/backup behavior and preserves
    logs under `.agent/tasks/<task-id>/logs/`.
  - Lists and filters task documents by chat session and project ID.
- `lib/core/services/task_system/task_service.dart`
  - Creates standalone and project task documents, loads/recoveries them,
    updates task plans, runs steps, evaluates gates, records tool calls and
    `TaskRun` history, handles approvals/questions, retries/skips/stops work,
    and replans unfinished steps.
  - Persists task state before/after execution work and persists task logs via
    `TaskRepository`.
- `lib/core/services/chat/chat_service.dart`
  - Reads the active task snapshot and task summaries for the UI, reloads and
    recovers task snapshots, and resolves the active project task through
    `ProjectState.activeTaskDocumentId`.
  - Coordinates task cancellation, step actions, chat-scope migration, and
    project execution callbacks.
- `lib/ui/chat/task_panel.dart`, `lib/ui/chat/project_panel_sections.dart`,
  and `lib/ui/overlays/workspace_panel.dart`
  - Read both `TaskDocument`/`TaskStatus` and `ProjectTask`/
    `ProjectTaskStatus` to render active task execution separately from the
    project backlog/history.

## Execution and replan behavior confirmed in Phase 1

`ProjectService.runProject` currently follows this boundary:

1. Recover an interrupted project and active task.
2. Process pending plan approval or eligible replan triggers.
3. Schedule and validate one project task.
4. Persist the project as the task becomes active.
5. Create/load the `TaskDocument`, then execute its runnable steps through
   `TaskService`.
6. Persist task execution state and synchronize the project-side task.
7. Evaluate task status, evidence, gates, recovery, criteria, and progress.
8. Persist the project at the task boundary.
9. Continue to another ready task until the configured `maxNewTasks` limit,
   a blocker, interruption, completion, or a valid replan trigger is reached.

Successful task completion does not add a runtime replan trigger by itself.
The runtime trigger set is limited to no-ready-task, task failure, rejected
evidence, an explicit task replan request, scope changes, and milestone
roadmap changes. A new regression test in
`test/core/services/project_service_test.dart` runs two distinct successful
tasks in one bounded batch and asserts that `revisePlan` is not called between
them.

## Existing behavior coverage

- Planning and validation: `project_service_test.dart`,
  `project_plan_validator_test.dart`, `project_plan_revision_service_test.dart`,
  `project_planning_gateway_test.dart`.
- Scheduling and dependencies: `project_scheduler_test.dart`.
- Task execution, approvals, gates, evidence claims, interruption, and task
  run history: `task_service_test.dart`, `task_gate_evaluator_test.dart`,
  `task_gate_test.dart`.
- Project evidence and criterion evaluation:
  `project_evidence_service_test.dart`.
- Recovery, cancellation, project/task identity mapping, and terminal history:
  `project_service_test.dart`, `project_lifecycle_characterization_test.dart`.
- Snapshot serialization and persistence/recovery:
  `model_json_test.dart`, `project_storage_service_test.dart`,
  `task_storage_service_test.dart`, `persistence_lifecycle_test.dart`.

This is the baseline for Phase 2. It does not introduce compatibility
adapters, migrations, batch fields, or domain model changes.
