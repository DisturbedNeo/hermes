// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'workspace_discovery_profile.dart';

/// @nodoc
class WorkspaceDiscoveryProfileMapper
    extends ClassMapperBase<WorkspaceDiscoveryProfile> {
  WorkspaceDiscoveryProfileMapper._();

  static WorkspaceDiscoveryProfileMapper? _instance;
  static WorkspaceDiscoveryProfileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = WorkspaceDiscoveryProfileMapper._(),
      );
      WorkspaceFileExcerptMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorkspaceDiscoveryProfile';

  static String _$workspaceName(WorkspaceDiscoveryProfile v) => v.workspaceName;
  static const Field<WorkspaceDiscoveryProfile, String> _f$workspaceName =
      Field('workspaceName', _$workspaceName);
  static List<String> _$treePaths(WorkspaceDiscoveryProfile v) => v.treePaths;
  static const Field<WorkspaceDiscoveryProfile, List<String>> _f$treePaths =
      Field('treePaths', _$treePaths, opt: true, def: const []);
  static List<WorkspaceFileExcerpt> _$highSignalFiles(
    WorkspaceDiscoveryProfile v,
  ) => v.highSignalFiles;
  static const Field<WorkspaceDiscoveryProfile, List<WorkspaceFileExcerpt>>
  _f$highSignalFiles = Field(
    'highSignalFiles',
    _$highSignalFiles,
    opt: true,
    def: const [],
  );
  static String? _$packageName(WorkspaceDiscoveryProfile v) => v.packageName;
  static const Field<WorkspaceDiscoveryProfile, String> _f$packageName = Field(
    'packageName',
    _$packageName,
    opt: true,
  );
  static Map<String, String> _$scripts(WorkspaceDiscoveryProfile v) =>
      v.scripts;
  static const Field<WorkspaceDiscoveryProfile, Map<String, String>>
  _f$scripts = Field('scripts', _$scripts, opt: true, def: const {});
  static List<String> _$dependencies(WorkspaceDiscoveryProfile v) =>
      v.dependencies;
  static const Field<WorkspaceDiscoveryProfile, List<String>> _f$dependencies =
      Field('dependencies', _$dependencies, opt: true, def: const []);
  static List<String> _$languages(WorkspaceDiscoveryProfile v) => v.languages;
  static const Field<WorkspaceDiscoveryProfile, List<String>> _f$languages =
      Field('languages', _$languages, opt: true, def: const []);
  static List<String> _$frameworks(WorkspaceDiscoveryProfile v) => v.frameworks;
  static const Field<WorkspaceDiscoveryProfile, List<String>> _f$frameworks =
      Field('frameworks', _$frameworks, opt: true, def: const []);
  static bool _$treeTruncated(WorkspaceDiscoveryProfile v) => v.treeTruncated;
  static const Field<WorkspaceDiscoveryProfile, bool> _f$treeTruncated = Field(
    'treeTruncated',
    _$treeTruncated,
    opt: true,
    def: false,
  );
  static bool _$contentTruncated(WorkspaceDiscoveryProfile v) =>
      v.contentTruncated;
  static const Field<WorkspaceDiscoveryProfile, bool> _f$contentTruncated =
      Field('contentTruncated', _$contentTruncated, opt: true, def: false);
  static int _$omittedPathCount(WorkspaceDiscoveryProfile v) =>
      v.omittedPathCount;
  static const Field<WorkspaceDiscoveryProfile, int> _f$omittedPathCount =
      Field('omittedPathCount', _$omittedPathCount, opt: true, def: 0);

  @override
  final MappableFields<WorkspaceDiscoveryProfile> fields = const {
    #workspaceName: _f$workspaceName,
    #treePaths: _f$treePaths,
    #highSignalFiles: _f$highSignalFiles,
    #packageName: _f$packageName,
    #scripts: _f$scripts,
    #dependencies: _f$dependencies,
    #languages: _f$languages,
    #frameworks: _f$frameworks,
    #treeTruncated: _f$treeTruncated,
    #contentTruncated: _f$contentTruncated,
    #omittedPathCount: _f$omittedPathCount,
  };
  @override
  final bool ignoreNull = true;

  static WorkspaceDiscoveryProfile _instantiate(DecodingData data) {
    return WorkspaceDiscoveryProfile(
      workspaceName: data.dec(_f$workspaceName),
      treePaths: data.dec(_f$treePaths),
      highSignalFiles: data.dec(_f$highSignalFiles),
      packageName: data.dec(_f$packageName),
      scripts: data.dec(_f$scripts),
      dependencies: data.dec(_f$dependencies),
      languages: data.dec(_f$languages),
      frameworks: data.dec(_f$frameworks),
      treeTruncated: data.dec(_f$treeTruncated),
      contentTruncated: data.dec(_f$contentTruncated),
      omittedPathCount: data.dec(_f$omittedPathCount),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkspaceDiscoveryProfile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkspaceDiscoveryProfile>(map);
  }

  static WorkspaceDiscoveryProfile fromJson(String json) {
    return ensureInitialized().decodeJson<WorkspaceDiscoveryProfile>(json);
  }
}

/// @nodoc
mixin WorkspaceDiscoveryProfileMappable {
  String toJson() {
    return WorkspaceDiscoveryProfileMapper.ensureInitialized()
        .encodeJson<WorkspaceDiscoveryProfile>(
          this as WorkspaceDiscoveryProfile,
        );
  }

  Map<String, dynamic> toMap() {
    return WorkspaceDiscoveryProfileMapper.ensureInitialized()
        .encodeMap<WorkspaceDiscoveryProfile>(
          this as WorkspaceDiscoveryProfile,
        );
  }
}

/// @nodoc
class WorkspaceFileExcerptMapper extends ClassMapperBase<WorkspaceFileExcerpt> {
  WorkspaceFileExcerptMapper._();

  static WorkspaceFileExcerptMapper? _instance;
  static WorkspaceFileExcerptMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceFileExcerptMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'WorkspaceFileExcerpt';

  static String _$path(WorkspaceFileExcerpt v) => v.path;
  static const Field<WorkspaceFileExcerpt, String> _f$path = Field(
    'path',
    _$path,
  );
  static String _$content(WorkspaceFileExcerpt v) => v.content;
  static const Field<WorkspaceFileExcerpt, String> _f$content = Field(
    'content',
    _$content,
  );
  static bool _$truncated(WorkspaceFileExcerpt v) => v.truncated;
  static const Field<WorkspaceFileExcerpt, bool> _f$truncated = Field(
    'truncated',
    _$truncated,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<WorkspaceFileExcerpt> fields = const {
    #path: _f$path,
    #content: _f$content,
    #truncated: _f$truncated,
  };

  static WorkspaceFileExcerpt _instantiate(DecodingData data) {
    return WorkspaceFileExcerpt(
      path: data.dec(_f$path),
      content: data.dec(_f$content),
      truncated: data.dec(_f$truncated),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkspaceFileExcerpt fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkspaceFileExcerpt>(map);
  }

  static WorkspaceFileExcerpt fromJson(String json) {
    return ensureInitialized().decodeJson<WorkspaceFileExcerpt>(json);
  }
}

/// @nodoc
mixin WorkspaceFileExcerptMappable {
  String toJson() {
    return WorkspaceFileExcerptMapper.ensureInitialized()
        .encodeJson<WorkspaceFileExcerpt>(this as WorkspaceFileExcerpt);
  }

  Map<String, dynamic> toMap() {
    return WorkspaceFileExcerptMapper.ensureInitialized()
        .encodeMap<WorkspaceFileExcerpt>(this as WorkspaceFileExcerpt);
  }
}

