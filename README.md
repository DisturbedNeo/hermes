# Hermes

Hermes is a Flutter application for chat, workspace tools, and task/project
execution.

## Persistence

Project and task data use the current snapshot envelope and DTO schema.
Transaction manifests, backup recovery, unknown fields, and optimistic
revision conflicts remain part of the persistence contract.
