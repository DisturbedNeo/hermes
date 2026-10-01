/// Typed task-plan update command. JSON compatibility is isolated to this
/// command value before it reaches task application ports.
class TaskPlanUpdateCommand {
  const TaskPlanUpdateCommand._(this._values);

  factory TaskPlanUpdateCommand.fromWire(Map<String, Object?> values) =>
      TaskPlanUpdateCommand._(Map.unmodifiable(values));

  final Map<String, Object?> _values;

  Map<String, Object?> toWire() => _values;
}
