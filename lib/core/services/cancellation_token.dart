import 'dart:async';

typedef CancellationRegistration = void Function();
typedef CancellationCallback = FutureOr<void> Function();

/// Cooperative cancellation shared by model requests, tools, and tasks.
class CancellationToken {
  final List<CancellationCallback> _callbacks = [];
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void throwIfCancelled() {
    if (_isCancelled) throw const OperationCancelledException();
  }

  CancellationRegistration onCancel(CancellationCallback callback) {
    if (_isCancelled) {
      Future.microtask(callback);
      return () {};
    }
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  /// Cancels once and waits for all registered cleanup callbacks.
  Future<void> cancel() async {
    if (_isCancelled) return;
    _isCancelled = true;
    final callbacks = List<CancellationCallback>.of(_callbacks);
    _callbacks.clear();
    await Future.wait([
      for (final callback in callbacks) Future<void>.sync(callback),
    ]);
  }
}

class OperationCancelledException implements Exception {
  const OperationCancelledException();

  @override
  String toString() => 'Operation cancelled';
}
