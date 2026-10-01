import 'dart:async';

/// Serializes chat persistence and owns the debounce timer used by the chat
/// session facade. It deliberately has no ChatState or Flutter dependency.
class ChatAutosaveCoordinator {
  ChatAutosaveCoordinator({this.delay = const Duration(milliseconds: 600)});

  final Duration delay;
  Timer? _timer;
  Future<void> _chain = Future.value();

  void schedule(Future<void> Function() save) {
    cancelPendingSchedule();
    _timer = Timer(delay, () {
      final operation = enqueue(save);
      unawaited(operation.catchError((Object _) {}));
    });
  }

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final next = _chain.then((_) => operation());
    _chain = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> waitForIdle() => _chain;

  void cancelPendingSchedule() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancelPendingSchedule();
}
