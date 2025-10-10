enum MessageRole {
  user,
  assistant,
  system,
}

extension MessageRoleWire on MessageRole {
  String get wire => switch (this) {
    MessageRole.user => 'user',
    MessageRole.assistant => 'assistant',
    MessageRole.system => 'system',
  };
}
