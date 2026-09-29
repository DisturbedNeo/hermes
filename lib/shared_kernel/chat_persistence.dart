class ChatSaveFailure {
  const ChatSaveFailure({
    required this.error,
    required this.stackTrace,
    required this.occurredAt,
  });

  final Object error;
  final StackTrace stackTrace;
  final DateTime occurredAt;
}

enum NewChatExitPolicy { save, discard }

class ChatFlushFailure {
  const ChatFlushFailure({
    required this.tabId,
    required this.title,
    required this.stage,
    required this.error,
    required this.stackTrace,
  });

  final String tabId;
  final String title;
  final String stage;
  final Object error;
  final StackTrace stackTrace;
}

class ChatFlushException implements Exception {
  const ChatFlushException(this.failures);

  final List<ChatFlushFailure> failures;

  @override
  String toString() {
    if (failures.isEmpty) return 'Chat exit preparation failed.';
    if (failures.length == 1) {
      final failure = failures.single;
      return 'Could not ${failure.stage} "${failure.title}": ${failure.error}';
    }
    return 'Could not prepare ${failures.length} chats for exit.';
  }
}
