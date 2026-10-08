part of 'project_plan_builder.dart';

extension ProjectPlanBuilderWorkspaceCommands on ProjectPlanBuilder {
  void setWorkspaceOrientation(String orientation, {String? commandId}) {
    final fingerprint = _encode({
      'op': 'set_workspace_orientation',
      'orientation': orientation.trim(),
    });
    _idempotent(commandId, fingerprint, () {
      _workspaceOrientation = _boundedText(
        orientation,
        'orientation',
        maxLength: 4000,
        allowEmpty: true,
      );
    });
  }

  List<String> addWorkspaceNodes(
    Iterable<ProjectWorkspaceNodeSpec> specs, {
    String? commandId,
  }) {
    final values = [...specs];
    if (values.isEmpty) {
      throw _error(
        'missing_workspace_nodes',
        'nodes',
        'At least one workspace node is required.',
      );
    }
    final fingerprint = _encode({
      'op': 'add_workspace_nodes',
      'nodes': [for (final spec in values) _workspaceNodeSpecMap(spec)],
    });
    return _idempotent(
      commandId,
      fingerprint,
      () => _atomic(() {
        final ids = <String>[];
        for (var index = 0; index < values.length; index++) {
          final spec = values[index];
          final type = _boundedText(spec.type, 'nodes[$index].type');
          final title = _boundedText(spec.title, 'nodes[$index].title');
          final id = _newId('workspace_node', _workspaceNodes.keys);
          final reference = _claimWorkspaceReference(
            spec.ref,
            namespace: 'workspace_node',
            fallback: _slug(title),
          );
          final now = _now;
          _workspaceNodes[id] = ProjectWorkspaceNode(
            id: id,
            type: type.toLowerCase(),
            title: title,
            description: _boundedText(
              spec.description,
              'nodes[$index].description',
              maxLength: 2000,
              allowEmpty: true,
            ),
            aliases: _boundedList(spec.aliases, 'nodes[$index].aliases'),
            tags: _boundedList(spec.tags, 'nodes[$index].tags'),
            references: _boundedList(
              spec.references,
              'nodes[$index].references',
            ),
            sourceType: ProjectWorkspaceSourceType.planner,
            sourceId: 'plan_revision_${_project.nextRevision}',
            confidence: ProjectWorkspaceConfidence.inferred,
            createdAt: now,
            updatedAt: now,
          );
          ids.add(id);
          _workspaceNodeRefs[reference] = id;
          _workspaceNodeRefs[id] = id;
        }
        return ids;
      }),
    );
  }

  String updateWorkspaceNode(
    String reference, {
    String? type,
    String? title,
    String? description,
    List<String>? aliases,
    List<String>? tags,
    List<String>? references,
    String? commandId,
  }) {
    final id = _resolveWorkspaceNode(reference);
    final existing = _workspaceNodes[id]!;
    if (existing.managedKey != null) {
      throw _error(
        'managed_workspace_node',
        'node',
        'Managed workspace node $id cannot be changed by the planner.',
      );
    }
    if (existing.protected) {
      throw _error(
        'protected_workspace_node',
        'node',
        'Protected workspace node $id cannot be changed by the planner.',
      );
    }
    final fingerprint = _encode({
      'op': 'update_workspace_node',
      'id': id,
      'type': type,
      'title': title,
      'description': description,
      'aliases': aliases,
      'tags': tags,
      'references': references,
    });
    return _idempotent(commandId, fingerprint, () {
      _workspaceNodes[id] = existing.copyWith(
        type: type == null
            ? existing.type
            : _boundedText(type, 'type').toLowerCase(),
        title: title == null ? existing.title : _boundedText(title, 'title'),
        description: description == null
            ? existing.description
            : _boundedText(
                description,
                'description',
                maxLength: 2000,
                allowEmpty: true,
              ),
        aliases: aliases == null
            ? existing.aliases
            : _boundedList(aliases, 'aliases'),
        tags: tags == null ? existing.tags : _boundedList(tags, 'tags'),
        references: references == null
            ? existing.references
            : _boundedList(references, 'references'),
        updatedAt: _now,
      );
      return id;
    });
  }

  List<String> addWorkspaceEdges(
    Iterable<ProjectWorkspaceEdgeSpec> specs, {
    String? commandId,
  }) {
    final values = [...specs];
    if (values.isEmpty) {
      throw _error(
        'missing_workspace_edges',
        'edges',
        'At least one workspace edge is required.',
      );
    }
    final fingerprint = _encode({
      'op': 'add_workspace_edges',
      'edges': [for (final spec in values) _workspaceEdgeSpecMap(spec)],
    });
    return _idempotent(
      commandId,
      fingerprint,
      () => _atomic(() {
        final ids = <String>[];
        for (var index = 0; index < values.length; index++) {
          final spec = values[index];
          final source = _resolveWorkspaceNode(spec.sourceRef);
          final target = _resolveWorkspaceNode(spec.targetRef);
          if (source == target) {
            throw _error(
              'self_workspace_edge',
              'edges[$index]',
              'A workspace edge cannot point from a node to itself.',
            );
          }
          final label = _boundedText(
            spec.label,
            'edges[$index].label',
            maxLength: 200,
          );
          final id = _newId('workspace_edge', _workspaceEdges.keys);
          final reference = _claimWorkspaceReference(
            spec.ref,
            namespace: 'workspace_edge',
            fallback: _slug(label),
            existing: _workspaceEdgeRefs,
          );
          final now = _now;
          _workspaceEdges[id] = ProjectWorkspaceEdge(
            id: id,
            sourceNodeId: source,
            targetNodeId: target,
            label: label,
            description: _boundedText(
              spec.description,
              'edges[$index].description',
              maxLength: 1000,
              allowEmpty: true,
            ),
            sourceType: ProjectWorkspaceSourceType.planner,
            sourceId: 'plan_revision_${_project.nextRevision}',
            confidence: ProjectWorkspaceConfidence.inferred,
            createdAt: now,
            updatedAt: now,
          );
          ids.add(id);
          _workspaceEdgeRefs[reference] = id;
          _workspaceEdgeRefs[id] = id;
        }
        return ids;
      }),
    );
  }

  String updateWorkspaceEdge(
    String reference, {
    String? sourceReference,
    String? targetReference,
    String? label,
    String? description,
    String? commandId,
  }) {
    final id = _resolveWorkspaceEdge(reference);
    final existing = _workspaceEdges[id]!;
    if (existing.managedKey != null) {
      throw _error(
        'managed_workspace_edge',
        'edge',
        'Managed workspace edge $id cannot be changed by the planner.',
      );
    }
    if (existing.protected) {
      throw _error(
        'protected_workspace_edge',
        'edge',
        'Protected workspace edge $id cannot be changed by the planner.',
      );
    }
    final fingerprint = _encode({
      'op': 'update_workspace_edge',
      'id': id,
      'source': sourceReference,
      'target': targetReference,
      'label': label,
      'description': description,
    });
    return _idempotent(commandId, fingerprint, () {
      final source = sourceReference == null
          ? existing.sourceNodeId
          : _resolveWorkspaceNode(sourceReference);
      final target = targetReference == null
          ? existing.targetNodeId
          : _resolveWorkspaceNode(targetReference);
      if (source == target) {
        throw _error(
          'self_workspace_edge',
          'edge',
          'A workspace edge cannot point from a node to itself.',
        );
      }
      _workspaceEdges[id] = existing.copyWith(
        sourceNodeId: source,
        targetNodeId: target,
        label: label == null
            ? existing.label
            : _boundedText(label, 'label', maxLength: 200),
        description: description == null
            ? existing.description
            : _boundedText(
                description,
                'description',
                maxLength: 1000,
                allowEmpty: true,
              ),
        updatedAt: _now,
      );
      return id;
    });
  }

  void removeWorkspaceNode(String reference, {String? commandId}) {
    final fingerprint = _encode({
      'op': 'remove_workspace_node',
      'reference': reference.trim(),
    });
    _idempotent(commandId, fingerprint, () {
      final id = _resolveWorkspaceNode(reference);
      final node = _workspaceNodes[id]!;
      if (node.managedKey != null) {
        throw _error(
          'managed_workspace_node',
          'node',
          'Managed workspace node $id cannot be removed by the planner.',
        );
      }
      if (node.protected) {
        throw _error(
          'protected_workspace_node',
          'node',
          'Protected workspace node $id cannot be removed by the planner.',
        );
      }
      final related = _workspaceEdges.values
          .where((edge) => edge.sourceNodeId == id || edge.targetNodeId == id)
          .toList();
      if (related.any((edge) => edge.protected)) {
        throw _error(
          'protected_workspace_edge',
          'node',
          'A node with protected relationships cannot be removed by the planner.',
        );
      }
      _workspaceNodes.remove(id);
      _workspaceNodeRefs.removeWhere((key, value) => value == id);
      for (final edge in related) {
        _workspaceEdges.remove(edge.id);
        _workspaceEdgeRefs.removeWhere((key, value) => value == edge.id);
      }
    });
  }

  void removeWorkspaceEdge(String reference, {String? commandId}) {
    final fingerprint = _encode({
      'op': 'remove_workspace_edge',
      'reference': reference.trim(),
    });
    _idempotent(commandId, fingerprint, () {
      final id = _resolveWorkspaceEdge(reference);
      final edge = _workspaceEdges[id]!;
      if (edge.managedKey != null) {
        throw _error(
          'managed_workspace_edge',
          'edge',
          'Managed workspace edge $id cannot be removed by the planner.',
        );
      }
      if (edge.protected) {
        throw _error(
          'protected_workspace_edge',
          'edge',
          'Protected workspace edge $id cannot be removed by the planner.',
        );
      }
      _workspaceEdges.remove(id);
      _workspaceEdgeRefs.removeWhere((key, value) => value == id);
    });
  }

  /// Runs several draft operations as one atomic command. Batch planning
  /// tools use this so a later invalid item cannot leave earlier items from
  /// the same model call behind.
  T transaction<T>(T Function() action) => _atomic(action);
}
