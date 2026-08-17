import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/serialization/model_json.dart';

void main() {
  test('uses model configuration defaults when snapshots omit them', () {
    final snapshot = ModelJson.decode<ModelConfigurationSnapshot>(const {});
    final legacy = ModelJson.decode<ModelConfigurationSnapshot>(const {
      'nGpuLayers': 24,
    });

    expect(snapshot.nThreads, ModelConfigurationSnapshot.defaultNThreads);
    expect(snapshot.minP, 0.05);
    expect(snapshot.reasoningEffort, 'default');
    expect(snapshot.mtpEnabled, isFalse);
    expect(snapshot.mtpDraftTokens, 3);
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
    expect(ModelJson.encode(legacy), isNot(contains('nGpuLayers')));
  });

  test('serialises KV cache quantisation settings', () {
    const snapshot = ModelConfigurationSnapshot(
      modelName: 'model',
      modelPath: '/models/model.gguf',
      llamaCppDirectory: '/llama.cpp',
      nCtx: 8192,
      nThreads: 8,
      temperature: 0.7,
      topP: 0.8,
      topK: 20,
      minP: 0.0,
      nBatch: 2048,
      nUBatch: 512,
      mirostat: 0,
      repeatPenalty: 1,
      repeatLastN: 64,
      presencePenalty: 1.5,
      frequencyPenalty: 0,
      thinking: true,
      reasoningEffort: 'xhigh',
      mtpEnabled: true,
      mtpDraftTokens: 7,
      flashAttention: true,
      cachePrompt: true,
      cacheReuse: 512,
      kvCacheQuantizationEnabled: true,
      kvCacheTypeK: 'q4_0',
      kvCacheTypeV: 'q8_0',
    );

    final encoded = ModelJson.encode(snapshot);
    expect(encoded, containsPair('flashAttention', true));
    expect(encoded, containsPair('cachePrompt', true));
    expect(encoded, containsPair('cacheReuse', 512));
    expect(encoded, containsPair('minP', 0.0));
    expect(encoded, containsPair('reasoningEffort', 'xhigh'));
    expect(encoded, containsPair('mtpEnabled', true));
    expect(encoded, containsPair('mtpDraftTokens', 7));
    expect(encoded, containsPair('kvCacheQuantizationEnabled', true));
    expect(encoded, containsPair('kvCacheTypeK', 'q4_0'));
    expect(encoded, containsPair('kvCacheTypeV', 'q8_0'));
  });

  test('matches treats corresponding NaN double values as equal', () {
    final first = _snapshot(
      temperature: double.nan,
      topP: double.nan,
      minP: double.nan,
      repeatPenalty: double.nan,
      presencePenalty: double.nan,
      frequencyPenalty: double.nan,
    );
    final second = _snapshot(
      temperature: double.nan,
      topP: double.nan,
      minP: double.nan,
      repeatPenalty: double.nan,
      presencePenalty: double.nan,
      frequencyPenalty: double.nan,
    );

    expect(first.matches(second), isTrue);
    expect(first, equals(second));
    expect(first.hashCode, second.hashCode);
  });

  test('matches distinguishes NaN double values from finite values', () {
    final first = _snapshot(temperature: double.nan);
    final second = _snapshot(temperature: 0.7);

    expect(first.matches(second), isFalse);
    expect(first == second, isFalse);
  });

  test('clamps cache reuse when snapshots are restored', () {
    final belowMin = ModelJson.decode<ModelConfigurationSnapshot>(const {
      'cacheReuse': 64,
    });
    final aboveMax = ModelJson.decode<ModelConfigurationSnapshot>(const {
      'cacheReuse': 2048,
    });

    expect(belowMin.cacheReuse, ModelConfigurationSnapshot.minCacheReuse);
    expect(aboveMax.cacheReuse, ModelConfigurationSnapshot.maxCacheReuse);
  });

  test('normalises reasoning effort and MTP draft tokens when restored', () {
    final invalid = ModelJson.decode<ModelConfigurationSnapshot>(const {
      'reasoningEffort': 'unsupported',
      'mtpEnabled': true,
      'mtpDraftTokens': 100,
    });
    final minimum = ModelJson.decode<ModelConfigurationSnapshot>(const {
      'reasoningEffort': 'X-HIGH',
      'mtpDraftTokens': 0,
    });

    expect(invalid.reasoningEffort, 'default');
    expect(invalid.mtpEnabled, isTrue);
    expect(
      invalid.mtpDraftTokens,
      ModelConfigurationSnapshot.maxMtpDraftTokens,
    );
    expect(minimum.reasoningEffort, 'xhigh');
    expect(
      minimum.mtpDraftTokens,
      ModelConfigurationSnapshot.minMtpDraftTokens,
    );
  });

  test('discards reasoning effort when thinking is disabled', () {
    final disabled = ModelJson.decode<ModelConfigurationSnapshot>(const {
      'thinking': false,
      'reasoningEffort': 'xhigh',
    });

    expect(disabled.thinking, isFalse);
    expect(disabled.reasoningEffort, 'default');
  });
}

ModelConfigurationSnapshot _snapshot({
  double temperature = 0.7,
  double topP = 0.8,
  double minP = 0.05,
  double repeatPenalty = 1,
  double presencePenalty = 1.5,
  double frequencyPenalty = 0,
}) {
  return ModelConfigurationSnapshot(
    modelName: 'model',
    modelPath: '/models/model.gguf',
    llamaCppDirectory: '/llama.cpp',
    nCtx: 8192,
    nThreads: 8,
    temperature: temperature,
    topP: topP,
    topK: 20,
    minP: minP,
    nBatch: 2048,
    nUBatch: 512,
    mirostat: 0,
    repeatPenalty: repeatPenalty,
    repeatLastN: 64,
    presencePenalty: presencePenalty,
    frequencyPenalty: frequencyPenalty,
    thinking: false,
    flashAttention: true,
    cachePrompt: true,
    cacheReuse: 512,
    kvCacheQuantizationEnabled: true,
    kvCacheTypeK: 'q4_0',
    kvCacheTypeV: 'q8_0',
  );
}
