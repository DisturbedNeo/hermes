import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/serialization/json_hooks.dart';

part 'chat_message.mapper.dart';

@MappableClass(
  generateMethods: GenerateMethods.encode,
  hook: JsonModelHook(
    omitEmpty: {'tool_calls'},
    omitEmptyStrings: {'reasoning_content', 'tool_call_id'},
  ),
)
class ChatMessage with ChatMessageMappable {
  final String role;
  final String content;
  @MappableField(key: 'reasoning_content')
  final String reasoningContent;
  @MappableField(key: 'tool_call_id')
  final String toolCallId;
  @MappableField(key: 'tool_calls')
  final List<Map<String, dynamic>> toolCalls;

  const ChatMessage({
    required this.role,
    required this.content,
    this.reasoningContent = '',
    this.toolCallId = '',
    this.toolCalls = const [],
  });
}
