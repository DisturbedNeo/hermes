import 'dart:async';

enum ApplicationLifecycleState {
  created,
  starting,
  running,
  quiescing,
  flushing,
  disposed,
}

/// Contract for the application scope that owns long-lived resources.
abstract interface class ApplicationLifecycle {
  ApplicationLifecycleState get lifecycleState;

  Future<void> start();
  Future<void> quiesce();
  Future<void> flush();
  Future<void> dispose();
}

/// Small lifecycle coordinator for resources with one owner and one disposal
/// path. Registration order is construction order; disposal is reverse order.
class ApplicationLifecycleCoordinator implements ApplicationLifecycle {
  ApplicationLifecycleCoordinator();

  final List<_LifecycleOwner> _owners = [];
  ApplicationLifecycleState _state = ApplicationLifecycleState.created;
  Future<void>? _operation;

  @override
  ApplicationLifecycleState get lifecycleState => _state;

  void register({
    required String name,
    FutureOr<void> Function()? quiesce,
    FutureOr<void> Function()? flush,
    required FutureOr<void> Function() dispose,
  }) {
    if (_state != ApplicationLifecycleState.created) {
      throw StateError('Cannot register $name after lifecycle startup.');
    }
    _owners.add(
      _LifecycleOwner(
        name: name,
        quiesce: quiesce ?? () {},
        flush: flush ?? () {},
        dispose: dispose,
      ),
    );
  }

  @override
  Future<void> start() async {
    if (_state == ApplicationLifecycleState.disposed) {
      throw StateError('Cannot start a disposed application.');
    }
    if (_state == ApplicationLifecycleState.running) return;
    _state = ApplicationLifecycleState.starting;
    _state = ApplicationLifecycleState.running;
  }

  @override
  Future<void> quiesce() =>
      _runOnce(ApplicationLifecycleState.quiescing, () async {
        for (final owner in _owners) {
          await owner.quiesce();
        }
      });

  @override
  Future<void> flush() =>
      _runOnce(ApplicationLifecycleState.flushing, () async {
        for (final owner in _owners) {
          await owner.flush();
        }
      });

  @override
  Future<void> dispose() =>
      _runOnce(ApplicationLifecycleState.disposed, () async {
        Object? firstError;
        StackTrace? firstStack;
        for (final owner in _owners.reversed) {
          try {
            await owner.dispose();
          } catch (error, stackTrace) {
            firstError ??= error;
            firstStack ??= stackTrace;
          }
        }
        if (firstError != null) {
          Error.throwWithStackTrace(firstError, firstStack!);
        }
      });

  Future<void> _runOnce(
    ApplicationLifecycleState target,
    Future<void> Function() operation,
  ) {
    if (_state == ApplicationLifecycleState.disposed &&
        target != ApplicationLifecycleState.disposed) {
      return Future.value();
    }
    if (_state == ApplicationLifecycleState.disposed &&
        target == ApplicationLifecycleState.disposed) {
      return Future.value();
    }
    final pending = _operation;
    if (pending != null) return pending;
    late final Future<void> current;
    current = operation().whenComplete(() {
      if (target == ApplicationLifecycleState.disposed) {
        _state = ApplicationLifecycleState.disposed;
      }
      if (identical(_operation, current)) _operation = null;
    });
    _operation = current;
    return current.then((_) {
      if (_state != ApplicationLifecycleState.disposed) {
        _state = target == ApplicationLifecycleState.quiescing
            ? ApplicationLifecycleState.running
            : target;
      }
    });
  }
}

class _LifecycleOwner {
  const _LifecycleOwner({
    required this.name,
    required this.quiesce,
    required this.flush,
    required this.dispose,
  });

  final String name;
  final FutureOr<void> Function() quiesce;
  final FutureOr<void> Function() flush;
  final FutureOr<void> Function() dispose;
}
