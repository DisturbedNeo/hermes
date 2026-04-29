import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/ui/model_configuration/model_configuration.dart';

void main() {
  testWidgets('hides KV cache type dropdowns until quantisation is enabled', (
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

    expect(find.text('K cache type'), findsNothing);
    expect(find.text('V cache type'), findsNothing);

    await tester.ensureVisible(find.text('Quantise KV Cache'));
    await tester.tap(find.text('Quantise KV Cache'));
    await tester.pumpAndSettle();

    expect(find.text('K cache type'), findsOneWidget);
    expect(find.text('V cache type'), findsOneWidget);
    expect(
      find.text(ModelConfigurationSnapshot.defaultKvCacheType),
      findsNWidgets(2),
    );
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

    await tester.ensureVisible(find.text('Quantise KV Cache'));
    await tester.tap(find.text('Quantise KV Cache'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

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
