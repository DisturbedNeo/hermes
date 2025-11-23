import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';

class ContentNormaliser {
  static final RegExp _thinkRegex = RegExp(
    r'<think>([\s\S]*?)</think>',
    multiLine: true,
  );

  static final RegExp _xmlToolRegex = RegExp(
    r'<tool_call>([\s\S]*?)</tool_call>',
    multiLine: true,
  );

  static Bubble normalise(Bubble bubble) {
    if (bubble.role != MessageRole.assistant) return bubble;
    if (bubble.text.isEmpty) return bubble;

    String remaining = bubble.text;
    String reasoning = bubble.reasoning;
    final toolsMap = Map<int, BubbleToolCall>.from(bubble.tools);
    var toolIndex = toolsMap.length;

    final thinkMatch = _thinkRegex.firstMatch(remaining);
    if (thinkMatch != null) {
      final thinkContent = thinkMatch.group(1)?.trim() ?? '';
      if (thinkContent.isNotEmpty) {
        reasoning = ('$reasoning\n$thinkContent').trim();
      }
      remaining = remaining
          .replaceRange(thinkMatch.start, thinkMatch.end, '')
          .trim();
    }

    final xmlToolMatches = _xmlToolRegex.allMatches(remaining).toList();
    for (final m in xmlToolMatches) {
      final inner = m.group(1) ?? '';
      final parsed = ToolCaller.parseXML(inner);
      if (parsed != null) {
        toolsMap[toolIndex++] = parsed;
      }
    }

    remaining = remaining.replaceAll(_xmlToolRegex, '').trim();

    return bubble.copyWith(
      reasoning: reasoning,
      text: remaining,
      tools: toolsMap,
    );
  }
}
