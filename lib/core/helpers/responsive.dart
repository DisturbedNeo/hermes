import 'package:flutter/material.dart';

/// Utility class providing breakpoint-aware responsive layout helpers.
///
/// **Actual breakpoints** (used in the code):
/// - Mobile: < 600px (`mobile`)
/// - Tablet: 600px – 900px (`tablet`)
/// - Desktop: >= 1200px (`desktop`)
///
/// Note: The tablet range (600–900) is narrower than Material Design's
/// recommended 600–1200. This was chosen to keep more mid-size screens in
/// the "mobile" layout path where the UI has been tested and validated.
class Responsive {
  Responsive._();

  /// Viewport width below which the mobile layout is used.
  static const double mobile = 600;

  /// Upper bound of the tablet range. Widths from [mobile] up to (but not
  /// including) this value are considered tablet.
  static const double tablet = 900;

  /// Viewport width at or above which the desktop layout is used.
  static const double desktop = 1200;

  /// Returns `true` when the viewport is narrower than [mobile].
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobile;

  /// Returns `true` when the viewport width falls between [mobile] and [tablet].
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobile && width < tablet;
  }

  /// Returns `true` when the viewport width is at or above [desktop].
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
