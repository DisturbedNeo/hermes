import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/prompt_assembler.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';

class SystemPromptLibraryPanel extends StatefulWidget {
  final VoidCallback? onPromptLoaded;
  final ChatTabsService? tabs;
  final SystemPromptLibraryService? library;

  const SystemPromptLibraryPanel({
    super.key,
    this.onPromptLoaded,
    this.tabs,
    this.library,
  });

  @override
  State<SystemPromptLibraryPanel> createState() =>
      _SystemPromptLibraryPanelState();
}

class _SystemPromptLibraryPanelState extends State<SystemPromptLibraryPanel> {
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
    _tabs = widget.tabs ?? serviceProvider.get<ChatTabsService>();
    _library =
        widget.library ?? serviceProvider.get<SystemPromptLibraryService>();
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
    final draft = await showDialog<_PresetDraft>(
      context: context,
      builder: (_) => _PresetEditorDialog(modules: _modules),
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
    final draft = await showDialog<_PresetDraft>(
      context: context,
      builder: (_) => _PresetEditorDialog(preset: preset, modules: _modules),
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
        final selection = await showDialog<List<String>>(
          context: context,
          builder: (_) => _PresetLoadDialog(
            preset: preset,
            modules: modules,
            library: _library,
            workspace: targetWorkspace,
          ),
        );
        if (selection == null) return;
        selectedOptionalModuleIds = selection;
      }

      final target = await _tabs.loadPromptPresetIntoActiveChat(
        preset,
        selectedOptionalModuleIds: selectedOptionalModuleIds,
      );
      if (!mounted) return;
      _showMessage(
        target == SystemPromptLoadTarget.currentChat
            ? 'Prompt loaded'
            : 'New chat opened with prompt',
      );
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
      await showDialog<void>(
        context: context,
        builder: (_) => _PreviewDialog(preset: preset, result: result),
      );
    } catch (e) {
      _showMessage('Failed to preview preset: $e');
    }
  }

  Future<void> _createModule() async {
    final draft = await showDialog<_ModuleDraft>(
      context: context,
      builder: (_) => _ModuleEditorDialog(modules: _modules),
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
    final draft = await showDialog<_ModuleDraft>(
      context: context,
      builder: (_) => _ModuleEditorDialog(module: module, modules: _modules),
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
      child: Column(
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorView(error: _error!)
                : TabBarView(children: [_buildPresetTab(), _buildModuleTab()]),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetTab() {
    return Column(
      children: [
        _PanelToolbar(
          controller: _presetSearchController,
          hintText: 'Search presets',
          createTooltip: 'Create preset',
          onCreate: _createPreset,
        ),
        const Divider(height: 1),
        Expanded(
          child: _presets.isEmpty
              ? Center(
                  child: Text(
                    _presetQuery.isEmpty
                        ? 'No prompt presets'
                        : 'No matching presets',
                  ),
                )
              : ListView.separated(
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
                ),
        ),
      ],
    );
  }

  Widget _buildModuleTab() {
    return Column(
      children: [
        _PanelToolbar(
          controller: _moduleSearchController,
          hintText: 'Search modules',
          createTooltip: 'Create module',
          onCreate: _createModule,
        ),
        const Divider(height: 1),
        Expanded(
          child: _modules.isEmpty
              ? Center(
                  child: Text(
                    _moduleQuery.isEmpty
                        ? 'No prompt modules'
                        : 'No matching modules',
                  ),
                )
              : ListView.separated(
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
                ),
        ),
      ],
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
    return ListTile(
      leading: Icon(
        preset.isLegacy ? Icons.article_outlined : Icons.account_tree_outlined,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (preset.isBuiltIn)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.lock_outline, size: 14),
            ),
        ],
      ),
      subtitle: Text(
        preset.isLegacy
            ? _preview(preset.legacyFullPrompt ?? '')
            : '${preset.baseModuleIds.length} base, ${preset.optionalModuleIds.length} optional${preset.customInstructions.trim().isEmpty ? '' : ' + custom instructions'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Load'),
            onPressed: onLoad,
          ),
          PopupMenuButton<_PresetAction>(
            tooltip: 'Preset actions',
            onSelected: (action) {
              switch (action) {
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
            },
            itemBuilder: (_) => [
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
          ),
        ],
      ),
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
    return ListTile(
      leading: const Icon(Icons.view_module_outlined),
      title: Row(
        children: [
          Expanded(
            child: Text(
              module.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (module.isBuiltIn)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.lock_outline, size: 14),
            ),
        ],
      ),
      subtitle: Text(
        '${module.category} - priority ${module.priority} - ${_preview(module.content)}',
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
  }
}

class _PresetLoadDialog extends StatefulWidget {
  final PromptPreset preset;
  final List<PromptModule> modules;
  final SystemPromptLibraryService library;
  final WorkspaceAttachment? workspace;

  const _PresetLoadDialog({
    required this.preset,
    required this.modules,
    required this.library,
    required this.workspace,
  });

  @override
  State<_PresetLoadDialog> createState() => _PresetLoadDialogState();
}

class _PresetLoadDialogState extends State<_PresetLoadDialog> {
  late final Set<String> _selectedOptionalIds;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _selectedOptionalIds = <String>{};
  }

  @override
  Widget build(BuildContext context) {
    final baseModules = _modulesForIds(
      widget.preset.baseModuleIds,
      widget.modules,
    );
    final optionalModules = _modulesForIds(
      widget.preset.optionalModuleIds,
      widget.modules,
    );

    return AlertDialog(
      title: Text('Load ${widget.preset.name}'),
      content: SizedBox(
        width: 640,
        height: 560,
        child: ListView(
          children: [
            if (baseModules.isNotEmpty)
              ExpansionTile(
                title: const Text('Base modules'),
                initiallyExpanded: true,
                children: [
                  for (final module in baseModules)
                    CheckboxListTile(
                      dense: true,
                      value: true,
                      onChanged: null,
                      title: Text(module.name),
                      subtitle: Text(
                        '${module.category} - priority ${module.priority}',
                      ),
                    ),
                ],
              ),
            _ModuleIdPickerSection(
              title: 'Optional modules',
              modules: optionalModules,
              selectedIds: _selectedOptionalIds,
              enabled: true,
              initiallyExpanded: true,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _previewing ? null : _preview,
          child: const Text('Preview'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_selectedOptionalIds.toList()),
          child: const Text('Load'),
        ),
      ],
    );
  }

  Future<void> _preview() async {
    setState(() => _previewing = true);
    try {
      final result = await widget.library.assemblePreset(
        widget.preset,
        selectedOptionalModuleIds: _selectedOptionalIds.toList(),
        workspace: widget.workspace,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _PreviewDialog(preset: widget.preset, result: result),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to preview preset: $e')));
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }
}

enum _PresetAction { preview, edit, duplicate, delete }

enum _ModuleAction { edit, duplicate, delete }

class _PresetDraft {
  final String name;
  final List<String> baseModuleIds;
  final List<String> optionalModuleIds;
  final String customInstructions;
  final String? legacyFullPrompt;

  const _PresetDraft({
    required this.name,
    required this.baseModuleIds,
    required this.optionalModuleIds,
    required this.customInstructions,
    required this.legacyFullPrompt,
  });
}

class _PresetEditorDialog extends StatefulWidget {
  final PromptPreset? preset;
  final List<PromptModule> modules;

  const _PresetEditorDialog({this.preset, required this.modules});

  @override
  State<_PresetEditorDialog> createState() => _PresetEditorDialogState();
}

class _PresetEditorDialogState extends State<_PresetEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _customController;
  late final TextEditingController _legacyController;
  late final Set<String> _baseModuleIds;
  late final Set<String> _optionalModuleIds;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    _nameController = TextEditingController(text: preset?.name ?? '');
    _customController = TextEditingController(
      text: preset?.customInstructions ?? '',
    );
    _legacyController = TextEditingController(
      text: preset?.legacyFullPrompt ?? '',
    );
    _baseModuleIds = {...?preset?.baseModuleIds};
    _optionalModuleIds = {...?preset?.optionalModuleIds};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customController.dispose();
    _legacyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.preset != null;
    final legacy = widget.preset?.isLegacy == true;

    return AlertDialog(
      title: Text(editing ? 'Edit preset' : 'Create preset'),
      content: SizedBox(
        width: 760,
        height: 680,
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _customController,
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Custom instructions',
                  alignLabelWithHint: true,
                ),
              ),
              if (legacy) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _legacyController,
                  minLines: 5,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Legacy full prompt',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _ModulePickerSection(
                title: 'Base modules',
                modules: widget.modules,
                selectedIds: _baseModuleIds,
                disabledIds: _optionalModuleIds,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 8),
              _ModulePickerSection(
                title: 'Optional modules',
                modules: widget.modules,
                selectedIds: _optionalModuleIds,
                disabledIds: _baseModuleIds,
                onChanged: () => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _preview, child: const Text('Preview')),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  void _preview() {
    final preset = PromptPreset(
      id: widget.preset?.id ?? 'draft',
      name: _nameController.text.trim().isEmpty
          ? 'Draft preset'
          : _nameController.text.trim(),
      baseModuleIds: _baseModuleIds.toList(),
      optionalModuleIds: _optionalModuleIds.toList(),
      customInstructions: _customController.text.trim(),
      legacyFullPrompt: _legacyController.text.trim().isEmpty
          ? null
          : _legacyController.text.trim(),
      isBuiltIn: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final result = const PromptAssembler().assemble(
      PromptAssemblyRequest(preset: preset, availableModules: widget.modules),
    );
    showDialog<void>(
      context: context,
      builder: (_) => _PreviewDialog(preset: preset, result: result),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _PresetDraft(
        name: _nameController.text.trim(),
        baseModuleIds: _baseModuleIds.toList(),
        optionalModuleIds: _optionalModuleIds.toList(),
        customInstructions: _customController.text.trim(),
        legacyFullPrompt: _legacyController.text.trim().isEmpty
            ? null
            : _legacyController.text.trim(),
      ),
    );
  }
}

class _ModuleDraft {
  final String name;
  final String category;
  final String content;
  final int priority;
  final List<String> requiredModuleIds;
  final List<String> conflictingModuleIds;

  const _ModuleDraft({
    required this.name,
    required this.category,
    required this.content,
    required this.priority,
    required this.requiredModuleIds,
    required this.conflictingModuleIds,
  });
}

class _ModuleEditorDialog extends StatefulWidget {
  final PromptModule? module;
  final List<PromptModule> modules;

  const _ModuleEditorDialog({this.module, required this.modules});

  @override
  State<_ModuleEditorDialog> createState() => _ModuleEditorDialogState();
}

class _ModuleEditorDialogState extends State<_ModuleEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _priorityController;
  late final TextEditingController _contentController;
  late final Set<String> _requiredIds;
  late final Set<String> _conflictingIds;

  @override
  void initState() {
    super.initState();
    final module = widget.module;
    _nameController = TextEditingController(text: module?.name ?? '');
    _categoryController = TextEditingController(text: module?.category ?? '');
    _priorityController = TextEditingController(
      text: (module?.priority ?? 100).toString(),
    );
    _contentController = TextEditingController(text: module?.content ?? '');
    _requiredIds = {...?module?.requiredModuleIds};
    _conflictingIds = {...?module?.conflictingModuleIds};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _priorityController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.module != null;
    final readOnly = widget.module?.isBuiltIn == true;

    return AlertDialog(
      title: Text(
        readOnly
            ? 'View module'
            : editing
            ? 'Edit module'
            : 'Create module',
      ),
      content: SizedBox(
        width: 760,
        height: 680,
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                readOnly: readOnly,
                autofocus: !readOnly,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _categoryController,
                      readOnly: readOnly,
                      decoration: const InputDecoration(labelText: 'Category'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a category'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: TextFormField(
                      controller: _priorityController,
                      readOnly: readOnly,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      validator: (value) =>
                          int.tryParse(value?.trim() ?? '') == null
                          ? 'Enter a number'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentController,
                readOnly: readOnly,
                minLines: 8,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter module content'
                    : null,
              ),
              const SizedBox(height: 16),
              _ModuleIdPickerSection(
                title: 'Required modules',
                modules: widget.modules
                    .where((module) => module.id != widget.module?.id)
                    .toList(),
                selectedIds: _requiredIds,
                enabled: !readOnly,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 8),
              _ModuleIdPickerSection(
                title: 'Conflicting modules',
                modules: widget.modules
                    .where((module) => module.id != widget.module?.id)
                    .toList(),
                selectedIds: _conflictingIds,
                enabled: !readOnly,
                onChanged: () => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(readOnly ? 'Close' : 'Cancel'),
        ),
        if (!readOnly)
          FilledButton(
            onPressed: _submit,
            child: Text(editing ? 'Save' : 'Create'),
          ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _ModuleDraft(
        name: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        content: _contentController.text.trim(),
        priority: int.parse(_priorityController.text.trim()),
        requiredModuleIds: _requiredIds.toList(),
        conflictingModuleIds: _conflictingIds.toList(),
      ),
    );
  }
}

class _ModulePickerSection extends StatelessWidget {
  final String title;
  final List<PromptModule> modules;
  final Set<String> selectedIds;
  final Set<String> disabledIds;
  final VoidCallback onChanged;

  const _ModulePickerSection({
    required this.title,
    required this.modules,
    required this.selectedIds,
    required this.disabledIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title),
      initiallyExpanded: true,
      children: [
        for (final module in modules)
          CheckboxListTile(
            dense: true,
            value: selectedIds.contains(module.id),
            onChanged: disabledIds.contains(module.id)
                ? null
                : (selected) {
                    if (selected == true) {
                      selectedIds.add(module.id);
                    } else {
                      selectedIds.remove(module.id);
                    }
                    onChanged();
                  },
            title: Text(module.name),
            subtitle: Text('${module.category} - priority ${module.priority}'),
          ),
      ],
    );
  }
}

class _ModuleIdPickerSection extends StatelessWidget {
  final String title;
  final List<PromptModule> modules;
  final Set<String> selectedIds;
  final bool enabled;
  final bool initiallyExpanded;
  final VoidCallback onChanged;

  const _ModuleIdPickerSection({
    required this.title,
    required this.modules,
    required this.selectedIds,
    required this.enabled,
    this.initiallyExpanded = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title),
      initiallyExpanded: initiallyExpanded,
      children: [
        for (final module in modules)
          CheckboxListTile(
            dense: true,
            value: selectedIds.contains(module.id),
            onChanged: enabled
                ? (selected) {
                    if (selected == true) {
                      selectedIds.add(module.id);
                    } else {
                      selectedIds.remove(module.id);
                    }
                    onChanged();
                  }
                : null,
            title: Text(module.name),
            subtitle: Text(module.category),
          ),
      ],
    );
  }
}

class _PreviewDialog extends StatelessWidget {
  final PromptPreset preset;
  final PromptAssemblyResult result;

  const _PreviewDialog({required this.preset, required this.result});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${preset.name} preview'),
      content: SizedBox(
        width: 760,
        height: 680,
        child: ListView(
          children: [
            Text(
              'Assembled prompt',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SelectableText(result.text.isEmpty ? '(empty)' : result.text),
            const Divider(height: 28),
            Text('Included modules: ${result.includedModules.length}'),
            for (final module in result.includedModules)
              ListTile(
                dense: true,
                leading: const Icon(Icons.check, size: 18),
                title: Text(module.name),
                subtitle: Text(
                  '${module.category} - priority ${module.priority}',
                ),
              ),
            if (result.omittedModules.isNotEmpty) ...[
              const Divider(height: 28),
              Text('Omitted modules: ${result.omittedModules.length}'),
              for (final module in result.omittedModules)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.block, size: 18),
                  title: Text(module.name),
                  subtitle: Text(module.category),
                ),
            ],
            if (result.diagnostics.isNotEmpty) ...[
              const Divider(height: 28),
              const Text('Diagnostics'),
              for (final item in result.diagnostics)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline, size: 18),
                  title: Text(item),
                ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;

  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load prompt library: $error'),
      ),
    );
  }
}

String _preview(String content) {
  final compact = content.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.length <= 96) return compact;
  return '${compact.substring(0, 93)}...';
}

List<PromptModule> _modulesForIds(
  List<String> ids,
  List<PromptModule> modules,
) {
  final byId = {for (final module in modules) module.id: module};
  return [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];
}
