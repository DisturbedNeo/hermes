part of 'chat_session_orchestrator.dart';

/// Owns the chat tab exit contract: quiescing active work, optionally saving
/// the current session, and disposing all session-owned resources exactly once.
class ChatExitUseCase {
  ChatExitUseCase(this._host);

  final ChatExitCapabilities _host;

  Future<void> quiesceForExit({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_host._disposed) return;
    await _stopActiveWork().timeout(timeout);
    _host._session.flushPendingTokens();
  }

  Future<void> _stopActiveWork() async {
    if (_host.chatStream.isStreaming) await _host.cancelGeneration();
    if (!_host.taskBusy) return;
    await _host.cancelTaskRun();
    if (_host.taskBusy) await _waitForTaskIdle();
  }

  Future<void> _waitForTaskIdle() {
    if (!_host.taskBusy) return Future.value();
    final completer = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (_host.taskBusy || completer.isCompleted) return;
      _host.removeListener(listener);
      completer.complete();
    };
    _host.addListener(listener);
    return completer.future.whenComplete(() => _host.removeListener(listener));
  }

  Future<void> disposeAsync() => _startDispose(saveChanges: true);

  Future<void> disposeWithoutSavingAsync() => _startDispose(saveChanges: false);

  Future<void> _startDispose({required bool saveChanges}) {
    if (_host._disposed) return Future.value();
    final pending = _host._disposeFuture;
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _dispose(saveChanges: saveChanges).whenComplete(() {
      if (!_host._disposed && identical(_host._disposeFuture, operation)) {
        _host._disposeFuture = null;
      }
    });
    _host._disposeFuture = operation;
    return operation;
  }

  Future<void> _dispose({required bool saveChanges}) async {
    if (saveChanges) {
      await quiesceForExit();
      await _host.flushCurrentChat();
    } else {
      try {
        await quiesceForExit();
      } catch (error, stackTrace) {
        _reportDisposalFailure(error, stackTrace);
      }
    }

    _host._disposed = true;
    _host.messageStore.removeListener(_host._handleMessagesChanged);
    _host._preferencesService.removeListener(_host._handlePreferencesChanged);
    _host._contextEstimateScheduler.cancel();
    _host._taskModelOutputNotifier.cancel();
    _host._autosave.dispose();
    try {
      await _host._deleteTransientTasksForCurrentScope();
    } catch (error, stackTrace) {
      _reportDisposalFailure(error, stackTrace);
    }
    try {
      await _host._deleteTransientProjectsForCurrentScope();
    } catch (error, stackTrace) {
      _reportDisposalFailure(error, stackTrace);
    }
    _host.messageStore.clearCurrentId();
    _host.messageStore.clearToolBuffers();
    try {
      await _host.chatStream.stop();
    } finally {
      try {
        await _host._session.dispose();
      } finally {
        _host._disposeChangeNotifier();
      }
    }
  }

  void _reportDisposalFailure(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'hermes chat disposal',
        context: ErrorDescription('while disposing chat tab ${_host.tabId}'),
      ),
    );
  }
}
