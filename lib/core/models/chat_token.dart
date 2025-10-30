class ChatToken {
  final String? content;
  final String? reasoning;
  final ToolCallDelta? tool;

  ChatToken({ this.content, this.reasoning, this.tool });
}

class ToolCallDelta {
  final int index;
  final String? id;
  final String? name;
  final String? argumentsChunk;

  ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsChunk,
  });
}
