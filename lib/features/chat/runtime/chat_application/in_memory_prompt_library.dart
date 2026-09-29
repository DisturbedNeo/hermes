import 'package:hermes/shared_kernel/system_prompt.dart';
import 'package:hermes/shared_kernel/prompt_library_port.dart';

/// In-memory prompt repository for service and UI tests.
class InMemoryPromptLibrary implements PromptLibraryPort {
  final Map<String, PromptPreset> presets = {};
  final Map<String, PromptModule> modules = {};

  @override
  Future<void> dispose() async {}

  @override
  Future<List<PromptPreset>> listPresets() async => presets.values.toList();

  @override
  Future<List<PromptPreset>> searchPresets(String query) async => presets.values
      .where(
        (preset) => preset.name.toLowerCase().contains(query.toLowerCase()),
      )
      .toList();

  @override
  Future<PromptPreset?> getPreset(String id) async => presets[id];

  @override
  Future<PromptPreset> createPreset({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
    required bool isBuiltIn,
  }) async {
    final now = DateTime.now();
    return presets[id] = PromptPreset(
      id: id,
      name: name,
      baseModuleIds: baseModuleIds,
      optionalModuleIds: optionalModuleIds,
      customInstructions: customInstructions,
      isBuiltIn: isBuiltIn,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<PromptPreset> updatePreset({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
    required bool isBuiltIn,
    required DateTime createdAt,
    required DateTime? lastUsedAt,
  }) async => presets[id] = PromptPreset(
    id: id,
    name: name,
    baseModuleIds: baseModuleIds,
    optionalModuleIds: optionalModuleIds,
    customInstructions: customInstructions,
    isBuiltIn: isBuiltIn,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    lastUsedAt: lastUsedAt,
  );

  @override
  Future<void> deletePreset(String id) async => presets.remove(id);

  @override
  Future<void> markPresetUsed(String id) async {
    final preset = presets[id];
    if (preset != null) {
      presets[id] = preset.copyWith(lastUsedAt: DateTime.now());
    }
  }

  @override
  Future<List<PromptModule>> listModules() async => modules.values.toList();

  @override
  Future<List<PromptModule>> searchModules(String query) async => modules.values
      .where(
        (module) => module.name.toLowerCase().contains(query.toLowerCase()),
      )
      .toList();

  @override
  Future<PromptModule?> getModule(String id) async => modules[id];

  @override
  Future<PromptModule> createModule({
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required bool isBuiltIn,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
  }) async {
    final now = DateTime.now();
    return modules[id] = PromptModule(
      id: id,
      name: name,
      category: category,
      content: content,
      priority: priority,
      isBuiltIn: isBuiltIn,
      requiredModuleIds: requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<PromptModule> updateModule({
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required bool isBuiltIn,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
    required DateTime createdAt,
  }) => createModule(
    id: id,
    name: name,
    category: category,
    content: content,
    priority: priority,
    isBuiltIn: isBuiltIn,
    requiredModuleIds: requiredModuleIds,
    conflictingModuleIds: conflictingModuleIds,
  );

  @override
  Future<void> deleteModule(String id) async => modules.remove(id);
  @override
  Future<void> seedBuiltIns() async {}
  @override
  Future<void> seedStarterLibrary() async {}

  @override
  Future<void> throwIfNameExists(
    String table,
    String name, {
    String? excludingId,
  }) async {
    final existingId = table == 'prompt_presets'
        ? presets.values
              .where((item) => item.name.toLowerCase() == name.toLowerCase())
              .firstOrNull
              ?.id
        : modules.values
              .where((item) => item.name.toLowerCase() == name.toLowerCase())
              .firstOrNull
              ?.id;
    if (existingId != null && existingId != excludingId) {
      throw StateError('A record named $name already exists.');
    }
  }

  @override
  Future<String> copyNameFor(String table, String baseName) async =>
      uniqueNameFor(table, '$baseName copy');

  @override
  Future<String> uniqueNameFor(String table, String baseName) async {
    var candidate = baseName;
    var index = 2;
    while (await nameExists(table, candidate)) {
      candidate = '$baseName $index';
      index++;
    }
    return candidate;
  }

  @override
  Future<bool> nameExists(String table, String name) async {
    if (table == 'prompt_presets') {
      return presets.values.any(
        (item) => item.name.toLowerCase() == name.toLowerCase(),
      );
    }
    return modules.values.any(
      (item) => item.name.toLowerCase() == name.toLowerCase(),
    );
  }
}
