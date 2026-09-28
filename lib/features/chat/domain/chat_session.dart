/// Stable identity for a chat tab/session.
class ChatSessionId {
  final String value;

  const ChatSessionId(this.value) : assert(value != '');

  @override
  bool operator ==(Object other) =>
      other is ChatSessionId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
