import 'package:flutter/material.dart';

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

Route<dynamic> generateRoute(
  RouteSettings settings, {
  required WidgetBuilder homeBuilder,
}) {
  switch (settings.name) {
    case AppRoutes.home:
      return _buildHomeRoute(settings, homeBuilder);
    default:
      return _buildUnknownRoute(settings);
  }
}

Route<dynamic> _buildUnknownRoute(RouteSettings settings) => PageRouteBuilder(
  settings: settings,
  pageBuilder: (context, animation, secondaryAnimation) =>
      const _UnknownRoutePage(),
);

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text('Page not found', style: TextStyle(fontSize: 20)),
            SizedBox(height: 8),
            Text(
              'The requested route does not exist.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

Route<dynamic> _buildHomeRoute(
  RouteSettings settings,
  WidgetBuilder homeBuilder,
) => PageRouteBuilder(
  settings: settings,
  pageBuilder: (context, animation, secondaryAnimation) => homeBuilder(context),
);
