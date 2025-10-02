import 'package:flutter/material.dart';
import 'package:hermes/ui/chat.dart';

class AppRoutes {
  AppRoutes._();

  static const String home = '/';
}

class AppNavigator {
  AppNavigator._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static void goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  static void clearStack(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
  }
}

Route<dynamic> generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.home:
      return _buildChatRoute(settings);

    default:
      return _buildChatRoute(settings);
  }
}

Route<dynamic> _buildChatRoute(RouteSettings settings) => PageRouteBuilder(
  settings: settings,
  pageBuilder: (context, animation, secondaryAnimation) => const Chat(),
);
