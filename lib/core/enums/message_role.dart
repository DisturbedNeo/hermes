enum MessageRole {
  user,
  assistant,
  system,
  tool,
}

extension MessageRoleWire on MessageRole {
  String get wire => switch (this) {
    MessageRole.user => 'user',
    MessageRole.assistant => 'assistant',
    MessageRole.system => 'system',
    MessageRole.tool => 'tool'
  };
}
