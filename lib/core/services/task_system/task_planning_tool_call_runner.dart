import 'dart:convert';

import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_planning_tools.dart';
import 'package:hermes/core/serialization/model_json.dart';

class _StreamingPlanningToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

/// Runs the bounded task planning command loop.
class TaskPlanningToolCallRunner {
  const TaskPlanningToolCallRunner();

  static const int defaultMaxToolCalls = 24;
  static const int defaultMaxRepeatedToolCalls = 3;
  static const int defaultMaxIdleTurns = 2;

  Future<Map<String, dynamic>> complete({
    required ChatClient client,
    required TaskPlanningToolRegistry registry,
    required String label,
    required String system,
    required String user,
    int maxToolCalls = defaultMaxToolCalls,
    int maxRepeatedToolCalls = defaultMaxRepeatedToolCalls,
    int maxIdleTurns = defaultMaxIdleTurns,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: system),
      ChatMessage(role: 'user', content: user),
    ];
    final definitions = registry.toolDefinitions;
    var toolCallCount = 0;
    var idleTurns = 0;
    var repeatedCalls = 0;
    String? previousCallKey;
    var turn = 0;
    var usedPlanningTools = false;
    var metrics = const PlanningMetrics();

    while (toolCallCount < maxToolCalls) {
      cancellationToken?.throwIfCancelled();
      turn++;
      final completion = await _complete(
        client: client,
        label: label,
        messages: messages,
        definitions: definitions,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      cancellationToken?.throwIfCancelled();
      metrics = _recordModelCall(
        metrics,
        messages: messages,
        definitions: definitions,
        completion: completion,
      );

      if (completion.toolCalls.isEmpty) {
        final text = completion.content.trim().isNotEmpty
            ? completion.content.trim()
            : completion.reasoning.trim();
        // Old integrations still return the former whole-plan JSON. Let the
        // caller use its compatibility path without spending reminder turns.
        if (text.startsWith('{') || text.startsWith('```')) {
          final legacy = TaskJson.tryParseObject(text);
          return {
            'ok': false,
            'legacy_json': legacy,
            'used_planning_tools': usedPlanningTools,
            'planning_metrics': ModelJson.encode(metrics),
          };
        }
        if (text.isNotEmpty) {
          messages.add(
            ChatMessage(
              role: 'assistant',
              content: completion.content,
              reasoningContent: completion.reasoning,
            ),
          );
        }
        idleTurns++;
        if (idleTurns > maxIdleTurns) {
          return _error(
            code: 'planning_loop_incomplete',
            path: 'tool',
            message:
                'The task planner did not call task_commit_plan after $maxIdleTurns reminder turns.',
            usedPlanningTools: usedPlanningTools,
            metrics: metrics,
          );
        }
        messages.add(
          const ChatMessage(
            role: 'user',
            content:
                'Continue with the task planning tools. When the draft is complete, call task_commit_plan; do not return the plan as a JSON document in text.',
          ),
        );
        continue;
      }

      // Older adapters may still send the former single finalizer call. Keep
      // it lossless and let TaskService decode it through its compatibility
      // normalisation path without making a second model request.
      if (completion.toolCalls.length == 1 &&
          completion.toolCalls.first.name == 'finaliseTaskCreation') {
        return {
          'ok': false,
          'legacy_finalizer': true,
          'arguments': TaskJson.decodeJsonOrString(
            completion.toolCalls.first.arguments,
          ),
          'used_planning_tools': false,
          'planning_metrics': ModelJson.encode(metrics),
        };
      }

      usedPlanningTools = true;
      idleTurns = 0;
      final assistantCalls = <Map<String, dynamic>>[];
      for (var index = 0; index < completion.toolCalls.length; index++) {
        final call = completion.toolCalls[index];
        final commandId = _commandId(call, turn, index, label);
        assistantCalls.add({
          'id': commandId,
          'type': 'function',
          'function': {
            'name': call.name,
            'arguments': TaskJson.decodeJsonOrString(call.arguments),
          },
        });
      }
      messages.add(
        ChatMessage(
          role: 'assistant',
          content: completion.content,
          reasoningContent: completion.reasoning,
          toolCalls: assistantCalls,
        ),
      );

      for (var index = 0; index < completion.toolCalls.length; index++) {
        cancellationToken?.throwIfCancelled();
        final call = completion.toolCalls[index];
        final commandId = _commandId(call, turn, index, label);
        final callKey = '${call.name}:${call.arguments}';
        if (callKey == previousCallKey) {
          repeatedCalls++;
        } else {
          previousCallKey = callKey;
          repeatedCalls = 1;
        }
        final resultJson = repeatedCalls >= maxRepeatedToolCalls
            ? jsonEncode(
                _error(
                  code: 'planning_loop_guard',
                  path: 'tool',
                  message:
                      'The planner repeated the same tool call $repeatedCalls times.',
                  usedPlanningTools: true,
                ),
              )
            : await registry.execute(
                call.name,
                call.arguments,
                commandId: commandId,
              );
        toolCallCount++;
        _emit(
          onModelOutput,
          TaskModelOutputEvent(
            type: TaskModelOutputEventType.toolResult,
            label: label,
            text: resultJson,
            toolIndex: index,
          ),
        );
        messages.add(
          ChatMessage(role: 'tool', content: resultJson, toolCallId: commandId),
        );
        final result = _decodeMap(resultJson);
        metrics = _recordToolResult(metrics, resultJson, result);
        if (call.name == 'task_commit_plan' && result?['ok'] == true) {
          return {
            ...result!,
            'model_calls': turn,
            'planning_metrics': ModelJson.encode(metrics),
          };
        }
        if (toolCallCount >= maxToolCalls) {
          return _error(
            code: 'planning_loop_limit',
            path: 'tool',
            message:
                'The planner exceeded the task planning tool call limit of $maxToolCalls before committing.',
            usedPlanningTools: true,
            metrics: metrics,
          );
        }
      }
    }
    return _error(
      code: 'planning_loop_limit',
      path: 'tool',
      message:
          'The planner exceeded the task planning tool call limit before committing.',
      usedPlanningTools: usedPlanningTools,
      metrics: metrics,
    );
  }

  Future<ChatCompletionResponse> _complete({
    required ChatClient client,
    required String label,
    required List<ChatMessage> messages,
    required List<ToolDefinition> definitions,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    _emit(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.start, label: label),
    );
    final extraParams = ToolCaller.buildExtraParams(
      addGenerationPrompt: true,
      toolDefs: definitions,
    );
    final completion = client.supportsStreamingCancellation
        ? await _completeFromStream(
            client: client,
            messages: messages,
            extraParams: extraParams,
            label: label,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          )
        : await client.completeChatStreamed(
            messages: messages,
            extraParams: extraParams,
            onToken: (token) => _emitToken(onModelOutput, label, token),
            cancellationToken: cancellationToken,
            diagnosticsLabel: label,
          );
    _emit(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.done, label: label),
    );
    return completion;
  }

  Future<ChatCompletionResponse> _completeFromStream({
    required ChatClient client,
    required List<ChatMessage> messages,
    required Map<String, dynamic> extraParams,
    required String label,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final content = StringBuffer();
    final reasoning = StringBuffer();
    final toolCalls = <int, _StreamingPlanningToolCall>{};
    await for (final token in client.streamMessage(
      messages: messages,
      extraParams: extraParams,
      cancellationToken: cancellationToken,
      diagnosticsLabel: label,
    )) {
      _emitToken(onModelOutput, label, token);
      if (token.content != null) {
        content.write(token.content);
      }
      if (token.reasoning != null) {
        reasoning.write(token.reasoning);
      }
      final tool = token.tool;
      if (tool == null) {
        continue;
      }
      final call = toolCalls.putIfAbsent(
        tool.index,
        () => _StreamingPlanningToolCall(),
      );
      if (tool.id != null) call.id = tool.id;
      if (tool.name != null) call.name = tool.name;
      if (tool.argumentsChunk != null) {
        call.arguments.write(tool.argumentsChunk);
      }
    }
    return ChatCompletionResponse(
      content: content.toString(),
      reasoning: reasoning.toString(),
      toolCalls:
          (toolCalls.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
              .where((entry) => entry.value.name?.trim().isNotEmpty == true)
              .map(
                (entry) => ChatCompletionToolCall(
                  id: entry.value.id,
                  name: entry.value.name!,
                  arguments: entry.value.arguments.isEmpty
                      ? '{}'
                      : entry.value.arguments.toString(),
                ),
              )
              .toList(),
    );
  }

  void _emitToken(TaskModelOutputSink? sink, String label, ChatToken token) {
    final content = token.content;
    if (content != null && content.isNotEmpty) {
      _emit(
        sink,
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
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.reasoning,
          label: label,
          text: reasoning,
          token: token,
        ),
      );
    }
    final tool = token.tool;
    if (tool != null) {
      _emit(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.toolCall,
          label: label,
          token: token,
          toolIndex: tool.index,
        ),
      );
    }
  }

  static String _commandId(
    ChatCompletionToolCall call,
    int turn,
    int index,
    String label,
  ) {
    final id = call.id?.trim();
    return id == null || id.isEmpty ? '$label:$turn:$index' : id;
  }

  static Map<String, dynamic>? _decodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // A malformed result cannot be a successful commit.
    }
    return null;
  }

  static Map<String, dynamic> _error({
    required String code,
    required String path,
    required String message,
    required bool usedPlanningTools,
    PlanningMetrics metrics = const PlanningMetrics(),
  }) => _withMetrics({
    'ok': false,
    'code': code,
    'path': path,
    'message': message,
    'used_planning_tools': usedPlanningTools,
  }, metrics);

  static PlanningMetrics _recordModelCall(
    PlanningMetrics metrics, {
    required List<ChatMessage> messages,
    required List<ToolDefinition> definitions,
    required ChatCompletionResponse completion,
  }) {
    final extraParams = ToolCaller.buildExtraParams(
      addGenerationPrompt: true,
      toolDefs: definitions,
    );
    final promptTokens =
        completion.diagnostics?.promptTokens ??
        ContextEstimator.estimateChatCompletionRequest(
          messages: messages,
          extraParams: extraParams,
        );
    return metrics.copyWith(
      planningCalls: metrics.planningCalls + 1,
      promptTokenEstimate: metrics.promptTokenEstimate + promptTokens,
    );
  }

  static PlanningMetrics _recordToolResult(
    PlanningMetrics metrics,
    String resultJson,
    Map<String, dynamic>? result,
  ) {
    final code = result?['code']?.toString().toLowerCase() ?? '';
    return metrics.copyWith(
      planningCommandCount: metrics.planningCommandCount + 1,
      toolResultTokenEstimate:
          metrics.toolResultTokenEstimate +
          ContextEstimator.estimateText(resultJson),
      invalidCommandCount:
          metrics.invalidCommandCount + (result?['ok'] == false ? 1 : 0),
      validationBlockerCount:
          metrics.validationBlockerCount + (_isValidationFailure(code) ? 1 : 0),
    );
  }

  static bool _isValidationFailure(String code) =>
      code.contains('validation') ||
      code.contains('duplicate') ||
      code.contains('unknown_ref') ||
      code.contains('stale_revision');

  static Map<String, dynamic> _withMetrics(
    Map<String, dynamic> result,
    PlanningMetrics metrics,
  ) => {...result, 'planning_metrics': ModelJson.encode(metrics)};

  static void _emit(TaskModelOutputSink? sink, TaskModelOutputEvent event) {
    sink?.call(event);
  }
}
