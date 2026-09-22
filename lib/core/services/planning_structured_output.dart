import 'dart:convert';

import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';

class StructuredPlanningOutputException implements Exception {
  final String message;

  const StructuredPlanningOutputException(this.message);

  @override
  String toString() => message;
}

class StructuredPlanningOutputResult<T> {
  final T value;
  final PlanningMetrics planningMetrics;
  final bool repaired;

  const StructuredPlanningOutputResult({
    required this.value,
    this.planningMetrics = const PlanningMetrics(),
    this.repaired = false,
  });
}

/// Provides one bounded structured-output call plus one repair call for all
/// model-backed planning and evaluation paths.
class StructuredPlanningOutputService {
  const StructuredPlanningOutputService();

  Future<StructuredPlanningOutputResult<Map<String, dynamic>>> completeObject({
    required ChatClient client,
    required String label,
    required String system,
    required String user,
    required String expectedShape,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    var metrics = const PlanningMetrics();
    final first = await _completeRaw(
      client: client,
      label: label,
      system: system,
      user: user,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    metrics = metrics.copyWith(planningCalls: 1);
    final parsed = _tryParseObject(first);
    if (parsed != null) {
      return StructuredPlanningOutputResult(
        value: parsed,
        planningMetrics: metrics,
      );
    }

    cancellationToken?.throwIfCancelled();

    final repaired = await _completeRaw(
      client: client,
      label: '$label Repair',
      system: system,
      user:
          '''Repair this malformed model output into one valid JSON object matching this shape:
$expectedShape

Malformed output:
$first

Return only the repaired JSON object.''',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    metrics = metrics.copyWith(planningCalls: metrics.planningCalls + 1);
    final repairedObject = _tryParseObject(repaired);
    if (repairedObject == null) {
      throw StructuredPlanningOutputException(
        '$label did not return a valid JSON object after one repair attempt.',
      );
    }
    return StructuredPlanningOutputResult(
      value: repairedObject,
      planningMetrics: metrics,
      repaired: true,
    );
  }

  Future<String> _completeRaw({
    required ChatClient client,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    _emit(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.start, label: label),
    );
    final completion = await client.completeChatStreamed(
      messages: [
        ChatMessage(role: 'system', content: system),
        ChatMessage(role: 'user', content: user),
      ],
      diagnosticsLabel: label,
      onToken: (token) {
        final content = token.content;
        if (content != null && content.isNotEmpty) {
          _emit(
            onModelOutput,
            TaskModelOutputEvent(
              type: TaskModelOutputEventType.content,
              label: label,
              text: content,
              token: token,
            ),
          );
        }
        final reasoning = token.reasoning;
        if (reasoning != null && reasoning.isNotEmpty) {
          _emit(
            onModelOutput,
            TaskModelOutputEvent(
              type: TaskModelOutputEventType.reasoning,
              label: label,
              text: reasoning,
              token: token,
            ),
          );
        }
      },
      cancellationToken: cancellationToken,
    );
    _emit(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.done, label: label),
    );
    return completion.content.trim().isNotEmpty
        ? completion.content
        : completion.reasoning;
  }

  static Map<String, dynamic>? _tryParseObject(String raw) {
    final value = _stripCodeFence(raw.trim());
    final direct = _decodeMap(value);
    if (direct != null) return direct;
    final start = value.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < value.length; index++) {
      final character = value[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character == '\\') {
          escaped = true;
        } else if (character == '"') {
          inString = false;
        }
        continue;
      }
      if (character == '"') {
        inString = true;
      } else if (character == '{') {
        depth++;
      } else if (character == '}') {
        depth--;
        if (depth == 0) return _decodeMap(value.substring(start, index + 1));
      }
    }
    return null;
  }

  static Map<String, dynamic>? _decodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _stripCodeFence(String value) {
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim() ?? value;
  }

  static void _emit(TaskModelOutputSink? sink, TaskModelOutputEvent event) {
    sink?.call(event);
  }
}
