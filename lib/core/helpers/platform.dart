import 'dart:io';

class PlatformX {
  static bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;
  static bool get isWeb => identical(0, 0.0); // This is a hack to check for web
}
