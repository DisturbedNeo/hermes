import 'package:hermes/app/modules/chat_module.dart';
import 'package:hermes/app/modules/model_module.dart';
import 'package:hermes/app/modules/persistence_module.dart';
import 'package:hermes/app/modules/project_module.dart';
import 'package:hermes/app/modules/task_module.dart';
import 'package:hermes/app/modules/workspace_tools_module.dart';
import 'package:hermes/features/chat/presentation/theme_manager.dart';
import 'package:hermes/features/chat/application/chat_workspace_controller.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/application/system_prompt_library_service.dart';
import 'package:hermes/features/chat/application/contracts/chat_persistence.dart';
import 'package:hermes/features/model/infrastructure/llama_server_manager.dart';
import 'package:hermes/features/model/application/model_catalog.dart';
import 'package:hermes/features/model/infrastructure/model_catalog_service.dart';
import 'package:hermes/features/project/application/project_application/project_application.dart';
import 'package:hermes/features/settings/infrastructure/preferences_service.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/platform/workspace_sandbox.dart';
import 'package:hermes/platform/workspace_service.dart';
import 'package:hermes/core/application_lifecycle.dart';
import 'package:hermes/app/mappers.init.dart';

/// The eagerly-created, application-scoped dependency graph.
///
/// This class owns service lifetimes but intentionally has no type-based lookup
/// API. Dependencies are exposed as typed fields and injected explicitly.
class AppDependencies implements ApplicationLifecycle {
  AppDependencies._({
    required this.preferencesService,
    required this.themeManager,
    required this.workspaceSandbox,
    required this.workspaceService,
    required this.toolService,
    required this.modelManager,
    required this.modelCatalog,
    required this.taskController,
    required this.projectApplication,
    required this.chatLibraryService,
    required this.systemPromptLibraryService,
    required this.chatWorkspaceController,
    required this.lifecycleCoordinator,
  });

  static AppDependencies create() {
    initializeMappers();
    final preferencesService = PreferencesService();
    final modelCatalog = ModelCatalogService(preferences: preferencesService);
    final workspaceModule = WorkspaceToolsModule.create();
    final persistenceModule = PersistenceModule.create();
    final modelModule = ModelModule.create();
    final taskModule = TaskModule.create(
      persistence: persistenceModule,
      workspace: workspaceModule,
    );
    final projectModule = ProjectModule.create(
      persistence: persistenceModule,
      workspace: workspaceModule,
      task: taskModule.controller,
    );
    final chatModule = ChatModule.create(
      preferences: preferencesService,
      model: modelModule,
      workspace: workspaceModule,
      task: taskModule.controller,
      project: projectModule.application,
    );
    final themeManager = ThemeManager(preferencesService: preferencesService);
    final lifecycleCoordinator = ApplicationLifecycleCoordinator();
    lifecycleCoordinator.register(
      name: 'preferences',
      dispose: preferencesService.dispose,
    );
    lifecycleCoordinator.register(name: 'theme', dispose: themeManager.dispose);
    lifecycleCoordinator.register(
      name: 'workspace',
      dispose: workspaceModule.workspace.dispose,
    );
    lifecycleCoordinator.register(
      name: 'chat library',
      dispose: chatModule.chatLibrary.dispose,
    );
    lifecycleCoordinator.register(
      name: 'system prompt library',
      dispose: chatModule.systemPromptLibrary.dispose,
    );
    lifecycleCoordinator.register(
      name: 'model',
      dispose: modelModule.manager.dispose,
    );
    lifecycleCoordinator.register(
      name: 'chat workspace',
      quiesce: () => chatModule.workspaceController.prepareForExit(
        NewChatExitPolicy.discard,
      ),
      flush: () =>
          chatModule.workspaceController.prepareForExit(NewChatExitPolicy.save),
      dispose: chatModule.workspaceController.dispose,
      disposeWithoutSaving: chatModule.workspaceController.disposeWithoutSaving,
    );
    return AppDependencies._(
      preferencesService: preferencesService,
      themeManager: themeManager,
      workspaceSandbox: workspaceModule.sandbox,
      workspaceService: workspaceModule.workspace,
      toolService: workspaceModule.tools,
      modelManager: modelModule.manager,
      modelCatalog: modelCatalog,
      taskController: taskModule.controller,
      projectApplication: projectModule.application,
      chatLibraryService: chatModule.chatLibrary,
      systemPromptLibraryService: chatModule.systemPromptLibrary,
      chatWorkspaceController: chatModule.workspaceController,
      lifecycleCoordinator: lifecycleCoordinator,
    );
  }

  final PreferencesService preferencesService;
  final ThemeManager themeManager;
  final WorkspaceSandbox workspaceSandbox;
  final WorkspaceService workspaceService;
  final ToolService toolService;
  final LlamaServerManager modelManager;
  final ModelCatalogPort modelCatalog;
  final TaskController taskController;
  final ProjectApplication projectApplication;
  final ChatLibraryService chatLibraryService;
  final SystemPromptLibraryService systemPromptLibraryService;
  final ChatWorkspaceController chatWorkspaceController;
  final ApplicationLifecycleCoordinator lifecycleCoordinator;

  @override
  ApplicationLifecycleState get lifecycleState =>
      lifecycleCoordinator.lifecycleState;

  @override
  Future<void> start() => lifecycleCoordinator.start();

  @override
  Future<void> quiesce() => lifecycleCoordinator.quiesce();

  @override
  Future<void> flush() => lifecycleCoordinator.flush();

  /// Disposes owned dependencies once, in reverse construction order.
  Future<void> dispose() => lifecycleCoordinator.dispose();

  Future<void> disposeWithoutSaving() =>
      lifecycleCoordinator.disposeWithoutSaving();
}
