// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'acceptance.dart';

/// @nodoc

class AcceptanceVerifierKindMapper extends EnumMapper<AcceptanceVerifierKind> {
  AcceptanceVerifierKindMapper._();

  static AcceptanceVerifierKindMapper? _instance;
  static AcceptanceVerifierKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AcceptanceVerifierKindMapper._());
    }
    return _instance!;
  }

  static AcceptanceVerifierKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AcceptanceVerifierKind decode(dynamic value) {
    switch (value) {
      case r'command':
        return AcceptanceVerifierKind.command;
      case r'artifact':
        return AcceptanceVerifierKind.artifact;
      case r'review':
        return AcceptanceVerifierKind.review;
      case r'approval':
        return AcceptanceVerifierKind.approval;
      default:
        return AcceptanceVerifierKind.values[0];
    }
  }

  @override
  dynamic encode(AcceptanceVerifierKind self) {
    switch (self) {
      case AcceptanceVerifierKind.command:
        return r'command';
      case AcceptanceVerifierKind.artifact:
        return r'artifact';
      case AcceptanceVerifierKind.review:
        return r'review';
      case AcceptanceVerifierKind.approval:
        return r'approval';
    }
  }
}

/// @nodoc

extension AcceptanceVerifierKindMapperExtension on AcceptanceVerifierKind {
  String toValue() {
    AcceptanceVerifierKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AcceptanceVerifierKind>(this)
        as String;
  }
}

/// @nodoc
class AcceptanceVerifierMapper extends ClassMapperBase<AcceptanceVerifier> {
  AcceptanceVerifierMapper._();

  static AcceptanceVerifierMapper? _instance;
  static AcceptanceVerifierMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AcceptanceVerifierMapper._());
      AcceptanceVerifierKindMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AcceptanceVerifier';

  static AcceptanceVerifierKind _$kind(AcceptanceVerifier v) => v.kind;
  static const Field<AcceptanceVerifier, AcceptanceVerifierKind> _f$kind =
      Field('kind', _$kind);
  static bool _$required(AcceptanceVerifier v) => v.required;
  static const Field<AcceptanceVerifier, bool> _f$required = Field(
    'required',
    _$required,
    opt: true,
    def: true,
  );
  static String? _$command(AcceptanceVerifier v) => v.command;
  static const Field<AcceptanceVerifier, String> _f$command = Field(
    'command',
    _$command,
    opt: true,
  );
  static String _$workingDirectory(AcceptanceVerifier v) => v.workingDirectory;
  static const Field<AcceptanceVerifier, String> _f$workingDirectory = Field(
    'workingDirectory',
    _$workingDirectory,
    opt: true,
    def: '.',
  );
  static String? _$path(AcceptanceVerifier v) => v.path;
  static const Field<AcceptanceVerifier, String> _f$path = Field(
    'path',
    _$path,
    opt: true,
  );
  static String _$artifactKind(AcceptanceVerifier v) => v.artifactKind;
  static const Field<AcceptanceVerifier, String> _f$artifactKind = Field(
    'artifactKind',
    _$artifactKind,
    opt: true,
    def: 'file',
  );
  static String? _$description(AcceptanceVerifier v) => v.description;
  static const Field<AcceptanceVerifier, String> _f$description = Field(
    'description',
    _$description,
    opt: true,
  );

  @override
  final MappableFields<AcceptanceVerifier> fields = const {
    #kind: _f$kind,
    #required: _f$required,
    #command: _f$command,
    #workingDirectory: _f$workingDirectory,
    #path: _f$path,
    #artifactKind: _f$artifactKind,
    #description: _f$description,
  };
  @override
  final bool ignoreNull = true;

  static AcceptanceVerifier _instantiate(DecodingData data) {
    return AcceptanceVerifier(
      kind: data.dec(_f$kind),
      required: data.dec(_f$required),
      command: data.dec(_f$command),
      workingDirectory: data.dec(_f$workingDirectory),
      path: data.dec(_f$path),
      artifactKind: data.dec(_f$artifactKind),
      description: data.dec(_f$description),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AcceptanceVerifier fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AcceptanceVerifier>(map);
  }

  static AcceptanceVerifier fromJson(String json) {
    return ensureInitialized().decodeJson<AcceptanceVerifier>(json);
  }
}

/// @nodoc
mixin AcceptanceVerifierMappable {
  String toJson() {
    return AcceptanceVerifierMapper.ensureInitialized()
        .encodeJson<AcceptanceVerifier>(this as AcceptanceVerifier);
  }

  Map<String, dynamic> toMap() {
    return AcceptanceVerifierMapper.ensureInitialized()
        .encodeMap<AcceptanceVerifier>(this as AcceptanceVerifier);
  }
}

/// @nodoc
class AcceptanceItemMapper extends ClassMapperBase<AcceptanceItem> {
  AcceptanceItemMapper._();

  static AcceptanceItemMapper? _instance;
  static AcceptanceItemMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AcceptanceItemMapper._());
      AcceptanceVerifierMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AcceptanceItem';

  static String _$ref(AcceptanceItem v) => v.ref;
  static const Field<AcceptanceItem, String> _f$ref = Field('ref', _$ref);
  static String _$statement(AcceptanceItem v) => v.statement;
  static const Field<AcceptanceItem, String> _f$statement = Field(
    'statement',
    _$statement,
  );
  static List<String> _$criterionIds(AcceptanceItem v) => v.criterionIds;
  static const Field<AcceptanceItem, List<String>> _f$criterionIds = Field(
    'criterionIds',
    _$criterionIds,
    opt: true,
    def: const [],
  );
  static List<AcceptanceVerifier> _$verifiers(AcceptanceItem v) => v.verifiers;
  static const Field<AcceptanceItem, List<AcceptanceVerifier>> _f$verifiers =
      Field('verifiers', _$verifiers, opt: true, def: const []);

  @override
  final MappableFields<AcceptanceItem> fields = const {
    #ref: _f$ref,
    #statement: _f$statement,
    #criterionIds: _f$criterionIds,
    #verifiers: _f$verifiers,
  };
  @override
  final bool ignoreNull = true;

  static AcceptanceItem _instantiate(DecodingData data) {
    return AcceptanceItem(
      ref: data.dec(_f$ref),
      statement: data.dec(_f$statement),
      criterionIds: data.dec(_f$criterionIds),
      verifiers: data.dec(_f$verifiers),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AcceptanceItem fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AcceptanceItem>(map);
  }

  static AcceptanceItem fromJson(String json) {
    return ensureInitialized().decodeJson<AcceptanceItem>(json);
  }
}

/// @nodoc
mixin AcceptanceItemMappable {
  String toJson() {
    return AcceptanceItemMapper.ensureInitialized().encodeJson<AcceptanceItem>(
      this as AcceptanceItem,
    );
  }

  Map<String, dynamic> toMap() {
    return AcceptanceItemMapper.ensureInitialized().encodeMap<AcceptanceItem>(
      this as AcceptanceItem,
    );
  }
}

