# Project and Task System Refactor Plan

## Goal

Make the project/task architecture small and easy to reason about while preserving the core behavior:

- plan work before changing the workspace;
- execute planned work in explicit project batches;
- keep approvals, gates, evidence, and recovery behavior;
- resume safely after interruption; and
- retain a clear history of task execution.

The central change is to remove the duplicate `ProjectTask`/`TaskDocument` split. There should be one canonical `Task` model.

This plan deliberately does not add new policy, event, synchronization, metrics, or storage layers. Existing repositories, task runs, logs, sandbox controls, and gate/evidence services should be reused.

## Target model

### `Project`

`Project` owns project-level planning and scheduling state:

- project goal and completion criteria;
- an ordered list of canonical task IDs;
- the current active task ID;
- the current batch task IDs and cursor;
- the current plan revision; and
- project status and a short pending-replan reason, when needed.

It does not embed task definitions or maintain a second copy of task state.

### `Task`

`Task` replaces both `ProjectTask` and `TaskDocument`. It owns everything about one unit of work:

- task identity and project identity;
- objective, constraints, completion criteria, dependencies, and boundaries;
- priority, risk, effort, milestone, paths, artifacts, evidence, and gates;
- executable plan and current step;
- task status; and
- existing execution history (`TaskRun`, tool records, and logs).

The existing `TaskDocument` is the simplest starting point: rename/extend it to `Task` and move the fields currently held by `ProjectTask` into it. Do not introduce a third model or a `TaskReference` class.

There is one task status lifecycle. Map the current project-task and standalone-task status values into that lifecycle during the refactor. Keep distinctions such as `rejected` or `split` only if current behavior genuinely needs them; they remain values on `Task`, not separate concepts.

Task conversations remain related through the existing chat mechanism. A new task-chat store is out of scope for this refactor.

## Minimal project state for batching

Store the batch state directly on `Project`; do not create a separate `ProjectExecutionBatch` object.

The required fields are:

- `currentBatchTaskIds`;
- `currentBatchIndex`;
- `currentBatchPlanRevision`; and
- `pendingReplanReason`, if a replan is waiting at a safe boundary.

The existing project status and task status provide the rest of the observable state. The scheduler loads each task by ID when it needs it.

## Execution flow

1. The project planner creates or updates the project and its ordered task IDs.
2. The task records are persisted using their canonical IDs.
3. Before workspace mutation, the selected task must have a valid executable plan. If necessary, the task planner fills in that plan once.
4. The batch runner executes selected task IDs in order.
5. Save the task before and after each meaningful execution step, using the existing task-run and log persistence.
6. Save the project at task boundaries so the batch cursor can resume.
7. Do not call the project planner after every successful task. Replan once at the batch boundary, or sooner only when work can no longer safely continue.

If execution is interrupted, mark the task/project paused and leave the cursor at the last persisted boundary. On restart, resume from that boundary; do not silently replay a step whose completion is unknown.

## When to stop and replan

Use only the triggers needed for safe behavior:

- a task fails and needs a decision or recovery;
- a dependency, workspace assumption, gate, or evidence requirement is no longer valid; or
- the configured batch is complete and more work remains.

An explicit user request to change scope also causes a replan. Otherwise, successful tasks should continue without planner calls between them.

## Plan updates

Keep plan revision handling simple:

- every task has a stable canonical ID;
- a new ID creates a task;
- an existing ID updates that task if it is not terminal;
- omitted existing IDs remain unchanged;
- terminal tasks are not silently rewritten; and
- an explicit `deferred` or `obsolete` status is used when planned work should no longer run.

The project planner must return a complete, valid task list. An empty or malformed response is rejected and must not clear the existing backlog.

No operation-log, fingerprint, outbox, or cross-store transaction mechanism is needed for this refactor. The existing persistence and recovery behavior is sufficient; improve it only where a concrete failing test demonstrates otherwise.

## Data migration

Use the existing `ProjectTask.id` as the canonical task ID wherever possible.

Migration should:

1. read each project task and matching task document;
2. merge them into one `Task` record;
3. preserve the existing task-run, log, evidence, gate, artifact, and recovery history;
4. rewrite project task lists and task dependencies to canonical IDs;
5. preserve records whose counterpart is missing rather than deleting history; and
6. be safe to run again without creating duplicate tasks.

Keep compatibility conversion at the persistence boundary only. The domain and execution code should use `Project`, `Task`, and task IDs after the migration.

## Implementation phases

### Phase 1: Confirm current behavior

**Status: Complete — 2026-09-10 08:23:41 BST (Europe/London)**

- Identify all reads and writes of `ProjectTask`, `TaskDocument`, task status, task IDs, and task history.
- Preserve or add focused tests for planning, approvals, gates, evidence, batching, interruption, and recovery.
- Add a test proving a successful task does not trigger an immediate project replan.

### Phase 2: Collapse the domain models

**Status: Complete — 2026-09-10 09:09:04 BST (Europe/London)**

- Rename or replace `TaskDocument` with `Task`.
- Move the necessary `ProjectTask` fields onto `Task`.
- Change `Project` to store ordered task IDs only.
- Update services and UI code to load tasks by ID.
- Keep temporary compatibility adapters only at the persistence boundary.

### Phase 3: Migrate stored data

**Status: Complete — 2026-09-10 09:28:25 BST (Europe/London)**

- Add the one-time snapshot migration from the two old records to one `Task` record.
- Preserve history and canonical IDs.
- Make the migration idempotent and test old, partial, and already-migrated snapshots.

### Phase 4: Simplify execution and batching

**Status: Complete — 2026-09-10 11:29:22 BST (Europe/London)**

- Add the minimal batch fields directly to `Project`.
- Run tasks sequentially by ID.
- Persist task progress and the project cursor at safe boundaries.
- Implement pause/resume and the small set of replan triggers above.

### Phase 5: Simplify plan revisions

**Status: Complete — 2026-09-10 11:41:34 BST (Europe/London)**

- Apply new, updated, deferred, and obsolete task IDs using the rules above.
- Reject incomplete planner responses without changing the current plan.
- Keep terminal task history intact.

### Phase 6: Remove compatibility code

**Status: Complete — 2026-09-10 12:08:42 BST (Europe/London)**

- Update remaining callers and UI code to use `Task`.
- Remove `ProjectTask`, duplicate status handling, and old persistence adapters once migrated data is no longer dependent on them.

The application and UI now use `Task` and its canonical status, objective,
evidence, artifact, and run identifiers. Legacy wire keys are accepted only
by the persistence hooks and migration tests; `Task.taskDocumentId` remains a
one-time migration-only field so old project/task snapshots can be merged
without losing execution history.

## Non-goals

Do not add any of the following as part of this refactor:

- a separate task-reference model;
- a separate task-chat model or store;
- a separate batch aggregate;
- a policy/rules subsystem;
- an event log, outbox, fingerprint, or distributed coordination layer;
- new metrics, budgeting, or concurrency abstractions; or
- broad defensive behavior without a demonstrated requirement.

## Completion criteria

The refactor is ready when:

- `Task` is the only domain model for task definition and execution;
- `Project` stores task IDs rather than duplicate task objects;
- planning happens before mutation and not after every successful task;
- batches are explicit, resumable, and persisted with minimal project state;
- approvals, gates, evidence, recovery, and task history still work; and
- old snapshots migrate successfully without losing history.

If a proposed change does not support one of these criteria, leave it out of this refactor.
