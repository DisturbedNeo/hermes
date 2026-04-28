import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/tool_service.dart';

enum OpenChatTarget { currentTab, newTab }

class ChatTabsService extends ChangeNotifier {
  final ChatLibraryService _chatLibrary;
  final ToolService _toolService;

  final LlamaServerManager serverManager = LlamaServerManager();
  final List<ChatService> _tabs = [];

  String? activeTabId;
  bool _disposed = false;

  ChatTabsService({
    required ChatLibraryService chatLibrary,
    required ToolService toolService,
  }) : _chatLibrary = chatLibrary,
       _toolService = toolService {
    newTab();
  }

  UnmodifiableListView<ChatService> get tabs => UnmodifiableListView(_tabs);

  ChatService? get activeChat {
    final id = activeTabId;
    if (id == null) return _tabs.firstOrNull;
    return _tabs.where((tab) => tab.tabId == id).firstOrNull;
  }

  ChatService newTab() {
    final tab = _createTab();
    _tabs.add(tab);
    activeTabId = tab.tabId;
    notifyListeners();
    return tab;
  }

  Future<void> selectTab(String tabId) async {
    if (activeTabId == tabId) return;
    final tab = _tabById(tabId);
    if (tab == null) return;

    activeTabId = tabId;
    notifyListeners();
    await tab.refreshModelRestorePrompt();
  }

  bool isSavedChatOpen(String chatId) =>
      _tabs.any((tab) => tab.currentChatId == chatId);

  ChatService? tabForSavedChat(String chatId) =>
      _tabs.where((tab) => tab.currentChatId == chatId).firstOrNull;

  Future<bool> openSavedChat(
    String chatId, {
    required OpenChatTarget target,
  }) async {
    final existing = tabForSavedChat(chatId);
    if (existing != null) {
      await selectTab(existing.tabId);
      return true;
    }

    final tab = target == OpenChatTarget.newTab ? _createTab() : activeChat;
    if (tab == null) return false;

    if (target == OpenChatTarget.newTab) {
      _tabs.add(tab);
      activeTabId = tab.tabId;
      notifyListeners();
    }

    final opened = await tab.openChat(chatId);
    if (!opened && target == OpenChatTarget.newTab) {
      await _removeTab(tab);
    }

    notifyListeners();
    return opened;
  }

  Future<void> saveCurrentChat({String? title}) async {
    await activeChat?.saveCurrentChat(title: title);
    notifyListeners();
  }

  Future<void> closeTab(String tabId) async {
    final tab = _tabById(tabId);
    if (tab == null) return;
    final wasActive = activeTabId == tabId;
    await _removeTab(tab);
    if (_tabs.isEmpty) {
      newTab();
    } else if (wasActive) {
      await activeChat?.refreshModelRestorePrompt();
      notifyListeners();
    }
  }

  Future<void> saveAndCloseTab(String tabId) async {
    final tab = _tabById(tabId);
    if (tab == null) return;
    await tab.saveCurrentChat();
    await closeTab(tabId);
  }

  Future<void> deleteSavedChat(String chatId) async {
    await _chatLibrary.deleteChat(chatId);
    for (final tab in _tabs.where((tab) => tab.currentChatId == chatId)) {
      await tab.newChat();
    }
    notifyListeners();
  }

  ChatService _createTab() {
    final tab = ChatService(
      serverManager: serverManager,
      toolService: _toolService,
      chatLibrary: _chatLibrary,
    );
    tab.addListener(notifyListeners);
    tab.messageStore.addListener(notifyListeners);
    tab.chatStream.addListener(notifyListeners);
    return tab;
  }

  ChatService? _tabById(String tabId) =>
      _tabs.where((tab) => tab.tabId == tabId).firstOrNull;

  Future<void> _removeTab(ChatService tab) async {
    final index = _tabs.indexOf(tab);
    if (index == -1) return;

    tab.removeListener(notifyListeners);
    tab.messageStore.removeListener(notifyListeners);
    tab.chatStream.removeListener(notifyListeners);
    _tabs.removeAt(index);

    if (activeTabId == tab.tabId) {
      if (_tabs.isEmpty) {
        activeTabId = null;
      } else {
        final nextIndex = index.clamp(0, _tabs.length - 1);
        activeTabId = _tabs[nextIndex].tabId;
      }
    }

    await tab.dispose();
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final tab in List<ChatService>.of(_tabs)) {
      await _removeTab(tab);
    }
    await serverManager.dispose();
    super.dispose();
  }
}
