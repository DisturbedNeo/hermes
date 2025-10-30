import 'package:hermes/core/enums/message_role.dart';

class Bubble {
  final String id;
  final MessageRole role;
  final String text;
  final String reasoning;
  final Map<int, BubbleToolCall> tools;

  const Bubble({required this.id, required this.role, required this.text, required this.reasoning, this.tools = const {}});

  Bubble copyWith({
    String? id,
    MessageRole? role,
    String? text,
    String? reasoning,
    Map<int, BubbleToolCall>? tools,
  }) {
    return Bubble(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      reasoning: reasoning ?? this.reasoning,
      tools: tools ?? this.tools,
    );
  }
}

class BubbleToolCall {
  final String? id;
  final String? name;
  final String arguments;

  const BubbleToolCall({
    this.id,
    this.name,
    this.arguments = '',
  });

  BubbleToolCall copyWith({
    String? id,
    String? name,
    String? arguments
  }) {
    return BubbleToolCall(
      id: id ?? this.id,
      name: name ?? this.name,
      arguments: arguments ?? this.arguments
    );
  }
}
