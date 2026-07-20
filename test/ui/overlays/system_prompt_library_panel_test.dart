import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/prompt_assembler.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/overlays/system_prompt_library_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;
  late ChatLibraryService chatLibrary;
  late _FakeSystemPromptLibraryService promptLibrary;
  late ChatTabsService tabs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesService();
    chatLibrary = ChatLibraryService(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    promptLibrary = _FakeSystemPromptLibraryService();
    final sandbox = WorkspaceSandbox();
    final toolService = ToolService(workspaceSandbox: sandbox);
    final taskService = TaskService(toolService: toolService, sandbox: sandbox);
    tabs = ChatTabsService(
      chatLibrary: chatLibrary,
      systemPromptLibrary: promptLibrary,
      toolService: toolService,
      taskService: taskService,
      projectService: ProjectService(taskService: taskService),
      workspaceService: WorkspaceService(sandbox: sandbox),
      preferencesService: preferences,
    );
  });

  tearDown(() async {
    await tabs.dispose();
    await chatLibrary.dispose();
    await promptLibrary.dispose();
    preferences.dispose();
  });

  testWidgets('creates a preset from the panel', (tester) async {
    await tester.pumpWidget(
      _panelApp(tabs: tabs, promptLibrary: promptLibrary),
    );
    await _pumpAsyncWork(tester);

    expect(find.text('No prompt presets'), findsOneWidget);

    await tester.tap(find.byTooltip('Create preset'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Reviewer');
    await tester.tap(find.text('Create'));
    await _pumpAsyncWork(tester);
    await tester.pumpAndSettle();

    expect(find.text('Reviewer'), findsOneWidget);
  });

  testWidgets('creates a module from the panel', (tester) async {
    await tester.pumpWidget(
      _panelApp(tabs: tabs, promptLibrary: promptLibrary),
    );
    await _pumpAsyncWork(tester);

    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create module'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Reviewer rules');
    await tester.enterText(find.byType(TextFormField).at(1), 'Task');
    await tester.enterText(find.byType(TextFormField).at(2), '40');
    await tester.enterText(
      find.byType(TextFormField).at(3),
      'Review code carefully.',
    );
    await tester.tap(find.text('Create'));
    await _pumpAsyncWork(tester);
    await tester.pumpAndSettle();

    expect(find.text('Reviewer rules'), findsOneWidget);
  });

  testWidgets('loads a preset into the active unlocked chat', (tester) async {
    final module = await promptLibrary.createModule(
      name: 'Architect rules',
      category: 'Task',
      content: 'Design APIs carefully.',
      priority: 40,
    );
    final preset = await promptLibrary.createPreset(
      name: 'Architect',
      baseModuleIds: [module.id],
    );

    var loaded = false;
    await tester.pumpWidget(
      _panelApp(
        tabs: tabs,
        promptLibrary: promptLibrary,
        onPromptLoaded: () => loaded = true,
      ),
    );
    await _pumpAsyncWork(tester);

    await tester.tap(find.text('Load'));
    await _pumpAsyncWork(tester);

    expect(loaded, isTrue);
    expect(tabs.tabs, hasLength(1));
    expect(tabs.activeChat?.currentSystemPromptSnapshot?.name, preset.name);
  });

  testWidgets('selects optional modules when loading a preset', (tester) async {
    final base = await promptLibrary.createModule(
      name: 'Coding base',
      category: 'Core',
      content: 'You are a senior software engineer.',
      priority: 10,
    );
    final csharp = await promptLibrary.createModule(
      name: 'C# specialist',
      category: 'Capability',
      content: 'You specialise in C#.',
      priority: 20,
    );
    final rust = await promptLibrary.createModule(
      name: 'Rust specialist',
      category: 'Capability',
      content: 'You specialise in Rust.',
      priority: 20,
    );
    await promptLibrary.createPreset(
      name: 'Coding',
      baseModuleIds: [base.id],
      optionalModuleIds: [csharp.id, rust.id],
    );

    await tester.pumpWidget(
      _panelApp(tabs: tabs, promptLibrary: promptLibrary),
    );
    await _pumpAsyncWork(tester);

    await tester.tap(find.text('Load').first);
    await tester.pumpAndSettle();

    expect(find.text('Load Coding'), findsOneWidget);
    expect(find.text('Optional modules'), findsOneWidget);

    await tester.tap(find.text('C# specialist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Load').last);
    await _pumpAsyncWork(tester);

    final systemText = tabs.activeChat!.messageStore.first.text;
    expect(systemText, contains('You are a senior software engineer.'));
    expect(systemText, contains('You specialise in C#.'));
    expect(systemText, isNot(contains('You specialise in Rust.')));
    expect(tabs.activeChat!.currentSystemPromptSnapshot!.selectedModuleIds, [
      csharp.id,
    ]);
  });

  testWidgets('lays out built-in rows in a narrow panel', (tester) async {
    final now = DateTime(2024, 1, 1);
    promptLibrary.seedPreset(
      PromptPreset(
        id: 'preset-built-in',
        name: 'Built-in coding workflow preset with a long display name',
        baseModuleIds: const [],
        optionalModuleIds: const [],
        customInstructions: 'Prefer concise responses.',
        legacyFullPrompt: null,
        isBuiltIn: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    promptLibrary.seedModule(
      PromptModule(
        id: 'module-built-in',
        name: 'Built-in workspace context module with a long display name',
        category: 'Context',
        content: 'Use the attached workspace context.',
        priority: 20,
        isBuiltIn: true,
        requiredModuleIds: const [],
        conflictingModuleIds: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      _panelApp(tabs: tabs, promptLibrary: promptLibrary, width: 240),
    );
    await _pumpAsyncWork(tester);

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out with very short panel heights', (tester) async {
    await tester.pumpWidget(
      _panelApp(
        tabs: tabs,
        promptLibrary: promptLibrary,
        width: 431,
        height: 185,
      ),
    );
    await _pumpAsyncWork(tester);

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _panelApp(tabs: tabs, promptLibrary: promptLibrary, width: 1, height: 1),
    );
    await _pumpAsyncWork(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the unified state display for load errors', (tester) async {
    promptLibrary.failLoads = true;

    await tester.pumpWidget(
      _panelApp(tabs: tabs, promptLibrary: promptLibrary),
    );
    await _pumpAsyncWork(tester);

    expect(
      find.textContaining('Failed to load prompt library'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

    promptLibrary.failLoads = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await _pumpAsyncWork(tester);

    expect(find.text('No prompt presets'), findsOneWidget);
  });
}

Widget _panelApp({
  required ChatTabsService tabs,
  required SystemPromptLibraryService promptLibrary,
  VoidCallback? onPromptLoaded,
  double width = 520,
  double? height,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: SystemPromptLibraryPanel(
          onPromptLoaded: onPromptLoaded,
          tabs: tabs,
          library: promptLibrary,
        ),
      ),
    ),
  );
}

Future<void> _pumpAsyncWork(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

class _FakeSystemPromptLibraryService extends SystemPromptLibraryService {
  _FakeSystemPromptLibraryService()
    : super(preferencesService: PreferencesService(), databasePath: ':memory:');

  final List<PromptPreset> _presets = [];
  final List<PromptModule> _modules = [];
  int _nextId = 0;
  bool failLoads = false;

  void seedPreset(PromptPreset preset) {
    _presets.add(preset);
  }

  void seedModule(PromptModule module) {
    _modules.add(module);
  }

  @override
  Future<List<PromptPreset>> listPresets() async {
    if (failLoads) throw StateError('load failed');
    return List<PromptPreset>.of(_presets);
  }

  @override
  Future<List<PromptPreset>> searchPresets(String query) async {
    if (failLoads) throw StateError('load failed');
    final lower = query.toLowerCase();
    return _presets
        .where((preset) => preset.name.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Future<PromptPreset?> getPreset(String id) async {
    return _presets.where((preset) => preset.id == id).firstOrNull;
  }

  @override
  Future<PromptPreset> createPreset({
    required String name,
    List<String> baseModuleIds = const [],
    List<String> optionalModuleIds = const [],
    String customInstructions = '',
    String? legacyFullPrompt,
  }) async {
    final now = DateTime.now();
    final preset = PromptPreset(
      id: 'preset-${_nextId++}',
      name: name.trim(),
      baseModuleIds: baseModuleIds,
      optionalModuleIds: optionalModuleIds,
      customInstructions: customInstructions,
      legacyFullPrompt: legacyFullPrompt,
      isBuiltIn: false,
      createdAt: now,
      updatedAt: now,
    );
    _presets.add(preset);
    notifyListeners();
    return preset;
  }

  @override
  Future<PromptPreset> updatePreset({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
    String? legacyFullPrompt,
  }) async {
    final index = _presets.indexWhere((preset) => preset.id == id);
    final existing = _presets[index];
    final updated = existing.copyWith(
      name: name,
      baseModuleIds: baseModuleIds,
      optionalModuleIds: optionalModuleIds,
      customInstructions: customInstructions,
      legacyFullPrompt: legacyFullPrompt,
      updatedAt: DateTime.now(),
    );
    _presets[index] = updated;
    notifyListeners();
    return updated;
  }

  @override
  Future<PromptPreset> duplicatePreset(String id) async {
    final source = await getPreset(id);
    return createPreset(
      name: '${source!.name} copy',
      baseModuleIds: source.baseModuleIds,
      optionalModuleIds: source.optionalModuleIds,
      customInstructions: source.customInstructions,
      legacyFullPrompt: source.legacyFullPrompt,
    );
  }

  @override
  Future<void> deletePreset(String id) async {
    _presets.removeWhere((preset) => preset.id == id);
    notifyListeners();
  }

  @override
  Future<void> markPresetUsed(String id) async {}

  @override
  Future<List<PromptModule>> listModules() async {
    if (failLoads) throw StateError('load failed');
    return List<PromptModule>.of(_modules);
  }

  @override
  Future<List<PromptModule>> searchModules(String query) async {
    if (failLoads) throw StateError('load failed');
    final lower = query.toLowerCase();
    return _modules
        .where((module) => module.name.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Future<PromptModule?> getModule(String id) async {
    return _modules.where((module) => module.id == id).firstOrNull;
  }

  @override
  Future<PromptModule> createModule({
    required String name,
    required String category,
    required String content,
    required int priority,
    List<String> requiredModuleIds = const [],
    List<String> conflictingModuleIds = const [],
  }) async {
    final now = DateTime.now();
    final module = PromptModule(
      id: 'module-${_nextId++}',
      name: name.trim(),
      category: category.trim(),
      content: content.trim(),
      priority: priority,
      isBuiltIn: false,
      requiredModuleIds: requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds,
      createdAt: now,
      updatedAt: now,
    );
    _modules.add(module);
    notifyListeners();
    return module;
  }

  @override
  Future<PromptModule> updateModule({
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
  }) async {
    final index = _modules.indexWhere((module) => module.id == id);
    final updated = _modules[index].copyWith(
      name: name,
      category: category,
      content: content,
      priority: priority,
      requiredModuleIds: requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds,
      updatedAt: DateTime.now(),
    );
    _modules[index] = updated;
    notifyListeners();
    return updated;
  }

  @override
  Future<PromptModule> duplicateModule(String id) async {
    final source = await getModule(id);
    return createModule(
      name: '${source!.name} copy',
      category: source.category,
      content: source.content,
      priority: source.priority,
      requiredModuleIds: source.requiredModuleIds,
      conflictingModuleIds: source.conflictingModuleIds,
    );
  }

  @override
  Future<void> deleteModule(String id) async {
    _modules.removeWhere((module) => module.id == id);
    notifyListeners();
  }

  @override
  Future<PromptAssemblyResult> assemblePreset(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds = const [],
    workspace,
    String? currentUserRequest,
  }) async {
    final optionalIds = preset.optionalModuleIds.toSet();
    return const PromptAssembler().assemble(
      PromptAssemblyRequest(
        preset: preset,
        availableModules: _modules,
        selectedModuleIds: [
          for (final id in selectedOptionalModuleIds)
            if (optionalIds.contains(id)) id,
        ],
        currentUserRequest: currentUserRequest,
      ),
    );
  }

  @override
  Future<SystemPromptSnapshot> snapshotForPreset(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds = const [],
    workspace,
    String? currentUserRequest,
  }) async {
    final result = await assemblePreset(
      preset,
      selectedOptionalModuleIds: selectedOptionalModuleIds,
      currentUserRequest: currentUserRequest,
    );
    return SystemPromptSnapshot(
      id: preset.id,
      name: preset.name,
      text: result.text,
      preset: preset,
      modules: _modules,
      selectedModuleIds: [
        for (final id in selectedOptionalModuleIds)
          if (preset.optionalModuleIds.contains(id)) id,
      ],
      diagnostics: result.diagnostics,
    );
  }

  @override
  Future<void> dispose() async {
    _presets.clear();
    _modules.clear();
    super.dispose();
  }
}
