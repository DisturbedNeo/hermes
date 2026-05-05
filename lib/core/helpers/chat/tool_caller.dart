import 'dart:convert';

import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/tool_definition.dart';

class ToolCaller {
  final Map<String, Map<int, StringBuffer>> _toolBuffers = {};

  static final RegExp _toolCallBlockRegex = RegExp(
    r'<tool_call\b[^>]*>([\s\S]*?)</tool_call>',
    multiLine: true,
    caseSensitive: false,
  );

  static final RegExp _functionBlockRegex = RegExp(
    r'<function\s*=\s*([^>\s]+)\s*>([\s\S]*?)</function>',
    multiLine: true,
    caseSensitive: false,
  );

  static final RegExp _parameterRegex = RegExp(
    r'<parameter\s*=\s*([^>\s]+)\s*>([\s\S]*?)</parameter>',
    multiLine: true,
    caseSensitive: false,
  );

  static BubbleToolCall? parseXML(String body) {
    return _parseTaggedFunctionCall(body) ?? _parseLegacyXmlCall(body);
  }

  static InlineToolCallExtraction extractInlineToolCalls(String text) {
    if (text.isEmpty || !text.toLowerCase().contains('<tool_call')) {
      return InlineToolCallExtraction(text: text);
    }

    final calls = <BubbleToolCall>[];
    final remaining = StringBuffer();
    var cursor = 0;

    for (final match in _toolCallBlockRegex.allMatches(text)) {
      remaining.write(text.substring(cursor, match.start));
      final rawBlock = match.group(0) ?? '';
      final body = match.group(1) ?? '';
      final parsed = parseXML(body);

      if (parsed == null) {
        remaining.write(rawBlock);
      } else {
        calls.add(parsed);
      }

      cursor = match.end;
    }

    remaining.write(text.substring(cursor));

    return InlineToolCallExtraction(
      text: _tidyAfterToolRemoval(remaining.toString()),
      calls: calls,
    );
  }

  static BubbleToolCall? _parseTaggedFunctionCall(String body) {
    final match = _functionBlockRegex.firstMatch(body);
    if (match == null) return _parseJsonToolCall(body);

    final name = _cleanTagValue(match.group(1));
    if (name == null || !_looksLikeToolName(name)) return null;

    final args = <String, dynamic>{};
    final functionBody = match.group(2) ?? '';

    for (final parameter in _parameterRegex.allMatches(functionBody)) {
      final key = _cleanTagValue(parameter.group(1));
      if (key == null || key.isEmpty) continue;
      args[key] = _coerceParameterValue(parameter.group(2) ?? '');
    }

    return BubbleToolCall(name: name, arguments: jsonEncode(args));
  }

  static BubbleToolCall? _parseJsonToolCall(String body) {
    final trimmed = _stripCodeFence(body.trim());
    if (trimmed.isEmpty ||
        !(trimmed.startsWith('{') || trimmed.startsWith('['))) {
      return null;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return null;
    }

    if (decoded is List) {
      decoded = decoded.whereType<Map>().firstOrNull;
    }

    if (decoded is! Map) return null;

    final map = Map<String, dynamic>.from(decoded);
    final function = map['function'];
    final functionMap = function is Map
        ? Map<String, dynamic>.from(function)
        : <String, dynamic>{};

    final name = _stringValue(
      functionMap['name'] ?? map['name'] ?? map['tool'] ?? map['tool_name'],
    );
    if (name == null || !_looksLikeToolName(name)) return null;

    final rawArgs =
        functionMap['arguments'] ?? map['arguments'] ?? map['parameters'];

    return BubbleToolCall(
      id: _stringValue(map['id']),
      name: name,
      arguments: _argumentsJson(rawArgs),
    );
  }

  static BubbleToolCall? _parseLegacyXmlCall(String body) {
    final lines = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final toolName = lines.first;
    if (!_looksLikeToolName(toolName)) return null;
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

  static String? _cleanTagValue(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  static bool _looksLikeToolName(String value) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(value);
  }

  static String _argumentsJson(Object? rawArgs) {
    if (rawArgs == null) return '{}';
    if (rawArgs is String) {
      final trimmed = rawArgs.trim();
      return trimmed.isEmpty ? '{}' : trimmed;
    }
    return jsonEncode(rawArgs);
  }

  static dynamic _coerceParameterValue(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    final looksJson =
        value.startsWith('{') ||
        value.startsWith('[') ||
        value.startsWith('"') ||
        value == 'true' ||
        value == 'false' ||
        value == 'null' ||
        RegExp(
          r'^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$',
        ).hasMatch(value);

    if (looksJson) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }

    return value;
  }

  static String _stripCodeFence(String value) {
    final fence = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(value);
    return fence?.group(1)?.trim() ?? value;
  }

  static String _tidyAfterToolRemoval(String text) {
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
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

  Map<int, BubbleToolCall> applyDelta({
    required String messageId,
    required ToolCallDelta delta,
    required Map<int, BubbleToolCall> currentTools,
  }) {
    final buffersForMsg = _toolBuffers.putIfAbsent(
      messageId,
      () => <int, StringBuffer>{},
    );
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

    final calls = b.tools.entries.where((t) => t.value.result == null).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return calls.map((c) => c.value).toList();
  }

  static Bubble withResult(
    Bubble bubble, {
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

  void clearForMessage(String messageId) {
    _toolBuffers.remove(messageId);
  }

  void clearAll() {
    _toolBuffers.clear();
  }
}

class InlineToolCallExtraction {
  final String text;
  final List<BubbleToolCall> calls;

  const InlineToolCallExtraction({required this.text, this.calls = const []});
}
