import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';

class ContentNormaliser {
  static final RegExp _thinkRegex = RegExp(
    r'<think>([\s\S]*?)</think>\s*',
    multiLine: true,
  );

  static Bubble normalise(Bubble bubble) {
    if (bubble.role != MessageRole.assistant) return bubble;

    String remaining = bubble.text;
    String reasoning = bubble.reasoning;
    final toolsMap = Map<int, BubbleToolCall>.from(bubble.tools);
    var toolIndex = toolsMap.length;

    final thinkMatches = _thinkRegex.allMatches(remaining).toList();
    for (final thinkMatch in thinkMatches) {
      final thinkContent = thinkMatch.group(1)?.trim() ?? '';
      if (thinkContent.isNotEmpty) {
        reasoning = ('$reasoning\n$thinkContent').trim();
      }
    }

    remaining = remaining.replaceAllMapped(_thinkRegex, (match) {
      final before = match.start > 0 ? remaining[match.start - 1] : '';
      final after = match.end < remaining.length ? remaining[match.end] : '';
      final joinsWords = _isWordBoundary(before) && _isWordBoundary(after);
      return joinsWords ? ' ' : '';
    }).trim();

    final textExtraction = ToolCaller.extractInlineToolCalls(remaining);
    remaining = textExtraction.text;
    for (final call in textExtraction.calls) {
      toolsMap[toolIndex++] = call;
    }

    final reasoningExtraction = ToolCaller.extractInlineToolCalls(reasoning);
    reasoning = reasoningExtraction.text;
    for (final call in reasoningExtraction.calls) {
      toolsMap[toolIndex++] = call;
    }

    return bubble.copyWith(
      reasoning: reasoning,
      text: remaining,
      tools: toolsMap,
    );
  }

  static bool _isWordBoundary(String value) {
    return value.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(value);
  }
}
