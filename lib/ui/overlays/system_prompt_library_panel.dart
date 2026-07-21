import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/ui/common/state_display.dart';
import 'system_prompt_library_dialogs.dart';

class SystemPromptLibraryPanel extends StatefulWidget {
  final VoidCallback? onPromptLoaded;
  final ChatTabsService tabs;
  final SystemPromptLibraryService library;

  const SystemPromptLibraryPanel({
    super.key,
    this.onPromptLoaded,
    required this.tabs,
    required this.library,
  });

  @override
  State<SystemPromptLibraryPanel> createState() =>
      _SystemPromptLibraryPanelState();
}

class _SystemPromptLibraryPanelState extends State<SystemPromptLibraryPanel> {
  static const double _shortPanelHeight = 220;
  static const double _shortTabHeight = 96;
  static const double _compactTabViewHeight = 180;

  final _presetSearchController = TextEditingController();
  final _moduleSearchController = TextEditingController();

  late final ChatTabsService _tabs;
  late final SystemPromptLibraryService _library;

  List<PromptPreset> _presets = const [];
  List<PromptModule> _modules = const [];
  bool _loading = true;
  Object? _error;
  String _presetQuery = '';
  String _moduleQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = widget.tabs;
    _library = widget.library;
    _presetSearchController.addListener(_handlePresetSearchChanged);
    _moduleSearchController.addListener(_handleModuleSearchChanged);
    _library.addListener(_refresh);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _presetSearchController.removeListener(_handlePresetSearchChanged);
    _moduleSearchController.removeListener(_handleModuleSearchChanged);
    _presetSearchController.dispose();
    _moduleSearchController.dispose();
    _library.removeListener(_refresh);
    super.dispose();
  }

  void _handlePresetSearchChanged() {
    final next = _presetSearchController.text.trim();
    if (next == _presetQuery) return;
    setState(() => _presetQuery = next);
    unawaited(_reload(showLoading: false));
  }

  void _handleModuleSearchChanged() {
    final next = _moduleSearchController.text.trim();
    if (next == _moduleQuery) return;
    setState(() => _moduleQuery = next);
    unawaited(_reload(showLoading: false));
  }

  void _refresh() {
    if (!mounted) return;
    unawaited(_reload(showLoading: false));
  }

  Future<void> _reload({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final presets = _presetQuery.isEmpty
          ? await _library.listPresets()
          : await _library.searchPresets(_presetQuery);
      final modules = _moduleQuery.isEmpty
          ? await _library.listModules()
          : await _library.searchModules(_moduleQuery);
      if (!mounted) return;
      setState(() {
        _presets = presets;
        _modules = modules;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _createPreset() async {
    final draft = await PromptLibraryPresetEditorDialog.show(
      context,
      modules: _modules,
    );
    if (draft == null) return;

    try {
      await _library.createPreset(
        name: draft.name,
        baseModuleIds: draft.baseModuleIds,
        optionalModuleIds: draft.optionalModuleIds,
        customInstructions: draft.customInstructions,
        legacyFullPrompt: draft.legacyFullPrompt,
      );
      await _reload(showLoading: false);
      _showMessage('Preset created');
    } catch (e) {
      _showMessage('Failed to create preset: $e');
    }
  }

  Future<void> _editPreset(PromptPreset preset) async {
    final draft = await PromptLibraryPresetEditorDialog.show(
      context,
      preset: preset,
      modules: _modules,
    );
    if (draft == null) return;

    try {
      await _library.updatePreset(
        id: preset.id,
        name: draft.name,
        baseModuleIds: draft.baseModuleIds,
        optionalModuleIds: draft.optionalModuleIds,
        customInstructions: draft.customInstructions,
        legacyFullPrompt: draft.legacyFullPrompt,
      );
      await _reload(showLoading: false);
      _showMessage('Preset saved');
    } catch (e) {
      _showMessage('Failed to save preset: $e');
    }
  }

  Future<void> _duplicatePreset(PromptPreset preset) async {
    try {
      await _library.duplicatePreset(preset.id);
      await _reload(showLoading: false);
      _showMessage('Preset duplicated');
    } catch (e) {
      _showMessage('Failed to duplicate preset: $e');
    }
  }

  Future<void> _deletePreset(PromptPreset preset) async {
    final confirmed = await _confirmDelete('Delete preset', preset.name);
    if (confirmed != true) return;

    try {
      await _library.deletePreset(preset.id);
      await _reload(showLoading: false);
      _showMessage('Preset deleted');
    } catch (e) {
      _showMessage('Failed to delete preset: $e');
    }
  }

  Future<void> _loadPreset(PromptPreset preset) async {
    try {
      final modules = await _library.listModules();
      var selectedOptionalModuleIds = const <String>[];
      final optionalModules = modules
          .where((module) => preset.optionalModuleIds.contains(module.id))
          .toList();
      if (!preset.isLegacy && optionalModules.isNotEmpty) {
        if (!mounted) return;
        final activeChat = _tabs.activeChat;
        final targetWorkspace =
            activeChat != null && !activeChat.isSystemPromptLocked
            ? activeChat.workspace
            : null;
        final selection = await PromptLibraryPresetLoadDialog.show(
          context,
          preset: preset,
          modules: modules,
          library: _library,
          workspace: targetWorkspace,
        );
        if (selection == null) return;
        selectedOptionalModuleIds = selection;
      }

      await _tabs.loadPromptPresetIntoActiveChat(
        preset,
        selectedOptionalModuleIds: selectedOptionalModuleIds,
      );
      if (!mounted) return;
      widget.onPromptLoaded?.call();
    } catch (e) {
      _showMessage('Failed to load preset: $e');
    }
  }

  Future<void> _previewPreset(PromptPreset preset) async {
    try {
      final result = await _library.assemblePreset(
        preset,
        workspace: _tabs.activeChat?.workspace,
      );
      if (!mounted) return;
      await PromptLibraryPreviewDialog.show(
        context,
        preset: preset,
        result: result,
      );
    } catch (e) {
      _showMessage('Failed to preview preset: $e');
    }
  }

  Future<void> _createModule() async {
    final draft = await PromptLibraryModuleEditorDialog.show(
      context,
      modules: _modules,
    );
    if (draft == null) return;

    try {
      await _library.createModule(
        name: draft.name,
        category: draft.category,
        content: draft.content,
        priority: draft.priority,
        requiredModuleIds: draft.requiredModuleIds,
        conflictingModuleIds: draft.conflictingModuleIds,
      );
      await _reload(showLoading: false);
      _showMessage('Module created');
    } catch (e) {
      _showMessage('Failed to create module: $e');
    }
  }

  Future<void> _editModule(PromptModule module) async {
    final draft = await PromptLibraryModuleEditorDialog.show(
      context,
      module: module,
      modules: _modules,
    );
    if (draft == null) return;

    try {
      await _library.updateModule(
        id: module.id,
        name: draft.name,
        category: draft.category,
        content: draft.content,
        priority: draft.priority,
        requiredModuleIds: draft.requiredModuleIds,
        conflictingModuleIds: draft.conflictingModuleIds,
      );
      await _reload(showLoading: false);
      _showMessage('Module saved');
    } catch (e) {
      _showMessage('Failed to save module: $e');
    }
  }

  Future<void> _duplicateModule(PromptModule module) async {
    try {
      await _library.duplicateModule(module.id);
      await _reload(showLoading: false);
      _showMessage('Module duplicated');
    } catch (e) {
      _showMessage('Failed to duplicate module: $e');
    }
  }

  Future<void> _deleteModule(PromptModule module) async {
    final confirmed = await _confirmDelete('Delete module', module.name);
    if (confirmed != true) return;

    try {
      await _library.deleteModule(module.id);
      await _reload(showLoading: false);
      _showMessage('Module deleted');
    } catch (e) {
      _showMessage('Failed to delete module: $e');
    }
  }

  Future<bool?> _confirmDelete(String title, String name) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(
          'Delete "$name"? Existing saved chats keep their prompt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.hasBoundedHeight &&
              constraints.maxHeight < _shortPanelHeight;
          final state = _loading
              ? DisplayState.loading
              : (_error != null ? DisplayState.error : DisplayState.content);
          final tabView = StateDisplay(
            state: state,
            content: TabBarView(
              children: [_buildPresetTab(), _buildModuleTab()],
            ),
            errorMessage: 'Failed to load prompt library: $_error',
            onRetry: _error != null ? _reload : null,
          );
          final content = Column(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              const ListTile(
                title: Text(
                  'System Prompts',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('Presets assemble reusable prompt modules'),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Presets'),
                  Tab(text: 'Modules'),
                ],
              ),
              const Divider(height: 1),
              if (compact)
                SizedBox(height: _compactTabViewHeight, child: tabView)
              else
                Expanded(child: tabView),
            ],
          );

          if (!compact) return content;

          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: content,
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresetTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight &&
            constraints.maxHeight < _shortTabHeight;
        final body = _buildPresetTabBody(scrollable: !compact);

        return _buildLibraryTab(
          compact: compact,
          toolbar: _PanelToolbar(
            controller: _presetSearchController,
            hintText: 'Search presets',
            createTooltip: 'Create preset',
            onCreate: _createPreset,
          ),
          body: body,
        );
      },
    );
  }

  Widget _buildModuleTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight &&
            constraints.maxHeight < _shortTabHeight;
        final body = _buildModuleTabBody(scrollable: !compact);

        return _buildLibraryTab(
          compact: compact,
          toolbar: _PanelToolbar(
            controller: _moduleSearchController,
            hintText: 'Search modules',
            createTooltip: 'Create module',
            onCreate: _createModule,
          ),
          body: body,
        );
      },
    );
  }

  Widget _buildLibraryTab({
    required bool compact,
    required Widget toolbar,
    required Widget body,
  }) {
    final content = Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        toolbar,
        const Divider(height: 1),
        if (compact) body else Expanded(child: body),
      ],
    );

    if (!compact) return content;

    return SingleChildScrollView(child: content);
  }

  Widget _buildPresetTabBody({required bool scrollable}) {
    if (_presets.isEmpty) {
      return StateDisplay(
        state: DisplayState.empty,
        emptyMessage: _presetQuery.isEmpty
            ? 'No prompt presets'
            : 'No matching presets',
        emptyHint: _presetQuery.isEmpty
            ? 'Create a preset to reuse prompt modules'
            : 'Try a different search term',
        icon: Icons.display_settings_outlined,
      );
    }

    return ListView.separated(
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      itemCount: _presets.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _PresetTile(
        preset: _presets[i],
        onLoad: () => unawaited(_loadPreset(_presets[i])),
        onPreview: () => unawaited(_previewPreset(_presets[i])),
        onEdit: _presets[i].isBuiltIn
            ? null
            : () => unawaited(_editPreset(_presets[i])),
        onDuplicate: () => unawaited(_duplicatePreset(_presets[i])),
        onDelete: _presets[i].isBuiltIn
            ? null
            : () => unawaited(_deletePreset(_presets[i])),
      ),
    );
  }

  Widget _buildModuleTabBody({required bool scrollable}) {
    if (_modules.isEmpty) {
      return StateDisplay(
        state: DisplayState.empty,
        emptyMessage: _moduleQuery.isEmpty
            ? 'No prompt modules'
            : 'No matching modules',
        emptyHint: _moduleQuery.isEmpty
            ? 'Create a module to build reusable prompts'
            : 'Try a different search term',
        icon: Icons.extension_outlined,
      );
    }

    return ListView.separated(
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      itemCount: _modules.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _ModuleTile(
        module: _modules[i],
        onEdit: _modules[i].isBuiltIn
            ? null
            : () => unawaited(_editModule(_modules[i])),
        onDuplicate: () => unawaited(_duplicateModule(_modules[i])),
        onDelete: _modules[i].isBuiltIn
            ? null
            : () => unawaited(_deleteModule(_modules[i])),
      ),
    );
  }
}

class _PanelToolbar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String createTooltip;
  final VoidCallback onCreate;

  const _PanelToolbar({
    required this.controller,
    required this.hintText,
    required this.createTooltip,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: hintText,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: createTooltip,
            icon: const Icon(Icons.add),
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  static const double _compactWidth = 360;

  final PromptPreset preset;
  final VoidCallback onLoad;
  final VoidCallback onPreview;
  final VoidCallback? onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  const _PresetTile({
    required this.preset,
    required this.onLoad,
    required this.onPreview,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth && constraints.maxWidth < _compactWidth;

        void handleAction(_PresetAction action) {
          switch (action) {
            case _PresetAction.load:
              onLoad();
              break;
            case _PresetAction.preview:
              onPreview();
              break;
            case _PresetAction.edit:
              onEdit?.call();
              break;
            case _PresetAction.duplicate:
              onDuplicate();
              break;
            case _PresetAction.delete:
              onDelete?.call();
              break;
          }
        }

        Widget actionMenu({required bool includeLoad}) {
          return PopupMenuButton<_PresetAction>(
            tooltip: 'Preset actions',
            onSelected: handleAction,
            itemBuilder: (_) => [
              if (includeLoad)
                const PopupMenuItem(
                  value: _PresetAction.load,
                  child: Text('Load'),
                ),
              const PopupMenuItem(
                value: _PresetAction.preview,
                child: Text('Preview'),
              ),
              PopupMenuItem(
                value: _PresetAction.edit,
                enabled: onEdit != null,
                child: const Text('Edit'),
              ),
              const PopupMenuItem(
                value: _PresetAction.duplicate,
                child: Text('Duplicate'),
              ),
              PopupMenuItem(
                value: _PresetAction.delete,
                enabled: onDelete != null,
                child: const Text('Delete'),
              ),
            ],
          );
        }

        return ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
          minLeadingWidth: compact ? 28 : 40,
          leading: Icon(
            preset.isLegacy
                ? Icons.article_outlined
                : Icons.account_tree_outlined,
          ),
          title: _LockableTitle(text: preset.name, locked: preset.isBuiltIn),
          subtitle: Text(
            preset.isLegacy
                ? compactPreview(preset.legacyFullPrompt ?? '')
                : '${preset.baseModuleIds.length} base, ${preset.optionalModuleIds.length} optional${preset.customInstructions.trim().isEmpty ? '' : ' + custom instructions'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: compact
              ? actionMenu(includeLoad: true)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Load'),
                      onPressed: onLoad,
                    ),
                    actionMenu(includeLoad: false),
                  ],
                ),
          onTap: compact ? onLoad : null,
        );
      },
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final PromptModule module;
  final VoidCallback? onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  const _ModuleTile({
    required this.module,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth && constraints.maxWidth < 320;

        return ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
          minLeadingWidth: compact ? 28 : 40,
          leading: const Icon(Icons.view_module_outlined),
          title: _LockableTitle(text: module.name, locked: module.isBuiltIn),
          subtitle: Text(
            '${module.category} - priority ${module.priority} - ${compactPreview(module.content)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: PopupMenuButton<_ModuleAction>(
            tooltip: 'Module actions',
            onSelected: (action) {
              switch (action) {
                case _ModuleAction.edit:
                  onEdit?.call();
                  break;
                case _ModuleAction.duplicate:
                  onDuplicate();
                  break;
                case _ModuleAction.delete:
                  onDelete?.call();
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _ModuleAction.edit,
                enabled: onEdit != null,
                child: Text(module.isBuiltIn ? 'View' : 'Edit'),
              ),
              const PopupMenuItem(
                value: _ModuleAction.duplicate,
                child: Text('Duplicate'),
              ),
              PopupMenuItem(
                value: _ModuleAction.delete,
                enabled: onDelete != null,
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LockableTitle extends StatelessWidget {
  static const double _minimumLockWidth = 32;

  final String text;
  final bool locked;

  const _LockableTitle({required this.text, required this.locked});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showLock =
            locked &&
            constraints.hasBoundedWidth &&
            constraints.maxWidth >= _minimumLockWidth;

        return Row(
          children: [
            Expanded(
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (showLock)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.lock_outline, size: 14),
              ),
          ],
        );
      },
    );
  }
}

enum _PresetAction { load, preview, edit, duplicate, delete }

enum _ModuleAction { edit, duplicate, delete }
