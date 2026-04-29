class ModelConfigurationSnapshot {
  static const String defaultKvCacheType = 'q8_0';
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
    required this.kvCacheQuantizationEnabled,
    required this.kvCacheTypeK,
    required this.kvCacheTypeV,
  });

  factory ModelConfigurationSnapshot.fromJson(Map<String, dynamic> json) {
    return ModelConfigurationSnapshot(
      modelName: json['modelName'] as String? ?? '',
      modelPath: json['modelPath'] as String? ?? '',
      llamaCppDirectory: json['llamaCppDirectory'] as String? ?? '',
      nCtx: _int(json['nCtx'], 4096),
      nThreads: _int(json['nThreads'], 1),
      nGpuLayers: _int(json['nGpuLayers'], 0),
      temperature: _double(json['temperature'], 0.7),
      topP: _double(json['topP'], 0.9),
      topK: _int(json['topK'], 40),
      nBatch: _int(json['nBatch'], 512),
      nUBatch: _int(json['nUBatch'], 512),
      mirostat: _int(json['mirostat'], 0),
      repeatPenalty: _double(json['repeatPenalty'], 1.1),
      repeatLastN: _int(json['repeatLastN'], 256),
      presencePenalty: _double(json['presencePenalty'], 1.2),
      frequencyPenalty: _double(json['frequencyPenalty'], 0.5),
      thinking: json['thinking'] as bool? ?? true,
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
        temperature == other.temperature &&
        topP == other.topP &&
        topK == other.topK &&
        nBatch == other.nBatch &&
        nUBatch == other.nUBatch &&
        mirostat == other.mirostat &&
        repeatPenalty == other.repeatPenalty &&
        repeatLastN == other.repeatLastN &&
        presencePenalty == other.presencePenalty &&
        frequencyPenalty == other.frequencyPenalty &&
        thinking == other.thinking &&
        kvCacheQuantizationEnabled == other.kvCacheQuantizationEnabled &&
        kvCacheTypeK == other.kvCacheTypeK &&
        kvCacheTypeV == other.kvCacheTypeV;
  }

  static int _int(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  static double _double(Object? value, double fallback) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return fallback;
  }

  static String _kvCacheType(Object? value) {
    if (value is String && allowedKvCacheTypes.contains(value)) return value;
    return defaultKvCacheType;
  }
}
