import 'package:hermes/core/enums/message_role.dart';

class Bubble {
  final String id;
  final MessageRole role;
  final String text;
  final String reasoning;

  const Bubble({required this.id, required this.role, required this.text, required this.reasoning});

  Bubble copyWith({
    String? id,
    MessageRole? role,
    String? text,
    String? reasoning,
  }) {
    return Bubble(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      reasoning: reasoning ?? this.reasoning,
    );
  }
}
