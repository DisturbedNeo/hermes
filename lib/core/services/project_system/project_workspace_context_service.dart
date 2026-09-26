import 'package:hermes/core/models/project.dart';

/// A bounded, task-oriented projection of the durable workspace graph.
class ProjectWorkspaceContextSelection {
  const ProjectWorkspaceContextSelection({
    required this.orientation,
    required this.nodes,
    required this.edges,
    required this.maxCharacters,
    required this.usedCharacters,
    required this.truncated,
  });

  final String orientation;
  final List<ProjectWorkspaceNode> nodes;
  final List<ProjectWorkspaceEdge> edges;
  final int maxCharacters;
  final int usedCharacters;
  final bool truncated;

  List<String> get lines => [
    for (final node in nodes) _nodeLine(node),
    for (final edge in edges) _edgeLine(edge, nodes),
  ];

  Map<String, dynamic> toMap({int maxItems = 24}) {
    final boundedNodes = nodes.take(maxItems).toList();
    final boundedEdges = edges.take(maxItems * 2).toList();
    final fieldsTruncated = boundedNodes.any(
      (node) =>
          node.aliases.length > maxItems ||
          node.tags.length > maxItems ||
          node.references.length > maxItems,
    );
    return {
      'orientation': orientation,
      'nodes': [for (final node in boundedNodes) _nodeMap(node, maxItems)],
      'edges': [for (final edge in boundedEdges) _edgeMap(edge)],
      'truncated':
          truncated ||
          nodes.length > maxItems ||
          edges.length > maxItems * 2 ||
          fieldsTruncated,
      'used_characters': usedCharacters,
      'max_characters': maxCharacters,
    };
  }

  static String _nodeLine(ProjectWorkspaceNode node) {
    final metadata = [
      if (node.aliases.isNotEmpty) 'aliases: ${node.aliases.join(', ')}',
      if (node.tags.isNotEmpty) 'tags: ${node.tags.join(', ')}',
      if (node.references.isNotEmpty)
        'references: ${node.references.join(', ')}',
      'source: ${node.sourceType.name}'
          '${node.sourceId == null ? '' : '/${node.sourceId}'}'
          '/${node.confidence.name}',
    ].join('; ');
    return '[${node.id}] ${node.type}: ${node.title} — '
        '${node.description}${metadata.isEmpty ? '' : ' ($metadata)'}';
  }

  static String _edgeLine(
    ProjectWorkspaceEdge edge,
    List<ProjectWorkspaceNode> nodes,
  ) {
    String title(String id) =>
        nodes
            .where((node) => node.id == id)
            .map((node) => node.title)
            .firstOrNull ??
        id;
    final description = edge.description.trim().isEmpty
        ? ''
        : ' — ${edge.description.trim()}';
    return '${title(edge.sourceNodeId)} -[${edge.label}]-> '
        '${title(edge.targetNodeId)}$description '
        '(${edge.sourceType.name}'
        '${edge.sourceId == null ? '' : '/${edge.sourceId}'}'
        '/${edge.confidence.name})';
  }

  static Map<String, dynamic> _nodeMap(
    ProjectWorkspaceNode node,
    int maxItems,
  ) => {
    'id': node.id,
    'type': node.type,
    'title': node.title,
    'description': node.description,
    'aliases': node.aliases.take(maxItems).toList(),
    'tags': node.tags.take(maxItems).toList(),
    'references': node.references.take(maxItems).toList(),
    'source': node.sourceType.name,
    'source_id': node.sourceId,
    'confidence': node.confidence.name,
    'protected': node.protected,
  };

  static Map<String, dynamic> _edgeMap(ProjectWorkspaceEdge edge) => {
    'id': edge.id,
    'source_node_id': edge.sourceNodeId,
    'target_node_id': edge.targetNodeId,
    'label': edge.label,
    'description': edge.description,
    'source': edge.sourceType.name,
    'source_id': edge.sourceId,
    'confidence': edge.confidence.name,
    'protected': edge.protected,
  };
}

/// Selects relevant graph context without invoking a model or touching the
/// workspace. The same deterministic selection is used by task prompts and
/// project inspection views.
class ProjectWorkspaceContextService {
  const ProjectWorkspaceContextService();

  static const int maxNodes = 200;
  static const int maxEdges = 500;
  static const int defaultContextCharacters = 8000;
  static const int defaultMaxNodes = 24;
  static const int defaultMaxEdges = 48;

  ProjectWorkspaceContextSelection selectContext({
    required ProjectDocument project,
    ProjectTaskNode? task,
    int maxCharacters = defaultContextCharacters,
    int maxSelectedNodes = defaultMaxNodes,
    int maxSelectedEdges = defaultMaxEdges,
  }) {
    if (maxCharacters < 0) {
      throw ArgumentError.value(
        maxCharacters,
        'maxCharacters',
        'Workspace context budget cannot be negative.',
      );
    }
    if (maxSelectedNodes < 0) {
      throw ArgumentError.value(
        maxSelectedNodes,
        'maxSelectedNodes',
        'Workspace node selection cannot be negative.',
      );
    }
    if (maxSelectedEdges < 0) {
      throw ArgumentError.value(
        maxSelectedEdges,
        'maxSelectedEdges',
        'Workspace edge selection cannot be negative.',
      );
    }
    final nodeLimit = maxSelectedNodes.clamp(0, defaultMaxNodes).toInt();
    final edgeLimit = maxSelectedEdges.clamp(0, defaultMaxEdges).toInt();
    final terms = _terms(project, task);
    final ranked =
        [
          for (final node in project.workspaceGraph.nodes)
            _RankedNode(node, _score(node, terms)),
        ]..sort((a, b) {
          final score = b.score.compareTo(a.score);
          if (score != 0) return score;
          return a.node.id.compareTo(b.node.id);
        });

    final selectedNodes = <ProjectWorkspaceNode>[];
    var used = project.workspaceGraph.orientation.trim().length;
    final orientation = _truncate(
      project.workspaceGraph.orientation.trim(),
      maxCharacters,
    );
    used = orientation.length;
    var truncated =
        orientation.length < project.workspaceGraph.orientation.trim().length;
    for (final rankedNode in ranked) {
      if (selectedNodes.length >= nodeLimit) {
        truncated = true;
        break;
      }
      final line = ProjectWorkspaceContextSelection._nodeLine(rankedNode.node);
      final separator = selectedNodes.isEmpty && used == 0 ? 0 : 1;
      if (used + separator + line.length > maxCharacters) {
        truncated = true;
        continue;
      }
      selectedNodes.add(rankedNode.node);
      used += separator + line.length;
    }

    final selectedIds = selectedNodes.map((node) => node.id).toSet();
    final selectedEdges = <ProjectWorkspaceEdge>[];
    final edges = [...project.workspaceGraph.edges]
      ..sort((a, b) {
        final label = a.label.compareTo(b.label);
        return label != 0 ? label : a.id.compareTo(b.id);
      });
    for (final edge in edges) {
      if (selectedEdges.length >= edgeLimit) {
        truncated = true;
        break;
      }
      if (!selectedIds.contains(edge.sourceNodeId) ||
          !selectedIds.contains(edge.targetNodeId)) {
        continue;
      }
      final line = ProjectWorkspaceContextSelection._edgeLine(
        edge,
        selectedNodes,
      );
      final separator = used == 0 ? 0 : 1;
      if (used + separator + line.length > maxCharacters) {
        truncated = true;
        continue;
      }
      selectedEdges.add(edge);
      used += separator + line.length;
    }

    return ProjectWorkspaceContextSelection(
      orientation: orientation,
      nodes: List.unmodifiable(selectedNodes),
      edges: List.unmodifiable(selectedEdges),
      maxCharacters: maxCharacters,
      usedCharacters: used,
      truncated: truncated || ranked.length > selectedNodes.length,
    );
  }

  List<String> _terms(ProjectDocument project, ProjectTaskNode? task) => [
    project.refinedGoal,
    ...project.constraints,
    ...project.criteria.map((item) => item.statement),
    if (task != null) ...[
      task.title,
      task.objective,
      ...task.context,
      ...task.readPaths,
      ...task.writePaths,
      ...task.doneCriteria,
    ],
  ].expand(_tokens).toSet().toList();

  Iterable<String> _tokens(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9_:/.-]+'))
      .where((item) => item.length >= 2);

  int _score(ProjectWorkspaceNode node, List<String> terms) {
    final values = [
      node.type,
      node.title,
      node.description,
      ...node.aliases,
      ...node.tags,
      ...node.references,
    ].join(' ').toLowerCase();
    var score = node.protected ? 2 : 0;
    for (final term in terms) {
      if (values.contains(term)) score += 1;
      if (node.title.toLowerCase().contains(term)) score += 2;
    }
    return score;
  }

  String _truncate(String value, int maxCharacters) {
    if (value.length <= maxCharacters) return value;
    if (maxCharacters <= 3) return value.substring(0, maxCharacters);
    return '${value.substring(0, maxCharacters - 3)}...';
  }
}

class _RankedNode {
  const _RankedNode(this.node, this.score);

  final ProjectWorkspaceNode node;
  final int score;
}
