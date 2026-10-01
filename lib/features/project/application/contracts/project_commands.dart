/// Typed project-plan update command. JSON compatibility is isolated to this
/// command value before it reaches project application ports.
class ProjectUpdateCommand {
  const ProjectUpdateCommand._(this._values);

  factory ProjectUpdateCommand.fromWire(Map<String, Object?> values) =>
      ProjectUpdateCommand._(Map.unmodifiable(values));

  final Map<String, Object?> _values;

  Map<String, Object?> toWire() => _values;
}
