import 'package:hermes/core/enums/message_role.dart';

class Bubble {
  final String id;
  final MessageRole role;
  final String text;

  const Bubble({required this.id, required this.role, required this.text});

  Bubble copyWith({
    String? id,
    MessageRole? role,
    String? text,
  }) {
    return Bubble(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
    );
  }
}
