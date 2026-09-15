import 'dart:convert';

import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_planning_tools.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';

/// Runs the model/tool loop for one project-planning draft.
///
/// The draft registry is the only tool surface, and [plan_commit] is the
/// terminal command.
class ProjectPlanningToolCallRunner {
  const ProjectPlanningToolCallRunner();

  Future<Map<String, dynamic>> complete({
    required ChatClient client,
    required ProjectPlanningToolRegistry registry,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: system),
      ChatMessage(role: 'user', content: user),
    ];
    final toolDefinitions = registry.toolDefinitions;
    var turn = 0;
    var metrics = const PlanningMetrics();

    while (true) {
      cancellationToken?.throwIfCancelled();
      turn++;
      final completion = await _complete(
        client: client,
        label: label,
        messages: messages,
        toolDefinitions: toolDefinitions,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      cancellationToken?.throwIfCancelled();
      metrics = _recordModelCall(
        metrics,
        messages: messages,
        toolDefinitions: toolDefinitions,
        completion: completion,
      );

      if (completion.toolCalls.isEmpty) {
        final text = completion.content.trim().isNotEmpty
            ? completion.content.trim()
            : completion.reasoning.trim();
        return _withMetrics({
          'ok': false,
          'code': 'planning_protocol_violation',
          'message': text.isEmpty
              ? 'The planner returned no planning command.'
              : 'The planner returned text instead of a planning command.',
        }, metrics);
      }

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
        final resultJson = await registry.execute(
          call.name,
          call.arguments,
          commandId: commandId,
        );
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
        if (call.name == 'plan_commit' && result?['ok'] == true) {
          for (
            var remaining = index + 1;
            remaining < completion.toolCalls.length;
            remaining++
          ) {
            _emit(
              onModelOutput,
              TaskModelOutputEvent(
                type: TaskModelOutputEventType.toolResult,
                label: label,
                text: jsonEncode({
                  'skipped': true,
                  'reason': 'plan_commit ended the planning draft.',
                }),
                toolIndex: remaining,
              ),
            );
          }
          final committed =
              result ??
              _error(
                code: 'planning_tool_failed',
                path: 'plan_commit',
                message: 'The plan commit returned an invalid tool result.',
              );
          return _withMetrics({...committed, 'model_calls': turn}, metrics);
        }
      }
    }
  }

  Future<ChatCompletionResponse> _complete({
    required ChatClient client,
    required String label,
    required List<ChatMessage> messages,
    required List<ToolDefinition> toolDefinitions,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    _emit(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.start, label: label),
    );
    final extraParams = ToolCaller.buildExtraParams(
      addGenerationPrompt: true,
      toolDefs: toolDefinitions,
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
      final contentToken = token.content;
      if (contentToken != null) content.write(contentToken);
      final reasoningToken = token.reasoning;
      if (reasoningToken != null) reasoning.write(reasoningToken);
      final tool = token.tool;
      if (tool != null) {
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
                  arguments: entry.value.arguments.length == 0
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
      // A malformed tool result cannot be a successful commit.
    }
    return null;
  }

  static Map<String, dynamic> _error({
    required String code,
    required String path,
    required String message,
    PlanningMetrics metrics = const PlanningMetrics(),
  }) => _withMetrics({
    'ok': false,
    'code': code,
    'path': path,
    'message': message,
  }, metrics);

  static PlanningMetrics _recordModelCall(
    PlanningMetrics metrics, {
    required List<ChatMessage> messages,
    required List<ToolDefinition> toolDefinitions,
    required ChatCompletionResponse completion,
  }) {
    final extraParams = ToolCaller.buildExtraParams(
      addGenerationPrompt: true,
      toolDefs: toolDefinitions,
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

class _StreamingPlanningToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
