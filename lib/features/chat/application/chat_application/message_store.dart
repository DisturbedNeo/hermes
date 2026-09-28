import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/upsert_result.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';

class MessageStore extends ChangeNotifier {
  MessageStore({ToolCaller? toolCaller})
    : toolCaller = toolCaller ?? ToolCaller();

  final ToolCaller toolCaller;

  List<Bubble> _messages = [];
  UnmodifiableListView<Bubble>? _messageCache;
  final Map<String, int> _indexMap = {};
  String? _currentId;
  bool _updatingCompactionMetadata = false;
  int _displayRevision = 0;

  UnmodifiableListView<Bubble> get messages =>
      _messageCache ??= UnmodifiableListView(_messages);
  set messages(List<Bubble> val) {
    _messages = val;
    _messageCache = UnmodifiableListView(val);
  }

  int get displayRevision => _displayRevision;

  int? get currentIndex => _currentId == null ? null : _indexMap[_currentId!];
  Bubble? get currentMessage {
    final i = currentIndex;
    return i == null ? null : _messages[i];
  }

  Bubble? messageById(String id) {
    final index = _indexMap[id];
    return index == null ? null : _messages[index];
  }

  Bubble get first => _messages.first;
  Bubble get last => _messages.last;

  bool get isEmpty => _messages.isEmpty;

  void setMessages(List<Bubble> items, {String? currentId}) {
    messages = _repairCompactionMetadata(
      List<Bubble>.of(items, growable: true),
    );
    _rebuildIndex();
    _currentId = currentId;
    if (_currentId != null && !_indexMap.containsKey(_currentId)) {
      _currentId = null;
    }
    _markDisplayChanged();
    notifyListeners();
  }

  void insertAt(int index, Bubble b) {
    index = index.clamp(0, _messages.length);
    _messages.insert(index, b);
    _rebuildIndex();
    _markDisplayChanged();
    notifyListeners();
  }

  UpsertResult upsert(Bubble b) {
    final index = _indexMap[b.id];
    if (index == null) {
      _messages.add(b);
      _indexMap[b.id] = _messages.length - 1;
      _markDisplayChanged();
      notifyListeners();
      return UpsertResult.inserted;
    } else {
      final existing = _messages[index];
      var displayChanged = _displayShapeChanged(existing, b);
      final summaryToInvalidate = _summaryToInvalidateForReplacement(
        existing,
        b,
      );
      if (summaryToInvalidate != null) {
        _invalidateSummary(summaryToInvalidate);
        b = b.copyWith(omittedFromModelPayload: false, summaryId: null);
        displayChanged = true;
      }
      final replacementIndex = _indexMap[b.id];
      if (replacementIndex == null) return UpsertResult.inserted;
      _messages[replacementIndex] = b;
      if (displayChanged) _markDisplayChanged();
      notifyListeners();
      return UpsertResult.updated;
    }
  }

  bool replaceById(String id, Bubble newMessage) {
    final index = _indexMap[id];
    if (index == null) return false;
    final existing = _messages[index];
    var displayChanged = _displayShapeChanged(existing, newMessage);
    assert(
      id == newMessage.id,
      'Replacing with a different id will break indexing',
    );
    final summaryToInvalidate = _summaryToInvalidateForReplacement(
      existing,
      newMessage,
    );
    if (summaryToInvalidate != null) {
      _invalidateSummary(summaryToInvalidate);
      newMessage = newMessage.copyWith(
        omittedFromModelPayload: false,
        summaryId: null,
      );
      displayChanged = true;
    }
    final replacementIndex = _indexMap[id];
    if (replacementIndex == null) return false;
    _messages[replacementIndex] = newMessage;
    if (displayChanged) _markDisplayChanged();
    notifyListeners();
    return true;
  }

  bool removeById(String id) {
    final index = _indexMap.remove(id);
    if (index == null) return false;
    final removed = _messages[index];
    _messages.removeAt(index);
    _rebuildIndex();
    if (id == _currentId) _currentId = null;
    if (!_updatingCompactionMetadata) {
      if (removed.isSummaryMemory) {
        _clearCoverageForSummary(id);
      } else if (removed.summaryId != null) {
        _invalidateSummary(removed.summaryId!);
      }
    }
    _markDisplayChanged();
    notifyListeners();
    return true;
  }

  bool removeFromId(String id) {
    final index = _indexMap[id];
    if (index == null) return false;

    final removed = _messages.sublist(index);
    final invalidSummaryIds = <String>{
      for (final message in removed)
        if (message.isSummaryMemory) message.id,
      for (final message in removed)
        if (message.summaryId != null) message.summaryId!,
    };

    _messages.removeRange(index, _messages.length);
    _rebuildIndex();

    if (!_indexMap.containsKey(_currentId)) {
      _currentId = null;
    }

    if (!_updatingCompactionMetadata) {
      for (final summaryId in invalidSummaryIds) {
        _invalidateSummary(summaryId);
      }
    }

    _markDisplayChanged();
    notifyListeners();

    return true;
  }

  bool move(String id, int newIndex) {
    final index = _indexMap[id];
    if (index == null) return false;
    final item = _messages.removeAt(index);
    final target = newIndex.clamp(0, _messages.length);
    _messages.insert(target, item);
    _rebuildIndex();
    _markDisplayChanged();
    notifyListeners();
    return true;
  }

  String ensureAssistantTarget(String? assistantId) {
    String? targetId = assistantId;

    if (targetId == null) {
      final bubble = Bubble(
        id: uuid.v7(),
        role: MessageRole.assistant,
        text: '',
        reasoning: '',
        createdAt: DateTime.now(),
      );
      upsert(bubble);
      targetId = bubble.id;
    } else {
      final index = messages.indexWhere((m) => m.id == targetId);
      if (index == -1 || messages[index].role != MessageRole.assistant) {
        final bubble = Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: '',
          reasoning: '',
          createdAt: DateTime.now(),
        );
        upsert(bubble);
        targetId = bubble.id;
      }
    }

    setCurrentId(targetId);

    return targetId;
  }

  void setCurrentId(String? id) {
    _currentId = (id != null && _indexMap.containsKey(id)) ? id : null;
  }

  void clearCurrentId() {
    if (_currentId != null) {
      toolCaller.clearForMessage(_currentId!);
    }

    setCurrentId(null);
  }

  void clearToolBuffers() {
    toolCaller.clearAll();
  }

  void markCoveredBySummary({
    required Iterable<String> messageIds,
    required String summaryId,
  }) {
    _withCompactionMetadataUpdate(() {
      final ids = messageIds.toSet();
      for (var i = 0; i < _messages.length; i++) {
        final message = _messages[i];
        if (!ids.contains(message.id) || message.id == summaryId) continue;
        _messages[i] = message.copyWith(
          omittedFromModelPayload: true,
          summaryId: summaryId,
        );
      }
    });
    _markDisplayChanged();
    notifyListeners();
  }

  bool isCoveredBySummary(String messageId) {
    final index = _indexMap[messageId];
    if (index == null) return false;
    return _messages[index].omittedFromModelPayload;
  }

  String? summaryIdFor(String messageId) {
    final index = _indexMap[messageId];
    if (index == null) return null;
    return _messages[index].summaryId;
  }

  List<String> coveredMessageIdsForSummary(String summaryId) {
    return _messages
        .where(
          (message) =>
              message.omittedFromModelPayload && message.summaryId == summaryId,
        )
        .map((message) => message.id)
        .toList();
  }

  void _withCompactionMetadataUpdate(VoidCallback update) {
    final previous = _updatingCompactionMetadata;
    _updatingCompactionMetadata = true;
    try {
      update();
    } finally {
      _updatingCompactionMetadata = previous;
    }
  }

  String? _summaryToInvalidateForReplacement(
    Bubble existing,
    Bubble replacement,
  ) {
    if (_updatingCompactionMetadata || existing.isSummaryMemory) {
      return null;
    }

    if (!existing.omittedFromModelPayload || existing.summaryId == null) {
      return null;
    }

    if (!_contentChanged(existing, replacement)) {
      return null;
    }

    return existing.summaryId;
  }

  bool _contentChanged(Bubble a, Bubble b) {
    if (a.role != b.role ||
        a.text != b.text ||
        a.reasoning != b.reasoning ||
        a.tools.length != b.tools.length) {
      return true;
    }

    for (final entry in a.tools.entries) {
      final other = b.tools[entry.key];
      final tool = entry.value;
      if (other == null ||
          tool.id != other.id ||
          tool.name != other.name ||
          tool.arguments != other.arguments ||
          tool.result != other.result) {
        return true;
      }
    }

    return false;
  }

  void _invalidateSummary(String summaryId) {
    _withCompactionMetadataUpdate(() {
      _clearCoverageForSummary(summaryId);
      final summaryIndex = _indexMap[summaryId];
      if (summaryIndex != null) {
        _messages.removeAt(summaryIndex);
        _rebuildIndex();
      }
    });
  }

  void _clearCoverageForSummary(String summaryId) {
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.summaryId != summaryId) continue;
      _messages[i] = message.copyWith(
        omittedFromModelPayload: false,
        summaryId: null,
      );
    }
  }

  List<Bubble> _repairCompactionMetadata(List<Bubble> items) {
    final summaryIds = items
        .where((message) => message.isSummaryMemory)
        .map((message) => message.id)
        .toSet();

    return items
        .map((message) {
          if (message.isSummaryMemory) {
            return message.copyWith(
              omittedFromModelPayload: false,
              summaryId: null,
            );
          }

          final summaryId = message.summaryId;
          if (!message.omittedFromModelPayload ||
              summaryId == null ||
              !summaryIds.contains(summaryId)) {
            return message.copyWith(
              omittedFromModelPayload: false,
              summaryId: null,
            );
          }

          return message;
        })
        .toList(growable: true);
  }

  void _rebuildIndex() {
    _indexMap
      ..clear()
      ..addEntries(
        Iterable<int>.generate(
          _messages.length,
        ).map((i) => MapEntry(_messages[i].id, i)),
      );
  }

  bool _displayShapeChanged(Bubble a, Bubble b) {
    return a.role != b.role ||
        a.omittedFromModelPayload != b.omittedFromModelPayload ||
        a.summaryId != b.summaryId ||
        a.isSummaryMemory != b.isSummaryMemory;
  }

  void _markDisplayChanged() {
    _displayRevision++;
  }
}
