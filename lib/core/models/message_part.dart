class MessagePart {
  final String id;
  final bool isThink;
  bool closed;
  final StringBuffer buffer = StringBuffer();
  String get text => buffer.toString();

  MessagePart(this.id, { required this.isThink, this.closed = false });
  void append(String s) => buffer.write(s);
}
