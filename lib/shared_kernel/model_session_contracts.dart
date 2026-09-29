/// Stable model-session values consumed by application and presentation
/// boundaries. The diagnostics implementation remains owned by the chat
/// runtime.
enum ModelServerState { stopped, starting, ready, failed, cancelled }

class ModelSessionLogEntry {
  final DateTime timestamp;
  final String source;
  final String message;

  const ModelSessionLogEntry({
    required this.timestamp,
    required this.source,
    required this.message,
  });
}
