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

  const JobModelOutputEvent({
    required this.type,
    required this.label,
    this.text = '',
  });
}
