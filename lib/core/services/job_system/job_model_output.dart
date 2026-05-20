import 'package:hermes/core/models/chat_token.dart';

enum JobModelOutputEventType {
  start,
  content,
  reasoning,
  toolCall,
  toolResult,
  done,
  error,
}

typedef JobModelOutputSink = void Function(JobModelOutputEvent event);

class JobModelOutputEvent {
  final JobModelOutputEventType type;
  final String label;
  final String text;
  final ChatToken? token;
  final int? toolIndex;

  const JobModelOutputEvent({
    required this.type,
    required this.label,
    this.text = '',
    this.token,
    this.toolIndex,
  });
}
