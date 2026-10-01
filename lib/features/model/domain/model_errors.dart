enum ChatTransportFailureKind {
  brokenPipe,
  connectionReset,
  connectionRefused,
  connectionClosed,
  socket,
}

class ChatProtocolException implements Exception {
  const ChatProtocolException({required this.uri, required this.reason});

  final Uri uri;
  final String reason;

  @override
  String toString() => 'Invalid model stream from $uri: $reason';
}

class ChatTransportEvent {
  final DateTime timestamp;
  final ChatTransportFailureKind kind;
  final Uri uri;
  final int attempt;
  final bool willRetry;
  final bool outputStarted;
  final Object error;
  final StackTrace stackTrace;

  ChatTransportEvent({
    required this.kind,
    required this.uri,
    required this.attempt,
    required this.willRetry,
    required this.outputStarted,
    required this.error,
    required this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ChatTransportException implements Exception {
  final ChatTransportFailureKind kind;
  final Uri uri;
  final int attempts;
  final bool outputStarted;
  final Object cause;
  final StackTrace causeStackTrace;

  const ChatTransportException({
    required this.kind,
    required this.uri,
    required this.attempts,
    required this.outputStarted,
    required this.cause,
    required this.causeStackTrace,
  });

  @override
  String toString() {
    final phase = outputStarted ? ' after model output began' : '';
    return 'Model transport failed$phase after $attempts attempt(s): $cause';
  }
}

class ChatRequestTimeoutException implements Exception {
  final Uri uri;
  final Duration inactivityTimeout;

  const ChatRequestTimeoutException({
    required this.uri,
    required this.inactivityTimeout,
  });

  @override
  String toString() =>
      'Model request received no data for ${inactivityTimeout.inSeconds} seconds: $uri';
}
