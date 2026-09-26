import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;

part 'project_workspace_graph.mapper.dart';

/// Identifies who supplied a workspace-graph entry.
@MappableEnum(defaultValue: ProjectWorkspaceSourceType.system)
enum ProjectWorkspaceSourceType { user, planner, task, system }

/// Confidence attached to a graph entry without making it part of execution
/// state. User-authored entries are normally confirmed; planner discoveries
/// are normally inferred.
@MappableEnum(defaultValue: ProjectWorkspaceConfidence.inferred)
enum ProjectWorkspaceConfidence { confirmed, inferred, uncertain }

/// A domain-neutral concept or artifact in a project's workspace model.
@MappableClass(ignoreNull: true)
class ProjectWorkspaceNode with ProjectWorkspaceNodeMappable {
  const ProjectWorkspaceNode({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.aliases = const [],
    this.tags = const [],
    this.references = const [],
    this.sourceType = ProjectWorkspaceSourceType.system,
    this.sourceId,
    this.confidence = ProjectWorkspaceConfidence.inferred,
    this.protected = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String type;
  final String title;
  final String description;
  final List<String> aliases;
  final List<String> tags;
  final List<String> references;
  final ProjectWorkspaceSourceType sourceType;
  final String? sourceId;
  final ProjectWorkspaceConfidence confidence;
  final bool protected;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectWorkspaceNode copyWith({
    String? id,
    String? type,
    String? title,
    String? description,
    List<String>? aliases,
    List<String>? tags,
    List<String>? references,
    ProjectWorkspaceSourceType? sourceType,
    Object? sourceId = kSentinel,
    ProjectWorkspaceConfidence? confidence,
    bool? protected,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProjectWorkspaceNode(
    id: id ?? this.id,
    type: type ?? this.type,
    title: title ?? this.title,
    description: description ?? this.description,
    aliases: aliases ?? this.aliases,
    tags: tags ?? this.tags,
    references: references ?? this.references,
    sourceType: sourceType ?? this.sourceType,
    sourceId: resolve(sourceId, this.sourceId),
    confidence: confidence ?? this.confidence,
    protected: protected ?? this.protected,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// A labeled relationship between two workspace concepts.
@MappableClass(ignoreNull: true)
class ProjectWorkspaceEdge with ProjectWorkspaceEdgeMappable {
  const ProjectWorkspaceEdge({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.label,
    this.description = '',
    this.sourceType = ProjectWorkspaceSourceType.system,
    this.sourceId,
    this.confidence = ProjectWorkspaceConfidence.inferred,
    this.protected = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final String label;
  final String description;
  final ProjectWorkspaceSourceType sourceType;
  final String? sourceId;
  final ProjectWorkspaceConfidence confidence;
  final bool protected;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectWorkspaceEdge copyWith({
    String? id,
    String? sourceNodeId,
    String? targetNodeId,
    String? label,
    String? description,
    ProjectWorkspaceSourceType? sourceType,
    Object? sourceId = kSentinel,
    ProjectWorkspaceConfidence? confidence,
    bool? protected,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProjectWorkspaceEdge(
    id: id ?? this.id,
    sourceNodeId: sourceNodeId ?? this.sourceNodeId,
    targetNodeId: targetNodeId ?? this.targetNodeId,
    label: label ?? this.label,
    description: description ?? this.description,
    sourceType: sourceType ?? this.sourceType,
    sourceId: resolve(sourceId, this.sourceId),
    confidence: confidence ?? this.confidence,
    protected: protected ?? this.protected,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// The durable, project-local orientation graph.
@MappableClass(ignoreNull: true)
class ProjectWorkspaceGraph with ProjectWorkspaceGraphMappable {
  ProjectWorkspaceGraph({
    this.orientation = '',
    List<ProjectWorkspaceNode>? nodes,
    List<ProjectWorkspaceEdge>? edges,
    this.updatedAt,
  }) : nodes = List.unmodifiable(nodes ?? const []),
       edges = List.unmodifiable(edges ?? const []);

  final String orientation;
  final List<ProjectWorkspaceNode> nodes;
  final List<ProjectWorkspaceEdge> edges;
  final DateTime? updatedAt;

  const ProjectWorkspaceGraph.empty()
    : orientation = '',
      nodes = const [],
      edges = const [],
      updatedAt = null;

  ProjectWorkspaceGraph copyWith({
    String? orientation,
    List<ProjectWorkspaceNode>? nodes,
    List<ProjectWorkspaceEdge>? edges,
    Object? updatedAt = kSentinel,
  }) => ProjectWorkspaceGraph(
    orientation: orientation ?? this.orientation,
    nodes: nodes ?? this.nodes,
    edges: edges ?? this.edges,
    updatedAt: resolve(updatedAt, this.updatedAt),
  );
}

/// Planner-only node input. Runtime metadata and IDs are assigned by Hermes.
class ProjectWorkspaceNodeSpec {
  const ProjectWorkspaceNodeSpec({
    this.ref = '',
    this.type = '',
    this.title = '',
    this.description = '',
    this.aliases = const [],
    this.tags = const [],
    this.references = const [],
  });

  final String ref;
  final String type;
  final String title;
  final String description;
  final List<String> aliases;
  final List<String> tags;
  final List<String> references;
}

/// Planner-only edge input. Node references are resolved by the builder.
class ProjectWorkspaceEdgeSpec {
  const ProjectWorkspaceEdgeSpec({
    this.ref = '',
    this.sourceRef = '',
    this.targetRef = '',
    this.label = '',
    this.description = '',
  });

  final String ref;
  final String sourceRef;
  final String targetRef;
  final String label;
  final String description;
}
