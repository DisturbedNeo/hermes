import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/serialization/json_hooks.dart';

part 'model_configuration_snapshot.mapper.dart';

@MappableClass()
class ModelConfigurationSnapshot with ModelConfigurationSnapshotMappable {
  static const String defaultKvCacheType = 'q8_0';
  static const String defaultReasoningEffort = 'default';
  static const int defaultMtpDraftTokens = 3;
  static const int minMtpDraftTokens = 1;
  static const int maxMtpDraftTokens = 16;
  static const int defaultCacheReuse = 256;
  static const int minCacheReuse = 128;
  static const int maxCacheReuse = 1024;
  static const List<String> allowedKvCacheTypes = [
    'f32',
    'f16',
    'bf16',
    'q8_0',
    'q4_0',
    'q4_1',
    'iq4_nl',
    'q5_0',
    'q5_1',
  ];
  static const List<String> allowedReasoningEfforts = [
    defaultReasoningEffort,
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  ];

  static int get defaultNThreads => Platform.numberOfProcessors;

  @MappableField(hook: JsonStringHook())
  final String modelName;
  @MappableField(hook: JsonStringHook())
  final String modelPath;
  @MappableField(hook: JsonStringHook())
  final String llamaCppDirectory;
  @MappableField(hook: JsonIntHook(fallback: 4096))
  final int nCtx;
  @MappableField(hook: PlatformThreadsHook())
  final int nThreads;
  @MappableField(hook: JsonDoubleHook(fallback: 0.7))
  final double temperature;
  @MappableField(hook: JsonDoubleHook(fallback: 0.9))
  final double topP;
  @MappableField(hook: JsonIntHook(fallback: 40))
  final int topK;
  @MappableField(hook: JsonDoubleHook(fallback: 0.05))
  final double minP;
  @MappableField(hook: JsonIntHook(fallback: 2048))
  final int nBatch;
  @MappableField(hook: JsonIntHook(fallback: 512))
  final int nUBatch;
  @MappableField(hook: JsonIntHook())
  final int mirostat;
  @MappableField(hook: JsonDoubleHook(fallback: 1.1))
  final double repeatPenalty;
  @MappableField(hook: JsonIntHook(fallback: 256))
  final int repeatLastN;
  @MappableField(hook: JsonDoubleHook(fallback: 1.2))
  final double presencePenalty;
  @MappableField(hook: JsonDoubleHook(fallback: 0.5))
  final double frequencyPenalty;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool thinking;
  @MappableField(hook: ReasoningEffortHook())
  final String reasoningEffort;
  @MappableField(hook: JsonBoolHook())
  final bool mtpEnabled;
  @MappableField(hook: JsonIntHook(fallback: 3, min: 1, max: 16))
  final int mtpDraftTokens;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool flashAttention;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool cachePrompt;
  @MappableField(hook: CacheReuseHook())
  final int cacheReuse;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool kvCacheQuantizationEnabled;
  @MappableField(hook: KvCacheTypeHook())
  final String kvCacheTypeK;
  @MappableField(hook: KvCacheTypeHook())
  final String kvCacheTypeV;

  const ModelConfigurationSnapshot({
    required this.modelName,
    required this.modelPath,
    required this.llamaCppDirectory,
    required this.nCtx,
    required this.nThreads,
    required this.temperature,
    required this.topP,
    required this.topK,
    this.minP = 0.05,
    required this.nBatch,
    required this.nUBatch,
    required this.mirostat,
    required this.repeatPenalty,
    required this.repeatLastN,
    required this.presencePenalty,
    required this.frequencyPenalty,
    required this.thinking,
    String reasoningEffort = defaultReasoningEffort,
    this.mtpEnabled = false,
    this.mtpDraftTokens = defaultMtpDraftTokens,
    required this.flashAttention,
    required this.cachePrompt,
    required this.cacheReuse,
    required this.kvCacheQuantizationEnabled,
    required this.kvCacheTypeK,
    required this.kvCacheTypeV,
  }) : reasoningEffort = thinking ? reasoningEffort : defaultReasoningEffort;

  bool matches(ModelConfigurationSnapshot? other) {
    if (other == null) return false;
    return modelName == other.modelName &&
        modelPath == other.modelPath &&
        llamaCppDirectory == other.llamaCppDirectory &&
        nCtx == other.nCtx &&
        nThreads == other.nThreads &&
        _doubleMatches(temperature, other.temperature) &&
        _doubleMatches(topP, other.topP) &&
        topK == other.topK &&
        _doubleMatches(minP, other.minP) &&
        nBatch == other.nBatch &&
        nUBatch == other.nUBatch &&
        mirostat == other.mirostat &&
        _doubleMatches(repeatPenalty, other.repeatPenalty) &&
        repeatLastN == other.repeatLastN &&
        _doubleMatches(presencePenalty, other.presencePenalty) &&
        _doubleMatches(frequencyPenalty, other.frequencyPenalty) &&
        thinking == other.thinking &&
        reasoningEffort == other.reasoningEffort &&
        mtpEnabled == other.mtpEnabled &&
        mtpDraftTokens == other.mtpDraftTokens &&
        flashAttention == other.flashAttention &&
        cachePrompt == other.cachePrompt &&
        cacheReuse == other.cacheReuse &&
        kvCacheQuantizationEnabled == other.kvCacheQuantizationEnabled &&
        kvCacheTypeK == other.kvCacheTypeK &&
        kvCacheTypeV == other.kvCacheTypeV;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelConfigurationSnapshot && matches(other);

  @override
  int get hashCode => Object.hashAll([
    modelName,
    modelPath,
    llamaCppDirectory,
    nCtx,
    nThreads,
    _doubleHashValue(temperature),
    _doubleHashValue(topP),
    topK,
    _doubleHashValue(minP),
    nBatch,
    nUBatch,
    mirostat,
    _doubleHashValue(repeatPenalty),
    repeatLastN,
    _doubleHashValue(presencePenalty),
    _doubleHashValue(frequencyPenalty),
    thinking,
    reasoningEffort,
    mtpEnabled,
    mtpDraftTokens,
    flashAttention,
    cachePrompt,
    cacheReuse,
    kvCacheQuantizationEnabled,
    kvCacheTypeK,
    kvCacheTypeV,
  ]);

  static int clampCacheReuse(int value) =>
      value.clamp(minCacheReuse, maxCacheReuse).toInt();

  static int clampMtpDraftTokens(int value) =>
      value.clamp(minMtpDraftTokens, maxMtpDraftTokens).toInt();

  static String normaliseReasoningEffort(String value) {
    final normalised = value.trim().toLowerCase().replaceAll('-', '');
    return allowedReasoningEfforts.contains(normalised)
        ? normalised
        : defaultReasoningEffort;
  }

  static bool _doubleMatches(double value, double other) =>
      value == other || (value.isNaN && other.isNaN);

  static final Object _nanHashValue = Object();

  static Object _doubleHashValue(double value) =>
      value.isNaN ? _nanHashValue : value;

  static String _kvCacheType(Object? value) {
    if (value is String && allowedKvCacheTypes.contains(value)) return value;
    return defaultKvCacheType;
  }
}

class PlatformThreadsHook extends MappingHook {
  const PlatformThreadsHook();

  @override
  Object? beforeDecode(Object? value) =>
      jsonInt(value, fallback: ModelConfigurationSnapshot.defaultNThreads);
}

class CacheReuseHook extends MappingHook {
  const CacheReuseHook();

  @override
  Object? beforeDecode(Object? value) =>
      ModelConfigurationSnapshot.clampCacheReuse(
        jsonInt(value, fallback: ModelConfigurationSnapshot.defaultCacheReuse),
      );
}

class KvCacheTypeHook extends MappingHook {
  const KvCacheTypeHook();

  @override
  Object? beforeDecode(Object? value) =>
      ModelConfigurationSnapshot._kvCacheType(value);
}

class ReasoningEffortHook extends MappingHook {
  const ReasoningEffortHook();

  @override
  Object? beforeDecode(Object? value) =>
      ModelConfigurationSnapshot.normaliseReasoningEffort(
        jsonString(
          value,
          fallback: ModelConfigurationSnapshot.defaultReasoningEffort,
        ),
      );
}
