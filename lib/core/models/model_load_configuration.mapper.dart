// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model_load_configuration.dart';

/// @nodoc
class ModelLoadConfigurationMapper
    extends ClassMapperBase<ModelLoadConfiguration> {
  ModelLoadConfigurationMapper._();

  static ModelLoadConfigurationMapper? _instance;
  static ModelLoadConfigurationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModelLoadConfigurationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ModelLoadConfiguration';

  static int _$nCtx(ModelLoadConfiguration v) => v.nCtx;
  static const Field<ModelLoadConfiguration, int> _f$nCtx = Field(
    'nCtx',
    _$nCtx,
    hook: JsonIntHook(fallback: 32768),
  );
  static int _$nThreads(ModelLoadConfiguration v) => v.nThreads;
  static const Field<ModelLoadConfiguration, int> _f$nThreads = Field(
    'nThreads',
    _$nThreads,
    hook: PlatformThreadsHook(),
  );
  static double _$temperature(ModelLoadConfiguration v) => v.temperature;
  static const Field<ModelLoadConfiguration, double> _f$temperature = Field(
    'temperature',
    _$temperature,
    hook: JsonDoubleHook(fallback: 0.7),
  );
  static double _$topP(ModelLoadConfiguration v) => v.topP;
  static const Field<ModelLoadConfiguration, double> _f$topP = Field(
    'topP',
    _$topP,
    hook: JsonDoubleHook(fallback: 0.95),
  );
  static int _$topK(ModelLoadConfiguration v) => v.topK;
  static const Field<ModelLoadConfiguration, int> _f$topK = Field(
    'topK',
    _$topK,
    hook: JsonIntHook(fallback: 20),
  );
  static double _$minP(ModelLoadConfiguration v) => v.minP;
  static const Field<ModelLoadConfiguration, double> _f$minP = Field(
    'minP',
    _$minP,
    opt: true,
    def: ModelLoadConfiguration.defaultMinP,
    hook: JsonDoubleHook(fallback: 0.0),
  );
  static int _$nBatch(ModelLoadConfiguration v) => v.nBatch;
  static const Field<ModelLoadConfiguration, int> _f$nBatch = Field(
    'nBatch',
    _$nBatch,
    hook: JsonIntHook(fallback: 2048),
  );
  static int _$nUBatch(ModelLoadConfiguration v) => v.nUBatch;
  static const Field<ModelLoadConfiguration, int> _f$nUBatch = Field(
    'nUBatch',
    _$nUBatch,
    hook: JsonIntHook(fallback: 2048),
  );
  static int _$mirostat(ModelLoadConfiguration v) => v.mirostat;
  static const Field<ModelLoadConfiguration, int> _f$mirostat = Field(
    'mirostat',
    _$mirostat,
    hook: JsonIntHook(fallback: 0),
  );
  static double _$repeatPenalty(ModelLoadConfiguration v) => v.repeatPenalty;
  static const Field<ModelLoadConfiguration, double> _f$repeatPenalty = Field(
    'repeatPenalty',
    _$repeatPenalty,
    hook: JsonDoubleHook(fallback: 1.0),
  );
  static int _$repeatLastN(ModelLoadConfiguration v) => v.repeatLastN;
  static const Field<ModelLoadConfiguration, int> _f$repeatLastN = Field(
    'repeatLastN',
    _$repeatLastN,
    hook: JsonIntHook(fallback: 64),
  );
  static double _$presencePenalty(ModelLoadConfiguration v) =>
      v.presencePenalty;
  static const Field<ModelLoadConfiguration, double> _f$presencePenalty = Field(
    'presencePenalty',
    _$presencePenalty,
    hook: JsonDoubleHook(fallback: 0.0),
  );
  static double _$frequencyPenalty(ModelLoadConfiguration v) =>
      v.frequencyPenalty;
  static const Field<ModelLoadConfiguration, double> _f$frequencyPenalty =
      Field(
        'frequencyPenalty',
        _$frequencyPenalty,
        hook: JsonDoubleHook(fallback: 0.0),
      );
  static bool _$thinking(ModelLoadConfiguration v) => v.thinking;
  static const Field<ModelLoadConfiguration, bool> _f$thinking = Field(
    'thinking',
    _$thinking,
    hook: JsonBoolHook(fallback: false),
  );
  static bool _$flashAttention(ModelLoadConfiguration v) => v.flashAttention;
  static const Field<ModelLoadConfiguration, bool> _f$flashAttention = Field(
    'flashAttention',
    _$flashAttention,
    hook: JsonBoolHook(fallback: true),
  );
  static bool _$cachePrompt(ModelLoadConfiguration v) => v.cachePrompt;
  static const Field<ModelLoadConfiguration, bool> _f$cachePrompt = Field(
    'cachePrompt',
    _$cachePrompt,
    hook: JsonBoolHook(fallback: true),
  );
  static int _$cacheReuse(ModelLoadConfiguration v) => v.cacheReuse;
  static const Field<ModelLoadConfiguration, int> _f$cacheReuse = Field(
    'cacheReuse',
    _$cacheReuse,
    hook: CacheReuseHook(),
  );
  static bool _$kvCacheQuantizationEnabled(ModelLoadConfiguration v) =>
      v.kvCacheQuantizationEnabled;
  static const Field<ModelLoadConfiguration, bool>
  _f$kvCacheQuantizationEnabled = Field(
    'kvCacheQuantizationEnabled',
    _$kvCacheQuantizationEnabled,
    hook: JsonBoolHook(fallback: false),
  );
  static String _$kvCacheTypeK(ModelLoadConfiguration v) => v.kvCacheTypeK;
  static const Field<ModelLoadConfiguration, String> _f$kvCacheTypeK = Field(
    'kvCacheTypeK',
    _$kvCacheTypeK,
    hook: ModelLoadKvCacheTypeHook(),
  );
  static String _$kvCacheTypeV(ModelLoadConfiguration v) => v.kvCacheTypeV;
  static const Field<ModelLoadConfiguration, String> _f$kvCacheTypeV = Field(
    'kvCacheTypeV',
    _$kvCacheTypeV,
    hook: ModelLoadKvCacheTypeHook(),
  );

  @override
  final MappableFields<ModelLoadConfiguration> fields = const {
    #nCtx: _f$nCtx,
    #nThreads: _f$nThreads,
    #temperature: _f$temperature,
    #topP: _f$topP,
    #topK: _f$topK,
    #minP: _f$minP,
    #nBatch: _f$nBatch,
    #nUBatch: _f$nUBatch,
    #mirostat: _f$mirostat,
    #repeatPenalty: _f$repeatPenalty,
    #repeatLastN: _f$repeatLastN,
    #presencePenalty: _f$presencePenalty,
    #frequencyPenalty: _f$frequencyPenalty,
    #thinking: _f$thinking,
    #flashAttention: _f$flashAttention,
    #cachePrompt: _f$cachePrompt,
    #cacheReuse: _f$cacheReuse,
    #kvCacheQuantizationEnabled: _f$kvCacheQuantizationEnabled,
    #kvCacheTypeK: _f$kvCacheTypeK,
    #kvCacheTypeV: _f$kvCacheTypeV,
  };

  static ModelLoadConfiguration _instantiate(DecodingData data) {
    return ModelLoadConfiguration(
      nCtx: data.dec(_f$nCtx),
      nThreads: data.dec(_f$nThreads),
      temperature: data.dec(_f$temperature),
      topP: data.dec(_f$topP),
      topK: data.dec(_f$topK),
      minP: data.dec(_f$minP),
      nBatch: data.dec(_f$nBatch),
      nUBatch: data.dec(_f$nUBatch),
      mirostat: data.dec(_f$mirostat),
      repeatPenalty: data.dec(_f$repeatPenalty),
      repeatLastN: data.dec(_f$repeatLastN),
      presencePenalty: data.dec(_f$presencePenalty),
      frequencyPenalty: data.dec(_f$frequencyPenalty),
      thinking: data.dec(_f$thinking),
      flashAttention: data.dec(_f$flashAttention),
      cachePrompt: data.dec(_f$cachePrompt),
      cacheReuse: data.dec(_f$cacheReuse),
      kvCacheQuantizationEnabled: data.dec(_f$kvCacheQuantizationEnabled),
      kvCacheTypeK: data.dec(_f$kvCacheTypeK),
      kvCacheTypeV: data.dec(_f$kvCacheTypeV),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModelLoadConfiguration fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModelLoadConfiguration>(map);
  }

  static ModelLoadConfiguration fromJson(String json) {
    return ensureInitialized().decodeJson<ModelLoadConfiguration>(json);
  }
}

/// @nodoc
mixin ModelLoadConfigurationMappable {
  String toJson() {
    return ModelLoadConfigurationMapper.ensureInitialized()
        .encodeJson<ModelLoadConfiguration>(this as ModelLoadConfiguration);
  }

  Map<String, dynamic> toMap() {
    return ModelLoadConfigurationMapper.ensureInitialized()
        .encodeMap<ModelLoadConfiguration>(this as ModelLoadConfiguration);
  }
}

