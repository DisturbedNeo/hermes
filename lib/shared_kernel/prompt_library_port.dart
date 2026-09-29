import 'package:hermes/shared_kernel/system_prompt.dart';

/// Storage contract consumed by prompt-library application services.
abstract interface class PromptLibraryPort {
  Future<void> dispose();
  Future<List<PromptPreset>> listPresets();
  Future<List<PromptPreset>> searchPresets(String query);
  Future<PromptPreset?> getPreset(String id);
  Future<PromptPreset> createPreset({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
    required bool isBuiltIn,
  });
  Future<PromptPreset> updatePreset({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
    required bool isBuiltIn,
    required DateTime createdAt,
    required DateTime? lastUsedAt,
  });
  Future<void> deletePreset(String id);
  Future<void> markPresetUsed(String id);

  Future<List<PromptModule>> listModules();
  Future<List<PromptModule>> searchModules(String query);
  Future<PromptModule?> getModule(String id);
  Future<PromptModule> createModule({
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required bool isBuiltIn,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
  });
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
  });
  Future<void> deleteModule(String id);

  Future<void> seedBuiltIns();
  Future<void> seedStarterLibrary();
  Future<void> throwIfNameExists(
    String table,
    String name, {
    String? excludingId,
  });
  Future<String> copyNameFor(String table, String baseName);
  Future<String> uniqueNameFor(String table, String baseName);
  Future<bool> nameExists(String table, String name);
}
