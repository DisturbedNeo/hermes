import 'package:hermes/features/chat/application/contracts/chat_token.dart';

enum TaskModelOutputEventType {
  start,
  content,
  reasoning,
  toolCall,
  toolResult,
  done,
  error,
}

typedef ModelOutputSink = void Function(TaskModelOutputEvent event);

class TaskModelOutputEvent {
  const TaskModelOutputEvent({
    required this.type,
    required this.label,
    this.text = '',
    this.token,
    this.toolIndex,
    this.estimatedContextTokens,
  });

  final TaskModelOutputEventType type;
  final String label;
  final String text;
  final ChatToken? token;
  final int? toolIndex;
  final int? estimatedContextTokens;
}
