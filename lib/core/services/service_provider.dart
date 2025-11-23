import 'package:flutter/foundation.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_factory.dart';
import 'package:hermes/core/services/theme_manager.dart';
import 'package:hermes/core/services/tool_service.dart';

class ServiceProvider {
  ServiceProvider._();

  static final ServiceProvider _instance = ServiceProvider._();
  static ServiceProvider get instance => _instance;

  factory ServiceProvider() => _instance;

  final Map<Type, Object> _singletonServices = {};
  final Map<Type, ServiceFactory> _transientServices = {};

  bool _initialized = false;

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
    registerSingleton(ToolService());
    registerSingleton(ChatService());

    _initialized = true;
  }

  void dispose() {
    _initialized = false;
    _singletonServices.forEach((key, value) {
      _disposeIfPossible(value);
    });

    _singletonServices.clear();
    _transientServices.clear();
  }

  void _disposeIfPossible(dynamic service) {
    if (service != null) {
      try {
        if (service.dispose is Function) {
          service.dispose();
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
