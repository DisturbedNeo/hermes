// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'project_workspace_graph.dart';

/// @nodoc

class ProjectWorkspaceSourceTypeMapper
    extends EnumMapper<ProjectWorkspaceSourceType> {
  ProjectWorkspaceSourceTypeMapper._();

  static ProjectWorkspaceSourceTypeMapper? _instance;
  static ProjectWorkspaceSourceTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectWorkspaceSourceTypeMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectWorkspaceSourceType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectWorkspaceSourceType decode(dynamic value) {
    switch (value) {
      case r'user':
        return ProjectWorkspaceSourceType.user;
      case r'planner':
        return ProjectWorkspaceSourceType.planner;
      case r'task':
        return ProjectWorkspaceSourceType.task;
      case r'system':
        return ProjectWorkspaceSourceType.system;
      default:
        return ProjectWorkspaceSourceType.values[3];
    }
  }

  @override
  dynamic encode(ProjectWorkspaceSourceType self) {
    switch (self) {
      case ProjectWorkspaceSourceType.user:
        return r'user';
      case ProjectWorkspaceSourceType.planner:
        return r'planner';
      case ProjectWorkspaceSourceType.task:
        return r'task';
      case ProjectWorkspaceSourceType.system:
        return r'system';
    }
  }
}

/// @nodoc

extension ProjectWorkspaceSourceTypeMapperExtension
    on ProjectWorkspaceSourceType {
  String toValue() {
    ProjectWorkspaceSourceTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectWorkspaceSourceType>(this)
        as String;
  }
}

/// @nodoc

class ProjectWorkspaceConfidenceMapper
    extends EnumMapper<ProjectWorkspaceConfidence> {
  ProjectWorkspaceConfidenceMapper._();

  static ProjectWorkspaceConfidenceMapper? _instance;
  static ProjectWorkspaceConfidenceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectWorkspaceConfidenceMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectWorkspaceConfidence fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectWorkspaceConfidence decode(dynamic value) {
    switch (value) {
      case r'confirmed':
        return ProjectWorkspaceConfidence.confirmed;
      case r'inferred':
        return ProjectWorkspaceConfidence.inferred;
      case r'uncertain':
        return ProjectWorkspaceConfidence.uncertain;
      default:
        return ProjectWorkspaceConfidence.values[1];
    }
  }

  @override
  dynamic encode(ProjectWorkspaceConfidence self) {
    switch (self) {
      case ProjectWorkspaceConfidence.confirmed:
        return r'confirmed';
      case ProjectWorkspaceConfidence.inferred:
        return r'inferred';
      case ProjectWorkspaceConfidence.uncertain:
        return r'uncertain';
    }
  }
}

/// @nodoc

extension ProjectWorkspaceConfidenceMapperExtension
    on ProjectWorkspaceConfidence {
  String toValue() {
    ProjectWorkspaceConfidenceMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectWorkspaceConfidence>(this)
        as String;
  }
}

/// @nodoc
class ProjectWorkspaceNodeMapper extends ClassMapperBase<ProjectWorkspaceNode> {
  ProjectWorkspaceNodeMapper._();

  static ProjectWorkspaceNodeMapper? _instance;
  static ProjectWorkspaceNodeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectWorkspaceNodeMapper._());
      ProjectWorkspaceSourceTypeMapper.ensureInitialized();
      ProjectWorkspaceConfidenceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectWorkspaceNode';

  static String _$id(ProjectWorkspaceNode v) => v.id;
  static const Field<ProjectWorkspaceNode, String> _f$id = Field('id', _$id);
  static String _$type(ProjectWorkspaceNode v) => v.type;
  static const Field<ProjectWorkspaceNode, String> _f$type = Field(
    'type',
    _$type,
  );
  static String _$title(ProjectWorkspaceNode v) => v.title;
  static const Field<ProjectWorkspaceNode, String> _f$title = Field(
    'title',
    _$title,
  );
  static String _$description(ProjectWorkspaceNode v) => v.description;
  static const Field<ProjectWorkspaceNode, String> _f$description = Field(
    'description',
    _$description,
  );
  static List<String> _$aliases(ProjectWorkspaceNode v) => v.aliases;
  static const Field<ProjectWorkspaceNode, List<String>> _f$aliases = Field(
    'aliases',
    _$aliases,
    opt: true,
    def: const [],
  );
  static List<String> _$tags(ProjectWorkspaceNode v) => v.tags;
  static const Field<ProjectWorkspaceNode, List<String>> _f$tags = Field(
    'tags',
    _$tags,
    opt: true,
    def: const [],
  );
  static List<String> _$references(ProjectWorkspaceNode v) => v.references;
  static const Field<ProjectWorkspaceNode, List<String>> _f$references = Field(
    'references',
    _$references,
    opt: true,
    def: const [],
  );
  static ProjectWorkspaceSourceType _$sourceType(ProjectWorkspaceNode v) =>
      v.sourceType;
  static const Field<ProjectWorkspaceNode, ProjectWorkspaceSourceType>
  _f$sourceType = Field(
    'sourceType',
    _$sourceType,
    opt: true,
    def: ProjectWorkspaceSourceType.system,
  );
  static String? _$sourceId(ProjectWorkspaceNode v) => v.sourceId;
  static const Field<ProjectWorkspaceNode, String> _f$sourceId = Field(
    'sourceId',
    _$sourceId,
    opt: true,
  );
  static ProjectWorkspaceConfidence _$confidence(ProjectWorkspaceNode v) =>
      v.confidence;
  static const Field<ProjectWorkspaceNode, ProjectWorkspaceConfidence>
  _f$confidence = Field(
    'confidence',
    _$confidence,
    opt: true,
    def: ProjectWorkspaceConfidence.inferred,
  );
  static bool _$protected(ProjectWorkspaceNode v) => v.protected;
  static const Field<ProjectWorkspaceNode, bool> _f$protected = Field(
    'protected',
    _$protected,
    opt: true,
    def: false,
  );
  static DateTime _$createdAt(ProjectWorkspaceNode v) => v.createdAt;
  static const Field<ProjectWorkspaceNode, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(ProjectWorkspaceNode v) => v.updatedAt;
  static const Field<ProjectWorkspaceNode, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );

  @override
  final MappableFields<ProjectWorkspaceNode> fields = const {
    #id: _f$id,
    #type: _f$type,
    #title: _f$title,
    #description: _f$description,
    #aliases: _f$aliases,
    #tags: _f$tags,
    #references: _f$references,
    #sourceType: _f$sourceType,
    #sourceId: _f$sourceId,
    #confidence: _f$confidence,
    #protected: _f$protected,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectWorkspaceNode _instantiate(DecodingData data) {
    return ProjectWorkspaceNode(
      id: data.dec(_f$id),
      type: data.dec(_f$type),
      title: data.dec(_f$title),
      description: data.dec(_f$description),
      aliases: data.dec(_f$aliases),
      tags: data.dec(_f$tags),
      references: data.dec(_f$references),
      sourceType: data.dec(_f$sourceType),
      sourceId: data.dec(_f$sourceId),
      confidence: data.dec(_f$confidence),
      protected: data.dec(_f$protected),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectWorkspaceNode fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectWorkspaceNode>(map);
  }

  static ProjectWorkspaceNode fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectWorkspaceNode>(json);
  }
}

/// @nodoc
mixin ProjectWorkspaceNodeMappable {
  String toJson() {
    return ProjectWorkspaceNodeMapper.ensureInitialized()
        .encodeJson<ProjectWorkspaceNode>(this as ProjectWorkspaceNode);
  }

  Map<String, dynamic> toMap() {
    return ProjectWorkspaceNodeMapper.ensureInitialized()
        .encodeMap<ProjectWorkspaceNode>(this as ProjectWorkspaceNode);
  }
}

/// @nodoc
class ProjectWorkspaceEdgeMapper extends ClassMapperBase<ProjectWorkspaceEdge> {
  ProjectWorkspaceEdgeMapper._();

  static ProjectWorkspaceEdgeMapper? _instance;
  static ProjectWorkspaceEdgeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectWorkspaceEdgeMapper._());
      ProjectWorkspaceSourceTypeMapper.ensureInitialized();
      ProjectWorkspaceConfidenceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectWorkspaceEdge';

  static String _$id(ProjectWorkspaceEdge v) => v.id;
  static const Field<ProjectWorkspaceEdge, String> _f$id = Field('id', _$id);
  static String _$sourceNodeId(ProjectWorkspaceEdge v) => v.sourceNodeId;
  static const Field<ProjectWorkspaceEdge, String> _f$sourceNodeId = Field(
    'sourceNodeId',
    _$sourceNodeId,
  );
  static String _$targetNodeId(ProjectWorkspaceEdge v) => v.targetNodeId;
  static const Field<ProjectWorkspaceEdge, String> _f$targetNodeId = Field(
    'targetNodeId',
    _$targetNodeId,
  );
  static String _$label(ProjectWorkspaceEdge v) => v.label;
  static const Field<ProjectWorkspaceEdge, String> _f$label = Field(
    'label',
    _$label,
  );
  static String _$description(ProjectWorkspaceEdge v) => v.description;
  static const Field<ProjectWorkspaceEdge, String> _f$description = Field(
    'description',
    _$description,
    opt: true,
    def: '',
  );
  static ProjectWorkspaceSourceType _$sourceType(ProjectWorkspaceEdge v) =>
      v.sourceType;
  static const Field<ProjectWorkspaceEdge, ProjectWorkspaceSourceType>
  _f$sourceType = Field(
    'sourceType',
    _$sourceType,
    opt: true,
    def: ProjectWorkspaceSourceType.system,
  );
  static String? _$sourceId(ProjectWorkspaceEdge v) => v.sourceId;
  static const Field<ProjectWorkspaceEdge, String> _f$sourceId = Field(
    'sourceId',
    _$sourceId,
    opt: true,
  );
  static ProjectWorkspaceConfidence _$confidence(ProjectWorkspaceEdge v) =>
      v.confidence;
  static const Field<ProjectWorkspaceEdge, ProjectWorkspaceConfidence>
  _f$confidence = Field(
    'confidence',
    _$confidence,
    opt: true,
    def: ProjectWorkspaceConfidence.inferred,
  );
  static bool _$protected(ProjectWorkspaceEdge v) => v.protected;
  static const Field<ProjectWorkspaceEdge, bool> _f$protected = Field(
    'protected',
    _$protected,
    opt: true,
    def: false,
  );
  static DateTime _$createdAt(ProjectWorkspaceEdge v) => v.createdAt;
  static const Field<ProjectWorkspaceEdge, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(ProjectWorkspaceEdge v) => v.updatedAt;
  static const Field<ProjectWorkspaceEdge, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );

  @override
  final MappableFields<ProjectWorkspaceEdge> fields = const {
    #id: _f$id,
    #sourceNodeId: _f$sourceNodeId,
    #targetNodeId: _f$targetNodeId,
    #label: _f$label,
    #description: _f$description,
    #sourceType: _f$sourceType,
    #sourceId: _f$sourceId,
    #confidence: _f$confidence,
    #protected: _f$protected,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectWorkspaceEdge _instantiate(DecodingData data) {
    return ProjectWorkspaceEdge(
      id: data.dec(_f$id),
      sourceNodeId: data.dec(_f$sourceNodeId),
      targetNodeId: data.dec(_f$targetNodeId),
      label: data.dec(_f$label),
      description: data.dec(_f$description),
      sourceType: data.dec(_f$sourceType),
      sourceId: data.dec(_f$sourceId),
      confidence: data.dec(_f$confidence),
      protected: data.dec(_f$protected),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectWorkspaceEdge fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectWorkspaceEdge>(map);
  }

  static ProjectWorkspaceEdge fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectWorkspaceEdge>(json);
  }
}

/// @nodoc
mixin ProjectWorkspaceEdgeMappable {
  String toJson() {
    return ProjectWorkspaceEdgeMapper.ensureInitialized()
        .encodeJson<ProjectWorkspaceEdge>(this as ProjectWorkspaceEdge);
  }

  Map<String, dynamic> toMap() {
    return ProjectWorkspaceEdgeMapper.ensureInitialized()
        .encodeMap<ProjectWorkspaceEdge>(this as ProjectWorkspaceEdge);
  }
}

/// @nodoc
class ProjectWorkspaceGraphMapper
    extends ClassMapperBase<ProjectWorkspaceGraph> {
  ProjectWorkspaceGraphMapper._();

  static ProjectWorkspaceGraphMapper? _instance;
  static ProjectWorkspaceGraphMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectWorkspaceGraphMapper._());
      ProjectWorkspaceNodeMapper.ensureInitialized();
      ProjectWorkspaceEdgeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectWorkspaceGraph';

  static String _$orientation(ProjectWorkspaceGraph v) => v.orientation;
  static const Field<ProjectWorkspaceGraph, String> _f$orientation = Field(
    'orientation',
    _$orientation,
    opt: true,
    def: '',
  );
  static List<ProjectWorkspaceNode> _$nodes(ProjectWorkspaceGraph v) => v.nodes;
  static const Field<ProjectWorkspaceGraph, List<ProjectWorkspaceNode>>
  _f$nodes = Field('nodes', _$nodes, opt: true);
  static List<ProjectWorkspaceEdge> _$edges(ProjectWorkspaceGraph v) => v.edges;
  static const Field<ProjectWorkspaceGraph, List<ProjectWorkspaceEdge>>
  _f$edges = Field('edges', _$edges, opt: true);
  static DateTime? _$updatedAt(ProjectWorkspaceGraph v) => v.updatedAt;
  static const Field<ProjectWorkspaceGraph, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    opt: true,
  );

  @override
  final MappableFields<ProjectWorkspaceGraph> fields = const {
    #orientation: _f$orientation,
    #nodes: _f$nodes,
    #edges: _f$edges,
    #updatedAt: _f$updatedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectWorkspaceGraph _instantiate(DecodingData data) {
    return ProjectWorkspaceGraph(
      orientation: data.dec(_f$orientation),
      nodes: data.dec(_f$nodes),
      edges: data.dec(_f$edges),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectWorkspaceGraph fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectWorkspaceGraph>(map);
  }

  static ProjectWorkspaceGraph fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectWorkspaceGraph>(json);
  }
}

/// @nodoc
mixin ProjectWorkspaceGraphMappable {
  String toJson() {
    return ProjectWorkspaceGraphMapper.ensureInitialized()
        .encodeJson<ProjectWorkspaceGraph>(this as ProjectWorkspaceGraph);
  }

  Map<String, dynamic> toMap() {
    return ProjectWorkspaceGraphMapper.ensureInitialized()
        .encodeMap<ProjectWorkspaceGraph>(this as ProjectWorkspaceGraph);
  }
}

