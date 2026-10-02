# Hermes Architecture Migration Specification

Status: authoritative implementation contract

This document defines the target architecture for the Hermes migration. The
agent implementing the migration must treat the companion
`MIGRATION_PLAN.md` as a mandatory finite checklist. Suggestions in the older
architecture review are converted here into required outcomes.

## Product and architecture decision

Hermes remains a modular monolith. Do not split it into microservices,
separate applications, or independently deployed packages as part of this
migration. The objective is stronger internal boundaries, lower coupling, and
more maintainable orchestration within one Flutter application.

The intended dependency direction is:

```text
presentation -> application ports/projections -> domain
use-case runtime -> domain + application ports
infrastructure -> application ports + core values
composition modules -> concrete infrastructure and runtime implementations
app -> composition modules and externally visible application capabilities
core/contracts -> framework-neutral shared contracts only
```

The dependency graph must remain acyclic at file and bounded-context level.

## Mandatory target outcomes

### 1. Neutral shared contracts

Shared concepts must not be owned by an incidental consumer feature. Extract
framework-neutral contracts used by model, chat, task, and project code into an
explicit neutral module, preferably `lib/core/contracts/`:

- model conversation messages, roles, tokens, and tool-call deltas;
- context-compaction settings;
- other cross-feature contracts identified by the import inventory.

The final graph must not require the model or task runtime to import chat-owned
message/compaction contracts. Project-to-task dependencies are permitted only
where they represent the genuine project/task relationship and use narrow
application ports.

### 2. Separate domain state from application and persistence contracts

`ProjectAggregate`, `TaskAggregate`, their domain entities, value objects, and
state-transition rules must have a domain-owned home. Application contracts
must contain commands, results, projections, and ports rather than being the
canonical home for every durable aggregate.

Persistence representation must be explicit and infrastructure-owned. Generated
JSON mappers, schema hooks, migration logic, and snapshot DTOs must stay at the
persistence/protocol boundary. Domain code must not depend on `dart_mappable`,
JSON hooks, generated mapper files, or persistence infrastructure.

Existing snapshot compatibility is mandatory. Existing documents, revisions,
backups, transaction recovery, unknown-field handling, and schema migrations
must continue to work without data loss.

### 3. Split large orchestration units by use case

The following responsibilities must not remain concentrated in one large
coordinator class:

- project planning, execution, recovery, persistence, completion evaluation,
  and command handling;
- task planning, step execution, recovery, persistence, and command handling;
- chat session lifecycle, chat commands, active task/project orchestration,
  persistence, and presentation-state updates.

Use focused application/runtime services and pure policies/reducers where
appropriate. Keep public facades thin and stable. Do not replace one large
class with many anemic wrappers: each extracted service must own a coherent
use case and have focused tests.

### 4. Apply interface segregation to capability ports

Consumers must receive only the capabilities they use. In particular:

- split model completion, streaming, token-counting, server metadata, and
  lifecycle capabilities where consumers do not need all of them;
- split workspace path policy, workspace reads, workspace writes, and host
  command execution;
- split the broad preferences capability into bounded settings capabilities;
- expose task/project/chat capability bundles or interfaces rather than making
  every consumer depend on a concrete all-capabilities controller.

Combined adapters may exist at the composition root, but feature services and
presentation code must depend on focused ports.

### 5. Harden the presentation boundary

Presentation must consume projections/read models and presentation/application
ports. It must not depend on runtime implementations, persistence DTOs,
aggregates, or direct model/filesystem discovery.

Move model catalog discovery, model-file enumeration, processor/platform
defaults, and similar platform work behind injected application capabilities.
Replace untyped presentation collections such as `List<dynamic>` with typed
presentation items or sealed view-model variants.

### 6. Make architecture enforcement evidence-based

The architecture test remains authoritative, but it must be strengthened to
cover the target outcomes rather than only file names and import strings. Add
checks for:

- bounded-context dependency allowlists and forbidden reverse edges;
- focused port usage and concrete-adapter leakage;
- orchestration class size/dependency/public-surface budgets;
- presentation platform and aggregate leakage;
- generated mapper and schema compatibility invariants.

The checks must be deterministic and run in the normal verification workflow.

### 7. Make verification and status durable

The repository must provide a working `tool/verify.sh` entry point and CI
automation that run formatting, mapper generation checks, analysis, the
architecture suite, and the full Flutter test suite.

The migration must maintain `MIGRATION_STATUS.md` after every milestone. No
milestone may be marked complete without recorded commands and passing output.

## Non-negotiable constraints

- Preserve user-visible behavior unless a deliberate behavior change is
  explicitly recorded in the migration plan.
- Preserve persistence compatibility and all existing safety boundaries around
  workspace confinement and host command execution.
- Preserve cancellation, lifecycle, disposal, optimistic revision, backup,
  and transaction-recovery behavior.
- Do not delete tests to make the migration pass.
- Do not weaken architecture rules to accommodate an implementation shortcut.
- Do not discard pre-existing user changes in the working tree.
- Keep generated files regenerated by the configured build tooling; never edit
  generated mapper output manually.

## Completion definition

The architecture migration is complete only when every mandatory item in
`MIGRATION_PLAN.md` is marked `DONE`, every deliberately excluded item is
marked `WONT-DO` with an explicit reason, the final verification command set
passes, and a final repository-wide audit finds no remaining target-state
violation.
