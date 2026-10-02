# Hermes

Hermes is a modular Flutter application for chat, workspace tools, and
bounded task/project execution.

## Architecture

Hermes is a modular monolith with explicit contract modules and typed
composition roots:

```text
presentation -> application projections/ports -> domain
runtime -> application/domain ports
infrastructure adapters -> application contracts and core values
composition modules -> owned ports and concrete adapters
core -> values, cancellation, lifecycle, parsing, schema abstractions
```

Feature application code consumes narrow ports. Chat depends on the typed
`TaskQueryPort`, `TaskExecutionPort`, `ProjectQueryPort`, and
`ProjectExecutionPort` contracts; it does not construct task/project
implementations directly. Project planning stores immutable `ProjectTaskNode`
values and materializes executable task documents only in the task boundary
adapter.

Workspace discovery follows the same boundary: runtimes consume the
application-layer `WorkspaceDiscoveryPort`, while `WorkspaceToolsModule`
injects the filesystem-backed discovery adapter.

`ChatController`, `TaskController`, and `ProjectApplication` are stable thin
facades over focused runtime/coordinator implementations. Concrete persistence
adapters live under feature `infrastructure/` directories and implement typed
ports. Model-server lifecycle and diagnostics are owned by `features/model`,
while chat consumes its application port.

Protocol adapters own model, tool, planning, command, and persistence wire
conversion. `ChatMessageWireAdapter`, `ToolProtocolAdapter`, and the planning
adapters convert JSON only at the edge; runtime code receives typed tool calls,
tool payloads, model request options, planning responses, and workspace
operation results. Model process handles and diagnostics telemetry writes stay
inside model infrastructure/runtime.

The main state and ownership boundaries are:

- `ChatState` is the authoritative immutable chat session state and
  `ChatViewState` is only its presentation projection. Its conversation,
  model-session, task-panel, project-panel, persistence, and transient slices
  expose read models rather than project/task aggregates.
- Project plan, execution, evidence, and control views are separated in
  `project_state_models.dart`.
- Project and task persistence expose application repository ports, retain
  optimistic revisions, and use atomic snapshot writes with backup recovery.
- `WorkspacePersistenceCoordinator` combines a cross-process lock file with
  process-local serialization and revision checks.
- `ApplicationLifecycle` owns startup, quiescing, flushing, cancellation, and
  reverse-order idempotent disposal.
- Workspace path policy, workspace-confined file operations, and host command
  execution are separate typed capabilities. Filesystem and process
  implementations live under platform or infrastructure modules.

The generated mapper files are build artifacts and must be regenerated rather
than edited manually.

## Development

Run the complete local verification workflow with:

```sh
bash tool/verify.sh
```

The workflow regenerates mappers, checks formatting, analyzes Dart, runs the
authoritative analyzer-backed architecture suite in
`test/architecture/architecture_test.dart` and the full Flutter test suite,
checks generated output and the final diff. For an individual change, use the narrowest
relevant command, then run the complete workflow before handoff.

## Persistence and compatibility

Project, task, chat, prompt-library, and settings data retain compatibility
with existing snapshots. `features/persistence/application/schema_migrations.dart` contains
explicit versioned migration registries; missing optional fields remain
compatible with legacy documents, while newer unsupported versions fail with
an actionable diagnostic. Transaction manifests, backup recovery, unknown
fields, and optimistic revision conflicts remain part of the persistence
contract.
