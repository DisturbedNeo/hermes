// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, override_on_non_overriding_member
part of 'chat_runtime_engine.dart';

extension _ChatLifecycleOperations on _ChatApplicationContext {
  Future<void> _stopActiveWork() async {
    if (chatStream.isStreaming) await cancelGeneration();
    if (!taskBusy) return;
    await cancelTaskRun();
    if (taskBusy) await _waitForTaskIdle();
  }

  Future<void> _waitForTaskIdle() {
    if (!taskBusy) return Future.value();
    final completer = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (taskBusy || completer.isCompleted) return;
      removeListener(listener);
      completer.complete();
    };
    addListener(listener);
    return completer.future.whenComplete(() => removeListener(listener));
  }

  @override
  // ignore: must_call_super, super.dispose is called by _dispose after async cleanup.
  Future<void> disposeAsync() => _startDispose(saveChanges: true);

  Future<void> disposeWithoutSavingAsync() => _startDispose(saveChanges: false);

  Future<void> _startDispose({required bool saveChanges}) {
    if (_disposed) return Future.value();
    final pending = _disposeFuture;
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _dispose(saveChanges: saveChanges).whenComplete(() {
      if (!_disposed && identical(_disposeFuture, operation)) {
        _disposeFuture = null;
      }
    });
    _disposeFuture = operation;
    return operation;
  }

  Future<void> _dispose({required bool saveChanges}) async {
    if (saveChanges) {
      await quiesceForExit();
      await flushCurrentChat();
    } else {
      try {
        await quiesceForExit();
      } catch (error, stackTrace) {
        _reportDisposalFailure(error, stackTrace);
      }
    }

    _disposed = true;
    messageStore.removeListener(_handleMessagesChanged);
    _preferencesService.removeListener(_handlePreferencesChanged);
    _contextEstimateScheduler.cancel();
    _taskModelOutputNotifier.cancel();
    _autosaveTimer?.cancel();
    try {
      await _deleteTransientTasksForCurrentScope();
    } catch (error, stackTrace) {
      _reportDisposalFailure(error, stackTrace);
    }
    try {
      await _deleteTransientProjectsForCurrentScope();
    } catch (error, stackTrace) {
      _reportDisposalFailure(error, stackTrace);
    }
    messageStore.clearCurrentId();
    messageStore.clearToolBuffers();
    try {
      await chatStream.stop();
    } finally {
      try {
        await _session.dispose();
      } finally {
        _disposeChangeNotifier();
      }
    }
  }

  void _reportDisposalFailure(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'hermes chat disposal',
        context: ErrorDescription('while disposing chat tab $tabId'),
      ),
    );
  }
}
