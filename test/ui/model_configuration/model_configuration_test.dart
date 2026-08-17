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
    expect(find.text('Reasoning'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Threads'), findsNothing);
    expect(find.text('Reset to defaults'), findsNothing);

    await tester.ensureVisible(find.text('Performance'));
    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();

    expect(find.text('Threads'), findsOneWidget);
    expect(find.text('GPU Layers'), findsNothing);
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

  testWidgets('shows MTP draft controls only when MTP is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(configurationApp());

    await tester.ensureVisible(find.text('Performance'));
    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();

    expect(find.text('MTP speculative decoding'), findsOneWidget);
    expect(find.text('Draft tokens'), findsNothing);

    await tester.ensureVisible(find.text('MTP speculative decoding'));
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'MTP speculative decoding'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Draft tokens'), findsOneWidget);
    expect(
      find.text('Requires a GGUF containing compatible MTP/NextN weights'),
      findsOneWidget,
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
    expect(submitted?.thinking, isTrue);
    expect(submitted?.reasoningEffort, 'default');
    expect(submitted?.mtpEnabled, isFalse);
    expect(submitted?.mtpDraftTokens, 3);
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
    final saved = _configuration(
      nCtx: 128 * 1024,
      thinking: true,
      reasoningEffort: 'xhigh',
      mtpEnabled: true,
      mtpDraftTokens: 7,
    );

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
    expect(find.text('X-high'), findsOneWidget);

    await tester.ensureVisible(find.text('Save & load'));
    await tester.tap(find.text('Save & load'));
    await tester.pumpAndSettle();

    expect(saveRequested, isTrue);
    expect(submitted?.nCtx, 128 * 1024);
    expect(submitted?.thinking, isTrue);
    expect(submitted?.reasoningEffort, 'xhigh');
    expect(submitted?.mtpEnabled, isTrue);
    expect(submitted?.mtpDraftTokens, 7);
  });

  testWidgets('maps the Off reasoning selection to disabled thinking', (
    tester,
  ) async {
    ModelLoadConfiguration? submitted;
    await tester.pumpWidget(
      configurationApp(
        onConfirm: (configuration, {required saveAsDefault}) async {
          submitted = configuration;
        },
      ),
    );

    final reasoningSelector = find.byKey(const ValueKey('reasoning-mode'));
    await tester.ensureVisible(reasoningSelector);
    await tester.pumpAndSettle();
    await tester.tap(reasoningSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Load model'));
    await tester.tap(find.text('Load model'));
    await tester.pumpAndSettle();

    expect(submitted?.thinking, isFalse);
    expect(submitted?.reasoningEffort, 'default');
  });

  testWidgets('reset removes the preset and restores canonical defaults', (
    tester,
  ) async {
    var resetCalls = 0;
    ModelLoadConfiguration? submitted;

    await tester.pumpWidget(
      configurationApp(
        initialConfiguration: _configuration(
          thinking: true,
          reasoningEffort: 'high',
        ),
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
    expect(
      submitted?.reasoningEffort,
      ModelLoadConfiguration.defaultReasoningEffort,
    );
  });

  testWidgets('failed reset retains the saved configuration', (tester) async {
    await tester.pumpWidget(
      configurationApp(
        initialConfiguration: _configuration(
          thinking: true,
          reasoningEffort: 'high',
        ),
        hasSavedConfiguration: true,
        onReset: () async => false,
      ),
    );

    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();

    expect(find.text('Saved configuration loaded for model'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsOneWidget);
    expect(find.text('Failed to reset saved configuration'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
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
  String reasoningEffort = ModelLoadConfiguration.defaultReasoningEffort,
  bool mtpEnabled = ModelLoadConfiguration.defaultMtpEnabled,
  int mtpDraftTokens = ModelLoadConfiguration.defaultMtpDraftTokens,
}) => ModelLoadConfiguration(
  nCtx: nCtx,
  nThreads: Platform.numberOfProcessors,
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
  reasoningEffort: reasoningEffort,
  mtpEnabled: mtpEnabled,
  mtpDraftTokens: mtpDraftTokens,
  flashAttention: ModelLoadConfiguration.defaultFlashAttention,
  cachePrompt: ModelLoadConfiguration.defaultCachePrompt,
  cacheReuse: ModelConfigurationSnapshot.defaultCacheReuse,
  kvCacheQuantizationEnabled:
      ModelLoadConfiguration.defaultKvCacheQuantizationEnabled,
  kvCacheTypeK: ModelLoadConfiguration.defaultKvCacheType,
  kvCacheTypeV: ModelLoadConfiguration.defaultKvCacheType,
);
