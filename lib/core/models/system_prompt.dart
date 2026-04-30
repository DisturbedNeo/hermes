class BuiltInPromptIds {
  const BuiltInPromptIds._();

  static const String coreDefaultModule = 'built_in.core.default';
  static const String workspaceRulesModule = 'built_in.context.workspace';
  static const String workspaceMissingModule =
      'built_in.context.workspace_missing';
  static const String defaultPreset = 'built_in.preset.default';
}

class PromptModule {
  final String id;
  final String name;
  final String category;
  final String content;
  final int priority;
  final bool isBuiltIn;
  final List<String> requiredModuleIds;
  final List<String> conflictingModuleIds;
  final DateTime createdAt;
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'content': content,
      'priority': priority,
      'isBuiltIn': isBuiltIn,
      'requiredModuleIds': requiredModuleIds,
      'conflictingModuleIds': conflictingModuleIds,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory PromptModule.fromJson(Map<String, dynamic> json) {
    return PromptModule(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      content: json['content'] as String,
      priority: json['priority'] as int? ?? 100,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      requiredModuleIds: _stringList(json['requiredModuleIds']),
      conflictingModuleIds: _stringList(json['conflictingModuleIds']),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }
}

class PromptPreset {
  final String id;
  final String name;
  final List<String> baseModuleIds;
  final List<String> optionalModuleIds;
  final String customInstructions;
  final String? legacyFullPrompt;
  final bool isBuiltIn;
  final DateTime createdAt;
  final DateTime updatedAt;
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
    Object? legacyFullPrompt = _sentinel,
    bool? isBuiltIn,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? lastUsedAt = _sentinel,
  }) {
    return PromptPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      baseModuleIds: baseModuleIds ?? this.baseModuleIds,
      optionalModuleIds: optionalModuleIds ?? this.optionalModuleIds,
      customInstructions: customInstructions ?? this.customInstructions,
      legacyFullPrompt: identical(legacyFullPrompt, _sentinel)
          ? this.legacyFullPrompt
          : legacyFullPrompt as String?,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: identical(lastUsedAt, _sentinel)
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseModuleIds': baseModuleIds,
      'optionalModuleIds': optionalModuleIds,
      'customInstructions': customInstructions,
      'legacyFullPrompt': legacyFullPrompt,
      'isBuiltIn': isBuiltIn,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'lastUsedAt': lastUsedAt?.millisecondsSinceEpoch,
    };
  }

  factory PromptPreset.fromJson(Map<String, dynamic> json) {
    return PromptPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      baseModuleIds: _stringList(json['baseModuleIds']),
      optionalModuleIds: _stringList(json['optionalModuleIds']),
      customInstructions: json['customInstructions'] as String? ?? '',
      legacyFullPrompt: json['legacyFullPrompt'] as String?,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      lastUsedAt: _nullableDate(json['lastUsedAt']),
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

class SystemPromptSnapshot {
  final String? id;
  final String name;
  final String text;
  final PromptPreset? preset;
  final List<PromptModule> modules;
  final List<String> selectedModuleIds;
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'text': text,
      'preset': preset?.toJson(),
      'modules': modules.map((module) => module.toJson()).toList(),
      'selectedModuleIds': selectedModuleIds,
      'diagnostics': diagnostics,
    };
  }

  factory SystemPromptSnapshot.fromJson(Map<String, dynamic> json) {
    return SystemPromptSnapshot(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'System prompt',
      text: json['text'] as String? ?? '',
      preset: json['preset'] is Map
          ? PromptPreset.fromJson(
              Map<String, dynamic>.from(json['preset'] as Map),
            )
          : null,
      modules: (json['modules'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => PromptModule.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      selectedModuleIds: _stringList(json['selectedModuleIds']),
      diagnostics: _stringList(json['diagnostics']),
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

const Object _sentinel = Object();

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const [];
}

DateTime _date(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _nullableDate(Object? value) {
  if (value == null) return null;
  return _date(value);
}
