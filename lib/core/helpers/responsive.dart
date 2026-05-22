import 'package:flutter/material.dart';

/// Utility class providing breakpoint-aware responsive layout helpers.
///
/// Follows Material Design's recommended breakpoints:
/// - Mobile: < 600px
/// - Tablet: 600px – 1200px
/// - Desktop: >= 1200px
class Responsive {
  Responsive._();

  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;

  /// Returns true if the current viewport width is below [mobile] breakpoint.
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobile;

  /// Returns true if the current viewport width is between [mobile] and [tablet].
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobile && width < tablet;
  }

  /// Returns true if the current viewport width is at or above [desktop] breakpoint.
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktop;

  /// Returns the current viewport width.
  static double availableWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  /// Returns the current viewport height.
  static double availableHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  /// Conditionally builds widgets based on the current breakpoint.
  static Widget when({
    required Widget Function(BuildContext) mobile,
    required Widget Function(BuildContext) tablet,
    required Widget Function(BuildContext) desktop,
    required BuildContext context,
  }) {
    if (isDesktop(context)) return desktop(context);
    if (isTablet(context)) return tablet(context);
    return mobile(context);
  }

  /// Builds a widget using the raw viewport width.
  static Widget whenWidth({
    required Widget Function(double) builder,
    required BuildContext context,
  }) {
    return builder(MediaQuery.of(context).size.width);
  }

  /// Returns true if the layout should use a narrow (stacked) mode.
  /// Useful for component-level decisions like "should the composer stack vertically?"
  static bool isNarrow(BuildContext context) =>
      MediaQuery.of(context).size.width < tablet;

  /// Returns true if the layout has enough horizontal space for side-by-side panels.
  static bool hasWideViewport(BuildContext context) =>
      MediaQuery.of(context).size.width >= 700;
}
