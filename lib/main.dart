import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/theme_manager.dart';
import 'package:hermes/ui/routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  serviceProvider.initialize();

  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final ThemeManager _themeManager = serviceProvider.get<ThemeManager>();
  //final CodexDb _db = serviceProvider.get<CodexDb>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeManager.addListener(_handleThemeChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeManager.removeListener(_handleThemeChanged);
    super.dispose();
  }

  void _handleThemeChanged() {
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    switch (state) {
      case AppLifecycleState.paused:
        // App is in background but may come back
        break;
      case AppLifecycleState.detached:
        // App is in background or terminated, clean up resources
        //_db.closeDatabase();
        serviceProvider.dispose();
        break;
      case AppLifecycleState.resumed:
        // App is visible again, reinitialize services if needed
        serviceProvider.initialize();
        break;
      case AppLifecycleState.inactive:
        // App is in an inactive state, like when receiving a phone call
        break;
      case AppLifecycleState.hidden:
        // App is hidden from user but still running
        break;
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() {
    serviceProvider.dispose();

    return super.didRequestAppExit();
  }

  @override
  void reassemble() {
    super.reassemble();

    serviceProvider.dispose();
    serviceProvider.initialize();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Codex',
    theme: _themeManager.currentTheme,
    initialRoute: AppRoutes.home,
    onGenerateRoute: generateRoute,
    navigatorKey: AppNavigator.navigatorKey,
    debugShowCheckedModeBanner: false,
  );
}
