import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/ui/model_configuration/model_configuration.dart';

void main() {
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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelConfiguration(
              modelName: 'model',
              modelPath: '/models/model.gguf',
              llamaCppDirectory: '/llama.cpp',
              onConfirm: (_) async {},
            ),
          ),
        ),
      );

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      return dialog.constraints!.maxWidth;
    }

    expect(await dialogWidthFor(800), 480);
    expect(await dialogWidthFor(1200), 560);
    expect(await dialogWidthFor(2000), 760);
  });

  testWidgets('auto-expands core settings and collapses other categories', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelConfiguration(
            modelName: 'model',
            modelPath: '/models/model.gguf',
            llamaCppDirectory: '/llama.cpp',
            onConfirm: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Context (K)'), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Threads'), findsNothing);
  });

  testWidgets('hides KV cache type dropdowns when quantisation is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelConfiguration(
            modelName: 'model',
            modelPath: '/models/model.gguf',
            llamaCppDirectory: '/llama.cpp',
            onConfirm: (_) async {},
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Cache'));
    await tester.tap(find.text('Cache'));
    await tester.pumpAndSettle();

    expect(find.text('K cache type'), findsOneWidget);
    expect(find.text('V cache type'), findsOneWidget);
    expect(find.text('Cache Prompt'), findsOneWidget);
    expect(find.text('Cache Reuse'), findsOneWidget);
    expect(
      find.text(ModelConfigurationSnapshot.defaultKvCacheType),
      findsNWidgets(2),
    );

    await tester.ensureVisible(find.text('Quantise KV Cache'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Quantise KV Cache'));
    await tester.pumpAndSettle();

    expect(find.text('K cache type'), findsNothing);
    expect(find.text('V cache type'), findsNothing);
  });

  testWidgets('submits KV cache quantisation defaults', (tester) async {
    ModelConfigurationSnapshot? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelConfiguration(
            modelName: 'model',
            modelPath: '/models/model.gguf',
            llamaCppDirectory: '/llama.cpp',
            onConfirm: (snapshot) async => submitted = snapshot,
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Confirm'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(submitted?.nThreads, Platform.numberOfProcessors);
    expect(submitted?.flashAttention, isTrue);
    expect(submitted?.cachePrompt, isTrue);
    expect(submitted?.cacheReuse, ModelConfigurationSnapshot.defaultCacheReuse);
    expect(submitted?.kvCacheQuantizationEnabled, isTrue);
    expect(
      submitted?.kvCacheTypeK,
      ModelConfigurationSnapshot.defaultKvCacheType,
    );
    expect(
      submitted?.kvCacheTypeV,
      ModelConfigurationSnapshot.defaultKvCacheType,
    );
  });
}
