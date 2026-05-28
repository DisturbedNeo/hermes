import 'dart:io';

import 'package:hermes/core/helpers/json_parsing.dart';

class ModelConfigurationSnapshot {
  static const String defaultKvCacheType = 'q8_0';
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

  static int get defaultNThreads => Platform.numberOfProcessors;

  final String modelName;
  final String modelPath;
  final String llamaCppDirectory;
  final int nCtx;
  final int nThreads;
  final int nGpuLayers;
  final double temperature;
  final double topP;
  final int topK;
  final int nBatch;
  final int nUBatch;
  final int mirostat;
  final double repeatPenalty;
  final int repeatLastN;
  final double presencePenalty;
  final double frequencyPenalty;
  final bool thinking;
  final bool flashAttention;
  final bool cachePrompt;
  final int cacheReuse;
  final bool kvCacheQuantizationEnabled;
  final String kvCacheTypeK;
  final String kvCacheTypeV;

  const ModelConfigurationSnapshot({
    required this.modelName,
    required this.modelPath,
    required this.llamaCppDirectory,
    required this.nCtx,
    required this.nThreads,
    required this.nGpuLayers,
    required this.temperature,
    required this.topP,
    required this.topK,
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

  factory ModelConfigurationSnapshot.fromJson(Map<String, dynamic> json) {
    return ModelConfigurationSnapshot(
      modelName: json['modelName'] as String? ?? '',
      modelPath: json['modelPath'] as String? ?? '',
      llamaCppDirectory: json['llamaCppDirectory'] as String? ?? '',
      nCtx: jsonInt(json['nCtx'], fallback: 4096),
      nThreads: jsonInt(json['nThreads'], fallback: defaultNThreads),
      nGpuLayers: jsonInt(json['nGpuLayers'], fallback: 0),
      temperature: jsonDouble(json['temperature'], fallback: 0.7),
      topP: jsonDouble(json['topP'], fallback: 0.9),
      topK: jsonInt(json['topK'], fallback: 40),
      nBatch: jsonInt(json['nBatch'], fallback: 2048),
      nUBatch: jsonInt(json['nUBatch'], fallback: 512),
      mirostat: jsonInt(json['mirostat'], fallback: 0),
      repeatPenalty: jsonDouble(json['repeatPenalty'], fallback: 1.1),
      repeatLastN: jsonInt(json['repeatLastN'], fallback: 256),
      presencePenalty: jsonDouble(json['presencePenalty'], fallback: 1.2),
      frequencyPenalty: jsonDouble(json['frequencyPenalty'], fallback: 0.5),
      thinking: json['thinking'] as bool? ?? true,
      flashAttention: json['flashAttention'] as bool? ?? true,
      cachePrompt: json['cachePrompt'] as bool? ?? true,
      cacheReuse: clampCacheReuse(
        jsonInt(json['cacheReuse'], fallback: defaultCacheReuse),
      ),
      kvCacheQuantizationEnabled:
          json['kvCacheQuantizationEnabled'] as bool? ?? true,
      kvCacheTypeK: _kvCacheType(json['kvCacheTypeK']),
      kvCacheTypeV: _kvCacheType(json['kvCacheTypeV']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'modelName': modelName,
      'modelPath': modelPath,
      'llamaCppDirectory': llamaCppDirectory,
      'nCtx': nCtx,
      'nThreads': nThreads,
      'nGpuLayers': nGpuLayers,
      'temperature': temperature,
      'topP': topP,
      'topK': topK,
      'nBatch': nBatch,
      'nUBatch': nUBatch,
      'mirostat': mirostat,
      'repeatPenalty': repeatPenalty,
      'repeatLastN': repeatLastN,
      'presencePenalty': presencePenalty,
      'frequencyPenalty': frequencyPenalty,
      'thinking': thinking,
      'flashAttention': flashAttention,
      'cachePrompt': cachePrompt,
      'cacheReuse': cacheReuse,
      'kvCacheQuantizationEnabled': kvCacheQuantizationEnabled,
      'kvCacheTypeK': kvCacheTypeK,
      'kvCacheTypeV': kvCacheTypeV,
    };
  }

  bool matches(ModelConfigurationSnapshot? other) {
    if (other == null) return false;
    return modelName == other.modelName &&
        modelPath == other.modelPath &&
        llamaCppDirectory == other.llamaCppDirectory &&
        nCtx == other.nCtx &&
        nThreads == other.nThreads &&
        nGpuLayers == other.nGpuLayers &&
        _doubleMatches(temperature, other.temperature) &&
        _doubleMatches(topP, other.topP) &&
        topK == other.topK &&
        nBatch == other.nBatch &&
        nUBatch == other.nUBatch &&
        mirostat == other.mirostat &&
        _doubleMatches(repeatPenalty, other.repeatPenalty) &&
        repeatLastN == other.repeatLastN &&
        _doubleMatches(presencePenalty, other.presencePenalty) &&
        _doubleMatches(frequencyPenalty, other.frequencyPenalty) &&
        thinking == other.thinking &&
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
    nGpuLayers,
    _doubleHashValue(temperature),
    _doubleHashValue(topP),
    topK,
    nBatch,
    nUBatch,
    mirostat,
    _doubleHashValue(repeatPenalty),
    repeatLastN,
    _doubleHashValue(presencePenalty),
    _doubleHashValue(frequencyPenalty),
    thinking,
    flashAttention,
    cachePrompt,
    cacheReuse,
    kvCacheQuantizationEnabled,
    kvCacheTypeK,
    kvCacheTypeV,
  ]);

  static int clampCacheReuse(int value) =>
      value.clamp(minCacheReuse, maxCacheReuse).toInt();

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
