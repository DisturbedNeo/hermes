# Hermes

Hermes is a modular Flutter application for chat, workspace tools, and
bounded task/project execution.

## Architecture

Hermes is a modular monolith with dependency flow toward the shared kernel:

```text
presentation -> feature application -> feature domain
                         |                 ^
                         v                 |
                 infrastructure adapters --+

composition root -> all feature ports and infrastructure implementations
shared kernel -> contracts, immutable values, cancellation, serialization
```

Feature application code consumes narrow ports. Chat depends on
`TaskChatPort` and `ProjectChatPort`; it does not construct or
call task/project implementations directly. Project planning stores immutable
`ProjectTaskNode` values and materializes executable task documents only in the
task boundary adapter.

`ChatController`, `TaskController`, and `ProjectApplication` are stable thin
facades over focused runtime/coordinator implementations. Concrete persistence
adapters live under feature `infrastructure/` directories and implement typed
ports. Model-server lifecycle and diagnostics are owned by `features/model`,
while chat consumes its application port.

The main state and ownership boundaries are:

- `ChatState` is the authoritative immutable chat session state and
  `ChatViewState` is only its presentation projection.
- Project plan, execution, evidence, and control views are separated in
  `project_state_models.dart`.
- Project and task persistence expose application repository ports, retain
  optimistic revisions, and use atomic snapshot writes with backup recovery.
- `WorkspacePersistenceCoordinator` combines a cross-process lock file with
  process-local serialization and revision checks. Lock ownership, timeout,
  stale-lock recovery, and diagnostics are described in
  [`docs/architecture.md`](docs/architecture.md).
- `ApplicationLifecycle` owns startup, quiescing, flushing, cancellation, and
  reverse-order idempotent disposal.

The generated mapper files are build artifacts and must be regenerated rather
than edited manually.

## Development

Run the complete local verification workflow with:

```sh
bash tool/verify.sh
```

The workflow regenerates mappers, checks formatting, analyzes Dart, runs the
authoritative architecture suite in
`test/architecture/architecture_test.dart` and the full Flutter test suite,
and checks the final diff. For an individual change, use the narrowest
relevant command, then run the complete workflow before handoff.

## Persistence and compatibility

Project, task, chat, prompt-library, and settings data retain compatibility
with existing snapshots. `shared_kernel/schema_migrations.dart` contains
explicit versioned migration registries; missing optional fields remain
compatible with legacy documents, while newer unsupported versions fail with
an actionable diagnostic. Transaction manifests, backup recovery, unknown
fields, and optimistic revision conflicts remain part of the persistence
contract.
