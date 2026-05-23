import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';

void main() {
  test('uses model configuration defaults when snapshots omit them', () {
    final snapshot = ModelConfigurationSnapshot.fromJson(const {});

    expect(snapshot.nThreads, ModelConfigurationSnapshot.defaultNThreads);
    expect(snapshot.flashAttention, isTrue);
    expect(snapshot.cachePrompt, isTrue);
    expect(snapshot.cacheReuse, ModelConfigurationSnapshot.defaultCacheReuse);
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
      nBatch: 2048,
      nUBatch: 512,
      mirostat: 0,
      repeatPenalty: 1,
      repeatLastN: 64,
      presencePenalty: 1.5,
      frequencyPenalty: 0,
      thinking: false,
      flashAttention: true,
      cachePrompt: true,
      cacheReuse: 512,
      kvCacheQuantizationEnabled: true,
      kvCacheTypeK: 'q4_0',
      kvCacheTypeV: 'q8_0',
    );

    expect(snapshot.toJson(), containsPair('flashAttention', true));
    expect(snapshot.toJson(), containsPair('cachePrompt', true));
    expect(snapshot.toJson(), containsPair('cacheReuse', 512));
    expect(snapshot.toJson(), containsPair('kvCacheQuantizationEnabled', true));
    expect(snapshot.toJson(), containsPair('kvCacheTypeK', 'q4_0'));
    expect(snapshot.toJson(), containsPair('kvCacheTypeV', 'q8_0'));
  });

  test('clamps cache reuse when snapshots are restored', () {
    final belowMin = ModelConfigurationSnapshot.fromJson(const {
      'cacheReuse': 64,
    });
    final aboveMax = ModelConfigurationSnapshot.fromJson(const {
      'cacheReuse': 2048,
    });

    expect(belowMin.cacheReuse, ModelConfigurationSnapshot.minCacheReuse);
    expect(aboveMax.cacheReuse, ModelConfigurationSnapshot.maxCacheReuse);
  });
}
