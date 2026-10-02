import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';

/// Applies explicit user-authored graph edits. User entries are confirmed and
/// protected so planner revisions cannot silently overwrite them.
class ProjectWorkspaceGraphService {
  const ProjectWorkspaceGraphService();

  ProjectAggregate upsertUserNode({
    required ProjectAggregate project,
    String? id,
    required String type,
    required String title,
    String description = '',
    List<String> aliases = const [],
    List<String> tags = const [],
    List<String> references = const [],
    String? sourceId,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final graph = project.workspaceGraph;
    final resolvedId = id?.trim().isNotEmpty == true
        ? _boundedText(id!, 'id')
        : 'workspace_node_${uuid.v7()}';
    final existing = graph.nodes
        .where((node) => node.id == resolvedId)
        .firstOrNull;
    if (existing == null &&
        graph.nodes.length >= ProjectWorkspaceContextService.maxNodes) {
      throw ArgumentError(
        'A workspace graph may contain at most '
        '${ProjectWorkspaceContextService.maxNodes} nodes.',
      );
    }
    final node = ProjectWorkspaceNode(
      id: resolvedId,
      type: _boundedText(type, 'type').toLowerCase(),
      title: _boundedText(title, 'title'),
      description: _boundedText(
        description,
        'description',
        maxLength: 2000,
        allowEmpty: true,
      ),
      aliases: _boundedList(aliases, 'aliases'),
      tags: _boundedList(tags, 'tags'),
      references: _boundedList(references, 'references'),
      sourceType: ProjectWorkspaceSourceType.user,
      sourceId: sourceId == null
          ? null
          : _boundedText(sourceId, 'sourceId', allowEmpty: true),
      confidence: ProjectWorkspaceConfidence.confirmed,
      protected: true,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final nodes = [
      for (final item in graph.nodes)
        if (item.id != resolvedId) item,
      node,
    ];
    return project.copyWith(
      workspaceGraph: graph.copyWith(nodes: nodes, updatedAt: now),
      updatedAt: now,
    );
  }

  ProjectAggregate upsertUserEdge({
    required ProjectAggregate project,
    String? id,
    required String sourceNodeId,
    required String targetNodeId,
    required String label,
    String description = '',
    String? sourceId,
    DateTime? timestamp,
  }) {
    final source = _required(sourceNodeId, 'sourceNodeId');
    final target = _required(targetNodeId, 'targetNodeId');
    if (source == target) {
      throw ArgumentError('A workspace edge cannot point to itself.');
    }
    final graph = project.workspaceGraph;
    if (!graph.nodes.any((node) => node.id == source) ||
        !graph.nodes.any((node) => node.id == target)) {
      throw ArgumentError(
        'Workspace edge endpoints must refer to existing nodes.',
      );
    }
    final now = timestamp ?? DateTime.now();
    final resolvedId = id?.trim().isNotEmpty == true
        ? _boundedText(id!, 'id')
        : 'workspace_edge_${uuid.v7()}';
    final existing = graph.edges
        .where((edge) => edge.id == resolvedId)
        .firstOrNull;
    if (existing == null &&
        graph.edges.length >= ProjectWorkspaceContextService.maxEdges) {
      throw ArgumentError(
        'A workspace graph may contain at most '
        '${ProjectWorkspaceContextService.maxEdges} edges.',
      );
    }
    final edge = ProjectWorkspaceEdge(
      id: resolvedId,
      sourceNodeId: source,
      targetNodeId: target,
      label: _boundedText(label, 'label'),
      description: _boundedText(
        description,
        'description',
        maxLength: 1000,
        allowEmpty: true,
      ),
      sourceType: ProjectWorkspaceSourceType.user,
      sourceId: sourceId == null
          ? null
          : _boundedText(sourceId, 'sourceId', allowEmpty: true),
      confidence: ProjectWorkspaceConfidence.confirmed,
      protected: true,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final edges = [
      for (final item in graph.edges)
        if (item.id != resolvedId) item,
      edge,
    ];
    return project.copyWith(
      workspaceGraph: graph.copyWith(edges: edges, updatedAt: now),
      updatedAt: now,
    );
  }

  static String _required(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError('$field is required.');
    return trimmed;
  }

  static String _boundedText(
    String value,
    String field, {
    int maxLength = 200,
    bool allowEmpty = false,
  }) {
    final text = value.trim();
    if (!allowEmpty && text.isEmpty) {
      throw ArgumentError('$field is required.');
    }
    if (text.length > maxLength) {
      throw ArgumentError('$field must be at most $maxLength characters.');
    }
    return text;
  }

  static List<String> _boundedList(Iterable<String> values, String field) {
    final result = [
      for (final value in values)
        if (value.trim().isNotEmpty) value.trim(),
    ];
    if (result.length > 20) {
      throw ArgumentError('$field may contain at most 20 values.');
    }
    for (final value in result) {
      if (value.length > 200) {
        throw ArgumentError('Values in $field must be at most 200 characters.');
      }
    }
    return result;
  }
}
