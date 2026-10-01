import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/application_lifecycle.dart';

void main() {
  test(
    'quiesces, flushes, and disposes owners once in reverse order',
    () async {
      final events = <String>[];
      final lifecycle = ApplicationLifecycleCoordinator();
      lifecycle.register(
        name: 'first',
        quiesce: () => events.add('quiesce:first'),
        flush: () => events.add('flush:first'),
        dispose: () => events.add('dispose:first'),
      );
      lifecycle.register(
        name: 'second',
        quiesce: () => events.add('quiesce:second'),
        flush: () => events.add('flush:second'),
        dispose: () => events.add('dispose:second'),
      );

      await lifecycle.start();
      await lifecycle.quiesce();
      await lifecycle.flush();
      await lifecycle.dispose();
      await lifecycle.dispose();

      expect(events, [
        'quiesce:first',
        'quiesce:second',
        'flush:first',
        'flush:second',
        'dispose:second',
        'dispose:first',
      ]);
      expect(lifecycle.lifecycleState, ApplicationLifecycleState.disposed);
    },
  );

  test(
    'disposal continues through owner failures and remains idempotent',
    () async {
      var disposedAfterFailure = false;
      final lifecycle = ApplicationLifecycleCoordinator();
      lifecycle.register(
        name: 'failing',
        dispose: () => throw StateError('expected'),
      );
      lifecycle.register(
        name: 'last',
        dispose: () => disposedAfterFailure = true,
      );

      await expectLater(lifecycle.dispose(), throwsStateError);
      expect(disposedAfterFailure, isTrue);
      await lifecycle.dispose();
    },
  );
}
