import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/prompt_assembler.dart';

import 'disposable.dart';
import 'system_prompt_library_repository.dart';

/// Business-logic orchestrator for the system prompt library.
///
/// Delegates all raw data access, JSON mapping, and file-system/SQLite
/// interactions to [SystemPromptLibraryRepository].  This class owns
/// state management (via [ChangeNotifier]), input validation, module
/// selection rules, and high-level convenience methods used by UI layers.
class SystemPromptLibraryService extends ChangeNotifier implements Disposable {
  static const String coreDefaultModuleId = BuiltInPromptIds.coreDefaultModule;
  static const String workspaceRulesModuleId =
      BuiltInPromptIds.workspaceRulesModule;
  static const String workspaceMissingModuleId =
      BuiltInPromptIds.workspaceMissingModule;
  static const String defaultPresetId = BuiltInPromptIds.defaultPreset;

  final SystemPromptLibraryRepository _repository;
  final PromptAssembler _assembler;

  bool _disposed = false;

  SystemPromptLibraryService({
    required SystemPromptLibraryRepository repository,
    PromptAssembler assembler = const PromptAssembler(),
  }) : _repository = repository,
       _assembler = assembler;

  // ── Preset CRUD (orchestrated) ─────────────────────────────────────────

  Future<List<PromptPreset>> listPresets() => _repository.listPresets();

  Future<List<PromptPreset>> searchPresets(String query) =>
      _repository.searchPresets(query);

  Future<PromptPreset?> getPreset(String id) => _repository.getPreset(id);

  Future<PromptPreset> createPreset({
    required String name,
    List<String> baseModuleIds = const [],
    List<String> optionalModuleIds = const [],
    String customInstructions = '',
  }) async {
    final trimmedName = _validatedName(name);
    await _repository.throwIfNameExists('prompt_presets', trimmedName);

    final preset = await _repository.createPreset(
      id: uuid.v7(),
      name: trimmedName,
      baseModuleIds: baseModuleIds,
      optionalModuleIds: optionalModuleIds,
      customInstructions: customInstructions,
      isBuiltIn: false,
    );

    notifyListeners();
    return preset;
  }

  Future<PromptPreset> updatePreset({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
  }) async {
    final existing = await getPreset(id);
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'Prompt preset not found');
    }
    if (existing.isBuiltIn) {
      throw StateError('Built-in presets cannot be edited');
    }

    final trimmedName = _validatedName(name);
    await _repository.throwIfNameExists(
      'prompt_presets',
      trimmedName,
      excludingId: id,
    );

    final preset = await _repository.updatePreset(
      id: id,
      name: trimmedName,
      baseModuleIds: baseModuleIds,
      optionalModuleIds: optionalModuleIds,
      customInstructions: customInstructions,
      isBuiltIn: existing.isBuiltIn,
      createdAt: existing.createdAt,
      lastUsedAt: existing.lastUsedAt,
    );

    notifyListeners();
    return preset;
  }

  Future<PromptPreset> duplicatePreset(String id) async {
    final source = await getPreset(id);
    if (source == null) {
      throw ArgumentError.value(id, 'id', 'Prompt preset not found');
    }

    final name = await _repository.copyNameFor('prompt_presets', source.name);
    return createPreset(
      name: name,
      baseModuleIds: source.baseModuleIds,
      optionalModuleIds: source.optionalModuleIds,
      customInstructions: source.customInstructions,
    );
  }

  Future<void> deletePreset(String id) async {
    final preset = await getPreset(id);
    if (preset?.isBuiltIn == true) {
      throw StateError('Built-in presets cannot be deleted');
    }

    await _repository.deletePreset(id);
    notifyListeners();
  }

  Future<void> markPresetUsed(String id) async {
    await _repository.markPresetUsed(id);
    notifyListeners();
  }

  // ── Module CRUD (orchestrated) ─────────────────────────────────────────

  Future<List<PromptModule>> listModules() => _repository.listModules();

  Future<List<PromptModule>> searchModules(String query) =>
      _repository.searchModules(query);

  Future<PromptModule?> getModule(String id) => _repository.getModule(id);

  Future<PromptModule> createModule({
    required String name,
    required String category,
    required String content,
    required int priority,
    List<String> requiredModuleIds = const [],
    List<String> conflictingModuleIds = const [],
  }) async {
    final trimmedName = _validatedName(name);
    final trimmedCategory = _validatedName(category);
    final trimmedContent = _validatedContent(content);
    await _repository.throwIfNameExists('prompt_modules', trimmedName);

    final module = await _repository.createModule(
      id: uuid.v7(),
      name: trimmedName,
      category: trimmedCategory,
      content: trimmedContent,
      priority: priority,
      isBuiltIn: false,
      requiredModuleIds: requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds,
    );

    notifyListeners();
    return module;
  }

  Future<PromptModule> updateModule({
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
  }) async {
    final existing = await getModule(id);
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'Prompt module not found');
    }
    if (existing.isBuiltIn) {
      throw StateError('Built-in modules cannot be edited');
    }

    final trimmedName = _validatedName(name);
    final trimmedCategory = _validatedName(category);
    final trimmedContent = _validatedContent(content);
    await _repository.throwIfNameExists(
      'prompt_modules',
      trimmedName,
      excludingId: id,
    );

    final module = await _repository.updateModule(
      id: id,
      name: trimmedName,
      category: trimmedCategory,
      content: trimmedContent,
      priority: priority,
      isBuiltIn: false,
      requiredModuleIds: requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds,
      createdAt: existing.createdAt,
    );

    notifyListeners();
    return module;
  }

  Future<PromptModule> duplicateModule(String id) async {
    final source = await getModule(id);
    if (source == null) {
      throw ArgumentError.value(id, 'id', 'Prompt module not found');
    }

    final name = await _repository.copyNameFor('prompt_modules', source.name);
    return createModule(
      name: name,
      category: source.category,
      content: source.content,
      priority: source.priority,
      requiredModuleIds: source.requiredModuleIds,
      conflictingModuleIds: source.conflictingModuleIds,
    );
  }

  Future<void> deleteModule(String id) async {
    final module = await getModule(id);
    if (module?.isBuiltIn == true) {
      throw StateError('Built-in modules cannot be deleted');
    }

    await _repository.deleteModule(id);
    notifyListeners();
  }

  // ── Assembly & snapshot (business orchestration) ────────────────────────

  Future<PromptAssemblyResult> assemblePreset(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds = const [],
    WorkspaceAttachment? workspace,
    String? currentUserRequest,
  }) async {
    final modules = await listModules();
    final selectedModuleIds = _selectedOptionalIdsFor(
      preset,
      selectedOptionalModuleIds,
    );
    return _assembler.assemble(
      PromptAssemblyRequest(
        preset: preset,
        availableModules: modules,
        selectedModuleIds: selectedModuleIds,
        autoModuleIds: _autoModuleIdsFor(workspace),
        workspaceRootPath: workspace?.rootPath,
        workspaceMissing: workspace?.missing ?? false,
        commandExecutionApproved: workspace?.commandExecutionApproved == true,
        currentUserRequest: currentUserRequest,
      ),
    );
  }

  Future<SystemPromptSnapshot> snapshotForPreset(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds = const [],
    WorkspaceAttachment? workspace,
    String? currentUserRequest,
  }) async {
    final modules = await listModules();
    final selectedModuleIds = _selectedOptionalIdsFor(
      preset,
      selectedOptionalModuleIds,
    );
    final result = _assembler.assemble(
      PromptAssemblyRequest(
        preset: preset,
        availableModules: modules,
        selectedModuleIds: selectedModuleIds,
        autoModuleIds: _autoModuleIdsFor(workspace),
        workspaceRootPath: workspace?.rootPath,
        workspaceMissing: workspace?.missing ?? false,
        commandExecutionApproved: workspace?.commandExecutionApproved == true,
        currentUserRequest: currentUserRequest,
      ),
    );

    return SystemPromptSnapshot(
      id: preset.id,
      name: preset.name,
      text: result.text,
      preset: preset,
      modules: modules,
      selectedModuleIds: selectedModuleIds,
      diagnostics: result.diagnostics,
    );
  }

  // ── Business-rule helpers ───────────────────────────────────────────────

  List<String> _autoModuleIdsFor(WorkspaceAttachment? workspace) {
    if (workspace == null) return const [];
    return workspace.missing
        ? const [workspaceMissingModuleId]
        : const [workspaceRulesModuleId];
  }

  List<String> _selectedOptionalIdsFor(
    PromptPreset preset,
    List<String> selectedOptionalModuleIds,
  ) {
    final optionalIds = preset.optionalModuleIds.toSet();
    final seen = <String>{};
    return [
      for (final id in selectedOptionalModuleIds)
        if (optionalIds.contains(id) && seen.add(id)) id,
    ];
  }

  // ── Input validation (business rules) ───────────────────────────────────

  String _validatedName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Name cannot be empty');
    }
    return trimmed;
  }

  String _validatedContent(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(content, 'content', 'Content cannot be empty');
    }
    return trimmed;
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _repository.dispose();
    super.dispose();
  }
}
