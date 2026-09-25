# hermes

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Generated serialization

Typed JSON mapping is generated with `dart_mappable`. After changing an
annotated DTO, regenerate and commit the mapper outputs:

```sh
dart run build_runner build
```

Application code should use `ModelJson` rather than calling generated mapper
classes or per-model JSON methods directly.

## Project system boundaries

The project system has three deliberately separate concerns:

- `ProjectLifecycleService` owns project status transitions and
  `ProjectControlStateService` records the durable, application-facing
  outcome and next action.
- Project planning exchanges `ProjectTaskSpec` values and commits through
  `ProjectPlanRevisionService`, which validates, evaluates risk, handles
  approval, and reconciles a complete desired plan atomically.
- The task system owns executable task documents, steps, runs, artifacts, and
  planning fallback diagnostics. Projects retain task IDs and hydrated
  compatibility views, while `ProjectScheduler` selects a dependency-aware
  execution frontier.

Frontier limits are bounded run budgets, not automatic replanning triggers.
Plans are revised only for an explicit scope, dependency, evidence,
workspace, failure, or roadmap change.

The runtime keeps deterministic project decisions separate from effects. The
`ProjectDecisionEngine` selects the next command boundary, while model calls,
task execution, and persistence execute that decision. `ProjectState` exposes
separate plan, execution, evidence, and control read models during the schema
migration; the persisted document remains compatible with older snapshots.

Every planning producer is adapted to a typed `ProjectPlanPatch`, which passes
through the same validation, risk, approval, and reconciliation service.
Aggregate transaction manifests record semantic persistence checkpoints.
Interrupted transactions can be explicitly rolled back when snapshot
revisions make that safe; unresolved transactions remain read-only and
diagnostic.
