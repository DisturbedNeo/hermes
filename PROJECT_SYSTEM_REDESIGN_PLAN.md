# Project and Task System Redesign Plan

Status: Implemented — Milestones 0–7 complete  
Scope: Hermes project planning, orchestration, verification, persistence, and task-panel UX  
Implementation approach: Incremental, backward-compatible milestones

## 1. Purpose

Redesign the project system so that Hermes can turn a broad goal into a durable,
inspectable project plan; choose work for explicit reasons; verify progress with
evidence; and revise the plan as the workspace changes.

The existing task executor, gates, recovery incidents, question policy, atomic
snapshots, and cancellation behavior remain the foundation. This redesign changes
how project work is represented and orchestrated around that foundation.

## 2. Desired outcome

After the redesign, a project should be able to answer all of these questions from
persisted state without asking a model to reconstruct the answers:

1. What outcomes must be achieved?
2. What evidence proves each outcome?
3. What milestones and tasks are currently planned?
4. Which tasks are ready, blocked, deferred, completed, or obsolete, and why?
5. Why was the current task selected?
6. What changed after the last task, and did that require replanning?
7. Which facts, assumptions, decisions, and risks are still active?
8. What exact condition will complete or block the project?

## 3. Design principles

1. **Outcomes before activities.** Project completion is based on verified success
   criteria, not task counts or task labels.
2. **Rolling-wave planning.** Plan milestones and the near-term backlog in detail;
   leave distant work coarse until new evidence makes it useful to refine.
3. **Models propose; deterministic code decides invariants.** Models may propose
   plans, evidence claims, and revisions. Code validates dependencies, readiness,
   state transitions, deduplication, budgets, and completion rules.
4. **Evidence is explicit.** A completed task may contribute evidence, but it does
   not automatically satisfy every criterion attached to it.
5. **Every scheduling decision is explainable.** Selection rationale and blocked
   reasons are persisted and visible.
6. **Replanning is an event, not an accident.** Every plan revision has a trigger,
   validation result, diff, and timestamp.
7. **User authority is preserved.** Irreversible choices, credentials, material
   scope changes, and subjective acceptance can still stop for user input.
8. **Recovery remains first-class.** Failed gates and recovery incidents take
   precedence over ordinary backlog work.
9. **Compatibility is a feature.** Existing schema-v2 projects must load, migrate,
   and remain operable without losing their history.
10. **Sequential execution first.** This redesign models future parallel-ready work
    but does not run mutating tasks concurrently until conflict isolation exists.

### Non-goals

- Replacing the existing workspace tools, task executor, or gate catalog wholesale.
- Moving `.agent` project state into a remote service or database.
- Introducing multi-agent execution as part of the redesign.
- Running project tasks concurrently.
- Removing raw task runs, tool-call records, artifacts, or recovery history.
- Automatically changing the user's project scope to make completion easier.

## 4. Current baseline and gaps

### Preserve

- Atomic project and task snapshots under `.agent/`.
- Versioned JSON decoding and in-place project migration.
- Bounded project tasks with done and out-of-scope criteria.
- Task steps, artifacts, gates, tool-call records, and replanning.
- Recovery incidents and repair-task prioritization.
- Question autonomy and durable user answers.
- Project decisions and task run history.
- Run, pause, resume, cancel, approval, and interruption recovery behavior.

### Address

- `successCriteria` are strings rather than independently tracked outcomes.
- A completed task currently credits all of its `relevantSuccessCriteria`.
- The backlog is an ordered list with no dependency, milestone, priority, risk, or
  readiness model.
- Selection takes the first valid queued task before considering relative value.
- `refreshBacklog()` exists but is not part of the orchestration loop.
- Project initialization, task selection, and completion use different levels of
  workspace awareness.
- `knownFacts` mixes requirements, assumptions, decisions, summaries, and risks,
  then truncates the combined text at a fixed character limit.
- Project phases are recorded, but do not correspond to persisted plan artifacts or
  explicit phase gates.
- Project approval UI exists for a `proposed` task state that ordinary scheduling
  does not normally produce.
- Project progress is primarily presented as completed-task and iteration counts.
- The hard-coded project-task plan limit of three steps is not tied to risk or
  expected effort.

## 5. Target architecture

Keep `ProjectService` as the transaction coordinator, but extract the following
roles behind small, testable services:

| Component | Responsibility |
| --- | --- |
| `ProjectDiscoveryService` | Build a compact, current evidence snapshot of the workspace and recent project activity. |
| `ProjectPlanningService` | Request initial plans and rolling plan revisions from the model. |
| `ProjectPlanValidator` | Enforce IDs, dependencies, boundedness, coverage, artifact paths, and revision invariants. |
| `ProjectScheduler` | Compute readiness and deterministically choose the next eligible task. |
| `ProjectEvidenceService` | Normalize task outputs, artifacts, gate results, and user approval into evidence records. |
| `ProjectCriterionEvaluator` | Update criterion status from evidence and request model review only where deterministic checks are insufficient. |
| `ProjectMemoryService` | Maintain structured active memory and compact historical context without losing protected entries. |
| `ProjectService` | Persist state transitions, invoke the components above, execute tasks, and enforce recovery/budget policy. |

The target orchestration cycle is:

```text
intake
  -> discovery snapshot
  -> initial plan proposal
  -> validate / optionally approve
  -> calculate task readiness
  -> select one ready task with rationale
  -> create and execute bounded TaskDocument
  -> collect gates, artifacts, claims, and failures
  -> update evidence and criterion states
  -> evaluate replan triggers
  -> revise or continue the rolling plan
  -> complete only when all required criteria are verified
```

## 6. Schema-v3 design

Increment `ProjectState.currentSchemaVersion` from 2 to 3. Task schema changes are
only required when evidence-output fields are added; those should be introduced in
a separate task-schema migration rather than coupled to the first project migration.

### 6.1 `ProjectCriterion`

Replace `List<String> successCriteria` in persisted v3 state with
`List<ProjectCriterion> criteria`.

Fields:

```text
id                    stable project-local ID
statement             user-visible outcome
required              whether project completion requires it
status                unsatisfied | partial | satisfied | invalidated
verificationMode      deterministic | modelReview | humanApproval | mixed
evidenceIds           accepted evidence supporting the current status
notes                 concise explanation of status
createdAt
updatedAt
verifiedAt            nullable
```

Rules:

- Criteria IDs never change when wording is edited.
- Only `required && status != satisfied` criteria block ordinary completion.
- `invalidated` requires a recorded plan revision or user decision explaining why.
- A criterion cannot become `satisfied` without at least one accepted evidence
  record, except for explicitly migrated legacy state.
- Compatibility getters may expose `successCriteria` as criterion statements while
  call sites migrate.

### 6.2 `ProjectEvidence`

Fields:

```text
id
type                  gate | artifact | command | taskClaim | userApproval | migrated
criterionIds
projectTaskId         nullable
taskDocumentId        nullable
sourceRef             gate ID, artifact path, run ID, or decision ID
sourceFingerprint     nullable hash or stable version for staleness checks
summary
status                proposed | accepted | rejected | stale
strength              advisory | supporting | conclusive
details               structured JSON-safe metadata
createdAt
evaluatedAt           nullable
```

Rules:

- Gate results and workspace-verifiable artifacts are normalized
  deterministically.
- Model-generated claims begin as `proposed` unless a configured verification mode
  permits model review to accept them.
- Evidence becomes `stale` when a later plan revision, failed verification, or
  changed artifact invalidates it.
- Artifact existence alone is not conclusive evidence of semantic correctness.

### 6.3 `ProjectMilestone`

Fields:

```text
id
title
objective
criterionIds
status                planned | active | completed | blocked | cancelled
exitConditions
taskIds
order
createdAt
updatedAt
completedAt           nullable
```

Milestones provide a stable roadmap. They are not executable and must not duplicate
task state.

### 6.4 Enriched `ProjectTask`

Keep the existing bounded-task fields and add:

```text
milestoneId           nullable for recovery or unclassified work
criterionIds          replaces persisted relevant criterion strings
dependsOnTaskIds
priority              critical | high | normal | low
risk                   high | medium | low | unknown
riskReduction          high | medium | low | none
effort                 small | medium | large
readiness              ready | waitingDependency | waitingInput | notEligible
readinessReasons
selectionRationale    populated when selected
revisionIntroduced
revisionUpdated
expectedEvidence      typed evidence expectations
readPaths             advisory footprint
writePaths            advisory footprint
```

Rules:

- Add `deferred` and `obsolete` to `ProjectTaskStatus` for plan-lifecycle state.
- Narrow `readiness` to `ready | waitingDependency | waitingInput | notEligible`;
  it is derived from task status, dependencies, questions, approvals, and incidents.
- `readiness` and `readinessReasons` are persisted caches for diagnostics and UI, but
  are always recomputed by the scheduler after load, manual editing, and transitions;
  model output is never authoritative for them.
- Dependencies must reference known tasks and form an acyclic graph.
- Completed, cancelled, rejected, split, and obsolete tasks are not schedulable.
- Recovery tasks may bypass ordinary dependencies but remain tied to their incident.
- `large` tasks fail validation unless the planner splits them or records a specific
  exception approved by the user.
- Read/write footprints are advisory in the first release and become prerequisites
  for any later parallel execution.

### 6.5 `ProjectMemoryEntry`

Replace persisted `knownFacts` with structured memory:

```text
id
kind                  requirement | fact | assumption | decision | risk | summary
content
sourceType            user | planner | task | gate | migration | system
sourceId              nullable
confidence            confirmed | inferred | uncertain
protected             prevents ordinary compaction
active
supersedesId          nullable
coveredEntryIds       source memory IDs represented by a summary/replacement
createdAt
updatedAt
```

Rules:

- User requirements, unresolved risks, and active decisions are protected.
- Superseded entries remain in history but are excluded from active planning context.
- Compaction creates a new summary entry and deactivates only the entries it covers.
- Compatibility getters may expose active entries as `knownFacts` during migration.

### 6.6 `ProjectPlanRevision`

Fields:

```text
revision
trigger               initialization | migration | taskCompleted | taskFailed | newContext |
                      noReadyTask | milestoneCompleted | manual | workspaceChanged
summary
rationale
addedTaskIds
updatedTaskIds
removedTaskIds
criterionChanges
milestoneChanges
validationWarnings
createdAt
approvedAt            nullable
approvedBy            automatic | user | nullable
```

`ProjectState` stores the current revision number and an append-only revision
history. The complete current plan remains in criteria, milestones, and task
collections; revisions store the audit diff rather than full duplicated snapshots.

### 6.7 Pending plan approval

Add a `PendingProjectPlanApproval` value containing:

```text
revision
reason
summary
highRiskChanges
createdAt
```

This replaces the currently disconnected concept of approving a single proposed
task. Approval policy should be configurable:

- `never`: accept valid revisions automatically.
- `highRiskOnly`: require approval for scope, destructive, high-risk, or criterion
  changes. Recommended default.
- `everyRevision`: require approval for every proposed plan revision.

Approving atomically applies the validated diff. Rejecting discards the proposal,
records a decision, and preserves the authoritative plan. If rejection leaves no
ready work, the project pauses with a plan-approval blocker rather than repeatedly
requesting the same revision.

## 7. Discovery and planning contracts

### 7.1 `ProjectEvidenceSnapshot`

Before initialization or replanning, collect a bounded snapshot containing:

- Workspace name and root structure.
- Relevant project and task artifact index.
- Git availability and a bounded changed-file summary when available.
- Recent task results, gate failures, and recovery incidents.
- Current criterion statuses and accepted evidence.
- Active memory entries and unresolved questions.
- Ready, blocked, and recently completed task summaries.
- Known verification commands and their most recent result.

Collection must be read-only, cancellable, size-bounded, and tolerant of missing Git
or command permission. Expensive command execution is not part of discovery unless
already represented by a gate result.

### 7.2 Initial plan output

Project initialization should produce:

- Refined goal, constraints, and structured criteria.
- Active memory entries for confirmed facts and explicit assumptions.
- One to three milestones for a typical project.
- A detailed near-term backlog of approximately three to seven bounded tasks.
- Coarser milestone descriptions for distant work.
- Dependencies, priority, risk, effort, expected evidence, and rationale.
- Only genuinely blocking questions under the existing question policy.

Initialization must not execute work.

### 7.3 Plan revision output

Replace the unused backlog-refresh result with `ProjectPlanProposal`, containing:

- Proposed criterion and milestone edits.
- Task additions, updates, deferrals, and obsoletions.
- New memory entries and proposed supersessions.
- Revision rationale and assumptions.
- Whether the model believes approval is required and why.

The model must never directly mutate completed task history, accepted gate results,
recovery incidents, or user-authored protected memory.

### 7.4 Validation

`ProjectPlanValidator` rejects or repairs proposals that contain:

- Unknown or duplicate stable IDs.
- Cyclic or missing dependencies.
- A task depending on itself.
- A task equivalent to the entire project goal.
- Duplicate work already queued, active, completed, or failed without retry context.
- A task with no done criteria, boundary, or expected verification.
- Paths outside the attached workspace.
- Removal of a required criterion without an approved scope decision.
- Mutation of immutable history.
- More ready tasks than the configured planning horizon without justification.

Validation returns structured codes and paths, not only prose. One model repair pass
is allowed. A deterministic safe fallback may preserve the existing plan and create
a blocker; it must not invent broad placeholder work such as “make focused progress.”

## 8. Scheduling

### 8.1 Readiness calculation

`ProjectScheduler` recalculates readiness after every persisted transition:

- `ready`: all dependencies completed and no blocking input or active incident.
- `waitingDependency`: at least one dependency is unfinished.
- `waitingInput`: linked question, approval, credential, or external decision blocks it.
- `notEligible`: task status is deferred, obsolete, running, or terminal.

Readiness reasons list the exact dependency, question, approval, or revision causing
the state. Deferred and obsolete remain persisted task statuses rather than computed
readiness states.

### 8.2 Deterministic task selection

Recovery work remains first. Otherwise, choose among ready tasks using this stable
ordering:

1. Critical priority before high, normal, and low.
2. Tasks that unblock the largest number of downstream tasks.
3. Higher `riskReduction` value before routine work.
4. Active milestone before later milestones.
5. Older ready task before newer task.
6. Stable task ID as the final tie-breaker.

Persist a human-readable rationale containing the winning factors. The model is
consulted only when no valid ready task exists and a plan revision is needed.

### 8.3 Parallelism boundary

Do not execute multiple tasks concurrently in this redesign. Model dependencies and
read/write footprints now so a future project can add parallel read-only or disjoint
work after implementing leases, conflict checks, result merging, and cancellation
semantics.

## 9. Execution and evidence flow

### 9.1 Task creation

Pass the task planner:

- Project and milestone objective.
- Stable criterion IDs and done criteria.
- Dependency result summaries and usable artifacts.
- Expected evidence.
- Active structured memory relevant to the task.
- Explicit out-of-scope boundaries.
- Risk and effort.

Replace the fixed three-step cap with an effort-derived cap:

- `small`: up to 3 steps.
- `medium`: up to 5 steps.
- `large`: must be split at project level; no normal task plan is created.

Task steps remain linear initially. This avoids introducing two dependency engines at
once.

### 9.2 Task completion output

Extend `finish_task_step` and task aggregation so the final task result can include
structured evidence claims:

```text
criterionId
claim
evidenceType
sourceRef
suggestedStrength
```

Claims are advisory until `ProjectEvidenceService` normalizes and evaluates them.
Existing artifacts, tool records, and gate results remain the authoritative raw data.

### 9.3 Criterion evaluation

For each task result:

1. Normalize gates, commands, artifacts, approvals, and task claims into evidence.
2. Apply deterministic verification rules first.
3. Invoke model review only for semantic or subjective criteria.
4. Persist accepted/rejected evidence and criterion status explanations.
5. Mark evidence stale if subsequent verification contradicts it.
6. Complete the project only when all required criteria are satisfied, no blocking
   question/approval/recovery incident remains, and required final gates pass.

A completed task may leave its criterion `partial` or `unsatisfied`; that is normal
and should trigger additional planning rather than rewriting task history.

## 10. Replanning policy

### Mandatory triggers

- Project initialization.
- No valid ready task exists and the project is incomplete.
- A milestone reaches all exit conditions.
- A task requests project-level replanning.
- A task fails without an immediately valid recovery task.
- The user materially changes scope, constraints, or requirements.
- Criterion evidence is rejected or becomes stale.

### Conditional triggers

- A task completes and introduces a new risk, assumption, dependency, or artifact.
- The workspace changed outside the active task's expected footprint.
- The ready backlog falls below two tasks.
- Three tasks have completed since the last revision.

### No-replan cases

- A task completes exactly as planned and enough ready work remains.
- Only task run summaries or timestamps changed.
- A recovery task is already ready for an active incident.

Replanning should be debounced: multiple triggers collected during one task transition
produce one revision with all reasons.

## 11. Memory and context management

Build model context from relevance-ranked active entries rather than concatenating all
history:

1. Protected user requirements and decisions.
2. Current criterion and milestone facts.
3. Active risks and assumptions.
4. Facts sourced by dependencies of the selected task.
5. Recent task summaries.
6. Older general summaries within the remaining budget.

Compaction must be semantic and auditable:

- Never truncate an entry mid-string.
- Never silently discard newest information.
- Retain the source IDs covered by a summary.
- Allow a later fact or user answer to supersede an earlier assumption.
- Test deterministic selection separately from model-generated summarization.

## 12. User experience

Redesign the project panel around decisions and outcomes.

### Overview

- Goal and current phase.
- Criterion progress: satisfied, partial, blocked, and remaining.
- Active milestone and current task.
- Current blocker or requested approval.
- Latest plan revision and why it occurred.

### Roadmap

- Milestones with exit-condition progress.
- Ready tasks in scheduler order.
- Waiting tasks grouped by dependency or input.
- Deferred and obsolete tasks collapsed by default.
- Selection rationale on the active task.

### Evidence

- Evidence grouped by criterion.
- Source gate, command, artifact, user approval, or task run.
- Accepted, proposed, rejected, and stale status.
- Direct artifact opening where the sandbox already supports it.

### Plan review

- Revision summary and rationale.
- Added, changed, deferred, and obsolete task diff.
- Criterion and milestone changes called out separately.
- Warnings and high-risk changes.
- Approve, reject, or edit actions.

### Controls

- `Run Next Ready Task`.
- `Continue Project`.
- `Replan` with an optional user reason.
- `Approve Plan Revision` when required.
- `Pause`, `Stop`, and recovery controls.
- Retain raw JSON editing as an advanced/debug action rather than the primary editor.

Task-level UI remains mostly unchanged except for displaying project criterion IDs and
evidence expectations when the task belongs to a project.

## 13. Persistence and migration

### 13.1 Project v2 to v3 migration

The migration must be deterministic and idempotent:

1. Convert each success-criterion string, in order, to a stable
   `criterion_001`, `criterion_002`, ... record.
2. Map each task's relevant criterion strings to criterion IDs using normalized exact
   matching. Preserve unmatched strings in task context rather than inventing new
   project criteria.
3. For completed legacy tasks, create accepted `migrated` evidence for matched
   criteria and preserve their prior satisfied interpretation. Mark its strength as
   `supporting` and explain its legacy source.
4. Convert each `knownFacts` entry into active memory. User-answer entries become
   protected facts; other entries become inferred facts or summaries.
5. Create a baseline milestone when existing task history is non-empty; otherwise
   leave milestones empty for the first plan revision.
6. Give existing backlog tasks no dependencies, normal priority, unknown risk, small
   effort unless their current shape requires a later planner repair.
7. Create revision 1 with trigger `migration` and no pending approval.
8. Preserve all decisions, artifacts, recovery incidents, task document IDs,
   timestamps, statuses, and chat associations.

Before the first v3 write, retain a one-time `project.v2.json` copy alongside the
atomic snapshot. Do not overwrite that migration backup on later saves. Loading and
listing should continue to skip unreadable projects without affecting healthy ones.

### 13.2 Transitional compatibility

- Provide compatibility getters for criterion statements and active fact strings.
- Migrate service and UI call sites incrementally, but serialize only the v3 shape
  after migration.
- Decode both camelCase and existing snake_case aliases.
- Regenerate and commit `dart_mappable` output with each model milestone.
- Do not require a task-schema migration until evidence claims are persisted in
  `TaskDocument` or `TaskRun`.

## 14. Observability and diagnostics

Add structured project events or enrich decision records with:

- Plan revision requested, repaired, accepted, rejected, or blocked.
- Replan trigger codes.
- Validator error codes and repair attempts.
- Readiness changes and reasons.
- Scheduler candidate scores and selected rationale.
- Evidence proposed, accepted, rejected, or invalidated.
- Criterion status transitions.
- Memory compaction and supersession.
- Model-call label, duration, cancellation, and parse/repair outcome.

Diagnostics must avoid storing secrets and should cap verbose model text independently
from authoritative state.

Track aggregate counters useful for regression testing and later telemetry:

- Model calls per completed project task.
- Invalid plan proposals per revision.
- Replans per completed task.
- Tasks completed without advancing any criterion.
- Criterion reversals after stale evidence.
- Runs blocked by no ready task.
- User approvals and questions per project.

### 14.1 Expected file impact

This map is directional; implementation goals should narrow it before editing.

| Area | Existing files expected to change | Likely additions |
| --- | --- | --- |
| Project models and migration | `lib/core/models/project.dart`, `lib/core/models/project_json_migration.dart`, generated project mapper | Focused model files may be extracted if `project.dart` becomes unwieldy. |
| Project orchestration | `lib/core/services/project_system/project_service.dart`, `project_model_calls.dart`, `project_repository.dart` | `project_discovery_service.dart`, `project_planning_service.dart`, `project_plan_validator.dart`, `project_scheduler.dart`, `project_evidence_service.dart`, `project_criterion_evaluator.dart`, `project_memory_service.dart` |
| Task integration | `lib/core/models/task.dart`, `lib/core/services/task_system/task_service.dart`, task mapper and repository if the task schema changes | Evidence-claim DTOs if they are shared across task and project layers. |
| Chat coordination | `lib/core/services/chat/chat_service.dart`, `lib/core/models/task_system_settings.dart`, preferences mapping | Plan-approval policy preference and manual-replan methods. |
| Project UI | `lib/ui/chat/task_panel.dart`, `task_panel_dialogs.dart`, settings overlay | Small criterion, roadmap, evidence, and revision widgets should be split into dedicated files rather than further enlarging `task_panel.dart`. |
| Serialization | `lib/core/serialization/mappers.init.dart` and generated mapper outputs | Schema-v3 fixtures under `test/fixtures/projects/`. |
| Tests | Existing project model, repository, service, task service, chat service, and task-panel tests | Pure validator, scheduler, evidence, criterion, memory, migration-fixture, and lifecycle integration tests. |

Generated mapper files must be changed only by the configured build-runner workflow,
not hand-edited.

## 15. Implementation milestones

Each milestone below is intended to be a separately executable implementation goal.

### Milestone 0: Characterization and scaffolding

Status: Implemented on 2026-09-02.

Deliverables:

- Add lifecycle characterization tests around current initialization, queued-task
  selection, task completion, recovery priority, question blocking, and completion.
- Record representative schema-v2 fixtures, including active, completed, blocked,
  recovery, and partially corrupt projects.
- Introduce service interfaces and pure result types without changing behavior.
- Document state-machine invariants in tests.

Acceptance:

- Existing behavior remains unchanged.
- Full tests and `dart analyze` pass.
- Fixtures can be decoded and round-tripped before the v3 migration is introduced.

### Milestone 1: Schema v3 and migration

Implementation status: Completed on 2026-09-02.

Deliverables:

- Add criteria, evidence, milestones, memory, revision, and enriched-task models.
- Implement deterministic v2-to-v3 migration and one-time migration backup.
- Add compatibility getters and mapper aliases.
- Add model, serialization, repository, corruption-recovery, and idempotence tests.

Acceptance:

- Every v2 fixture loads as a valid v3 project and retains historical fields.
- Loading a migrated project twice produces the same semantic state.
- New projects round-trip only the v3 JSON shape.
- Full tests and `dart analyze` pass.

### Milestone 2: Evidence-driven completion

Implementation status: Completed on 2026-09-02.

Deliverables:

- Implement `ProjectEvidenceService` and `ProjectCriterionEvaluator`.
- Normalize current gate results and artifacts into evidence.
- Stop automatically crediting a criterion solely because a task completed.
- Require accepted evidence for new-project completion.
- Preserve migrated completion semantics for legacy projects.

Acceptance:

- A completed task can leave a criterion partial or unsatisfied.
- Deterministic gate evidence can satisfy configured criteria without a model call.
- Semantic criteria use bounded model review with persisted rationale.
- Completion cannot occur while a required criterion lacks accepted evidence.

### Milestone 3: Rolling plan revisions

Implementation status: Completed on 2026-09-02.

Deliverables:

- Replace `ProjectBacklogRefresh` with a structured plan proposal.
- Implement discovery snapshots, initial roadmaps, and replan triggers.
- Add plan validation, one repair pass, revision diffs, and approval policy.
- Remove deterministic broad-placeholder splits in favor of preserving state and
  producing an actionable blocker when repair fails.

Acceptance:

- Initialization creates criteria, milestones, and a near-term backlog.
- Mandatory triggers create exactly one debounced revision.
- Invalid proposals cannot mutate authoritative state.
- High-risk revisions wait for approval under the default policy.

### Milestone 4: Dependency scheduler

Implementation status: Completed on 2026-09-02.

Deliverables:

- Implement dependency validation, readiness calculation, and deterministic selection.
- Persist selection rationale and readiness reasons.
- Prioritize active recovery incidents above normal scheduling.
- Replace first-valid-backlog selection.

Acceptance:

- Cycles and missing dependencies are rejected.
- Waiting tasks never execute.
- Scheduler selection is stable for identical state.
- Recovery behavior retains existing limits and retry semantics.

### Milestone 5: Structured memory

Implementation status: Completed on 2026-09-03.

Deliverables:

- Route user answers, task summaries, assumptions, decisions, and risks into typed
  memory entries.
- Implement supersession, protection, relevance selection, and auditable compaction.
- Replace fixed character truncation.

Acceptance:

- New facts are never silently discarded because the memory budget is full.
- User requirements survive compaction.
- Superseded assumptions stop appearing in active planning context.
- Context selection remains within configured limits.

### Milestone 6: Project UX

Implementation status: Completed on 2026-09-03.

Deliverables:

- Add outcome progress, roadmap, readiness, evidence, and revision-diff sections.
- Add manual replan and plan-approval flows.
- Display scheduler rationale and blocker reasons.
- Retain accessible labels, keyboard behavior, empty states, and raw JSON editing.

Acceptance:

- Users can understand why work is ready or blocked without inspecting JSON.
- Users can review material plan changes before execution.
- UI tests cover criterion, milestone, evidence, revision, and approval states.

### Milestone 7: Task-planning alignment and hardening

Implementation status: Completed on 2026-09-03.

Deliverables:

- Pass structured criterion and evidence context into project-bound tasks.
- Add effort-derived step limits and final task evidence claims.
- Add diagnostics counters, prompt-contract fixtures, and stagnation detection.
- Remove obsolete compatibility paths only after migration coverage proves they are
  unused.

Acceptance:

- Project-bound task plans remain inside their selected objective and effort limit.
- Task output evidence is attributable to a task run and criterion.
- Repeated no-progress loops produce a specific blocker with diagnostic context.
- Full tests and `dart analyze` pass.

Compatibility audit:

- Retained the legacy `successCriteria`, `knownFacts`, and task-reference adapters:
  schema-v2 migration fixtures and constructor compatibility tests still exercise
  them. Canonical schema-v3 writes omit the legacy fields, so they can be removed
  only after support for persisted schema-v2 projects is intentionally retired.

### Final refinement pass

Implementation status: Completed on 2026-09-03.

Hardening completed:

- Reject unsupported future snapshot schemas without rewriting the file or
  restoring an older backup over it.
- Validate same-revision criterion, milestone, task, and evidence relationships
  before applying a plan change.
- Preserve invalidated criteria and cancelled milestones for audit history, and
  stale accepted evidence when its criterion contract changes.
- Attribute evidence and artifacts to their exact task run and match
  source-specific expectations without cross-crediting unrelated commands.
- Count newly accepted supporting evidence as progress so useful task runs do not
  trigger false stagnation blockers.

Verification:

- `flutter analyze`: no issues.
- `flutter test`: 469 tests passed.

### Future milestone: Conflict-safe parallelism

Explicitly excluded from the redesign's completion criteria. It may begin only after
read/write footprints are reliable and should require:

- Workspace or path leases.
- Disjoint-write validation.
- Separate cancellation and recovery per worker.
- Deterministic merge and evidence ordering.
- UI for concurrent active tasks.

## 16. Test strategy

### Model and migration tests

- Round-trip every new enum and model.
- Decode camelCase and supported aliases.
- Golden v2-to-v3 fixtures.
- Idempotent repeated migration.
- Missing, malformed, duplicated, and partially populated legacy values.
- Migration backup behavior and atomic snapshot recovery.

### Pure orchestration tests

- Criterion state transitions and invalid transitions.
- Evidence normalization, deduplication, staleness, and strength rules.
- Dependency graph validation and cycle reporting.
- Readiness calculation for each blocking reason.
- Stable scheduler ordering and rationale.
- Replan trigger debouncing.
- Protected memory, supersession, selection, and compaction.

### Service tests with fake model clients

- Initial plan success, malformed output, repair, cancellation, and transport failure.
- Revision proposal success, no-op revision, invalid mutation, and approval.
- Completed task with no criterion progress.
- Failed task with recovery, exhausted recovery, and later manual retry.
- No-ready-task replan and irreparable-plan blocker.
- Deterministic completion without unnecessary model review.
- Semantic completion with accepted and rejected model review.

### Integration tests

- Create -> approve -> execute -> verify -> replan -> complete.
- Pause and resume during planning, execution, and verification.
- Restart recovery with a pending plan approval or active task.
- User context superseding an assumption and invalidating downstream work.
- External workspace changes invalidating evidence.
- Schema-v2 active project continuing after migration.

### UI tests

- Criterion progress and evidence details.
- Roadmap ready/waiting/deferred/obsolete grouping.
- Plan revision diff and approval actions.
- Scheduler rationale and blocker details.
- Accessible labels and controls for all new states.

### Regression commands

Every implementation milestone must finish with:

```sh
dart analyze
flutter test
```

Targeted tests should run during development, but neither command may be replaced by
targeted tests in milestone acceptance.

## 17. Rollout and compatibility strategy

1. Land characterization tests before behavior changes.
2. Land schema v3 and migration with compatibility accessors while orchestration still
   follows existing behavior.
3. Enable evidence-driven completion for newly created projects first; retain migrated
   legacy evidence semantics.
4. Enable rolling planning and dependency scheduling together so dependency metadata
   is never ignored by an older selector.
5. Enable the new UI once persisted state is stable.
6. Remove dead states, prompts, and compatibility getters only after at least one full
   release cycle and explicit repository search confirms no call sites remain.

If a feature flag is used during development, it must not create two writers for the
same schema. The flag may select orchestration behavior, but all post-migration writes
must remain valid schema v3.

## 18. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Schema growth makes model prompts too large. | Send purpose-built evidence snapshots and active memory, not the complete project document. |
| Model plans contain inconsistent IDs or dependencies. | Finalizer schemas, deterministic validation, one repair pass, then preserve state and block clearly. |
| Evidence rules become too rigid for creative work. | Per-criterion verification modes and advisory/supporting/conclusive strengths. |
| Legacy projects appear to lose progress. | Create explicit migrated evidence and preserve prior completed-criterion interpretation. |
| Replanning occurs after every small update. | Mandatory/conditional triggers, thresholding, and per-transition debounce. |
| Scheduler feels opaque. | Persist candidate factors and a concise selection rationale. |
| The redesign destabilizes recovery behavior. | Keep recovery priority and limits in `ProjectService`; add characterization tests before extraction. |
| Users face excessive approvals. | Default to `highRiskOnly`; treat ordinary valid revisions as automatic. |
| Plan history grows without bound. | Store compact diffs, cap verbose diagnostics separately, and never discard authoritative transitions. |
| Parallelism introduces workspace conflicts. | Keep execution sequential and defer concurrency to a separately approved milestone. |

## 19. Decisions adopted by this plan

- Use rolling-wave planning rather than a fully detailed up-front project plan.
- Use stable IDs for criteria, milestones, tasks, evidence, memory, and revisions.
- Keep one authoritative current plan plus compact append-only revision diffs.
- Use deterministic dependency scheduling rather than model-selected task ordering.
- Require evidence for new-project criterion completion.
- Preserve legacy progress with explicitly marked migrated evidence.
- Use `highRiskOnly` as the recommended plan-approval default.
- Keep task steps linear during the project redesign.
- Keep project task execution sequential.
- Split implementation into bounded goals rather than one long unreviewed migration.

## 20. Overall definition of done

The redesign is complete when:

1. New projects persist structured criteria, evidence, milestones, dependencies,
   revisions, and memory.
2. Existing schema-v2 projects migrate safely and retain historical behavior and data.
3. The scheduler can explain why every selected task was ready and preferred.
4. Completed tasks do not automatically imply achieved outcomes.
5. Every satisfied required criterion has accepted evidence.
6. Replanning occurs on defined triggers and produces validated, inspectable diffs.
7. Users can review material plan changes and understand blocked work in the UI.
8. Recovery, cancellation, pause/resume, question policy, and atomic persistence remain
   reliable.
9. No fixed-string truncation silently removes recent project context.
10. All model, migration, service, integration, and UI tests pass, and `dart analyze`
    reports no issues.

The future parallelism milestone is not required for this definition of done.
