part of 'project_state_models.dart';

/// Project documents omit embedded task payloads and persistence revisions.
class ProjectSnapshotAggregateJsonHook extends JsonModelHook {
  const ProjectSnapshotAggregateJsonHook()
    : super(removeKeys: const {'tasks', 'persistenceRevision'});

}
