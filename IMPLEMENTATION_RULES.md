# Hermes Migration Implementation Rules

This is the execution runbook for the architecture migration. It is
subordinate only to `ARCHITECTURE_SPEC.md` and is referenced by the Goal
prompt.

## Operating loop

At the beginning of every turn:

1. Read `ARCHITECTURE_SPEC.md`, `MIGRATION_PLAN.md`, and
   `MIGRATION_STATUS.md`.
2. Inspect `git status` and preserve all pre-existing user changes.
3. Select the first unchecked mandatory plan item, or resume the item marked
   `IN-PROGRESS`.
4. Inspect the current implementation and its tests before editing.

For every item:

1. State the item being implemented in the status file.
2. Make the smallest coherent set of changes that reaches its acceptance
   criteria.
3. Add or update tests before changing behaviorally sensitive code.
4. Run the item's verification commands.
5. Repair failures before moving to another item.
6. Record changed files, commands, results, and decisions in the status file.
7. Mark the item `DONE` only after the acceptance criteria and verification
   evidence are satisfied.
8. Immediately continue to the next item. Do not stop merely because one
   milestone completed.

## Scope and safety

- Do not reset, discard, or overwrite unrelated user work.
- Do not edit generated mapper files manually.
- Do not remove tests or weaken architecture checks to make a milestone pass.
- Preserve public behavior, persistence compatibility, cancellation, recovery,
  workspace confinement, and lifecycle semantics.
- Prefer composition and explicit ports over inheritance when changing facade
  boundaries.
- Prefer a few meaningful use-case services over dozens of trivial wrappers.
- Keep changes in the current repository and do not create a separate service
  or package unless the specification explicitly requires it.

## Verification rules

Passing a focused test is not enough to complete a migration item. Each item
must also preserve the relevant architecture checks. Before final closeout,
run the complete verification script and full test suite.

If generated output changes, regenerate it with the configured build runner,
format it, and include the generated result in the migration evidence.

## Blocked condition

Do not call the migration complete because of time, token, context, or
uncertainty. If a genuine blocker prevents progress:

- attempt safe, evidence-based alternatives;
- record each attempted path and its result;
- identify the exact external decision, missing dependency, or failing invariant;
- mark only the affected item `BLOCKED`;
- leave the repository in a buildable, testable state where possible.

If the agent reaches a turn or budget boundary, update `MIGRATION_STATUS.md`
before stopping so the next continuation can resume without rediscovery.

## Completion gate

The agent may report completion only when `ARCH-001` through `ARCH-016` are all
`DONE` or explicitly `WONT-DO`, the final verification commands pass, and the
final audit has been recorded in `MIGRATION_STATUS.md`.
