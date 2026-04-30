import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServiceProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('serializes initialize behind an in-flight dispose', () async {
      final provider = ServiceProvider.testing();
      final slow = _SlowDisposable();
      provider.registerSingleton<_SlowDisposable>(slow);

      final disposeFuture = provider.dispose();
      await slow.started.future;

      var initialized = false;
      final initializeFuture = provider.initialize().then((_) {
        initialized = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(initialized, isFalse);
      expect(provider.isRegistered<PreferencesService>(), isFalse);

      slow.release.complete();
      await disposeFuture;
      await initializeFuture;

      expect(slow.disposed, isTrue);
      expect(initialized, isTrue);
      expect(provider.isRegistered<ChatTabsService>(), isTrue);

      await Future<void>.delayed(Duration.zero);
      await provider.dispose();
    });
  });
}

class _SlowDisposable {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  bool disposed = false;

  Future<void> dispose() async {
    started.complete();
    await release.future;
    disposed = true;
  }
}
