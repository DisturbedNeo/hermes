import 'dart:io';

import 'package:flutter/foundation.dart';

/// Platform detection helpers.
class PlatformX {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;

  /// Whether the app is running in a web browser target.
  /// Uses [kIsWeb] from Flutter's foundation library (the standard approach).
  static bool get isWeb => kIsWeb;
}
