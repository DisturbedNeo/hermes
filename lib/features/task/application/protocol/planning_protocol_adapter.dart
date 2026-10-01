import 'dart:convert';

import 'package:hermes/features/task/application/protocol/planning_contracts.dart';

/// Owns the JSON boundary for planner tool arguments and results. Planning
/// registries receive [PlanningArguments] and return [PlanningResponse].
class PlanningProtocolAdapter {
  const PlanningProtocolAdapter({required this.registry});

  final PlanningToolRegistry registry;

  Future<String> execute(
    String toolId,
    String argumentsJson, {
    String? commandId,
  }) async {
    try {
      final decoded = jsonDecode(argumentsJson);
      if (decoded is! Map) {
        return jsonEncode({
          'ok': false,
          'code': 'invalid_argument',
          'path': 'arguments',
          'message': 'Tool arguments must be a JSON object.',
        });
      }
      final arguments = <String, Object?>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) {
          return jsonEncode({
            'ok': false,
            'code': 'invalid_argument',
            'path': 'arguments',
            'message': 'Tool argument names must be strings.',
          });
        }
        arguments[entry.key as String] = entry.value;
      }
      return jsonEncode(
        (await registry.invoke(
          toolId,
          PlanningArguments.fromWire(arguments),
          commandId: commandId,
        )).toWire(),
      );
    } on FormatException catch (error) {
      return jsonEncode({
        'ok': false,
        'code': 'invalid_argument',
        'path': 'arguments',
        'message': 'Malformed JSON arguments: ${error.message}',
      });
    }
  }
}
