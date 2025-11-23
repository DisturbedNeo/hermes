import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/upsert_result.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';

class MessageStore extends ChangeNotifier {
  List<Bubble> _messages = [];
  UnmodifiableListView<Bubble>? _messageCache;
  final Map<String, int> _indexMap = {};
  String? _currentId;

  UnmodifiableListView<Bubble> get messages => _messageCache ??= UnmodifiableListView(_messages);
  set messages(List<Bubble> val) {
    _messages = val;
    _messageCache = UnmodifiableListView(val);
  }
  int? get currentIndex => _currentId == null ? null : _indexMap[_currentId!];
  Bubble? get currentMessage {
    final i = currentIndex;
    return i == null ? null : _messages[i];
  }

  Bubble get first => _messages.first;
  Bubble get last => _messages.last;

  bool get isEmpty => _messages.isEmpty;

  void setMessages(List<Bubble> items, {String? currentId}) {
    messages = List<Bubble>.of(items, growable: true);
    _rebuildIndex();
    _currentId = currentId;
    if (_currentId != null && !_indexMap.containsKey(_currentId)) _currentId = null;
    notifyListeners();
  }

  void insertAt(int index, Bubble b) {
    index = index.clamp(0, _messages.length);
    _messages.insert(index, b);
    _rebuildIndex();
    notifyListeners();
  }

  UpsertResult upsert(Bubble b) {
    final index = _indexMap[b.id];
    if (index == null) {
      _messages.add(b);
      _indexMap[b.id] = _messages.length - 1;
      notifyListeners();
      return UpsertResult.inserted;
    } else {
      _messages[index] = b;
      notifyListeners();
      return UpsertResult.updated;
    }
  }

  bool replaceById(String id, Bubble newMessage) {
    final index = _indexMap[id];
    if (index == null) return false;
    assert(id == newMessage.id, 'Replacing with a different id will break indexing');
    _messages[index] = newMessage;
    notifyListeners();
    return true;
  }

  bool removeById(String id) {
    final index = _indexMap.remove(id);
    if (index == null) return false;
    _messages.removeAt(index);
    _rebuildIndex();
    if (id == _currentId) _currentId = null;
    notifyListeners();
    return true;
  }

  bool removeFromId(String id) {
    final index = _indexMap[id];
    if (index == null) return false;

    _messages.removeRange(index, _messages.length);
    _rebuildIndex();

    if (!_indexMap.containsKey(_currentId)) {
      _currentId = null;
    }

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
      );
      upsert(bubble);
      targetId = bubble.id;
    } else {
      final index = messages.indexWhere((m) => m.id == targetId);
      if (index == -1 ||
          messages[index].role != MessageRole.assistant) {
        final bubble = Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: '',
          reasoning: '',
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
      ToolCaller.clearForMessage(_currentId!);
    }

    setCurrentId(null);
  }

  void _rebuildIndex() {
    _indexMap..clear()..addEntries(Iterable<int>.generate(_messages.length).map((i) => MapEntry(_messages[i].id, i)));
  }
}
