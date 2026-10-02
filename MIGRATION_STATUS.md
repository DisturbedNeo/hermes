# Hermes Architecture Migration Status

This file is the durable progress ledger for the implementation Goal. Update
it after every milestone; do not rely on conversation history as the source of
truth.

## Current state

- Overall status: `READY TO START`
- Active item: `ARCH-001`
- Last verified baseline: 2026-10-02
- Pre-existing user change: `README.md` was modified before migration setup;
  preserve it unless the migration explicitly updates the same documentation.
- No architecture migration implementation has been performed yet.
- Workspace preparation verification: `bash tool/verify.sh` passed; mapper
  generation, formatting, analysis, architecture tests, full tests, and diff
  whitespace checks completed successfully.

## Baseline evidence before migration setup

- `flutter analyze`: passed with no issues.
- `flutter test`: passed; 605 tests passed.
- Architecture suite: included in the passing full test run.
- The README referenced `tool/verify.sh`, but that script did not exist.
- No CI workflow was present under `.github`.

## Milestone ledger

| ID | Status | Evidence / notes |
|---|---|---|
| ARCH-001 | `PENDING` |  |
| ARCH-002 | `PENDING` |  |
| ARCH-003 | `PENDING` |  |
| ARCH-004 | `PENDING` |  |
| ARCH-005 | `PENDING` |  |
| ARCH-006 | `PENDING` |  |
| ARCH-007 | `PENDING` |  |
| ARCH-008 | `PENDING` |  |
| ARCH-009 | `PENDING` |  |
| ARCH-010 | `PENDING` |  |
| ARCH-011 | `PENDING` |  |
| ARCH-012 | `PENDING` |  |
| ARCH-013 | `PENDING` |  |
| ARCH-014 | `PENDING` |  |
| ARCH-015 | `PENDING` | `tool/verify.sh` is prepared and verified; CI remains part of the migration. |
| ARCH-016 | `PENDING` |  |

## Decisions and blockers

Record architectural decisions, rejected alternatives, compatibility findings,
and blockers here with dates and affected milestone IDs.

## Final audit

Complete only after every milestone has evidence and the final verification
commands pass.
