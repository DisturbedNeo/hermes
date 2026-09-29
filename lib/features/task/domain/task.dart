/// Task-owned identity used by task planning and execution boundaries.
///
/// Durable task snapshots are decoded by task infrastructure into the task
/// aggregate; this value is the domain-level identity contract.
class Task {
  const Task({required this.id, this.title = ''});

  final String id;
  final String title;
}
