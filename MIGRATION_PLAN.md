# Hermes Architecture Migration Plan

Status values are `PENDING`, `IN-PROGRESS`, `DONE`, `BLOCKED`, or `WONT-DO`.
Every item is mandatory unless it is explicitly marked `WONT-DO` with a
recorded reason approved in the status log.

The implementation agent must execute items in order unless the dependency
inventory proves that two items are independent. It must update
`MIGRATION_STATUS.md` after each item and repair verification failures before
starting the next item.

## Phase 0 — Contract and baseline

### ARCH-001 — Freeze the dependency and responsibility inventory

Acceptance criteria:

- identify all imports crossing chat, model, task, project, workspace, tools,
  persistence, settings, and core boundaries;
- identify every production class above the agreed orchestration size budget;
- identify every broad port, concrete adapter injected into feature code, and
  presentation file using platform/filesystem or untyped data;
- record the inventory and chosen target moves in `MIGRATION_STATUS.md`;
- do not begin implementation until the inventory is complete.

Verification:

```sh
flutter analyze
flutter test test/architecture/architecture_test.dart
```

### ARCH-002 — Establish characterization coverage

Acceptance criteria:

- add or improve focused tests for project execution, task execution, chat
  lifecycle, persistence compatibility, model discovery, and relevant UI
  projections before moving their implementations;
- all tests pass before the first structural extraction;
- tests cover failure, cancellation, recovery, and persistence-conflict paths,
  not only happy paths.

Verification:

```sh
flutter test
```

## Phase 1 — Shared contract ownership

### ARCH-003 — Extract neutral model/workflow contracts

Acceptance criteria:

- move shared message, role, token/tool-delta, compaction, and any other
  cross-feature contracts identified by ARCH-001 into an explicitly declared
  neutral module;
- update all imports and generated mapper initialization safely;
- model and task runtime code no longer imports chat-owned shared contracts;
- feature-level dependency checks enforce the new ownership.

Verification:

```sh
flutter test test/architecture/architecture_test.dart
flutter test test/core/services/chat/chat_client_test.dart
flutter test test/core/services/chat/chat_save_lifecycle_test.dart
flutter test
```

### ARCH-004 — Separate shared settings ownership

Acceptance criteria:

- move shared execution/compaction settings to the bounded context that owns
  them or to the neutral contract module;
- remove accidental settings dependencies between unrelated features;
- preserve serialized values and defaults.

Verification:

```sh
flutter test test/core/services/preferences_service_test.dart
flutter test test/core/serialization/serialization_architecture_test.dart
flutter test
```

## Phase 2 — Domain and persistence boundaries

### ARCH-005 — Establish domain-owned task and project models

Acceptance criteria:

- task and project aggregates/entities/value objects have domain-owned source
  files;
- domain code contains domain invariants and transition policies, not wire or
  storage annotations;
- application contracts expose commands, results, projections, and ports;
- no domain source imports generated mappers, JSON hooks, or persistence
  infrastructure.

Verification:

```sh
flutter test test/architecture/architecture_test.dart
flutter test test/core/models/task_gate_test.dart
flutter test test/core/models/project_test.dart
flutter test test/core/models/project_schema_test.dart
flutter test
```

### ARCH-006 — Introduce explicit persistence DTO mapping

Acceptance criteria:

- persistence DTOs and adapters own durable JSON conversion;
- existing project/task/chat/settings snapshot documents remain readable;
- revisions, backups, migrations, unknown fields, transaction manifests,
  conflicts, and recovery behavior remain intact;
- generated output is regenerated rather than hand-edited.

Verification:

```sh
dart run build_runner build
flutter test test/core/serialization/serialization_architecture_test.dart
flutter test test/core/serialization/schema_migrations_test.dart
flutter test test/core/services/project_persistence_consistency_test.dart
flutter test test/core/services/persistence_lifecycle_test.dart
flutter test
```

## Phase 3 — Runtime/use-case decomposition

### ARCH-007 — Decompose project orchestration

Acceptance criteria:

- project planning, execution, recovery, persistence, completion/evidence
  evaluation, and command handling are separate coherent services;
- `ProjectExecutionStateMachine` is reduced to coordination rather than
  containing the complete project business workflow;
- constructor dependency count, public surface, and source size meet the
  architecture budgets;
- behavior and lifecycle transitions are preserved.

Verification:

```sh
flutter test test/core/services/project_application_test.dart
flutter test test/core/services/project_application_behavior_test.dart
flutter test test/core/services/project_lifecycle_characterization_test.dart
flutter test test/core/services/project_decision_engine_test.dart
flutter test test/architecture/architecture_test.dart
flutter test
```

### ARCH-008 — Decompose task orchestration

Acceptance criteria:

- task planning, step execution, gate evaluation, recovery, persistence, and
  command handling are separate coherent services;
- `TaskExecutionCoordinator` is reduced to coordination;
- model/tool protocol conversion is isolated at protocol boundaries;
- cancellation, approvals, replanning, recovery, and persistence behavior is
  preserved.

Verification:

```sh
flutter test test/core/services/execution_kernel_test.dart
flutter test test/core/services/task_controller_test.dart
flutter test test/core/services/task_controller_incremental_planning_test.dart
flutter test test/core/services/task_gate_evaluator_test.dart
flutter test test/architecture/architecture_test.dart
flutter test
```

### ARCH-009 — Decompose chat orchestration

Acceptance criteria:

- chat session lifecycle, command dispatch, task/project coordination,
  persistence/autosave, prompt construction, streaming, and presentation
  projection have clear service ownership;
- `ChatSessionOrchestrator` is reduced to coordination;
- immutable state slices remain authoritative;
- exit, cancellation, autosave, streaming, and active-work behavior is
  preserved.

Verification:

```sh
flutter test test/core/services/chat/chat_save_lifecycle_test.dart
flutter test test/core/services/chat/chat_client_test.dart
flutter test test/core/services/chat/message_store_test.dart
flutter test test/core/services/chat/system_prompt_loading_test.dart
flutter test test/architecture/architecture_test.dart
flutter test
```

## Phase 4 — Capability and presentation boundaries

### ARCH-010 — Narrow model capabilities

Acceptance criteria:

- consumers depend on focused model completion, streaming, token-counting,
  metadata, diagnostics, and lifecycle capabilities;
- `ModelCompletionPort` no longer forces unrelated consumers to depend on all
  completion operations;
- process handles, HTTP clients, and transport maps remain infrastructure-only.

Verification:

```sh
flutter test test/core/services/chat/chat_client_test.dart
flutter test test/core/services/llama_server_manager_test.dart
flutter test test/architecture/architecture_test.dart
```

### ARCH-011 — Narrow workspace capabilities

Acceptance criteria:

- path policy, read, write, search, and host command execution are injected as
  focused capabilities;
- combined workspace adapters exist only where composition compatibility
  requires them;
- command approval and workspace confinement behavior is unchanged.

Verification:

```sh
flutter test test/core/services/workspace_sandbox_test.dart
flutter test test/core/services/terminal_command_classifier_test.dart
flutter test test/architecture/architecture_test.dart
flutter test
```

### ARCH-012 — Narrow preferences and feature facades

Acceptance criteria:

- appearance, model, execution, compaction, and persistence settings have
  focused application ports;
- task/project/chat public facades expose capability-specific contracts;
- feature modules no longer require concrete all-capabilities controllers;
- provider wiring still exposes stable application capabilities.

Verification:

```sh
flutter test test/core/services/preferences_service_test.dart
flutter test test/app_dependencies_test.dart
flutter test test/architecture/architecture_test.dart
flutter test
```

### ARCH-013 — Remove platform work from presentation

Acceptance criteria:

- model catalog/file discovery is supplied by an injected application
  capability;
- presentation does not import `dart:io` for model discovery or use platform
  defaults directly;
- presentation consumes typed model descriptors and typed view-model items;
- untyped collections such as `List<dynamic>` are removed from production UI
  surfaces where they represent domain/presentation state.

Verification:

```sh
flutter test test/ui/model_configuration/model_configuration_test.dart
flutter test test/ui/chat/model_picker_test.dart
flutter test test/architecture/architecture_test.dart
flutter test
```

## Phase 5 — Enforcement and delivery

### ARCH-014 — Strengthen architecture enforcement

Acceptance criteria:

- architecture tests use AST/import information and explicit bounded-context
  policies rather than relying only on filename and regex conventions;
- forbidden reverse feature edges, broad-port leakage, facade surface growth,
  orchestration budgets, presentation platform access, and mapper placement are
  checked;
- tests fail with actionable file and line diagnostics.

Verification:

```sh
flutter test test/architecture/architecture_test.dart
flutter analyze
```

### ARCH-015 — Complete verification automation and CI

Acceptance criteria:

- `tool/verify.sh` is executable and runs the complete local workflow;
- CI runs the same workflow on pull requests and pushes;
- generated output, formatting, analysis, architecture tests, and full tests
  are all covered;
- README commands match the files and commands that actually exist.

Verification:

```sh
bash tool/verify.sh
```

### ARCH-016 — Final audit and closeout

Acceptance criteria:

- every item in this plan is `DONE` or explicitly `WONT-DO` with a reason;
- all mandatory final checks pass;
- `MIGRATION_STATUS.md` contains the final evidence and residual risks;
- the agent performs a final repository-wide search for the old boundaries and
  reports any remaining intentional compatibility seams.

Final verification:

```sh
bash tool/verify.sh
git diff --check
flutter test
```
