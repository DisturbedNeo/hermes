import 'package:hermes/features/tools/application/tool_contracts.dart';

/// Common typed contract for model-facing planning registries.
abstract interface class PlanningToolRegistry {
  List<ToolDefinition> get toolDefinitions;
  String get terminalToolId;
  bool get allowsWorkspaceMutation;

  Future<PlanningResponse> invoke(
    String toolId,
    PlanningArguments arguments, {
    String? commandId,
  });
}

/// Typed planning command arguments. Wire JSON is owned by the protocol
/// adapter.
class PlanningArguments {
  const PlanningArguments._(this._values);

  factory PlanningArguments.fromWire(Map<String, Object?> values) =>
      PlanningArguments._(Map.unmodifiable(values));

  final Map<String, Object?> _values;

  Object? operator [](String key) => _values[key];
  bool containsKey(String key) => _values.containsKey(key);
  Iterable<String> get keys => _values.keys;
  Map<String, Object?> toWire() => _values;
}

/// Typed planning command response. Encoding is owned by the protocol adapter.
class PlanningResponse {
  const PlanningResponse._(this._values);

  factory PlanningResponse.fromWire(Map<String, Object?> values) =>
      PlanningResponse._(Map.unmodifiable(values));

  final Map<String, Object?> _values;

  Object? operator [](String key) => _values[key];
  bool containsKey(String key) => _values.containsKey(key);
  bool get ok => _values['ok'] == true;
  Map<String, Object?> toWire() => _values;
}

class PlanningToolArgumentException implements Exception {
  final String code;
  final String path;
  final String message;

  const PlanningToolArgumentException(this.code, this.path, this.message);

  @override
  String toString() => '$code ($path): $message';
}
