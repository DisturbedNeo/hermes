import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';

void main() {
  test('uses KV cache quantisation defaults when snapshots omit them', () {
    final snapshot = ModelConfigurationSnapshot.fromJson(const {});

    expect(snapshot.kvCacheQuantizationEnabled, isTrue);
    expect(
      snapshot.kvCacheTypeK,
      ModelConfigurationSnapshot.defaultKvCacheType,
    );
    expect(
      snapshot.kvCacheTypeV,
      ModelConfigurationSnapshot.defaultKvCacheType,
    );
  });

  test('serialises KV cache quantisation settings', () {
    const snapshot = ModelConfigurationSnapshot(
      modelName: 'model',
      modelPath: '/models/model.gguf',
      llamaCppDirectory: '/llama.cpp',
      nCtx: 8192,
      nThreads: 8,
      nGpuLayers: 999,
      temperature: 0.7,
      topP: 0.8,
      topK: 20,
      nBatch: 512,
      nUBatch: 512,
      mirostat: 0,
      repeatPenalty: 1,
      repeatLastN: 64,
      presencePenalty: 1.5,
      frequencyPenalty: 0,
      thinking: false,
      kvCacheQuantizationEnabled: true,
      kvCacheTypeK: 'q4_0',
      kvCacheTypeV: 'q8_0',
    );

    expect(snapshot.toJson(), containsPair('kvCacheQuantizationEnabled', true));
    expect(snapshot.toJson(), containsPair('kvCacheTypeK', 'q4_0'));
    expect(snapshot.toJson(), containsPair('kvCacheTypeV', 'q8_0'));
  });
}
