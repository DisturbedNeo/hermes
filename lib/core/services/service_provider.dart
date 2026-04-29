import 'package:flutter/foundation.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_factory.dart';
import 'package:hermes/core/services/theme_manager.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';

class ServiceProvider {
  ServiceProvider._();

  static final ServiceProvider _instance = ServiceProvider._();
  static ServiceProvider get instance => _instance;

  factory ServiceProvider() => _instance;

  final Map<Type, Object> _singletonServices = {};
  final Map<Type, ServiceFactory> _transientServices = {};

  bool _initialized = false;
  Future<void>? _disposing;

  T get<T extends Object>() {
    if (_singletonServices.containsKey(T)) {
      return _singletonServices[T]! as T;
    }

    if (_transientServices.containsKey(T)) {
      return _transientServices[T]!.create() as T;
    }

    throw Exception('Service of type $T is not registered.');
  }

  void initialize() {
    if (_initialized) return;

    registerSingleton(PreferencesService());
    registerSingleton(ThemeManager());
    registerSingleton(WorkspaceService());
    registerSingleton(ToolService());
    registerSingleton(
      ChatLibraryService(preferencesService: get<PreferencesService>()),
    );
    registerSingleton(
      ChatTabsService(
        chatLibrary: get<ChatLibraryService>(),
        toolService: get<ToolService>(),
        workspaceService: get<WorkspaceService>(),
      ),
    );

    _initialized = true;
  }

  Future<void> dispose() => _disposing ??= _disposeServices();

  Future<void> _disposeServices() async {
    _initialized = false;
    final services = _singletonServices.values.toList().reversed.toList();

    _singletonServices.clear();
    _transientServices.clear();

    try {
      for (final service in services) {
        await _disposeIfPossible(service);
      }
    } finally {
      _disposing = null;
    }
  }

  Future<void> _disposeIfPossible(dynamic service) async {
    if (service != null) {
      try {
        if (service.dispose is Function) {
          final result = service.dispose();
          if (result is Future) {
            await result;
          }
          if (kDebugMode) {
            print('Disposed ${service.runtimeType}');
          }
        }
      } catch (_) {}
    }
  }

  void registerSingleton<T extends Object>(T service) {
    if (_singletonServices.containsKey(T)) {
      throw Exception('Service of type $T is already registered as singleton.');
    }

    _singletonServices[T] = service;
  }

  void registerTransient<T extends Object>(T Function() factory) {
    if (_transientServices.containsKey(T)) {
      throw Exception('Service of type $T is already registered as transient.');
    }

    _transientServices[T] = ServiceFactory(factory);
  }

  bool isRegistered<T>() =>
      _singletonServices.containsKey(T) || _transientServices.containsKey(T);
}

final serviceProvider = ServiceProvider.instance;
