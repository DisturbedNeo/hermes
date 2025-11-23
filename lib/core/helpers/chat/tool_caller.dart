import 'dart:convert';

import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/tool_definition.dart';

class ToolCaller {
  static final Map<String, Map<int, StringBuffer>> _toolBuffers = {};

  static BubbleToolCall? parseXML(String body) {
    final lines = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final toolName = lines.first;
    final rest = lines.skip(1).join('\n');

    final keyRegex = RegExp(r'<arg_key>([^<]+)</arg_key>');
    final valRegex = RegExp(r'<arg_value>([^<]+)</arg_value>');

    final keyMatches = keyRegex.allMatches(rest).toList();
    final valMatches = valRegex.allMatches(rest).toList();

    final args = <String, String>{};
    final len = keyMatches.length < valMatches.length
        ? keyMatches.length
        : valMatches.length;

    for (var i = 0; i < len; i++) {
      final k = keyMatches[i].group(1)?.trim();
      final v = valMatches[i].group(1)?.trim();
      if (k != null && v != null) {
        args[k] = v;
      }
    }

    return BubbleToolCall(name: toolName, arguments: jsonEncode(args));
  }

  static String buildReadableToolResult(Map<int, BubbleToolCall> tools) {
    final sb = StringBuffer();
    for (final entry in tools.entries) {
      final tc = entry.value;
      if (tc.result == null) continue;
      final name = tc.name ?? 'tool';
      sb.writeln('🔧 **$name**');
      sb.writeln(tc.result);
      sb.writeln();
    }
    return sb.toString().trim();
  }

  static Map<int, BubbleToolCall> applyDelta({
    required String messageId,
    required ToolCallDelta delta,
    required Map<int, BubbleToolCall> currentTools,
  }) {
    final buffersForMsg = _toolBuffers.putIfAbsent(messageId, () => <int, StringBuffer>{});
    final buf = buffersForMsg.putIfAbsent(delta.index, () => StringBuffer());

    if (delta.argumentsChunk != null && delta.argumentsChunk!.isNotEmpty) {
      buf.write(delta.argumentsChunk);
    }

    final existing = currentTools[delta.index];
    final updated = (existing ?? BubbleToolCall()).copyWith(
      id: delta.id ?? existing?.id,
      name: delta.name ?? existing?.name,
      arguments: buf.toString(),
    );

    final next = Map<int, BubbleToolCall>.from(currentTools);
    next[delta.index] = updated;
    return next;
  }

  static Map<String, dynamic> buildExtraParams({
    required bool addGenerationPrompt,
    required List<ToolDefinition> toolDefs,
  }) {
    final openAITools = toolDefs.map((t) {
      return {
        'type': 'function',
        'function': {
          'name': t.id,
          'description': t.description,
          'parameters': t.schema,
        },
      };
    }).toList();

    return {
      'add_generation_prompt': addGenerationPrompt,
      if (openAITools.isNotEmpty) 'tools': openAITools,
      if (openAITools.isNotEmpty) 'tool_choice': 'auto',
      if (!addGenerationPrompt)
        'chat_template_kwargs': {
          'enable_thinking': false,
          'reasoning_budget': 0,
        },
    };
  }

  static List<BubbleToolCall> extractToolCalls(Bubble? b) {
    if (b == null || b.tools.isEmpty) return const [];

    final calls =
        b.tools.entries.where((t) => t.value.result == null).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    return calls.map((c) => c.value).toList();
  }

  static Bubble withResult(Bubble bubble, {
    required int index,
    required String resultJson,
  }) {
    final tools = Map<int, BubbleToolCall>.from(bubble.tools);
    final existing = tools[index];
    if (existing == null) return bubble;

    tools[index] = existing.copyWith(
      arguments: '${existing.arguments}\n→ result: $resultJson',
    );

    return bubble.copyWith(tools: tools);
  }

  static void clearForMessage(String messageId) {
    _toolBuffers.remove(messageId);
  }

  static void clearAll() {
    _toolBuffers.clear();
  }
}
