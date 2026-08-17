// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model_configuration_snapshot.dart';

/// @nodoc
class ModelConfigurationSnapshotMapper
    extends ClassMapperBase<ModelConfigurationSnapshot> {
  ModelConfigurationSnapshotMapper._();

  static ModelConfigurationSnapshotMapper? _instance;
  static ModelConfigurationSnapshotMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ModelConfigurationSnapshotMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'ModelConfigurationSnapshot';

  static String _$modelName(ModelConfigurationSnapshot v) => v.modelName;
  static const Field<ModelConfigurationSnapshot, String> _f$modelName = Field(
    'modelName',
    _$modelName,
    hook: JsonStringHook(),
  );
  static String _$modelPath(ModelConfigurationSnapshot v) => v.modelPath;
  static const Field<ModelConfigurationSnapshot, String> _f$modelPath = Field(
    'modelPath',
    _$modelPath,
    hook: JsonStringHook(),
  );
  static String _$llamaCppDirectory(ModelConfigurationSnapshot v) =>
      v.llamaCppDirectory;
  static const Field<ModelConfigurationSnapshot, String> _f$llamaCppDirectory =
      Field('llamaCppDirectory', _$llamaCppDirectory, hook: JsonStringHook());
  static int _$nCtx(ModelConfigurationSnapshot v) => v.nCtx;
  static const Field<ModelConfigurationSnapshot, int> _f$nCtx = Field(
    'nCtx',
    _$nCtx,
    hook: JsonIntHook(fallback: 4096),
  );
  static int _$nThreads(ModelConfigurationSnapshot v) => v.nThreads;
  static const Field<ModelConfigurationSnapshot, int> _f$nThreads = Field(
    'nThreads',
    _$nThreads,
    hook: PlatformThreadsHook(),
  );
  static double _$temperature(ModelConfigurationSnapshot v) => v.temperature;
  static const Field<ModelConfigurationSnapshot, double> _f$temperature = Field(
    'temperature',
    _$temperature,
    hook: JsonDoubleHook(fallback: 0.7),
  );
  static double _$topP(ModelConfigurationSnapshot v) => v.topP;
  static const Field<ModelConfigurationSnapshot, double> _f$topP = Field(
    'topP',
    _$topP,
    hook: JsonDoubleHook(fallback: 0.9),
  );
  static int _$topK(ModelConfigurationSnapshot v) => v.topK;
  static const Field<ModelConfigurationSnapshot, int> _f$topK = Field(
    'topK',
    _$topK,
    hook: JsonIntHook(fallback: 40),
  );
  static double _$minP(ModelConfigurationSnapshot v) => v.minP;
  static const Field<ModelConfigurationSnapshot, double> _f$minP = Field(
    'minP',
    _$minP,
    opt: true,
    def: 0.05,
    hook: JsonDoubleHook(fallback: 0.05),
  );
  static int _$nBatch(ModelConfigurationSnapshot v) => v.nBatch;
  static const Field<ModelConfigurationSnapshot, int> _f$nBatch = Field(
    'nBatch',
    _$nBatch,
    hook: JsonIntHook(fallback: 2048),
  );
  static int _$nUBatch(ModelConfigurationSnapshot v) => v.nUBatch;
  static const Field<ModelConfigurationSnapshot, int> _f$nUBatch = Field(
    'nUBatch',
    _$nUBatch,
    hook: JsonIntHook(fallback: 512),
  );
  static int _$mirostat(ModelConfigurationSnapshot v) => v.mirostat;
  static const Field<ModelConfigurationSnapshot, int> _f$mirostat = Field(
    'mirostat',
    _$mirostat,
    hook: JsonIntHook(),
  );
  static double _$repeatPenalty(ModelConfigurationSnapshot v) =>
      v.repeatPenalty;
  static const Field<ModelConfigurationSnapshot, double> _f$repeatPenalty =
      Field(
        'repeatPenalty',
        _$repeatPenalty,
        hook: JsonDoubleHook(fallback: 1.1),
      );
  static int _$repeatLastN(ModelConfigurationSnapshot v) => v.repeatLastN;
  static const Field<ModelConfigurationSnapshot, int> _f$repeatLastN = Field(
    'repeatLastN',
    _$repeatLastN,
    hook: JsonIntHook(fallback: 256),
  );
  static double _$presencePenalty(ModelConfigurationSnapshot v) =>
      v.presencePenalty;
  static const Field<ModelConfigurationSnapshot, double> _f$presencePenalty =
      Field(
        'presencePenalty',
        _$presencePenalty,
        hook: JsonDoubleHook(fallback: 1.2),
      );
  static double _$frequencyPenalty(ModelConfigurationSnapshot v) =>
      v.frequencyPenalty;
  static const Field<ModelConfigurationSnapshot, double> _f$frequencyPenalty =
      Field(
        'frequencyPenalty',
        _$frequencyPenalty,
        hook: JsonDoubleHook(fallback: 0.5),
      );
  static bool _$thinking(ModelConfigurationSnapshot v) => v.thinking;
  static const Field<ModelConfigurationSnapshot, bool> _f$thinking = Field(
    'thinking',
    _$thinking,
    hook: JsonBoolHook(fallback: true),
  );
  static String _$reasoningEffort(ModelConfigurationSnapshot v) =>
      v.reasoningEffort;
  static const Field<ModelConfigurationSnapshot, String> _f$reasoningEffort =
      Field(
        'reasoningEffort',
        _$reasoningEffort,
        opt: true,
        def: ModelConfigurationSnapshot.defaultReasoningEffort,
        hook: ReasoningEffortHook(),
      );
  static bool _$mtpEnabled(ModelConfigurationSnapshot v) => v.mtpEnabled;
  static const Field<ModelConfigurationSnapshot, bool> _f$mtpEnabled = Field(
    'mtpEnabled',
    _$mtpEnabled,
    opt: true,
    def: false,
    hook: JsonBoolHook(),
  );
  static int _$mtpDraftTokens(ModelConfigurationSnapshot v) => v.mtpDraftTokens;
  static const Field<ModelConfigurationSnapshot, int> _f$mtpDraftTokens = Field(
    'mtpDraftTokens',
    _$mtpDraftTokens,
    opt: true,
    def: ModelConfigurationSnapshot.defaultMtpDraftTokens,
    hook: JsonIntHook(fallback: 3, min: 1, max: 16),
  );
  static bool _$flashAttention(ModelConfigurationSnapshot v) =>
      v.flashAttention;
  static const Field<ModelConfigurationSnapshot, bool> _f$flashAttention =
      Field(
        'flashAttention',
        _$flashAttention,
        hook: JsonBoolHook(fallback: true),
      );
  static bool _$cachePrompt(ModelConfigurationSnapshot v) => v.cachePrompt;
  static const Field<ModelConfigurationSnapshot, bool> _f$cachePrompt = Field(
    'cachePrompt',
    _$cachePrompt,
    hook: JsonBoolHook(fallback: true),
  );
  static int _$cacheReuse(ModelConfigurationSnapshot v) => v.cacheReuse;
  static const Field<ModelConfigurationSnapshot, int> _f$cacheReuse = Field(
    'cacheReuse',
    _$cacheReuse,
    hook: CacheReuseHook(),
  );
  static bool _$kvCacheQuantizationEnabled(ModelConfigurationSnapshot v) =>
      v.kvCacheQuantizationEnabled;
  static const Field<ModelConfigurationSnapshot, bool>
  _f$kvCacheQuantizationEnabled = Field(
    'kvCacheQuantizationEnabled',
    _$kvCacheQuantizationEnabled,
    hook: JsonBoolHook(fallback: true),
  );
  static String _$kvCacheTypeK(ModelConfigurationSnapshot v) => v.kvCacheTypeK;
  static const Field<ModelConfigurationSnapshot, String> _f$kvCacheTypeK =
      Field('kvCacheTypeK', _$kvCacheTypeK, hook: KvCacheTypeHook());
  static String _$kvCacheTypeV(ModelConfigurationSnapshot v) => v.kvCacheTypeV;
  static const Field<ModelConfigurationSnapshot, String> _f$kvCacheTypeV =
      Field('kvCacheTypeV', _$kvCacheTypeV, hook: KvCacheTypeHook());

  @override
  final MappableFields<ModelConfigurationSnapshot> fields = const {
    #modelName: _f$modelName,
    #modelPath: _f$modelPath,
    #llamaCppDirectory: _f$llamaCppDirectory,
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
    #reasoningEffort: _f$reasoningEffort,
    #mtpEnabled: _f$mtpEnabled,
    #mtpDraftTokens: _f$mtpDraftTokens,
    #flashAttention: _f$flashAttention,
    #cachePrompt: _f$cachePrompt,
    #cacheReuse: _f$cacheReuse,
    #kvCacheQuantizationEnabled: _f$kvCacheQuantizationEnabled,
    #kvCacheTypeK: _f$kvCacheTypeK,
    #kvCacheTypeV: _f$kvCacheTypeV,
  };

  static ModelConfigurationSnapshot _instantiate(DecodingData data) {
    return ModelConfigurationSnapshot(
      modelName: data.dec(_f$modelName),
      modelPath: data.dec(_f$modelPath),
      llamaCppDirectory: data.dec(_f$llamaCppDirectory),
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
      reasoningEffort: data.dec(_f$reasoningEffort),
      mtpEnabled: data.dec(_f$mtpEnabled),
      mtpDraftTokens: data.dec(_f$mtpDraftTokens),
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

  static ModelConfigurationSnapshot fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModelConfigurationSnapshot>(map);
  }

  static ModelConfigurationSnapshot fromJson(String json) {
    return ensureInitialized().decodeJson<ModelConfigurationSnapshot>(json);
  }
}

/// @nodoc
mixin ModelConfigurationSnapshotMappable {
  String toJson() {
    return ModelConfigurationSnapshotMapper.ensureInitialized()
        .encodeJson<ModelConfigurationSnapshot>(
          this as ModelConfigurationSnapshot,
        );
  }

  Map<String, dynamic> toMap() {
    return ModelConfigurationSnapshotMapper.ensureInitialized()
        .encodeMap<ModelConfigurationSnapshot>(
          this as ModelConfigurationSnapshot,
        );
  }
}

