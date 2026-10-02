# Hermes agent instructions

## Architecture migration

When working on the Hermes architecture migration, the authoritative files are:

1. `ARCHITECTURE_SPEC.md` — required target state and constraints.
2. `MIGRATION_PLAN.md` — finite mandatory checklist and acceptance criteria.
3. `IMPLEMENTATION_RULES.md` — execution, verification, and blocked-state rules.
4. `MIGRATION_STATUS.md` — durable progress ledger.

Read all four before changing migration-related code. Resume the first
`IN-PROGRESS` item or the first unchecked mandatory item. Do not stop after a
plan, analysis, single milestone, or partial fix. Update the status ledger and
continue to the next item after each verified milestone.

The migration is complete only when every plan item is `DONE` or explicitly
`WONT-DO` with a recorded reason, and `bash tool/verify.sh` passes. Preserve
existing behavior, persistence compatibility, safety boundaries, generated
mapper rules, and pre-existing user changes.

For work unrelated to the migration, follow the repository's existing design
and tests without treating this migration as an excuse for unrelated changes.
