# Hermes

Hermes is a Flutter application for chat, workspace tools, and task/project
execution.

## Persistence and compatibility

Project, task, chat, prompt-library, and settings data retain compatibility
with existing snapshots. `features/persistence/application/schema_migrations.dart` contains
explicit versioned migration registries; missing optional fields remain
compatible with legacy documents, while newer unsupported versions fail with
an actionable diagnostic. Transaction manifests, backup recovery, unknown
fields, and optimistic revision conflicts remain part of the persistence
contract.
