import 'dart:convert';

import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/tool_service.dart';

const Set<String> kCreationReadOnlyToolIds = {
  'calculator',
  'list_directory',
  'read_file',
  'search_files',
};

class _StreamingFinalizerToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

class FinalizerToolCallRunner {
  FinalizerToolCallRunner({required ToolService toolService})
    : _toolService = toolService;

  static const int defaultMaxToolCalls = 8;
  static const int defaultMaxRepeatedToolCalls = 3;

  final ToolService _toolService;

  Future<Map<String, dynamic>> completeWithFinalizer({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required String label,
    required String system,
    required String user,
    required ToolDefinition finalizerTool,
    required String reminderPrompt,
    bool allowReadOnlyTools = true,
    int maxToolCalls = defaultMaxToolCalls,
    int maxRepeatedToolCalls = defaultMaxRepeatedToolCalls,
    TaskModelOutputSink? onModelOutput,
    void Function()? throwIfCancelled,
  }) async {
    final allowedToolIds = {
      if (allowReadOnlyTools) ...kCreationReadOnlyToolIds,
    };
    final toolDefs = [
      ..._toolService.getToolDefinitions(
        ids: allowedToolIds.toList(),
        includeWorkspaceTools: true,
      ),
      finalizerTool,
    ];
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: system),
      ChatMessage(role: 'user', content: user),
    ];
    final context = WorkspaceToolContext(workspace: workspace);
    var toolCallCount = 0;
    var consecutiveRepeatCount = 0;
    String? previousToolKey;

    while (true) {
      throwIfCancelled?.call();
      final completion = await _complete(
        client: client,
        label: label,
        messages: messages,
        toolDefs: toolDefs,
        onModelOutput: onModelOutput,
      );
      throwIfCancelled?.call();

      final finalizerIndex = completion.toolCalls.indexWhere(
        (call) => call.name == finalizerTool.id,
      );
      if (finalizerIndex >= 0) {
        final finalizerCall = completion.toolCalls[finalizerIndex];
        final args = TaskJson.decodeJsonOrString(finalizerCall.arguments);
        _emitFinalizerResults(
          sink: onModelOutput,
          label: label,
          calls: completion.toolCalls,
          finalizerIndex: finalizerIndex,
        );
        if (args is Map<String, dynamic>) return args;
        if (args is Map) return Map<String, dynamic>.from(args);
        throw FormatException(
          '${finalizerTool.id} arguments must be a JSON object.',
        );
      }

      if (completion.toolCalls.isEmpty) {
        if (completion.content.trim().isNotEmpty ||
            completion.reasoning.trim().isNotEmpty) {
          messages.add(
            ChatMessage(
              role: 'assistant',
              content: completion.content,
              reasoningContent: completion.reasoning,
            ),
          );
        }
        break;
      }

      messages.add(
        ChatMessage(
          role: 'assistant',
          content: completion.content,
          reasoningContent: completion.reasoning,
          toolCalls: [
            for (var i = 0; i < completion.toolCalls.length; i++)
              {
                'id': completion.toolCalls[i].id ?? 'call_$i',
                'type': 'function',
                'function': {
                  'name': completion.toolCalls[i].name,
                  'arguments': TaskJson.decodeJsonOrString(
                    completion.toolCalls[i].arguments,
                  ),
                },
              },
          ],
        ),
      );

      String? loopGuardReason;
      for (var i = 0; i < completion.toolCalls.length; i++) {
        throwIfCancelled?.call();
        final call = completion.toolCalls[i];
        final callId = call.id ?? 'call_$i';
        final toolKey = _toolCallKey(call);
        if (toolKey == previousToolKey) {
          consecutiveRepeatCount++;
        } else {
          previousToolKey = toolKey;
          consecutiveRepeatCount = 1;
        }

        if (loopGuardReason == null &&
            consecutiveRepeatCount >= maxRepeatedToolCalls) {
          loopGuardReason =
              'The model repeated the same creation tool call $consecutiveRepeatCount times: ${call.name}.';
        }
        if (loopGuardReason == null && toolCallCount >= maxToolCalls) {
          loopGuardReason =
              'The model exceeded the creation read-only tool call limit of $maxToolCalls.';
        }

        final resultJson = await _executeToolCall(
          call: call,
          allowedToolIds: allowedToolIds,
          context: context,
          blockedReason: loopGuardReason,
        );
        toolCallCount++;
        _emit(
          onModelOutput,
          TaskModelOutputEvent(
            type: TaskModelOutputEventType.toolResult,
            label: label,
            text: resultJson,
            toolIndex: i,
          ),
        );
        messages.add(
          ChatMessage(role: 'tool', content: resultJson, toolCallId: callId),
        );
        if (loopGuardReason != null) break;
      }

      if (loopGuardReason != null) break;
    }

    final repair = await _complete(
      client: client,
      label: '$label Finalizer Repair',
      messages: [
        ...messages,
        ChatMessage(role: 'user', content: reminderPrompt),
      ],
      toolDefs: const [],
      onModelOutput: onModelOutput,
    );
    final text = repair.content.trim().isNotEmpty
        ? repair.content
        : repair.reasoning;
    return TaskJson.parseObject(text);
  }

  Future<ChatCompletionResponse> _complete({
    required ChatClient client,
    required String label,
    required List<ChatMessage> messages,
    required List<ToolDefinition> toolDefs,
    TaskModelOutputSink? onModelOutput,
  }) async {
    _emit(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.start, label: label),
    );
    final extraParams = ToolCaller.buildExtraParams(
      addGenerationPrompt: true,
      toolDefs: toolDefs,
    );
    final completion = client.supportsStreamingCancellation
        ? await _completeFromStream(
            client: client,
            messages: messages,
            extraParams: extraParams,
            label: label,
            onModelOutput: onModelOutput,
          )
        : await client.completeChatStreamed(
            messages: messages,
            extraParams: extraParams,
            onToken: (token) =>
                _emitToken(sink: onModelOutput, label: label, token: token),
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
  }) async {
    final content = StringBuffer();
    final reasoning = StringBuffer();
    final toolCalls = <int, _StreamingFinalizerToolCall>{};
    await for (final token in client.streamMessage(
      messages: messages,
      extraParams: extraParams,
    )) {
      _emitToken(sink: onModelOutput, label: label, token: token);
      final contentToken = token.content;
      if (contentToken != null) content.write(contentToken);
      final reasoningToken = token.reasoning;
      if (reasoningToken != null) reasoning.write(reasoningToken);
      final tool = token.tool;
      if (tool != null) {
        final call = toolCalls.putIfAbsent(
          tool.index,
          () => _StreamingFinalizerToolCall(),
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
                  arguments: entry.value.arguments.isEmpty
                      ? '{}'
                      : entry.value.arguments.toString(),
                ),
              )
              .toList(),
    );
  }

  void _emitToken({
    required TaskModelOutputSink? sink,
    required String label,
    required ChatToken token,
  }) {
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
    if (token.tool != null) {
      _emit(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.toolCall,
          label: label,
          token: token,
          toolIndex: token.tool!.index,
        ),
      );
    }
  }

  Future<String> _executeToolCall({
    required ChatCompletionToolCall call,
    required Set<String> allowedToolIds,
    required WorkspaceToolContext context,
    required String? blockedReason,
  }) {
    if (blockedReason != null) {
      return Future.value(
        jsonEncode({
          'error': 'Creation tool call skipped by loop guard.',
          'reason': blockedReason,
        }),
      );
    }
    if (!allowedToolIds.contains(call.name)) {
      return Future.value(
        jsonEncode({
          'error': 'Tool is not available during creation.',
          'tool': call.name,
          'availableTools': allowedToolIds.toList()..sort(),
          'reason':
              'Creation may only use read-only discovery tools before calling the finalizer tool.',
        }),
      );
    }
    return _toolService.execute(
      toolId: call.name,
      argumentsJson: call.arguments,
      context: context,
    );
  }

  void _emitFinalizerResults({
    required TaskModelOutputSink? sink,
    required String label,
    required List<ChatCompletionToolCall> calls,
    required int finalizerIndex,
  }) {
    for (var i = 0; i < calls.length; i++) {
      _emit(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.toolResult,
          label: label,
          text: i == finalizerIndex
              ? jsonEncode({'finalized': true})
              : jsonEncode({
                  'skipped': true,
                  'reason':
                      'The finalizer tool ended creation, so this tool call was ignored.',
                }),
          toolIndex: i,
        ),
      );
    }
  }

  String _toolCallKey(ChatCompletionToolCall call) {
    final decoded = TaskJson.decodeJsonOrString(call.arguments);
    return '${call.name}:${jsonEncode(decoded)}';
  }

  void _emit(TaskModelOutputSink? sink, TaskModelOutputEvent event) {
    sink?.call(event);
  }
}
