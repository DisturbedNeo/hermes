import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/model_load_configuration.dart';
import 'package:hermes/core/serialization/model_json.dart';

void main() {
  test('provides the canonical model dialog defaults', () {
    final config = ModelLoadConfiguration.defaults();

    expect(config.nCtx, 32 * 1024);
    expect(config.nThreads, Platform.numberOfProcessors);
    expect(config.temperature, 0.7);
    expect(config.topP, 0.95);
    expect(config.topK, 20);
    expect(config.minP, 0.0);
    expect(config.nBatch, 2048);
    expect(config.nUBatch, 2048);
    expect(config.mirostat, 0);
    expect(config.repeatPenalty, 1.0);
    expect(config.repeatLastN, 64);
    expect(config.presencePenalty, 0.0);
    expect(config.frequencyPenalty, 0.0);
    expect(config.thinking, isFalse);
    expect(config.flashAttention, isTrue);
    expect(config.cachePrompt, isTrue);
    expect(config.cacheReuse, 256);
    expect(config.kvCacheQuantizationEnabled, isFalse);
    expect(config.kvCacheTypeK, 'f16');
    expect(config.kvCacheTypeV, 'f16');
  });

  test('round trips through ModelJson and defaults omitted fields', () {
    final original = _configuration(temperature: 1.2, thinking: true);
    final decoded = ModelJson.decodeString<ModelLoadConfiguration>(
      ModelJson.encodeString(original),
    );
    final defaults = ModelJson.decode<ModelLoadConfiguration>(const {});
    final legacy = ModelJson.decode<ModelLoadConfiguration>(const {
      'nGpuLayers': 24,
    });

    expect(decoded.temperature, 1.2);
    expect(decoded.thinking, isTrue);
    expect(decoded.nCtx, original.nCtx);
    expect(defaults.nCtx, ModelLoadConfiguration.defaultNCtx);
    expect(defaults.topP, ModelLoadConfiguration.defaultTopP);
    expect(defaults.thinking, ModelLoadConfiguration.defaultThinking);
    expect(ModelJson.encode(legacy), isNot(contains('nGpuLayers')));
  });

  test('binds runtime model identity only when creating a snapshot', () {
    final config = _configuration(temperature: 1.2, thinking: true);
    final encoded = ModelJson.encode(config);

    final snapshot = config.toSnapshot(
      modelName: 'alias',
      modelPath: '/new/models/model.gguf',
      llamaCppDirectory: '/new/llama.cpp',
    );

    expect(snapshot.modelName, 'alias');
    expect(snapshot.modelPath, '/new/models/model.gguf');
    expect(snapshot.llamaCppDirectory, '/new/llama.cpp');
    expect(snapshot.temperature, 1.2);
    expect(snapshot.thinking, isTrue);
    expect(encoded, isNot(contains('modelName')));
    expect(encoded, isNot(contains('modelPath')));
    expect(encoded, isNot(contains('llamaCppDirectory')));
  });

  test('normalises persisted values to supported UI ranges', () {
    final normalised = ModelJson.decode<ModelLoadConfiguration>({
      'nCtx': 999999999,
      'nThreads': 999999,
      'temperature': -10,
      'topP': 9,
      'minP': -2,
      'cacheReuse': 10,
      'kvCacheTypeK': 'invalid',
    }).normalised();

    expect(normalised.nCtx, 2048 * 1024);
    expect(normalised.nThreads, Platform.numberOfProcessors);
    expect(normalised.temperature, 0.0);
    expect(normalised.topP, 1.0);
    expect(normalised.minP, 0.0);
    expect(normalised.cacheReuse, ModelConfigurationSnapshot.minCacheReuse);
    expect(normalised.kvCacheTypeK, ModelLoadConfiguration.defaultKvCacheType);
  });
}

ModelLoadConfiguration _configuration({
  double temperature = 0.7,
  bool thinking = false,
}) => ModelLoadConfiguration(
  nCtx: ModelLoadConfiguration.defaultNCtx,
  nThreads: Platform.numberOfProcessors,
  temperature: temperature,
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
