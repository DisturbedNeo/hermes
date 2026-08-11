import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/ui/chat/model_picker.dart';

void main() {
  test('does not save when model startup fails', () async {
    var startedCallbackCalled = false;
    var saveCalled = false;

    await expectLater(
      startModelAndMaybeSaveConfiguration(
        startModel: () async => throw StateError('startup failed'),
        onModelStarted: () => startedCallbackCalled = true,
        saveAsDefault: true,
        saveConfiguration: () async {
          saveCalled = true;
          return true;
        },
      ),
      throwsStateError,
    );

    expect(startedCallbackCalled, isFalse);
    expect(saveCalled, isFalse);
  });

  test('starts without saving for a one-off load', () async {
    var startedCallbackCalled = false;
    var saveCalled = false;

    final outcome = await startModelAndMaybeSaveConfiguration(
      startModel: () async {},
      onModelStarted: () => startedCallbackCalled = true,
      saveAsDefault: false,
      saveConfiguration: () async {
        saveCalled = true;
        return true;
      },
    );

    expect(outcome, ModelConfigurationSaveOutcome.notRequested);
    expect(startedCallbackCalled, isTrue);
    expect(saveCalled, isFalse);
  });

  test('reports persistence failure after successful startup', () async {
    var startedCallbackCalled = false;

    final outcome = await startModelAndMaybeSaveConfiguration(
      startModel: () async {},
      onModelStarted: () => startedCallbackCalled = true,
      saveAsDefault: true,
      saveConfiguration: () async => false,
    );

    expect(startedCallbackCalled, isTrue);
    expect(outcome, ModelConfigurationSaveOutcome.failed);
  });
}
