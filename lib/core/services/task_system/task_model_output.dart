import 'package:hermes/core/models/chat_token.dart';

enum TaskModelOutputEventType {
  start,
  content,
  reasoning,
  toolCall,
  toolResult,
  done,
  error,
}

typedef TaskModelOutputSink = void Function(TaskModelOutputEvent event);

class TaskModelOutputEvent {
  final TaskModelOutputEventType type;
  final String label;
  final String text;
  final ChatToken? token;
  final int? toolIndex;
  final int? estimatedContextTokens;

  const TaskModelOutputEvent({
    required this.type,
    required this.label,
    this.text = '',
    this.token,
    this.toolIndex,
    this.estimatedContextTokens,
  });
}
