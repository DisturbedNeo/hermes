import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/project.dart';

class ProjectMemoryMutation {
  final ProjectDocument project;
  final ProjectMemoryEntry entry;
  final List<String> deactivatedEntryIds;

  const ProjectMemoryMutation({
    required this.project,
    required this.entry,
    this.deactivatedEntryIds = const [],
  });
}

class ProjectMemoryContextItem {
  final String id;
  final String content;
  final String reason;
  final int rank;
  final String? memoryEntryId;

  const ProjectMemoryContextItem({
    required this.id,
    required this.content,
    required this.reason,
    required this.rank,
    this.memoryEntryId,
  });
}

class ProjectMemoryContextExclusion {
  final String entryId;
  final String reason;

  const ProjectMemoryContextExclusion({
    required this.entryId,
    required this.reason,
  });
}

class ProjectMemoryContextSelection {
  final List<ProjectMemoryContextItem> items;
  final List<ProjectMemoryContextExclusion> exclusions;
  final int maxCharacters;
  final int usedCharacters;

  const ProjectMemoryContextSelection({
    required this.items,
    required this.exclusions,
    required this.maxCharacters,
    required this.usedCharacters,
  });

  bool get withinBudget => usedCharacters <= maxCharacters;

  List<String> get lines => [for (final item in items) item.content];

  List<String> get selectedMemoryEntryIds => [
    for (final item in items)
      if (item.memoryEntryId != null) item.memoryEntryId!,
  ];
}

/// Owns typed project-memory writes and bounded model-context selection.
///
/// Memory is append-preserving: context budgets never delete persisted entries.
/// Supersession and compaction deactivate covered entries while retaining them as
/// audit history.
class ProjectMemoryService {
  const ProjectMemoryService();

  static const int defaultContextCharacters = 12000;

  ProjectMemoryMutation record({
    required ProjectDocument project,
    required ProjectMemoryKind kind,
    required String content,
    required ProjectMemorySourceType sourceType,
    ProjectMemoryConfidence confidence = ProjectMemoryConfidence.inferred,
    String? sourceId,
    String? id,
    bool? protected,
    bool deduplicate = true,
    bool allowProtectedSupersession = false,
    List<String> supersedesEntryIds = const [],
    DateTime? timestamp,
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(content, 'content', 'Memory cannot be empty.');
    }
    final existing = _activeEntryWithContent(project.memory, trimmed);
    if (deduplicate && existing != null && supersedesEntryIds.isEmpty) {
      return ProjectMemoryMutation(project: project, entry: existing);
    }

    final now = timestamp ?? DateTime.now();
    final requestedSupersessions = supersedesEntryIds.toSet();
    final deactivated = <String>[];
    final nextMemory = <ProjectMemoryEntry>[];
    for (final item in project.memory) {
      if (!requestedSupersessions.contains(item.id) || !item.active) {
        nextMemory.add(item);
        continue;
      }
      if (item.protected &&
          sourceType != ProjectMemorySourceType.user &&
          !allowProtectedSupersession) {
        throw StateError(
          'Protected memory ${item.id} can only be superseded by user input.',
        );
      }
      deactivated.add(item.id);
      nextMemory.add(item.copyWith(active: false, updatedAt: now));
    }

    final uniqueId = _uniqueId(project.memory, id ?? 'memory_${uuid.v7()}');
    final entry = ProjectMemoryEntry(
      id: uniqueId,
      kind: kind,
      content: trimmed,
      sourceType: sourceType,
      sourceId: sourceId,
      confidence: confidence,
      protected:
          protected ??
          sourceType == ProjectMemorySourceType.user ||
              kind == ProjectMemoryKind.requirement ||
              kind == ProjectMemoryKind.decision ||
              kind == ProjectMemoryKind.risk,
      supersedesId: deactivated.isEmpty ? null : deactivated.first,
      coveredEntryIds: deactivated,
      createdAt: now,
      updatedAt: now,
    );
    nextMemory.add(entry);
    return ProjectMemoryMutation(
      project: project.copyWith(memory: nextMemory, updatedAt: now),
      entry: entry,
      deactivatedEntryIds: deactivated,
    );
  }

  ProjectMemoryMutation recordUserAnswer({
    required ProjectDocument project,
    required PendingProjectQuestion question,
    required String answer,
    DateTime? timestamp,
  }) {
    final questionKey = _normalise(question.question);
    final matchingAssumptions = [
      for (final entry in project.memory)
        if (entry.active &&
            entry.kind == ProjectMemoryKind.assumption &&
            _normalise(entry.content).contains(questionKey))
          entry.id,
    ];
    return record(
      project: project,
      kind: ProjectMemoryKind.requirement,
      content: 'User answered: ${question.question}\nAnswer: ${answer.trim()}',
      sourceType: ProjectMemorySourceType.user,
      sourceId: question.id,
      confidence: ProjectMemoryConfidence.confirmed,
      protected: true,
      supersedesEntryIds: matchingAssumptions,
      timestamp: timestamp,
    );
  }

  ProjectMemoryMutation compact({
    required ProjectDocument project,
    required List<String> coveredEntryIds,
    required String summary,
    String? compactionId,
    DateTime? timestamp,
  }) {
    if (coveredEntryIds.isEmpty) {
      throw ArgumentError.value(
        coveredEntryIds,
        'coveredEntryIds',
        'Compaction must cover at least one entry.',
      );
    }
    final byId = {for (final entry in project.memory) entry.id: entry};
    final uniqueCoveredIds = coveredEntryIds.toSet().toList()..sort();
    for (final entryId in uniqueCoveredIds) {
      final entry = byId[entryId];
      if (entry == null || !entry.active) {
        throw StateError('Compaction source $entryId is not active memory.');
      }
      if (entry.protected ||
          entry.kind == ProjectMemoryKind.requirement ||
          entry.kind == ProjectMemoryKind.decision ||
          entry.kind == ProjectMemoryKind.risk) {
        throw StateError(
          'Compaction cannot deactivate protected memory $entryId.',
        );
      }
    }
    return record(
      project: project,
      kind: ProjectMemoryKind.summary,
      content: summary,
      sourceType: ProjectMemorySourceType.system,
      sourceId: compactionId ?? 'compaction_${uuid.v7()}',
      confidence: ProjectMemoryConfidence.inferred,
      protected: false,
      supersedesEntryIds: uniqueCoveredIds,
      timestamp: timestamp,
    );
  }

  ProjectDocument supersede({
    required ProjectDocument project,
    required String replacementEntryId,
    required List<String> coveredEntryIds,
    ProjectMemorySourceType actor = ProjectMemorySourceType.planner,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final covered = coveredEntryIds.toSet()..remove(replacementEntryId);
    final replacement = project.memory
        .where((entry) => entry.id == replacementEntryId)
        .firstOrNull;
    if (replacement == null) {
      throw StateError(
        'Replacement memory $replacementEntryId does not exist.',
      );
    }
    for (final entry in project.memory) {
      if (covered.contains(entry.id) &&
          entry.protected &&
          actor != ProjectMemorySourceType.user) {
        throw StateError(
          'Protected memory ${entry.id} can only be superseded by user input.',
        );
      }
    }
    final coveredIds = covered.toList()..sort();
    return project.copyWith(
      memory: [
        for (final entry in project.memory)
          if (entry.id == replacementEntryId)
            entry.copyWith(
              supersedesId: coveredIds.isEmpty ? null : coveredIds.first,
              coveredEntryIds: {
                ...entry.coveredEntryIds,
                ...coveredIds,
              }.toList()..sort(),
              updatedAt: now,
            )
          else if (covered.contains(entry.id) && entry.active)
            entry.copyWith(active: false, updatedAt: now)
          else
            entry,
      ],
      updatedAt: now,
    );
  }

  ProjectMemoryMutation? resolveRisksForSource({
    required ProjectDocument project,
    required String sourceId,
    required String resolution,
    DateTime? timestamp,
  }) {
    final riskIds = [
      for (final entry in project.memory)
        if (entry.active &&
            entry.kind == ProjectMemoryKind.risk &&
            entry.sourceId == sourceId)
          entry.id,
    ];
    if (riskIds.isEmpty) return null;
    return record(
      project: project,
      kind: ProjectMemoryKind.fact,
      content: resolution,
      sourceType: ProjectMemorySourceType.gate,
      sourceId: sourceId,
      confidence: ProjectMemoryConfidence.confirmed,
      protected: false,
      supersedesEntryIds: riskIds,
      allowProtectedSupersession: true,
      timestamp: timestamp,
    );
  }

  ProjectMemoryContextSelection selectContext({
    required ProjectDocument project,
    ProjectTask? task,
    int maxCharacters = defaultContextCharacters,
  }) {
    if (maxCharacters < 0) {
      throw ArgumentError.value(
        maxCharacters,
        'maxCharacters',
        'Context budget cannot be negative.',
      );
    }
    final dependencyIds = task?.dependsOnTaskIds.toSet() ?? const <String>{};
    final relevanceTerms = _relevanceTerms(project, task);
    final candidates = <_ContextCandidate>[
      for (final entry in project.memory)
        if (entry.active)
          _memoryCandidate(entry, dependencyIds, relevanceTerms),
      for (final criterion in project.criteria)
        _ContextCandidate(
          item: ProjectMemoryContextItem(
            id: 'criterion:${criterion.id}',
            content:
                '${criterion.id} [${criterion.status.name}]: ${criterion.statement}',
            reason: 'Current project criterion state.',
            rank: 1,
          ),
          updatedAt: criterion.updatedAt,
          relevanceScore: _termScore(criterion.statement, relevanceTerms),
        ),
      for (final milestone in project.milestones)
        if (milestone.status == ProjectMilestoneStatus.active ||
            milestone.id == task?.milestoneId)
          _ContextCandidate(
            item: ProjectMemoryContextItem(
              id: 'milestone:${milestone.id}',
              content:
                  '${milestone.id} [${milestone.status.name}]: ${milestone.objective}',
              reason: 'Current or task-linked milestone state.',
              rank: 1,
            ),
            updatedAt: milestone.updatedAt,
            relevanceScore: _termScore(milestone.objective, relevanceTerms),
          ),
    ];
    candidates.sort((a, b) {
      var result = a.item.rank.compareTo(b.item.rank);
      if (result != 0) return result;
      result = b.relevanceScore.compareTo(a.relevanceScore);
      if (result != 0) return result;
      result = b.updatedAt.compareTo(a.updatedAt);
      if (result != 0) return result;
      return a.item.id.compareTo(b.item.id);
    });

    final selected = <ProjectMemoryContextItem>[];
    final exclusions = <ProjectMemoryContextExclusion>[];
    var used = 0;
    for (final candidate in candidates) {
      final separator = selected.isEmpty ? 0 : 1;
      final cost = candidate.item.content.length + separator;
      if (used + cost <= maxCharacters) {
        selected.add(candidate.item);
        used += cost;
      } else if (candidate.item.memoryEntryId != null) {
        exclusions.add(
          ProjectMemoryContextExclusion(
            entryId: candidate.item.memoryEntryId!,
            reason:
                'Excluded from this prompt because the $maxCharacters-character context budget was exhausted.',
          ),
        );
      }
    }
    return ProjectMemoryContextSelection(
      items: List.unmodifiable(selected),
      exclusions: List.unmodifiable(exclusions),
      maxCharacters: maxCharacters,
      usedCharacters: used,
    );
  }

  static _ContextCandidate _memoryCandidate(
    ProjectMemoryEntry entry,
    Set<String> dependencyIds,
    Set<String> relevanceTerms,
  ) {
    final dependencyFact =
        entry.kind == ProjectMemoryKind.fact &&
        entry.sourceId != null &&
        dependencyIds.contains(entry.sourceId);
    final recentTaskSummary =
        entry.sourceType == ProjectMemorySourceType.task &&
        (entry.kind == ProjectMemoryKind.summary ||
            entry.kind == ProjectMemoryKind.fact);
    final rank =
        entry.kind == ProjectMemoryKind.risk ||
            entry.kind == ProjectMemoryKind.assumption
        ? 2
        : entry.protected ||
              entry.sourceType == ProjectMemorySourceType.user ||
              entry.kind == ProjectMemoryKind.requirement ||
              entry.kind == ProjectMemoryKind.decision
        ? 0
        : dependencyFact
        ? 3
        : recentTaskSummary
        ? 4
        : 5;
    final reason = switch (rank) {
      0 => 'Protected requirement or active decision.',
      2 => 'Active risk or assumption.',
      3 => 'Fact sourced by a selected-task dependency.',
      4 => 'Recent task memory.',
      _ => 'General fact or older summary.',
    };
    return _ContextCandidate(
      item: ProjectMemoryContextItem(
        id: 'memory:${entry.id}',
        content: '${entry.id} [${entry.kind.name}]: ${entry.content}',
        reason: reason,
        rank: rank,
        memoryEntryId: entry.id,
      ),
      updatedAt: entry.updatedAt,
      relevanceScore: _termScore(entry.content, relevanceTerms),
    );
  }

  static Set<String> _relevanceTerms(
    ProjectDocument project,
    ProjectTask? task,
  ) {
    final text = [
      project.refinedGoal,
      if (task != null) ...[
        task.title,
        task.objective,
        ...task.context,
        ...task.doneCriteria,
        ...project.criterionStatementsFor(task),
      ],
    ].join(' ');
    return _terms(text);
  }

  static int _termScore(String content, Set<String> relevanceTerms) =>
      _terms(content).intersection(relevanceTerms).length;

  static Set<String> _terms(String value) => _normalise(value)
      .split(' ')
      .where((term) => term.length > 2 && !_stopWords.contains(term))
      .toSet();

  static ProjectMemoryEntry? _activeEntryWithContent(
    List<ProjectMemoryEntry> entries,
    String content,
  ) {
    final key = _normalise(content);
    for (final entry in entries) {
      if (entry.active && _normalise(entry.content) == key) return entry;
    }
    return null;
  }

  static String _uniqueId(List<ProjectMemoryEntry> entries, String proposed) {
    final ids = entries.map((entry) => entry.id).toSet();
    if (!ids.contains(proposed)) return proposed;
    var suffix = 2;
    while (ids.contains('${proposed}_$suffix')) {
      suffix++;
    }
    return '${proposed}_$suffix';
  }

  static String _normalise(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _ContextCandidate {
  final ProjectMemoryContextItem item;
  final DateTime updatedAt;
  final int relevanceScore;

  const _ContextCandidate({
    required this.item,
    required this.updatedAt,
    required this.relevanceScore,
  });
}

const _stopWords = <String>{
  'and',
  'are',
  'for',
  'from',
  'that',
  'the',
  'this',
  'use',
  'with',
};
