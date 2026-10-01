import 'package:hermes/features/task/application/protocol/planning_runtime.dart';

Future<Map<String, dynamic>> invokePlanning(
  PlanningToolRegistry registry,
  String toolId,
  Object arguments, {
  String? commandId,
}) async {
  final wire = arguments is Map
      ? Map<String, Object?>.from(arguments)
      : const <String, Object?>{};
  return Map<String, dynamic>.from(
    (await registry.invoke(
      toolId,
      PlanningArguments.fromWire(wire),
      commandId: commandId,
    )).toWire(),
  );
}

Future<String> executePlanning(
  PlanningToolRegistry registry,
  String toolId,
  String argumentsJson, {
  String? commandId,
}) => PlanningProtocolAdapter(
  registry: registry,
).execute(toolId, argumentsJson, commandId: commandId);
