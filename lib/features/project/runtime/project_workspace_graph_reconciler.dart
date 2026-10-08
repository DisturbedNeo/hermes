import 'dart:convert';

import 'package:path/path.dart' as path;

import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/features/workspace/application/workspace_change_discovery.dart';
import 'package:hermes/features/workspace/application/workspace_discovery_profile.dart';

/// The result of reconciling bounded workspace facts into the durable graph.
class ProjectWorkspaceGraphReconciliation {
  const ProjectWorkspaceGraphReconciliation({
    required this.graph,
    required this.addedManagedKeys,
    required this.updatedManagedKeys,
    required this.removedManagedKeys,
    required this.derivedFingerprint,
    this.fingerprintChanged = false,
    required this.plannerMaintenanceRecommended,
  });

  final ProjectWorkspaceGraph graph;
  final List<String> addedManagedKeys;
  final List<String> updatedManagedKeys;
  final List<String> removedManagedKeys;
  final String derivedFingerprint;
  final bool fingerprintChanged;
  final bool plannerMaintenanceRecommended;

  bool get changed =>
      addedManagedKeys.isNotEmpty ||
      updatedManagedKeys.isNotEmpty ||
      removedManagedKeys.isNotEmpty ||
      fingerprintChanged;

  int get derivedUpdateCount =>
      addedManagedKeys.length +
      updatedManagedKeys.length +
      removedManagedKeys.length;

  Map<String, dynamic> toMap() => {
    'added_managed_keys': addedManagedKeys,
    'updated_managed_keys': updatedManagedKeys,
    'removed_managed_keys': removedManagedKeys,
    'derived_fingerprint': derivedFingerprint,
    'fingerprint_changed': fingerprintChanged,
    'planner_maintenance_recommended': plannerMaintenanceRecommended,
  };
}

/// Builds the high-confidence, deterministic portion of a project workspace
/// graph. It never invokes a model and never changes authored entries.
class ProjectWorkspaceGraphReconciler {
  const ProjectWorkspaceGraphReconciler();

  ProjectWorkspaceGraphReconciliation reconcile({
    required ProjectAggregate project,
    required WorkspaceDiscoveryProfile workspaceProfile,
    required WorkspaceChangeSet changeSet,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final fingerprint = _fingerprint(workspaceProfile, changeSet, project);
    final fingerprintChanged =
        project.workspaceGraph.discoveryFingerprint != fingerprint;
    final existingNodesByKey = <String, ProjectWorkspaceNode>{
      for (final node in project.workspaceGraph.nodes)
        if (node.managedKey != null) node.managedKey!: node,
    };
    final existingEdgesByKey = <String, ProjectWorkspaceEdge>{
      for (final edge in project.workspaceGraph.edges)
        if (edge.managedKey != null) edge.managedKey!: edge,
    };
    final authoredNodeIds = project.workspaceGraph.nodes
        .where((node) => node.managedKey == null)
        .map((node) => node.id)
        .toSet();
    final generatedNodeIds = <String>{};
    final authoredEdgeIds = project.workspaceGraph.edges
        .where((edge) => edge.managedKey == null)
        .map((edge) => edge.id)
        .toSet();
    final generatedEdgeIds = <String>{};

    final generatedNodes = <String, ProjectWorkspaceNode>{};
    final generatedEdges = <String, _GeneratedEdge>{};

    void addNode({
      required String managedKey,
      required String type,
      required String title,
      String description = '',
      List<String> references = const [],
      String? sourceId,
    }) {
      if (generatedNodes.containsKey(managedKey)) return;
      final existing = existingNodesByKey[managedKey];
      var id = existing?.id ?? 'workspace_auto_node_${_token(managedKey)}';
      var collisionIndex = 0;
      while ((authoredNodeIds.contains(id) || generatedNodeIds.contains(id)) &&
          existing == null) {
        collisionIndex++;
        id = 'workspace_auto_node_${_token('$managedKey:$collisionIndex')}';
      }
      generatedNodeIds.add(id);
      var candidate = ProjectWorkspaceNode(
        id: id,
        type: type,
        title: title,
        description: description,
        references: references,
        sourceType: managedKey.startsWith('task:')
            ? ProjectWorkspaceSourceType.task
            : ProjectWorkspaceSourceType.system,
        sourceId: sourceId,
        managedKey: managedKey,
        confidence: ProjectWorkspaceConfidence.inferred,
        protected: false,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      if (existing != null && _sameNodeContent(existing, candidate)) {
        candidate = candidate.copyWith(updatedAt: existing.updatedAt);
      }
      generatedNodes[managedKey] = candidate;
    }

    void addEdge({
      required String managedKey,
      required String sourceKey,
      required String targetKey,
      required String label,
      String description = '',
      String? sourceId,
    }) {
      generatedEdges[managedKey] = _GeneratedEdge(
        managedKey: managedKey,
        sourceKey: sourceKey,
        targetKey: targetKey,
        label: label,
        description: description,
        sourceId: sourceId,
      );
    }

    addNode(
      managedKey: 'system:workspace',
      type: 'workspace',
      title: workspaceProfile.workspaceName.trim().isEmpty
          ? 'Workspace'
          : workspaceProfile.workspaceName,
      description: 'The attached workspace.',
      references: const ['workspace:root'],
      sourceId: 'workspace:root',
    );

    final packageName = workspaceProfile.packageName?.trim();
    if (packageName != null && packageName.isNotEmpty) {
      addNode(
        managedKey: 'system:package:$packageName',
        type: 'package',
        title: packageName,
        description: 'Package or project declared by the workspace manifest.',
        references: _manifestReferences(workspaceProfile),
        sourceId: 'workspace:package:$packageName',
      );
      addEdge(
        managedKey: 'system:edge:workspace:package:$packageName',
        sourceKey: 'system:workspace',
        targetKey: 'system:package:$packageName',
        label: 'contains',
        sourceId: 'workspace:root',
      );
    }

    for (final language in [...workspaceProfile.languages]..sort()) {
      final key = 'system:language:${language.toLowerCase()}';
      addNode(
        managedKey: key,
        type: 'language',
        title: language,
        description: 'Language detected from workspace file extensions.',
        sourceId: 'workspace:language:$language',
      );
      if (packageName != null && packageName.isNotEmpty) {
        addEdge(
          managedKey: 'system:edge:package:language:${language.toLowerCase()}',
          sourceKey: 'system:package:$packageName',
          targetKey: key,
          label: 'uses',
          sourceId: 'workspace:language:$language',
        );
      }
    }

    for (final framework in [...workspaceProfile.frameworks]..sort()) {
      final key = 'system:framework:${framework.toLowerCase()}';
      addNode(
        managedKey: key,
        type: 'framework',
        title: framework,
        description: 'Framework detected from workspace dependencies.',
        sourceId: 'workspace:framework:$framework',
      );
      if (packageName != null && packageName.isNotEmpty) {
        addEdge(
          managedKey:
              'system:edge:package:framework:${framework.toLowerCase()}',
          sourceKey: 'system:package:$packageName',
          targetKey: key,
          label: 'uses',
          sourceId: 'workspace:framework:$framework',
        );
      }
    }

    for (final dependency in [...workspaceProfile.dependencies]..sort()) {
      final key = 'system:dependency:$dependency';
      addNode(
        managedKey: key,
        type: 'dependency',
        title: dependency,
        description: 'Dependency declared by the workspace manifest.',
        references: _manifestReferences(workspaceProfile),
        sourceId: 'workspace:dependency:$dependency',
      );
      if (packageName != null && packageName.isNotEmpty) {
        addEdge(
          managedKey: 'system:edge:package:dependency:$dependency',
          sourceKey: 'system:package:$packageName',
          targetKey: key,
          label: 'depends_on',
          sourceId: 'workspace:dependency:$dependency',
        );
        addEdge(
          managedKey: 'system:edge:package:declares:dependency:$dependency',
          sourceKey: 'system:package:$packageName',
          targetKey: key,
          label: 'declares',
          sourceId: 'workspace:dependency:$dependency',
        );
      }
    }

    final filePaths =
        workspaceProfile.treePaths
            .where((item) => !item.endsWith('/'))
            .map(_normalisePath)
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    for (final relativePath in filePaths) {
      final key = 'system:file:$relativePath';
      addNode(
        managedKey: key,
        type: 'file',
        title: relativePath,
        description: 'File discovered in the attached workspace.',
        references: ['workspace:$relativePath'],
        sourceId: 'workspace:$relativePath',
      );
      final parentKey = packageName == null || packageName.isEmpty
          ? 'system:workspace'
          : 'system:package:$packageName';
      addEdge(
        managedKey: 'system:edge:$parentKey:file:$relativePath',
        sourceKey: parentKey,
        targetKey: key,
        label: 'contains',
        sourceId: 'workspace:$relativePath',
      );
    }

    final taskById = {for (final task in project.tasks) task.id: task};
    final artifacts = [...project.artifacts]
      ..sort((a, b) {
        final taskOrder = (a.taskId ?? '').compareTo(b.taskId ?? '');
        if (taskOrder != 0) return taskOrder;
        final pathOrder = _normalisePath(
          a.path,
        ).compareTo(_normalisePath(b.path));
        if (pathOrder != 0) return pathOrder;
        return a.id.compareTo(b.id);
      });
    for (final artifact in artifacts) {
      final relativePath = _normalisePath(artifact.path);
      if (relativePath.isEmpty) continue;
      final artifactKey = artifact.taskId == null
          ? 'task:artifact:${artifact.id.isEmpty ? relativePath : artifact.id}'
          : 'task:artifact:${artifact.taskId}:$relativePath';
      addNode(
        managedKey: artifactKey,
        type: 'artifact',
        title: relativePath,
        description: artifact.description?.trim().isNotEmpty == true
            ? artifact.description!.trim()
            : 'Durable artifact produced by project work.',
        references: [
          'artifact:${artifact.id.isEmpty ? relativePath : artifact.id}',
          'workspace:$relativePath',
        ],
        sourceId:
            'artifact:${artifact.id.isEmpty ? relativePath : artifact.id}',
      );
      if (artifact.taskId != null && taskById.containsKey(artifact.taskId)) {
        final taskKey = 'task:task:${artifact.taskId}';
        final task = taskById[artifact.taskId]!;
        addNode(
          managedKey: taskKey,
          type: 'task',
          title: task.title,
          description: task.objective,
          sourceId: 'task:${task.id}',
        );
        addEdge(
          managedKey: 'task:edge:${artifact.taskId}:produces:$relativePath',
          sourceKey: taskKey,
          targetKey: artifactKey,
          label: 'produces',
          sourceId: 'task:${artifact.taskId}',
        );
      }
    }
    void addDeclaredTaskOutput(
      ProjectTaskNode task,
      String outputPath,
      String? description,
    ) {
      final relativePath = _normalisePath(outputPath);
      if (relativePath.isEmpty) return;
      final artifactKey = 'task:artifact:${task.id}:$relativePath';
      addNode(
        managedKey: artifactKey,
        type: 'artifact',
        title: relativePath,
        description: description?.trim().isNotEmpty == true
            ? description!.trim()
            : 'Declared output path for project work.',
        references: ['workspace:$relativePath'],
        sourceId: 'task:${task.id}',
      );
      final taskKey = 'task:task:${task.id}';
      addNode(
        managedKey: taskKey,
        type: 'task',
        title: task.title,
        description: task.objective,
        sourceId: 'task:${task.id}',
      );
      addEdge(
        managedKey: 'task:edge:${task.id}:produces:$relativePath',
        sourceKey: taskKey,
        targetKey: artifactKey,
        label: 'produces',
        sourceId: 'task:${task.id}',
      );
    }

    for (final task in project.tasks) {
      for (final expectedArtifact in task.expectedArtifacts) {
        addDeclaredTaskOutput(
          task,
          expectedArtifact.path,
          expectedArtifact.description,
        );
      }
      for (final writePath in task.writePaths) {
        addDeclaredTaskOutput(task, writePath, null);
      }
    }

    // Authored relationships are immutable. Keep a managed endpoint alive
    // when an authored relationship still refers to it; otherwise a source
    // fact disappearing from discovery would leave a protected dangling
    // relationship that blocks every later graph validation.
    final referencedManagedKeys = <String>{};
    final nodesById = {
      for (final node in project.workspaceGraph.nodes) node.id: node,
    };
    for (final edge in project.workspaceGraph.edges.where(
      (edge) => edge.managedKey == null,
    )) {
      for (final nodeId in [edge.sourceNodeId, edge.targetNodeId]) {
        final node = nodesById[nodeId];
        final managedKey = node?.managedKey;
        if (managedKey == null) continue;
        referencedManagedKeys.add(managedKey);
        generatedNodes.putIfAbsent(managedKey, () => node!);
      }
    }

    final authoredNodeCount = project.workspaceGraph.nodes
        .where((node) => node.managedKey == null)
        .length;
    final availableNodeSlots =
        ProjectWorkspaceContextService.maxNodes - authoredNodeCount;
    final selectedNodes = _selectNodes(
      generatedNodes.values.toList(),
      availableNodeSlots < 0 ? 0 : availableNodeSlots,
      retainKeys: {
        ...existingNodesByKey.keys.where(generatedNodes.containsKey),
        ...referencedManagedKeys,
      },
    );
    final selectedKeys = selectedNodes.map((node) => node.managedKey!).toSet();
    final selectedEdges = <ProjectWorkspaceEdge>[];
    final orderedGeneratedEdges = generatedEdges.values.toList()
      ..sort((a, b) => a.managedKey.compareTo(b.managedKey));
    for (final generated in orderedGeneratedEdges) {
      if (!selectedKeys.contains(generated.sourceKey) ||
          !selectedKeys.contains(generated.targetKey)) {
        continue;
      }
      final existing = existingEdgesByKey[generated.managedKey];
      final sourceId = selectedNodes
          .firstWhere((node) => node.managedKey == generated.sourceKey)
          .id;
      final targetId = selectedNodes
          .firstWhere((node) => node.managedKey == generated.targetKey)
          .id;
      var id =
          existing?.id ?? 'workspace_auto_edge_${_token(generated.managedKey)}';
      var collisionIndex = 0;
      while ((authoredEdgeIds.contains(id) || generatedEdgeIds.contains(id)) &&
          existing == null) {
        collisionIndex++;
        id =
            'workspace_auto_edge_${_token('${generated.managedKey}:$collisionIndex')}';
      }
      generatedEdgeIds.add(id);
      var candidate = ProjectWorkspaceEdge(
        id: id,
        sourceNodeId: sourceId,
        targetNodeId: targetId,
        label: generated.label,
        description: generated.description,
        sourceType: generated.managedKey.startsWith('task:')
            ? ProjectWorkspaceSourceType.task
            : ProjectWorkspaceSourceType.system,
        sourceId: generated.sourceId,
        managedKey: generated.managedKey,
        confidence: ProjectWorkspaceConfidence.inferred,
        protected: false,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      if (existing != null && _sameEdgeContent(existing, candidate)) {
        candidate = candidate.copyWith(updatedAt: existing.updatedAt);
      }
      selectedEdges.add(candidate);
    }

    final authoredEdgeCount = project.workspaceGraph.edges
        .where((edge) => edge.managedKey == null)
        .length;
    final selectedEdgeLimit =
        ProjectWorkspaceContextService.maxEdges - authoredEdgeCount;
    final selectedEdgesBounded = _selectEdges(
      selectedEdges,
      selectedEdgeLimit < 0 ? 0 : selectedEdgeLimit,
      retainKeys: existingEdgesByKey.keys
          .where((key) => selectedEdges.any((edge) => edge.managedKey == key))
          .toSet(),
    );

    final nodes = [
      for (final node in project.workspaceGraph.nodes)
        if (node.managedKey == null) node,
      ...selectedNodes,
    ];
    final edges = [
      for (final edge in project.workspaceGraph.edges)
        if (edge.managedKey == null) edge,
      ...selectedEdgesBounded,
    ];
    final updatedGraph = ProjectWorkspaceGraph(
      orientation: project.workspaceGraph.orientation,
      nodes: nodes,
      edges: edges,
      updatedAt: project.workspaceGraph.discoveryFingerprint == fingerprint
          ? project.workspaceGraph.updatedAt
          : now,
      discoveryFingerprint: fingerprint,
    );

    final currentNodeKeys = existingNodesByKey.keys.toSet();
    final currentEdgeKeys = existingEdgesByKey.keys.toSet();
    final nextNodeKeys = selectedNodes.map((node) => node.managedKey!).toSet();
    final nextEdgeKeys = selectedEdgesBounded
        .map((edge) => edge.managedKey!)
        .toSet();
    final added = <String>{
      ...nextNodeKeys.difference(currentNodeKeys),
      ...nextEdgeKeys.difference(currentEdgeKeys),
    }.toList()..sort();
    final removed = <String>{
      ...currentNodeKeys.difference(nextNodeKeys),
      ...currentEdgeKeys.difference(nextEdgeKeys),
    }.toList()..sort();
    final updated = <String>{
      for (final node in selectedNodes)
        if (existingNodesByKey[node.managedKey!] != null &&
            !_sameNodeContent(existingNodesByKey[node.managedKey!]!, node))
          node.managedKey!,
      for (final edge in selectedEdgesBounded)
        if (existingEdgesByKey[edge.managedKey!] != null &&
            !_sameEdgeContent(existingEdgesByKey[edge.managedKey!]!, edge))
          edge.managedKey!,
    }.toList()..sort();

    return ProjectWorkspaceGraphReconciliation(
      graph: updatedGraph,
      addedManagedKeys: List.unmodifiable(added),
      updatedManagedKeys: List.unmodifiable(updated),
      removedManagedKeys: List.unmodifiable(removed),
      derivedFingerprint: fingerprint,
      plannerMaintenanceRecommended:
          (added.isNotEmpty ||
              updated.isNotEmpty ||
              removed.isNotEmpty ||
              fingerprintChanged) &&
          _hasSemanticEvidence(workspaceProfile, project),
      fingerprintChanged: fingerprintChanged,
    );
  }

  bool _hasSemanticEvidence(
    WorkspaceDiscoveryProfile profile,
    ProjectAggregate project,
  ) =>
      profile.packageName?.trim().isNotEmpty == true ||
      profile.dependencies.isNotEmpty ||
      profile.frameworks.isNotEmpty ||
      profile.highSignalFiles.isNotEmpty ||
      project.artifacts.isNotEmpty ||
      project.tasks.any(
        (task) =>
            task.writePaths.isNotEmpty || task.expectedArtifacts.isNotEmpty,
      );

  List<ProjectWorkspaceNode> _selectNodes(
    List<ProjectWorkspaceNode> candidates,
    int availableSlots, {
    Set<String> retainKeys = const <String>{},
  }) {
    final sorted = [...candidates]
      ..sort((a, b) {
        final priority = _nodePriority(a).compareTo(_nodePriority(b));
        return priority != 0
            ? priority
            : a.managedKey!.compareTo(b.managedKey!);
      });
    final retained = sorted
        .where((node) => retainKeys.contains(node.managedKey))
        .toList(growable: false);
    final additions = sorted
        .where((node) => !retainKeys.contains(node.managedKey))
        .toList(growable: false);
    return [
      ...retained.take(availableSlots),
      ...additions.take(
        (availableSlots - retained.length).clamp(0, availableSlots),
      ),
    ];
  }

  List<ProjectWorkspaceEdge> _selectEdges(
    List<ProjectWorkspaceEdge> candidates,
    int availableSlots, {
    Set<String> retainKeys = const <String>{},
  }) {
    final sorted = [...candidates]
      ..sort((a, b) => a.managedKey!.compareTo(b.managedKey!));
    final retained = sorted
        .where((edge) => retainKeys.contains(edge.managedKey))
        .toList(growable: false);
    final additions = sorted
        .where((edge) => !retainKeys.contains(edge.managedKey))
        .toList(growable: false);
    return [
      ...retained.take(availableSlots),
      ...additions.take(
        (availableSlots - retained.length).clamp(0, availableSlots),
      ),
    ];
  }

  int _nodePriority(ProjectWorkspaceNode node) => switch (node.type) {
    'workspace' => 0,
    'package' => 1,
    'language' || 'framework' => 2,
    'dependency' => 3,
    'task' => 4,
    'artifact' => 5,
    _ => 6,
  };

  List<String> _manifestReferences(WorkspaceDiscoveryProfile profile) => [
    for (final file in profile.highSignalFiles)
      if ({'package.json', 'pubspec.yaml'}.contains(path.basename(file.path)))
        'workspace:${_normalisePath(file.path)}',
  ];

  String _fingerprint(
    WorkspaceDiscoveryProfile profile,
    WorkspaceChangeSet changeSet,
    ProjectAggregate project,
  ) {
    final values = <String>[
      profile.workspaceName,
      ...profile.treePaths.map(_normalisePath),
      ...profile.languages,
      ...profile.frameworks,
      ...profile.dependencies,
      profile.packageName ?? '',
      ...profile.scripts.entries.map((entry) => '${entry.key}=${entry.value}'),
      ...profile.highSignalFiles.map(
        (file) =>
            '${_normalisePath(file.path)}|${file.content}|${file.truncated}',
      ),
      changeSet.isRepository.toString(),
      ...changeSet.changedFiles.map(_normalisePath),
      ...project.artifacts.map(
        (artifact) =>
            '${artifact.id}|${artifact.taskId}|${_normalisePath(artifact.path)}|${artifact.kind}|${artifact.description}',
      ),
      ...project.tasks.map(
        (task) =>
            '${task.id}|${task.title}|${task.objective}|${task.writePaths.join(',')}|${task.expectedArtifacts.map((artifact) => '${_normalisePath(artifact.path)}|${artifact.description}').join(',')}',
      ),
    ]..sort();
    return _token(values.join('\n'));
  }

  static bool _sameNodeContent(
    ProjectWorkspaceNode first,
    ProjectWorkspaceNode second,
  ) =>
      first.id == second.id &&
      first.type == second.type &&
      first.title == second.title &&
      first.description == second.description &&
      _sameStrings(first.aliases, second.aliases) &&
      _sameStrings(first.tags, second.tags) &&
      _sameStrings(first.references, second.references) &&
      first.sourceType == second.sourceType &&
      first.sourceId == second.sourceId &&
      first.managedKey == second.managedKey &&
      first.confidence == second.confidence &&
      first.protected == second.protected;

  static bool _sameEdgeContent(
    ProjectWorkspaceEdge first,
    ProjectWorkspaceEdge second,
  ) =>
      first.id == second.id &&
      first.sourceNodeId == second.sourceNodeId &&
      first.targetNodeId == second.targetNodeId &&
      first.label == second.label &&
      first.description == second.description &&
      first.sourceType == second.sourceType &&
      first.sourceId == second.sourceId &&
      first.managedKey == second.managedKey &&
      first.confidence == second.confidence &&
      first.protected == second.protected;

  static bool _sameStrings(Iterable<String> first, Iterable<String> second) {
    final left = first.toList();
    final right = second.toList();
    return left.length == right.length && left.every(right.contains);
  }

  static String _normalisePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return path
        .normalize(trimmed.replaceAll('\\', '/'))
        .replaceFirst(RegExp(r'^\./'), '');
  }

  static String _token(String value) {
    var hash = 2166136261;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _GeneratedEdge {
  const _GeneratedEdge({
    required this.managedKey,
    required this.sourceKey,
    required this.targetKey,
    required this.label,
    required this.description,
    required this.sourceId,
  });

  final String managedKey;
  final String sourceKey;
  final String targetKey;
  final String label;
  final String description;
  final String? sourceId;
}
