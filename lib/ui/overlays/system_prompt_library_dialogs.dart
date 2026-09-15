import 'package:flutter/material.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/prompt_assembler.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';

// ── Data classes ──────────────────────────────────────────────────────────────

/// Parsed draft values from the preset editor dialog.
class PresetEditorDraft {
  final String name;
  final List<String> baseModuleIds;
  final List<String> optionalModuleIds;
  final String customInstructions;

  const PresetEditorDraft({
    required this.name,
    required this.baseModuleIds,
    required this.optionalModuleIds,
    required this.customInstructions,
  });
}

/// Parsed draft values from the module editor dialog.
class ModuleEditorDraft {
  final String name;
  final String category;
  final String content;
  final int priority;
  final List<String> requiredModuleIds;
  final List<String> conflictingModuleIds;

  const ModuleEditorDraft({
    required this.name,
    required this.category,
    required this.content,
    required this.priority,
    required this.requiredModuleIds,
    required this.conflictingModuleIds,
  });
}

// ── Utility functions ─────────────────────────────────────────────────────────

/// Returns a compact one-line preview of [content], truncating at 96 chars.
String compactPreview(String content) {
  final compact = content.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.length <= 96) return compact;
  return '${compact.substring(0, 93)}...';
}

/// Resolves module IDs to their corresponding [PromptModule] objects.
List<PromptModule> modulesById(List<String> ids, List<PromptModule> modules) {
  final byId = {for (final module in modules) module.id: module};
  return [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];
}

// ── Helper widgets ────────────────────────────────────────────────────────────

/// An expansion tile with checkboxes for selecting modules.
///
/// Used inside preset editors to pick base and optional modules.
class ModulePickerSection extends StatelessWidget {
  final String title;
  final List<PromptModule> modules;
  final Set<String> selectedIds;
  final Set<String> disabledIds;
  final VoidCallback onChanged;

  const ModulePickerSection({
    super.key,
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

/// An expansion tile with checkboxes for selecting module IDs.
///
/// Used inside module editors to pick required and conflicting modules.
class ModuleIdPickerSection extends StatelessWidget {
  final String title;
  final List<PromptModule> modules;
  final Set<String> selectedIds;
  final bool enabled;
  final bool initiallyExpanded;
  final VoidCallback onChanged;

  const ModuleIdPickerSection({
    super.key,
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

// ── Dialog widgets ────────────────────────────────────────────────────────────

/// Preview dialog showing the assembled prompt result for a preset.
class PromptLibraryPreviewDialog extends StatelessWidget {
  final PromptPreset preset;
  final PromptAssemblyResult result;

  const PromptLibraryPreviewDialog({
    super.key,
    required this.preset,
    required this.result,
  });

  /// Shows the preview dialog.
  static Future<void> show(
    BuildContext context, {
    required PromptPreset preset,
    required PromptAssemblyResult result,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          PromptLibraryPreviewDialog(preset: preset, result: result),
    );
  }

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

/// Dialog for selecting optional modules when loading a preset.
class PromptLibraryPresetLoadDialog extends StatefulWidget {
  final PromptPreset preset;
  final List<PromptModule> modules;
  final SystemPromptLibraryService library;
  final WorkspaceAttachment? workspace;

  const PromptLibraryPresetLoadDialog({
    super.key,
    required this.preset,
    required this.modules,
    required this.library,
    required this.workspace,
  });

  /// Shows the preset-load dialog and returns the selected optional module IDs.
  static Future<List<String>?> show(
    BuildContext context, {
    required PromptPreset preset,
    required List<PromptModule> modules,
    required SystemPromptLibraryService library,
    required WorkspaceAttachment? workspace,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => PromptLibraryPresetLoadDialog(
        preset: preset,
        modules: modules,
        library: library,
        workspace: workspace,
      ),
    );
  }

  @override
  State<PromptLibraryPresetLoadDialog> createState() =>
      _PromptLibraryPresetLoadDialogState();
}

class _PromptLibraryPresetLoadDialogState
    extends State<PromptLibraryPresetLoadDialog> {
  late final Set<String> _selectedOptionalIds;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _selectedOptionalIds = <String>{};
  }

  @override
  Widget build(BuildContext context) {
    final baseModules = modulesById(
      widget.preset.baseModuleIds,
      widget.modules,
    );
    final optionalModules = modulesById(
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
            ModuleIdPickerSection(
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
      await PromptLibraryPreviewDialog.show(
        context,
        preset: widget.preset,
        result: result,
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

/// Dialog for creating or editing a prompt preset.
class PromptLibraryPresetEditorDialog extends StatefulWidget {
  final PromptPreset? preset;
  final List<PromptModule> modules;

  const PromptLibraryPresetEditorDialog({
    super.key,
    this.preset,
    required this.modules,
  });

  /// Shows the preset editor dialog and returns the parsed draft.
  static Future<PresetEditorDraft?> show(
    BuildContext context, {
    PromptPreset? preset,
    required List<PromptModule> modules,
  }) {
    return showDialog<PresetEditorDraft>(
      context: context,
      builder: (dialogContext) =>
          PromptLibraryPresetEditorDialog(preset: preset, modules: modules),
    );
  }

  @override
  State<PromptLibraryPresetEditorDialog> createState() =>
      _PromptLibraryPresetEditorDialogState();
}

class _PromptLibraryPresetEditorDialogState
    extends State<PromptLibraryPresetEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _customController;
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
    _baseModuleIds = {...?preset?.baseModuleIds};
    _optionalModuleIds = {...?preset?.optionalModuleIds};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.preset != null;

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
              const SizedBox(height: 16),
              ModulePickerSection(
                title: 'Base modules',
                modules: widget.modules,
                selectedIds: _baseModuleIds,
                disabledIds: _optionalModuleIds,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 8),
              ModulePickerSection(
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
      isBuiltIn: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final result = const PromptAssembler().assemble(
      PromptAssemblyRequest(preset: preset, availableModules: widget.modules),
    );
    PromptLibraryPreviewDialog.show(context, preset: preset, result: result);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      PresetEditorDraft(
        name: _nameController.text.trim(),
        baseModuleIds: _baseModuleIds.toList(),
        optionalModuleIds: _optionalModuleIds.toList(),
        customInstructions: _customController.text.trim(),
      ),
    );
  }
}

/// Dialog for creating, editing, or viewing a prompt module.
class PromptLibraryModuleEditorDialog extends StatefulWidget {
  final PromptModule? module;
  final List<PromptModule> modules;

  const PromptLibraryModuleEditorDialog({
    super.key,
    this.module,
    required this.modules,
  });

  /// Shows the module editor dialog and returns the parsed draft.
  static Future<ModuleEditorDraft?> show(
    BuildContext context, {
    PromptModule? module,
    required List<PromptModule> modules,
  }) {
    return showDialog<ModuleEditorDraft>(
      context: context,
      builder: (dialogContext) =>
          PromptLibraryModuleEditorDialog(module: module, modules: modules),
    );
  }

  @override
  State<PromptLibraryModuleEditorDialog> createState() =>
      _PromptLibraryModuleEditorDialogState();
}

class _PromptLibraryModuleEditorDialogState
    extends State<PromptLibraryModuleEditorDialog> {
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.hasBoundedWidth && constraints.maxWidth < 360;
                  final categoryField = TextFormField(
                    controller: _categoryController,
                    readOnly: readOnly,
                    decoration: const InputDecoration(labelText: 'Category'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a category'
                        : null,
                  );
                  final priorityField = TextFormField(
                    controller: _priorityController,
                    readOnly: readOnly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    validator: (value) =>
                        int.tryParse(value?.trim() ?? '') == null
                        ? 'Enter a number'
                        : null,
                  );

                  if (compact) {
                    return Column(
                      children: [
                        categoryField,
                        const SizedBox(height: 12),
                        priorityField,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: categoryField),
                      const SizedBox(width: 12),
                      SizedBox(width: 140, child: priorityField),
                    ],
                  );
                },
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
              ModuleIdPickerSection(
                title: 'Required modules',
                modules: widget.modules
                    .where((module) => module.id != widget.module?.id)
                    .toList(),
                selectedIds: _requiredIds,
                enabled: !readOnly,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 8),
              ModuleIdPickerSection(
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
      ModuleEditorDraft(
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
