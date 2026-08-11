import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/model_load_configuration.dart';
import 'package:hermes/ui/model_configuration/model_configuration.dart';

void main() {
  Widget configurationApp({
    ModelLoadConfiguration? initialConfiguration,
    bool hasSavedConfiguration = false,
    ModelConfigurationConfirm? onConfirm,
    ModelConfigurationReset? onReset,
  }) => MaterialApp(
    home: Scaffold(
      body: ModelConfiguration(
        modelName: 'model',
        initialConfiguration:
            initialConfiguration ?? ModelLoadConfiguration.defaults(),
        hasSavedConfiguration: hasSavedConfiguration,
        onConfirm:
            onConfirm ?? (configuration, {required saveAsDefault}) async {},
        onResetSavedConfiguration: onReset ?? () async => true,
      ),
    ),
  );

  testWidgets('sizes dialog from available width with min and max bounds', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    Future<double> dialogWidthFor(double width) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(configurationApp());

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      return dialog.constraints!.maxWidth;
    }

    expect(await dialogWidthFor(800), 480);
    expect(await dialogWidthFor(1200), 560);
    expect(await dialogWidthFor(2000), 760);
  });

  testWidgets('shows default status and expands only core settings', (
    tester,
  ) async {
    await tester.pumpWidget(configurationApp());

    expect(find.text('Using default configuration for model'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Context (K)'), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Threads'), findsNothing);
    expect(find.text('Reset to defaults'), findsNothing);
  });

  testWidgets('exposes Min P with the other sampling controls', (tester) async {
    await tester.pumpWidget(configurationApp());

    await tester.ensureVisible(find.text('Sampling'));
    await tester.tap(find.text('Sampling'));
    await tester.pumpAndSettle();

    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Top P'), findsOneWidget);
    expect(find.text('Top K'), findsOneWidget);
    expect(find.text('Min P'), findsOneWidget);
  });

  testWidgets('shows KV cache types only when quantisation is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(configurationApp());

    await tester.ensureVisible(find.text('Cache'));
    await tester.tap(find.text('Cache'));
    await tester.pumpAndSettle();

    expect(find.text('K cache type'), findsNothing);
    expect(find.text('V cache type'), findsNothing);
    expect(find.text('Cache Prompt'), findsOneWidget);
    expect(find.text('Cache Reuse'), findsOneWidget);
    await tester.ensureVisible(find.text('Quantise KV Cache'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Quantise KV Cache'));
    await tester.pumpAndSettle();

    expect(find.text('K cache type'), findsOneWidget);
    expect(find.text('V cache type'), findsOneWidget);
    expect(
      find.text(ModelLoadConfiguration.defaultKvCacheType),
      findsNWidgets(2),
    );
  });

  testWidgets('load model submits defaults without requesting a save', (
    tester,
  ) async {
    ModelLoadConfiguration? submitted;
    bool? saveRequested;

    await tester.pumpWidget(
      configurationApp(
        onConfirm: (configuration, {required saveAsDefault}) async {
          submitted = configuration;
          saveRequested = saveAsDefault;
        },
      ),
    );

    await tester.ensureVisible(find.text('Load model'));
    await tester.tap(find.text('Load model'));
    await tester.pumpAndSettle();

    expect(saveRequested, isFalse);
    expect(submitted?.nCtx, ModelLoadConfiguration.defaultNCtx);
    expect(submitted?.nThreads, Platform.numberOfProcessors);
    expect(submitted?.minP, ModelLoadConfiguration.defaultMinP);
    expect(submitted?.flashAttention, isTrue);
    expect(submitted?.cachePrompt, isTrue);
    expect(submitted?.cacheReuse, ModelConfigurationSnapshot.defaultCacheReuse);
    expect(submitted?.kvCacheQuantizationEnabled, isFalse);
    expect(submitted?.kvCacheTypeK, ModelLoadConfiguration.defaultKvCacheType);
    expect(submitted?.kvCacheTypeV, ModelLoadConfiguration.defaultKvCacheType);
  });

  testWidgets('prefills saved values and save and load requests persistence', (
    tester,
  ) async {
    ModelLoadConfiguration? submitted;
    bool? saveRequested;
    final saved = _configuration(nCtx: 128 * 1024, thinking: true);

    await tester.pumpWidget(
      configurationApp(
        initialConfiguration: saved,
        hasSavedConfiguration: true,
        onConfirm: (configuration, {required saveAsDefault}) async {
          submitted = configuration;
          saveRequested = saveAsDefault;
        },
      ),
    );

    expect(find.text('Saved configuration loaded for model'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Thinking'),
          )
          .value,
      isTrue,
    );

    await tester.ensureVisible(find.text('Save & load'));
    await tester.tap(find.text('Save & load'));
    await tester.pumpAndSettle();

    expect(saveRequested, isTrue);
    expect(submitted?.nCtx, 128 * 1024);
    expect(submitted?.thinking, isTrue);
  });

  testWidgets('reset removes the preset and restores canonical defaults', (
    tester,
  ) async {
    var resetCalls = 0;
    ModelLoadConfiguration? submitted;

    await tester.pumpWidget(
      configurationApp(
        initialConfiguration: _configuration(thinking: true),
        hasSavedConfiguration: true,
        onReset: () async {
          resetCalls++;
          return true;
        },
        onConfirm: (configuration, {required saveAsDefault}) async {
          submitted = configuration;
        },
      ),
    );

    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();

    expect(resetCalls, 1);
    expect(find.text('Using default configuration for model'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsNothing);

    await tester.ensureVisible(find.text('Load model'));
    await tester.tap(find.text('Load model'));
    await tester.pumpAndSettle();
    expect(submitted?.thinking, ModelLoadConfiguration.defaultThinking);
  });

  testWidgets('failed reset retains the saved configuration', (tester) async {
    await tester.pumpWidget(
      configurationApp(
        initialConfiguration: _configuration(thinking: true),
        hasSavedConfiguration: true,
        onReset: () async => false,
      ),
    );

    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();

    expect(find.text('Saved configuration loaded for model'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsOneWidget);
    expect(find.text('Failed to reset saved configuration'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Thinking'),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('prevents duplicate submissions while loading', (tester) async {
    final completer = Completer<void>();
    var submitCalls = 0;

    await tester.pumpWidget(
      configurationApp(
        onConfirm: (configuration, {required saveAsDefault}) {
          submitCalls++;
          return completer.future;
        },
      ),
    );

    await tester.ensureVisible(find.text('Save & load'));
    await tester.tap(find.text('Save & load'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(submitCalls, 1);
    completer.complete();
    await tester.pumpAndSettle();
  });
}

ModelLoadConfiguration _configuration({
  int nCtx = ModelLoadConfiguration.defaultNCtx,
  bool thinking = false,
}) => ModelLoadConfiguration(
  nCtx: nCtx,
  nThreads: Platform.numberOfProcessors,
  nGpuLayers: ModelLoadConfiguration.defaultNGpuLayers,
  temperature: ModelLoadConfiguration.defaultTemperature,
  topP: ModelLoadConfiguration.defaultTopP,
  topK: ModelLoadConfiguration.defaultTopK,
  minP: ModelLoadConfiguration.defaultMinP,
  nBatch: ModelLoadConfiguration.defaultNBatch,
  nUBatch: ModelLoadConfiguration.defaultNUBatch,
  mirostat: ModelLoadConfiguration.defaultMirostat,
  repeatPenalty: ModelLoadConfiguration.defaultRepeatPenalty,
  repeatLastN: ModelLoadConfiguration.defaultRepeatLastN,
  presencePenalty: ModelLoadConfiguration.defaultPresencePenalty,
  frequencyPenalty: ModelLoadConfiguration.defaultFrequencyPenalty,
  thinking: thinking,
  flashAttention: ModelLoadConfiguration.defaultFlashAttention,
  cachePrompt: ModelLoadConfiguration.defaultCachePrompt,
  cacheReuse: ModelConfigurationSnapshot.defaultCacheReuse,
  kvCacheQuantizationEnabled:
      ModelLoadConfiguration.defaultKvCacheQuantizationEnabled,
  kvCacheTypeK: ModelLoadConfiguration.defaultKvCacheType,
  kvCacheTypeV: ModelLoadConfiguration.defaultKvCacheType,
);
