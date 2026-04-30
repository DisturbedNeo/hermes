import 'dart:convert';
import 'dart:math' as math;

import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/chat/context_summary_prompt.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/message_store.dart';

class CompactionManager {
  final CompactionSettings settings;
  final ChatClient client;

  const CompactionManager({required this.settings, required this.client});

  bool shouldCompact({
    required List<Bubble> messages,
    required int contextLimit,
    required Map<String, dynamic> extraParams,
  }) {
    if (!settings.enabled || contextLimit <= 0 || messages.isEmpty) {
      return false;
    }

    if (_hasUnresolvedToolCalls(messages)) {
      return false;
    }

    final estimate = _estimateOutgoingPayload(
      messages: messages,
      extraParams: extraParams,
    );

    return estimate >= (contextLimit * settings.triggerThreshold).ceil() &&
        _selectCandidates(messages, aggressive: false).isNotEmpty;
  }

  Future<CompactionResult> compactIfNeeded({
    required MessageStore messageStore,
    required int contextLimit,
    required Map<String, dynamic> extraParams,
    required void Function(String status) onStatusChanged,
  }) async {
    final messages = messageStore.messages.toList();
    if (!settings.enabled || contextLimit <= 0 || messages.isEmpty) {
      return const CompactionResult(compacted: false);
    }

    if (_hasUnresolvedToolCalls(messages)) {
      return const CompactionResult(compacted: false);
    }

    final estimatedBefore = _estimateOutgoingPayload(
      messages: messages,
      extraParams: extraParams,
    );
    final triggerTokens = (contextLimit * settings.triggerThreshold).ceil();
    if (estimatedBefore < triggerTokens) {
      return CompactionResult(
        compacted: false,
        estimatedTokensBefore: estimatedBefore,
        estimatedTokensAfter: estimatedBefore,
      );
    }

    final aggressive =
        estimatedBefore >= (contextLimit * settings.hardLimitThreshold).ceil();
    final candidateMessages = _selectCandidates(
      messages,
      aggressive: aggressive,
    );

    if (candidateMessages.isEmpty) {
      onStatusChanged('No eligible messages to compact.');
      return CompactionResult(
        compacted: false,
        estimatedTokensBefore: estimatedBefore,
        estimatedTokensAfter: estimatedBefore,
      );
    }

    onStatusChanged(
      aggressive
          ? 'Compacting context aggressively...'
          : 'Compacting context...',
    );

    final existingSummary = _latestSummary(messages);
    final anchorMessages = _preservedAnchorMessages(messages);
    late final ContextSummary summary;
    try {
      summary = await _summariseCandidates(
        candidates: candidateMessages,
        anchorMessages: anchorMessages,
        previousSummaryText: existingSummary?.text,
        contextLimit: contextLimit,
        onStatusChanged: onStatusChanged,
      );
    } catch (error) {
      if (settings.allowEmergencyPayloadTruncation) {
        return _emergencyResult(
          messages: messages,
          candidates: candidateMessages,
          extraParams: extraParams,
          estimatedBefore: estimatedBefore,
          status:
              'Summary request failed; emergency payload truncation will be used for this request.',
          onStatusChanged: onStatusChanged,
        );
      }
      rethrow;
    }

    if (!summary.hasUsableContent) {
      throw const CompactionException(
        'Compaction summary was empty or unusable.',
      );
    }

    final summaryId = existingSummary?.id ?? uuid.v7();
    final summaryBubble = Bubble(
      id: summaryId,
      role: MessageRole.user,
      text: summary.toBubbleText(),
      reasoning: '',
      isSummaryMemory: true,
      summarySchemaVersion: summary.schemaVersion,
    );

    final proposedMessages = _applyCompactionToCopy(
      messages: messages,
      summaryBubble: summaryBubble,
      coveredMessageIds: candidateMessages.map((message) => message.id),
    );
    final estimatedAfter = _estimateOutgoingPayload(
      messages: proposedMessages,
      extraParams: extraParams,
    );

    if (estimatedAfter >= estimatedBefore) {
      if (settings.allowEmergencyPayloadTruncation) {
        return _emergencyResult(
          messages: messages,
          candidates: candidateMessages,
          extraParams: extraParams,
          estimatedBefore: estimatedBefore,
          status:
              'Summary did not reduce context; emergency payload truncation will be used for this request.',
          onStatusChanged: onStatusChanged,
        );
      }

      onStatusChanged('Compaction skipped because it did not reduce context.');
      return CompactionResult(
        compacted: false,
        estimatedTokensBefore: estimatedBefore,
        estimatedTokensAfter: estimatedAfter,
      );
    }

    if (existingSummary == null) {
      messageStore.insertAt(
        _summaryInsertIndex(messageStore.messages),
        summaryBubble,
      );
    } else {
      messageStore.replaceById(summaryId, summaryBubble);
    }

    messageStore.markCoveredBySummary(
      messageIds: candidateMessages.map((message) => message.id),
      summaryId: summaryId,
    );

    final saved = math.max(0, estimatedBefore - estimatedAfter);
    onStatusChanged(
      'Compacted ${candidateMessages.length} messages; saved about $saved tokens.',
    );

    return CompactionResult(
      compacted: true,
      estimatedTokensBefore: estimatedBefore,
      estimatedTokensAfter: estimatedAfter,
      messagesCovered: candidateMessages.length,
    );
  }

  CompactionResult _emergencyResult({
    required List<Bubble> messages,
    required List<Bubble> candidates,
    required Map<String, dynamic> extraParams,
    required int estimatedBefore,
    required String status,
    required void Function(String status) onStatusChanged,
  }) {
    final omittedIds = candidates.map((message) => message.id).toSet();
    final estimatedAfter = _estimateOutgoingPayload(
      messages: messages,
      extraParams: extraParams,
      omittedMessageIds: omittedIds,
    );

    onStatusChanged(status);

    return CompactionResult(
      compacted: false,
      estimatedTokensBefore: estimatedBefore,
      estimatedTokensAfter: estimatedAfter,
      emergencyPayloadTruncation: true,
      emergencyOmittedMessageIds: omittedIds,
    );
  }

  Future<ContextSummary> _summariseCandidates({
    required List<Bubble> candidates,
    required List<Bubble> anchorMessages,
    required String? previousSummaryText,
    required int contextLimit,
    required void Function(String status) onStatusChanged,
  }) async {
    final chunks = _chunkCandidates(
      candidates: candidates,
      anchorMessages: anchorMessages,
      previousSummaryText: previousSummaryText,
      contextLimit: contextLimit,
    );

    final intermediate = <ContextSummary>[];
    for (var i = 0; i < chunks.length; i++) {
      if (chunks.length > 1) {
        onStatusChanged('Summarising context chunk ${i + 1}/${chunks.length}.');
      }
      final raw = await client.completeMessage(
        messages: _buildSummaryMessages(
          candidates: chunks[i],
          anchorMessages: anchorMessages,
          previousSummaryText: previousSummaryText,
        ),
        extraParams: ToolCaller.buildExtraParams(
          addGenerationPrompt: true,
          toolDefs: const [],
        ),
      );
      intermediate.add(_parseSummary(raw, chunks[i]));
    }

    if (intermediate.length == 1 && previousSummaryText == null) {
      return intermediate.single;
    }

    final mergeRaw = await client.completeMessage(
      messages: _buildMergeMessages(
        anchorMessages: anchorMessages,
        previousSummaryText: previousSummaryText,
        summaries: intermediate,
      ),
      extraParams: ToolCaller.buildExtraParams(
        addGenerationPrompt: true,
        toolDefs: const [],
      ),
    );

    return _parseSummary(mergeRaw, candidates);
  }

  List<List<Bubble>> _chunkCandidates({
    required List<Bubble> candidates,
    required List<Bubble> anchorMessages,
    required String? previousSummaryText,
    required int contextLimit,
  }) {
    final budget = math.max(1024, (contextLimit * 0.65).floor());
    final chunks = <List<Bubble>>[];
    var current = <Bubble>[];

    for (final candidate in candidates) {
      final trial = [...current, candidate];
      final estimate = ContextEstimator.estimateChatCompletionRequest(
        messages: _buildSummaryMessages(
          candidates: trial,
          anchorMessages: anchorMessages,
          previousSummaryText: previousSummaryText,
        ),
      );

      if (current.isNotEmpty && estimate > budget) {
        chunks.add(current);
        current = [candidate];
      } else {
        current = trial;
      }
    }

    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  List<ChatMessage> _buildSummaryMessages({
    required List<Bubble> candidates,
    required List<Bubble> anchorMessages,
    required String? previousSummaryText,
  }) {
    return [
      const ChatMessage(
        role: 'system',
        content: ContextSummaryPrompt.systemPrompt,
      ),
      ChatMessage(
        role: 'user',
        content: _buildSummaryUserContent(
          candidates: candidates,
          anchorMessages: anchorMessages,
          previousSummaryText: previousSummaryText,
        ),
      ),
    ];
  }

  List<ChatMessage> _buildMergeMessages({
    required List<Bubble> anchorMessages,
    required String? previousSummaryText,
    required List<ContextSummary> summaries,
  }) {
    final buffer = StringBuffer(ContextSummaryPrompt.mergeInstruction)
      ..writeln()
      ..writeln();

    if (anchorMessages.isNotEmpty) {
      buffer
        ..writeln('Preserved anchor messages that remain verbatim:')
        ..writeln(_serialiseBubblesForSummary(anchorMessages))
        ..writeln();
    }

    if (previousSummaryText != null && previousSummaryText.trim().isNotEmpty) {
      buffer
        ..writeln('Existing summary memory:')
        ..writeln(previousSummaryText.trim())
        ..writeln();
    }

    for (var i = 0; i < summaries.length; i++) {
      buffer
        ..writeln('Intermediate summary ${i + 1}:')
        ..writeln(summaries[i].toJsonText())
        ..writeln();
    }

    return [
      const ChatMessage(
        role: 'system',
        content: ContextSummaryPrompt.systemPrompt,
      ),
      ChatMessage(role: 'user', content: buffer.toString().trim()),
    ];
  }

  String _buildSummaryUserContent({
    required List<Bubble> candidates,
    required List<Bubble> anchorMessages,
    required String? previousSummaryText,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'Summarise the compacted transcript below for future context memory.',
      )
      ..writeln(
        'The preserved anchor messages remain in the model payload verbatim; use them as grounding context and do not treat them as messages to omit.',
      )
      ..writeln();

    if (anchorMessages.isNotEmpty) {
      buffer
        ..writeln('Preserved anchor messages:')
        ..writeln(_serialiseBubblesForSummary(anchorMessages))
        ..writeln();
    }

    if (previousSummaryText != null && previousSummaryText.trim().isNotEmpty) {
      buffer
        ..writeln('Existing summary memory to preserve and update:')
        ..writeln(previousSummaryText.trim())
        ..writeln();
    }

    buffer
      ..writeln('Transcript range to summarise:')
      ..writeln(_serialiseBubblesForSummary(candidates));

    return buffer.toString().trim();
  }

  String _serialiseBubblesForSummary(List<Bubble> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      buffer
        ..writeln('--- ${message.role.wire} message (${message.id}) ---')
        ..writeln('Role: ${message.role.wire}');

      if (message.reasoning.trim().isNotEmpty) {
        buffer
          ..writeln('Reasoning:')
          ..writeln(message.reasoning.trim());
      }

      if (message.text.trim().isNotEmpty) {
        buffer
          ..writeln('Content:')
          ..writeln(message.text.trim());
      }

      if (message.tools.isNotEmpty) {
        buffer.writeln('Tool calls and results:');
        final entries = message.tools.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final entry in entries) {
          final tool = entry.value;
          buffer
            ..writeln('- index: ${entry.key}')
            ..writeln('  id: ${tool.id ?? ''}')
            ..writeln('  name: ${tool.name ?? ''}')
            ..writeln('  arguments: ${tool.arguments ?? ''}')
            ..writeln('  result: ${tool.result ?? ''}');
        }
      }

      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  ContextSummary _parseSummary(String raw, List<Bubble> candidates) {
    final trimmed = raw.trim();
    final decoded = _tryDecodeSummary(trimmed);
    if (decoded != null) {
      final summary = ContextSummary.fromJson(decoded);
      if (summary.hasUsableContent) return summary;
    }

    final rawTokens = ContextEstimator.estimateText(trimmed);
    final candidateTokens = ContextEstimator.estimateChatCompletionRequest(
      messages: PayloadBuilder.buildPayloadWithTools(
        messages: candidates,
        upToIndexInclusive: candidates.length - 1,
      ),
    );

    if (trimmed.isNotEmpty && rawTokens < candidateTokens) {
      return ContextSummary.fromRawText(trimmed);
    }

    throw const CompactionException(
      'Compaction summary was not valid JSON and was not small enough to use.',
    );
  }

  Map<String, dynamic>? _tryDecodeSummary(String raw) {
    Object? decode(String value) {
      try {
        return jsonDecode(value);
      } on FormatException {
        return null;
      }
    }

    final direct = decode(raw);
    if (direct is Map<String, dynamic>) return direct;
    if (direct is Map) return Map<String, dynamic>.from(direct);

    final firstBrace = raw.indexOf('{');
    final lastBrace = raw.lastIndexOf('}');
    if (firstBrace < 0 || lastBrace <= firstBrace) return null;

    final extracted = decode(raw.substring(firstBrace, lastBrace + 1));
    if (extracted is Map<String, dynamic>) return extracted;
    if (extracted is Map) return Map<String, dynamic>.from(extracted);
    return null;
  }

  List<Bubble> _applyCompactionToCopy({
    required List<Bubble> messages,
    required Bubble summaryBubble,
    required Iterable<String> coveredMessageIds,
  }) {
    final ids = coveredMessageIds.toSet();
    final copy = List<Bubble>.of(messages);
    final existingIndex = copy.indexWhere(
      (message) => message.id == summaryBubble.id,
    );

    if (existingIndex >= 0) {
      copy[existingIndex] = summaryBubble;
    } else {
      copy.insert(_summaryInsertIndex(copy), summaryBubble);
    }

    for (var i = 0; i < copy.length; i++) {
      final message = copy[i];
      if (!ids.contains(message.id) || message.id == summaryBubble.id) {
        continue;
      }
      copy[i] = message.copyWith(
        omittedFromModelPayload: true,
        summaryId: summaryBubble.id,
      );
    }

    return copy;
  }

  int _estimateOutgoingPayload({
    required List<Bubble> messages,
    required Map<String, dynamic> extraParams,
    Set<String> omittedMessageIds = const {},
  }) {
    if (messages.isEmpty) return 0;
    final payload = PayloadBuilder.buildPayloadWithTools(
      messages: messages,
      upToIndexInclusive: messages.length - 1,
      omitCoveredMessages: true,
      omittedMessageIds: omittedMessageIds,
    );
    return ContextEstimator.estimateChatCompletionRequest(
      messages: payload,
      extraParams: extraParams,
    );
  }

  List<Bubble> _selectCandidates(
    List<Bubble> messages, {
    required bool aggressive,
  }) {
    final firstUserIndex = messages.indexWhere(
      (message) => message.role == MessageRole.user,
    );
    final preserveRecent = aggressive ? 2 : settings.recentWindowUnits;

    final eligibleIndices = <int>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (i == 0 ||
          i == firstUserIndex ||
          message.isSummaryMemory ||
          message.omittedFromModelPayload ||
          message.role == MessageRole.system ||
          message.role == MessageRole.tool) {
        continue;
      }
      eligibleIndices.add(i);
    }

    if (eligibleIndices.length <= preserveRecent) return const [];

    final recentIndices = eligibleIndices
        .skip(math.max(0, eligibleIndices.length - preserveRecent))
        .toSet();

    return [
      for (final index in eligibleIndices)
        if (!recentIndices.contains(index)) messages[index],
    ];
  }

  Bubble? _latestSummary(List<Bubble> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isSummaryMemory) return messages[i];
    }
    return null;
  }

  List<Bubble> _preservedAnchorMessages(List<Bubble> messages) {
    final anchors = <Bubble>[];
    if (messages.isNotEmpty && messages.first.role == MessageRole.system) {
      anchors.add(messages.first);
    }

    final firstUser = messages.where((message) {
      return message.role == MessageRole.user &&
          !message.omittedFromModelPayload;
    }).firstOrNull;

    if (firstUser != null) {
      anchors.add(firstUser);
    }

    return anchors;
  }

  int _summaryInsertIndex(List<Bubble> messages) {
    final firstUserIndex = messages.indexWhere(
      (message) => message.role == MessageRole.user,
    );
    if (firstUserIndex >= 0) return firstUserIndex + 1;
    return messages.isEmpty ? 0 : 1;
  }

  bool _hasUnresolvedToolCalls(List<Bubble> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role != MessageRole.assistant) continue;
      return message.tools.values.any((tool) => tool.result == null);
    }
    return false;
  }
}

class CompactionResult {
  final bool compacted;
  final int? estimatedTokensBefore;
  final int? estimatedTokensAfter;
  final int messagesCovered;
  final bool emergencyPayloadTruncation;
  final Set<String> emergencyOmittedMessageIds;

  const CompactionResult({
    required this.compacted,
    this.estimatedTokensBefore,
    this.estimatedTokensAfter,
    this.messagesCovered = 0,
    this.emergencyPayloadTruncation = false,
    this.emergencyOmittedMessageIds = const {},
  });

  int? get estimatedTokensSaved {
    final before = estimatedTokensBefore;
    final after = estimatedTokensAfter;
    if (before == null || after == null) return null;
    return math.max(0, before - after);
  }
}

class CompactionException implements Exception {
  final String message;

  const CompactionException(this.message);

  @override
  String toString() => message;
}
