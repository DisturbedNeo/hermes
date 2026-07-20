import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/sentinel.dart';
import 'package:hermes/core/serialization/json_hooks.dart';

part 'system_prompt.mapper.dart';

class BuiltInPromptIds {
  const BuiltInPromptIds._();

  static const String coreDefaultModule = 'built_in.core.default';
  static const String workspaceRulesModule = 'built_in.context.workspace';
  static const String workspaceMissingModule =
      'built_in.context.workspace_missing';
  static const String defaultPreset = 'built_in.preset.default';
}

@MappableClass()
class PromptModule with PromptModuleMappable {
  final String id;
  final String name;
  final String category;
  final String content;
  @MappableField(hook: JsonIntHook(fallback: 100))
  final int priority;
  @MappableField(hook: JsonBoolHook())
  final bool isBuiltIn;
  @MappableField(hook: JsonStringListHook())
  final List<String> requiredModuleIds;
  @MappableField(hook: JsonStringListHook())
  final List<String> conflictingModuleIds;
  @MappableField(hook: EpochDateHook(fallbackNow: true))
  final DateTime createdAt;
  @MappableField(hook: EpochDateHook(fallbackNow: true))
  final DateTime updatedAt;

  const PromptModule({
    required this.id,
    required this.name,
    required this.category,
    required this.content,
    required this.priority,
    required this.isBuiltIn,
    required this.requiredModuleIds,
    required this.conflictingModuleIds,
    required this.createdAt,
    required this.updatedAt,
  });

  PromptModule copyWith({
    String? id,
    String? name,
    String? category,
    String? content,
    int? priority,
    bool? isBuiltIn,
    List<String>? requiredModuleIds,
    List<String>? conflictingModuleIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PromptModule(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      content: content ?? this.content,
      priority: priority ?? this.priority,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      requiredModuleIds: requiredModuleIds ?? this.requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds ?? this.conflictingModuleIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@MappableClass()
class PromptPreset with PromptPresetMappable {
  final String id;
  final String name;
  @MappableField(hook: JsonStringListHook())
  final List<String> baseModuleIds;
  @MappableField(hook: JsonStringListHook())
  final List<String> optionalModuleIds;
  @MappableField(hook: JsonStringHook())
  final String customInstructions;
  final String? legacyFullPrompt;
  @MappableField(hook: JsonBoolHook())
  final bool isBuiltIn;
  @MappableField(hook: EpochDateHook(fallbackNow: true))
  final DateTime createdAt;
  @MappableField(hook: EpochDateHook(fallbackNow: true))
  final DateTime updatedAt;
  @MappableField(hook: EpochDateHook())
  final DateTime? lastUsedAt;

  const PromptPreset({
    required this.id,
    required this.name,
    required this.baseModuleIds,
    required this.optionalModuleIds,
    required this.customInstructions,
    required this.legacyFullPrompt,
    required this.isBuiltIn,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
  });

  bool get isLegacy =>
      legacyFullPrompt != null && legacyFullPrompt!.trim().isNotEmpty;

  PromptPreset copyWith({
    String? id,
    String? name,
    List<String>? baseModuleIds,
    List<String>? optionalModuleIds,
    String? customInstructions,
    Object? legacyFullPrompt = kSentinel,
    bool? isBuiltIn,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? lastUsedAt = kSentinel,
  }) {
    return PromptPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      baseModuleIds: baseModuleIds ?? this.baseModuleIds,
      optionalModuleIds: optionalModuleIds ?? this.optionalModuleIds,
      customInstructions: customInstructions ?? this.customInstructions,
      legacyFullPrompt: identical(legacyFullPrompt, kSentinel)
          ? this.legacyFullPrompt
          : legacyFullPrompt as String?,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: identical(lastUsedAt, kSentinel)
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
    );
  }
}

class PromptAssemblyRequest {
  final PromptPreset? preset;
  final List<PromptModule> availableModules;
  final List<String> selectedModuleIds;
  final List<String> autoModuleIds;
  final String? workspaceRootPath;
  final bool workspaceMissing;
  final bool commandExecutionApproved;
  final String? currentUserRequest;

  const PromptAssemblyRequest({
    required this.preset,
    required this.availableModules,
    this.selectedModuleIds = const [],
    this.autoModuleIds = const [],
    this.workspaceRootPath,
    this.workspaceMissing = false,
    this.commandExecutionApproved = false,
    this.currentUserRequest,
  });

  factory PromptAssemblyRequest.fromSnapshot(
    SystemPromptSnapshot snapshot, {
    List<String> autoModuleIds = const [],
    String? workspaceRootPath,
    bool workspaceMissing = false,
    bool commandExecutionApproved = false,
    String? currentUserRequest,
  }) {
    return PromptAssemblyRequest(
      preset: snapshot.preset,
      availableModules: snapshot.modules,
      selectedModuleIds: snapshot.selectedModuleIds,
      autoModuleIds: autoModuleIds,
      workspaceRootPath: workspaceRootPath,
      workspaceMissing: workspaceMissing,
      commandExecutionApproved: commandExecutionApproved,
      currentUserRequest: currentUserRequest,
    );
  }
}

class PromptAssemblyResult {
  final String text;
  final List<PromptModule> includedModules;
  final List<PromptModule> omittedModules;
  final List<String> diagnostics;

  const PromptAssemblyResult({
    required this.text,
    required this.includedModules,
    required this.omittedModules,
    required this.diagnostics,
  });

  SystemPromptSnapshot toSnapshot({required PromptPreset preset}) {
    return SystemPromptSnapshot(
      id: preset.id,
      name: preset.name,
      text: text,
      preset: preset,
      modules: includedModules,
      selectedModuleIds: includedModules.map((module) => module.id).toList(),
      diagnostics: diagnostics,
    );
  }
}

@MappableClass()
class SystemPromptSnapshot with SystemPromptSnapshotMappable {
  final String? id;
  @MappableField(hook: JsonStringHook(fallback: 'System prompt'))
  final String name;
  @MappableField(hook: JsonStringHook())
  final String text;
  final PromptPreset? preset;
  @MappableField(hook: JsonObjectListHook())
  final List<PromptModule> modules;
  @MappableField(hook: JsonStringListHook())
  final List<String> selectedModuleIds;
  @MappableField(hook: JsonStringListHook())
  final List<String> diagnostics;

  const SystemPromptSnapshot({
    required this.id,
    required this.name,
    required this.text,
    this.preset,
    this.modules = const [],
    this.selectedModuleIds = const [],
    this.diagnostics = const [],
  });

  factory SystemPromptSnapshot.legacy({
    required String? id,
    required String name,
    required String text,
  }) {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    return SystemPromptSnapshot(
      id: id,
      name: name,
      text: text,
      preset: PromptPreset(
        id: id ?? 'legacy',
        name: name,
        baseModuleIds: const [],
        optionalModuleIds: const [],
        customInstructions: '',
        legacyFullPrompt: text,
        isBuiltIn: false,
        createdAt: now,
        updatedAt: now,
      ),
      modules: const [],
      selectedModuleIds: const [],
    );
  }
}

class SavedSystemPrompt {
  final String id;
  final String name;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;

  const SavedSystemPrompt({
    required this.id,
    required this.name,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
  });

  SystemPromptSnapshot toSnapshot() {
    return SystemPromptSnapshot.legacy(id: id, name: name, text: content);
  }
}
