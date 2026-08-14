import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/serialization/json_hooks.dart';

part 'model_load_configuration.mapper.dart';

@MappableClass()
class ModelLoadConfiguration with ModelLoadConfigurationMappable {
  static const int defaultNCtx = 32 * 1024;
  static const double defaultTemperature = 0.7;
  static const double defaultTopP = 0.95;
  static const int defaultTopK = 20;
  static const double defaultMinP = 0.0;
  static const int defaultNBatch = 2048;
  static const int defaultNUBatch = 2048;
  static const int defaultMirostat = 0;
  static const double defaultRepeatPenalty = 1.0;
  static const int defaultRepeatLastN = 64;
  static const double defaultPresencePenalty = 0.0;
  static const double defaultFrequencyPenalty = 0.0;
  static const bool defaultThinking = false;
  static const bool defaultFlashAttention = true;
  static const bool defaultCachePrompt = true;
  static const bool defaultKvCacheQuantizationEnabled = false;
  static const String defaultKvCacheType = 'f16';

  @MappableField(hook: JsonIntHook(fallback: 32768))
  final int nCtx;
  @MappableField(hook: PlatformThreadsHook())
  final int nThreads;
  @MappableField(hook: JsonDoubleHook(fallback: 0.7))
  final double temperature;
  @MappableField(hook: JsonDoubleHook(fallback: 0.95))
  final double topP;
  @MappableField(hook: JsonIntHook(fallback: 20))
  final int topK;
  @MappableField(hook: JsonDoubleHook(fallback: 0.0))
  final double minP;
  @MappableField(hook: JsonIntHook(fallback: 2048))
  final int nBatch;
  @MappableField(hook: JsonIntHook(fallback: 2048))
  final int nUBatch;
  @MappableField(hook: JsonIntHook(fallback: 0))
  final int mirostat;
  @MappableField(hook: JsonDoubleHook(fallback: 1.0))
  final double repeatPenalty;
  @MappableField(hook: JsonIntHook(fallback: 64))
  final int repeatLastN;
  @MappableField(hook: JsonDoubleHook(fallback: 0.0))
  final double presencePenalty;
  @MappableField(hook: JsonDoubleHook(fallback: 0.0))
  final double frequencyPenalty;
  @MappableField(hook: JsonBoolHook(fallback: false))
  final bool thinking;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool flashAttention;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool cachePrompt;
  @MappableField(hook: CacheReuseHook())
  final int cacheReuse;
  @MappableField(hook: JsonBoolHook(fallback: false))
  final bool kvCacheQuantizationEnabled;
  @MappableField(hook: ModelLoadKvCacheTypeHook())
  final String kvCacheTypeK;
  @MappableField(hook: ModelLoadKvCacheTypeHook())
  final String kvCacheTypeV;

  const ModelLoadConfiguration({
    required this.nCtx,
    required this.nThreads,
    required this.temperature,
    required this.topP,
    required this.topK,
    this.minP = defaultMinP,
    required this.nBatch,
    required this.nUBatch,
    required this.mirostat,
    required this.repeatPenalty,
    required this.repeatLastN,
    required this.presencePenalty,
    required this.frequencyPenalty,
    required this.thinking,
    required this.flashAttention,
    required this.cachePrompt,
    required this.cacheReuse,
    required this.kvCacheQuantizationEnabled,
    required this.kvCacheTypeK,
    required this.kvCacheTypeV,
  });

  factory ModelLoadConfiguration.defaults() => ModelLoadConfiguration(
    nCtx: defaultNCtx,
    nThreads: ModelConfigurationSnapshot.defaultNThreads,
    temperature: defaultTemperature,
    topP: defaultTopP,
    topK: defaultTopK,
    minP: defaultMinP,
    nBatch: defaultNBatch,
    nUBatch: defaultNUBatch,
    mirostat: defaultMirostat,
    repeatPenalty: defaultRepeatPenalty,
    repeatLastN: defaultRepeatLastN,
    presencePenalty: defaultPresencePenalty,
    frequencyPenalty: defaultFrequencyPenalty,
    thinking: defaultThinking,
    flashAttention: defaultFlashAttention,
    cachePrompt: defaultCachePrompt,
    cacheReuse: ModelConfigurationSnapshot.defaultCacheReuse,
    kvCacheQuantizationEnabled: defaultKvCacheQuantizationEnabled,
    kvCacheTypeK: defaultKvCacheType,
    kvCacheTypeV: defaultKvCacheType,
  );

  ModelLoadConfiguration normalised() => ModelLoadConfiguration(
    nCtx: (nCtx.clamp(1024, 2048 * 1024).toInt() ~/ 1024) * 1024,
    nThreads: nThreads.clamp(1, Platform.numberOfProcessors).toInt(),
    temperature: temperature.clamp(0.0, 1.5).toDouble(),
    topP: topP.clamp(0.1, 1.0).toDouble(),
    topK: topK.clamp(0, 100).toInt(),
    minP: minP.clamp(0.0, 1.0).toDouble(),
    nBatch: nBatch.clamp(256, 8192).toInt(),
    nUBatch: nUBatch.clamp(256, 8192).toInt(),
    mirostat: mirostat.clamp(0, 2).toInt(),
    repeatPenalty: repeatPenalty.clamp(0.5, 2.0).toDouble(),
    repeatLastN: repeatLastN.clamp(0, 2048).toInt(),
    presencePenalty: presencePenalty.clamp(-2.0, 2.0).toDouble(),
    frequencyPenalty: frequencyPenalty.clamp(-2.0, 2.0).toDouble(),
    thinking: thinking,
    flashAttention: flashAttention,
    cachePrompt: cachePrompt,
    cacheReuse: ModelConfigurationSnapshot.clampCacheReuse(cacheReuse),
    kvCacheQuantizationEnabled: kvCacheQuantizationEnabled,
    kvCacheTypeK: _normaliseKvCacheType(kvCacheTypeK),
    kvCacheTypeV: _normaliseKvCacheType(kvCacheTypeV),
  );

  ModelConfigurationSnapshot toSnapshot({
    required String modelName,
    required String modelPath,
    required String llamaCppDirectory,
  }) {
    final config = normalised();
    return ModelConfigurationSnapshot(
      modelName: modelName,
      modelPath: modelPath,
      llamaCppDirectory: llamaCppDirectory,
      nCtx: config.nCtx,
      nThreads: config.nThreads,
      temperature: config.temperature,
      topP: config.topP,
      topK: config.topK,
      minP: config.minP,
      nBatch: config.nBatch,
      nUBatch: config.nUBatch,
      mirostat: config.mirostat,
      repeatPenalty: config.repeatPenalty,
      repeatLastN: config.repeatLastN,
      presencePenalty: config.presencePenalty,
      frequencyPenalty: config.frequencyPenalty,
      thinking: config.thinking,
      flashAttention: config.flashAttention,
      cachePrompt: config.cachePrompt,
      cacheReuse: config.cacheReuse,
      kvCacheQuantizationEnabled: config.kvCacheQuantizationEnabled,
      kvCacheTypeK: config.kvCacheTypeK,
      kvCacheTypeV: config.kvCacheTypeV,
    );
  }

  static String _normaliseKvCacheType(String value) =>
      ModelConfigurationSnapshot.allowedKvCacheTypes.contains(value)
      ? value
      : defaultKvCacheType;
}

class ModelLoadKvCacheTypeHook extends MappingHook {
  const ModelLoadKvCacheTypeHook();

  @override
  Object? beforeDecode(Object? value) =>
      value is String &&
          ModelConfigurationSnapshot.allowedKvCacheTypes.contains(value)
      ? value
      : ModelLoadConfiguration.defaultKvCacheType;
}
