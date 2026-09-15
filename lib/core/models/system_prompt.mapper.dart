// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'system_prompt.dart';

/// @nodoc
class PromptModuleMapper extends ClassMapperBase<PromptModule> {
  PromptModuleMapper._();

  static PromptModuleMapper? _instance;
  static PromptModuleMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PromptModuleMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PromptModule';

  static String _$id(PromptModule v) => v.id;
  static const Field<PromptModule, String> _f$id = Field('id', _$id);
  static String _$name(PromptModule v) => v.name;
  static const Field<PromptModule, String> _f$name = Field('name', _$name);
  static String _$category(PromptModule v) => v.category;
  static const Field<PromptModule, String> _f$category = Field(
    'category',
    _$category,
  );
  static String _$content(PromptModule v) => v.content;
  static const Field<PromptModule, String> _f$content = Field(
    'content',
    _$content,
  );
  static int _$priority(PromptModule v) => v.priority;
  static const Field<PromptModule, int> _f$priority = Field(
    'priority',
    _$priority,
    hook: JsonIntHook(fallback: 100),
  );
  static bool _$isBuiltIn(PromptModule v) => v.isBuiltIn;
  static const Field<PromptModule, bool> _f$isBuiltIn = Field(
    'isBuiltIn',
    _$isBuiltIn,
    hook: JsonBoolHook(),
  );
  static List<String> _$requiredModuleIds(PromptModule v) =>
      v.requiredModuleIds;
  static const Field<PromptModule, List<String>> _f$requiredModuleIds = Field(
    'requiredModuleIds',
    _$requiredModuleIds,
    hook: JsonStringListHook(),
  );
  static List<String> _$conflictingModuleIds(PromptModule v) =>
      v.conflictingModuleIds;
  static const Field<PromptModule, List<String>> _f$conflictingModuleIds =
      Field(
        'conflictingModuleIds',
        _$conflictingModuleIds,
        hook: JsonStringListHook(),
      );
  static DateTime _$createdAt(PromptModule v) => v.createdAt;
  static const Field<PromptModule, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: EpochDateHook(fallbackNow: true),
  );
  static DateTime _$updatedAt(PromptModule v) => v.updatedAt;
  static const Field<PromptModule, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: EpochDateHook(fallbackNow: true),
  );

  @override
  final MappableFields<PromptModule> fields = const {
    #id: _f$id,
    #name: _f$name,
    #category: _f$category,
    #content: _f$content,
    #priority: _f$priority,
    #isBuiltIn: _f$isBuiltIn,
    #requiredModuleIds: _f$requiredModuleIds,
    #conflictingModuleIds: _f$conflictingModuleIds,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };

  static PromptModule _instantiate(DecodingData data) {
    return PromptModule(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      category: data.dec(_f$category),
      content: data.dec(_f$content),
      priority: data.dec(_f$priority),
      isBuiltIn: data.dec(_f$isBuiltIn),
      requiredModuleIds: data.dec(_f$requiredModuleIds),
      conflictingModuleIds: data.dec(_f$conflictingModuleIds),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PromptModule fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PromptModule>(map);
  }

  static PromptModule fromJson(String json) {
    return ensureInitialized().decodeJson<PromptModule>(json);
  }
}

/// @nodoc
mixin PromptModuleMappable {
  String toJson() {
    return PromptModuleMapper.ensureInitialized().encodeJson<PromptModule>(
      this as PromptModule,
    );
  }

  Map<String, dynamic> toMap() {
    return PromptModuleMapper.ensureInitialized().encodeMap<PromptModule>(
      this as PromptModule,
    );
  }
}

/// @nodoc
class PromptPresetMapper extends ClassMapperBase<PromptPreset> {
  PromptPresetMapper._();

  static PromptPresetMapper? _instance;
  static PromptPresetMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PromptPresetMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PromptPreset';

  static String _$id(PromptPreset v) => v.id;
  static const Field<PromptPreset, String> _f$id = Field('id', _$id);
  static String _$name(PromptPreset v) => v.name;
  static const Field<PromptPreset, String> _f$name = Field('name', _$name);
  static List<String> _$baseModuleIds(PromptPreset v) => v.baseModuleIds;
  static const Field<PromptPreset, List<String>> _f$baseModuleIds = Field(
    'baseModuleIds',
    _$baseModuleIds,
    hook: JsonStringListHook(),
  );
  static List<String> _$optionalModuleIds(PromptPreset v) =>
      v.optionalModuleIds;
  static const Field<PromptPreset, List<String>> _f$optionalModuleIds = Field(
    'optionalModuleIds',
    _$optionalModuleIds,
    hook: JsonStringListHook(),
  );
  static String _$customInstructions(PromptPreset v) => v.customInstructions;
  static const Field<PromptPreset, String> _f$customInstructions = Field(
    'customInstructions',
    _$customInstructions,
    hook: JsonStringHook(),
  );
  static bool _$isBuiltIn(PromptPreset v) => v.isBuiltIn;
  static const Field<PromptPreset, bool> _f$isBuiltIn = Field(
    'isBuiltIn',
    _$isBuiltIn,
    hook: JsonBoolHook(),
  );
  static DateTime _$createdAt(PromptPreset v) => v.createdAt;
  static const Field<PromptPreset, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: EpochDateHook(fallbackNow: true),
  );
  static DateTime _$updatedAt(PromptPreset v) => v.updatedAt;
  static const Field<PromptPreset, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: EpochDateHook(fallbackNow: true),
  );
  static DateTime? _$lastUsedAt(PromptPreset v) => v.lastUsedAt;
  static const Field<PromptPreset, DateTime> _f$lastUsedAt = Field(
    'lastUsedAt',
    _$lastUsedAt,
    opt: true,
    hook: EpochDateHook(),
  );

  @override
  final MappableFields<PromptPreset> fields = const {
    #id: _f$id,
    #name: _f$name,
    #baseModuleIds: _f$baseModuleIds,
    #optionalModuleIds: _f$optionalModuleIds,
    #customInstructions: _f$customInstructions,
    #isBuiltIn: _f$isBuiltIn,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #lastUsedAt: _f$lastUsedAt,
  };

  static PromptPreset _instantiate(DecodingData data) {
    return PromptPreset(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      baseModuleIds: data.dec(_f$baseModuleIds),
      optionalModuleIds: data.dec(_f$optionalModuleIds),
      customInstructions: data.dec(_f$customInstructions),
      isBuiltIn: data.dec(_f$isBuiltIn),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      lastUsedAt: data.dec(_f$lastUsedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PromptPreset fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PromptPreset>(map);
  }

  static PromptPreset fromJson(String json) {
    return ensureInitialized().decodeJson<PromptPreset>(json);
  }
}

/// @nodoc
mixin PromptPresetMappable {
  String toJson() {
    return PromptPresetMapper.ensureInitialized().encodeJson<PromptPreset>(
      this as PromptPreset,
    );
  }

  Map<String, dynamic> toMap() {
    return PromptPresetMapper.ensureInitialized().encodeMap<PromptPreset>(
      this as PromptPreset,
    );
  }
}

/// @nodoc
class SystemPromptSnapshotMapper extends ClassMapperBase<SystemPromptSnapshot> {
  SystemPromptSnapshotMapper._();

  static SystemPromptSnapshotMapper? _instance;
  static SystemPromptSnapshotMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SystemPromptSnapshotMapper._());
      PromptPresetMapper.ensureInitialized();
      PromptModuleMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SystemPromptSnapshot';

  static String? _$id(SystemPromptSnapshot v) => v.id;
  static const Field<SystemPromptSnapshot, String> _f$id = Field('id', _$id);
  static String _$name(SystemPromptSnapshot v) => v.name;
  static const Field<SystemPromptSnapshot, String> _f$name = Field(
    'name',
    _$name,
    hook: JsonStringHook(fallback: 'System prompt'),
  );
  static String _$text(SystemPromptSnapshot v) => v.text;
  static const Field<SystemPromptSnapshot, String> _f$text = Field(
    'text',
    _$text,
    hook: JsonStringHook(),
  );
  static PromptPreset? _$preset(SystemPromptSnapshot v) => v.preset;
  static const Field<SystemPromptSnapshot, PromptPreset> _f$preset = Field(
    'preset',
    _$preset,
    opt: true,
  );
  static List<PromptModule> _$modules(SystemPromptSnapshot v) => v.modules;
  static const Field<SystemPromptSnapshot, List<PromptModule>> _f$modules =
      Field(
        'modules',
        _$modules,
        opt: true,
        def: const [],
        hook: JsonObjectListHook(),
      );
  static List<String> _$selectedModuleIds(SystemPromptSnapshot v) =>
      v.selectedModuleIds;
  static const Field<SystemPromptSnapshot, List<String>> _f$selectedModuleIds =
      Field(
        'selectedModuleIds',
        _$selectedModuleIds,
        opt: true,
        def: const [],
        hook: JsonStringListHook(),
      );
  static List<String> _$diagnostics(SystemPromptSnapshot v) => v.diagnostics;
  static const Field<SystemPromptSnapshot, List<String>> _f$diagnostics = Field(
    'diagnostics',
    _$diagnostics,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );

  @override
  final MappableFields<SystemPromptSnapshot> fields = const {
    #id: _f$id,
    #name: _f$name,
    #text: _f$text,
    #preset: _f$preset,
    #modules: _f$modules,
    #selectedModuleIds: _f$selectedModuleIds,
    #diagnostics: _f$diagnostics,
  };

  static SystemPromptSnapshot _instantiate(DecodingData data) {
    return SystemPromptSnapshot(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      text: data.dec(_f$text),
      preset: data.dec(_f$preset),
      modules: data.dec(_f$modules),
      selectedModuleIds: data.dec(_f$selectedModuleIds),
      diagnostics: data.dec(_f$diagnostics),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SystemPromptSnapshot fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SystemPromptSnapshot>(map);
  }

  static SystemPromptSnapshot fromJson(String json) {
    return ensureInitialized().decodeJson<SystemPromptSnapshot>(json);
  }
}

/// @nodoc
mixin SystemPromptSnapshotMappable {
  String toJson() {
    return SystemPromptSnapshotMapper.ensureInitialized()
        .encodeJson<SystemPromptSnapshot>(this as SystemPromptSnapshot);
  }

  Map<String, dynamic> toMap() {
    return SystemPromptSnapshotMapper.ensureInitialized()
        .encodeMap<SystemPromptSnapshot>(this as SystemPromptSnapshot);
  }
}

