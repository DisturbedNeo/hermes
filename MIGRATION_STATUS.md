# Hermes Architecture Migration Status

This file is the durable progress ledger for the implementation Goal. Update
it after every milestone; do not rely on conversation history as the source of
truth.

## Current state

- Overall status: `COMPLETE`
- Active item: none
- Last verified baseline: 2026-10-02
- Pre-existing user change: `README.md` was modified before migration setup;
  preserve it unless the migration explicitly updates the same documentation.
- Migration implementation is complete through ARCH-016.
- Final verification: `bash tool/verify.sh` passed; mapper generation,
  formatting (432 files unchanged), analysis, the 21-test architecture suite,
  all 608 Flutter tests, and generated-file-aware diff whitespace checks all
  completed successfully.

## Baseline evidence before migration setup

- `flutter analyze`: passed with no issues.
- `flutter test`: passed; 605 tests passed.
- Architecture suite: included in the passing full test run.
- The README referenced `tool/verify.sh`, but that script did not exist.
- No CI workflow was present under `.github`.

## Milestone ledger

| ID | Status | Evidence / notes |
|---|---|---|
| ARCH-001 | `DONE` | Inventory recorded below. `flutter analyze` and `flutter test test/architecture/architecture_test.dart` passed. |
| ARCH-002 | `DONE` | Existing characterization suite covers project/task execution, chat streaming/autosave/exit, persistence revision/backup/transaction recovery, model discovery/startup, and UI projections, including failure/cancellation/recovery/conflict paths. Baseline `flutter test` passed with 605 tests. |
| ARCH-003 | `DONE` | Added `lib/core/contracts/model_conversation.dart` and `conversation_store.dart`; converted legacy chat contract files to exports and moved all model/task/project/tool/settings shared-contract imports to neutral ownership. Verification: architecture suite plus compaction, context, payload, and execution-kernel tests passed. |
| ARCH-004 | `DONE` | Added framework-neutral `core/contracts/execution_settings.dart` for task execution settings, question autonomy, and project plan approval policy; removed production imports of task/project-owned settings contracts and regenerated mapper outputs. `flutter analyze`, preferences/serialization tests, and full `flutter test` (606 passed) passed. |
| ARCH-005 | `DONE` | Added domain-owned task/project import surfaces, moved domain policies and project/task persistence ports to those surfaces, and enforced domain/persistence ownership in the architecture suite. `flutter analyze`, architecture gate, task gate/project/project schema acceptance tests, and full `flutter test` (607 passed) passed. |
| ARCH-006 | `DONE` | Persistence adapters now use domain-owned project/task surfaces; aggregate transaction staging uses `ProjectPersistenceAdapter`/`TaskPersistenceAdapter` instead of direct model encoding. Mapper generation, serialization architecture, schema migration, project persistence consistency, persistence lifecycle, and full `flutter test` (607 passed) passed. Existing revisions, backups, migrations, unknown fields, manifests, conflicts, and recovery remained green. |
| ARCH-007 | `DONE` | Split project orchestration into explicit command, planning, recovery, persistence, evaluation, completion, evidence, and decision collaborators; moved the remaining state-machine workflow into separate same-library coordination units while retaining the stable facade API. `flutter analyze`, architecture gate, project application/behavior/lifecycle/decision tests, and all 607 tests passed. |
| ARCH-008 | `DONE` | Split task execution implementation from the stable coordinator surface into planning, step-loop, gate, recovery, persistence, command, and tool-execution collaborators; retained public task ports and compatibility runtime facade. `flutter analyze`, task execution-kernel/controller/incremental-planning/gate tests, architecture gate, and all 607 tests passed. |
| ARCH-009 | `DONE` | Split chat session operations from the stable notifier/host state boundary while retaining explicit session manager, command, task/project, autosave, persistence, prompt, streaming, and presentation collaborators. `flutter analyze`, chat save/client/message-store/system-prompt tests, architecture gate, and all 607 tests passed. |
| ARCH-010 | `DONE` | Added focused model text, streaming, token-counting, metadata, lifecycle, generation, context, and conversation ports; kept `ModelCompletionPort` as a composition-only combined adapter and migrated chat/task/tool consumers to focused capability types. `flutter analyze`, chat-client/llama-manager tests, architecture gate, and all 607 tests passed. |
| ARCH-011 | `DONE` | Added focused workspace read/write/search capabilities and planning/tool/verification bundles; task execution, artifact tools, gate evaluation, and project planning readers now receive focused workspace contracts while `WorkspaceSandboxPort` remains composition-only. Workspace safety, terminal classifier, architecture, and full verification paths remained green. |
| ARCH-012 | `DONE` | Split preferences into appearance, model-directory/configuration, diagnostics, compaction, execution, persistence, notification, and focused feature bundles; chat runtime, repositories, settings, theme, diagnostics, and model configuration now depend on focused contracts while `PreferencesPort` remains composition-only. Preferences, app dependency, architecture, and full verification paths stayed green. |
| ARCH-013 | `DONE` | Added typed `ModelCatalogPort`/`ModelDescriptor` and an infrastructure catalog adapter; injected it through app composition into the model picker, removed presentation `dart:io`/platform thread discovery, and retained the legacy platform helper only for compatibility tests. Model configuration, picker/chat, catalog discovery, architecture, and full verification paths remained green. |
| ARCH-014 | `DONE` | Strengthened the AST-backed architecture suite with deterministic facade line/constructor budgets, focused model/workspace/preferences capability leakage checks, typed model-catalog/presentation checks, platform-default isolation, and generated mapper placement diagnostics. Architecture suite and `flutter analyze` passed. |
| ARCH-015 | `DONE` | Added `.github/workflows/ci.yml` for push/PR verification and confirmed executable `tool/verify.sh` runs mapper generation, formatting, analysis, architecture tests, full Flutter tests, and whitespace checks. `bash tool/verify.sh` passed; README was preserved unchanged. |
| ARCH-016 | `DONE` | Final audit completed. `bash tool/verify.sh` passed after the final preference-port refinement; all 608 Flutter tests and all 21 architecture checks passed. README remains unchanged. |

## Decisions and blockers

Record architectural decisions, rejected alternatives, compatibility findings,
and blockers here with dates and affected milestone IDs.

### ARCH-001 inventory (2026-10-02)

- Cross-context imports are concentrated in the application/composition roots,
  but the feature inventory still contains reverse/shared edges: chat imports
  model (20 production files), task (14), project (11), workspace (23), tools
  (15), persistence (5), and settings (12); model imports chat (4); task
  imports chat (8), model (10), project (4), workspace (13), tools (6), and
  persistence (7); project imports chat (2), model (9), task (22), workspace
  (17), tools (3), and persistence (12). These edges will be reduced to
  neutral contracts and narrow application ports where they are not genuine
  bounded-context relationships.
- Chat-owned shared contracts currently include `ChatMessage`, tool-call
  deltas, and `CompactionSettings` under
  `lib/features/chat/application/contracts/`; model completion ports and task
  settings import them. Target move: `lib/core/contracts/` with compatibility
  exports only at the old boundary where needed.
- Durable project/task snapshot state remains in application contract files
  (`project_snapshot_models.dart`, `project_task_models.dart`, and generated
  mapper companions), while domain aggregates/entities and transitions are
  split across project/task domain/runtime files. Target move: domain-owned
  state and explicit persistence DTOs/mappers under persistence infrastructure;
  generated files must be regenerated by build tooling.
- The orchestration size inventory (non-generated production Dart) identifies
  `project_execution_state_machine.dart` (4,433 lines),
  `chat_session_orchestrator.dart` (2,876), and
  `task_execution_coordinator.dart` (2,727) as mandatory decomposition
  targets. Additional large collaborators require focused review but are not
  the three named facade targets.
- Broad capability seams: `ModelCompletionPort` combines completion,
  streaming, token counting, server metadata, and disposal; `WorkspaceSandboxPort`
  combines path, file, and host-command capabilities; `PreferencesPort`
  combines appearance, model, execution, compaction, persistence, and model
  configuration settings. Feature consumers currently also receive combined
  adapters in several runtime constructors. Target: focused ports with
  composition-only combined adapters.
- Presentation/platform leaks: `lib/features/chat/presentation/chat/model_picker.dart`
  and settings presentation call model-directory discovery through the broad
  preferences service; model file enumeration is implemented in
  `lib/platform/models_directory.dart`. Target: injected model-catalog
  application port and typed presentation descriptors/items; no `dart:io` or
  platform discovery from presentation.
- Existing boundary enforcement is deterministic and AST/import based for
  graph and platform checks, but lacks explicit class-size, constructor/public
  surface, focused-port usage, and quantitative presentation budgets. ARCH-014
  will extend it with actionable diagnostics while preserving the current
  safety and persistence invariants.
- Existing workspace safety, host-command approval, cancellation, lifecycle,
  optimistic revision, backup, transaction recovery, unknown-field handling,
  and schema migration paths are covered by the current focused test suite and
  are protected as structural changes proceed.

## Final audit

Complete only after every milestone has evidence and the final verification
commands pass.

### Final audit (2026-10-02)

- All ARCH-001 through ARCH-016 rows are `DONE`; no mandatory item remains
  unchecked or duplicated.
- Non-chat production code has no imports from the legacy chat contract paths;
  those paths remain only as compatibility exports within the chat feature.
- `WorkspaceSandboxPort` and `PreferencesPort` are composition-only contracts;
  feature consumers use focused capabilities or focused bundles. The combined
  `ModelCompletionPort` remains at the model-provider boundary and the project
  planning compatibility seam, while chat/task/tool consumers use focused
  model capabilities.
- Presentation has no `dart:io`, host platform thread discovery,
  `ModelsDirectory`, or untyped model catalog collection; model discovery is
  provided by `ModelCatalogPort` and `ModelDescriptor`.
- Orchestration facades are within the enforced budgets: project state machine
  341 lines, task coordinator 363 lines, and chat orchestrator 471 lines.
- Generated mapper output was regenerated by build tooling. The verifier’s
  whitespace check excludes only generated files because the configured builder
  emits a harmless blank line at EOF; the non-generated diff whitespace check
  passes.
- `git diff -- README.md` is empty, preserving the pre-existing README change.
- CI verification is recorded in `.github/workflows/ci.yml`, and the local
  closeout entry point is executable `tool/verify.sh`.
