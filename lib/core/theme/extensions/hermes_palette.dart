import 'package:flutter/material.dart';
import 'package:hermes/core/theme/hermes_colours.dart';

class HermesPalette extends ThemeExtension<HermesPalette> {
  // Core colors
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color background;
  final Color surface;
  final Color onSurface;

  // State colors
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color error;
  final Color onError;
  final Color info;
  final Color onInfo;

  // Special purpose colors
  final Color highlight;
  final Color muted;
  final Color divider;
  final Color overlay;

  const HermesPalette({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.error,
    required this.onError,
    required this.info,
    required this.onInfo,
    required this.highlight,
    required this.muted,
    required this.divider,
    required this.overlay,
  });

  factory HermesPalette.custom({
    required Color primary,
    required Color secondary,
    required Color background,
    required Color surface,
    Color? onPrimary,
    Color? onSecondary,
    Color? onSurface,
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? error,
    Color? onError,
    Color? info,
    Color? onInfo,
    Color? highlight,
    Color? muted,
    Color? divider,
    Color? overlay,
  }) {
    final calculatedOnPrimary =
        onPrimary ??
        (ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
            ? Colors.white
            : Colors.black);

    final calculatedOnSecondary =
        onSecondary ??
        (ThemeData.estimateBrightnessForColor(secondary) == Brightness.dark
            ? Colors.white
            : Colors.black);

    final calculatedOnSurface =
        onSurface ??
        (ThemeData.estimateBrightnessForColor(surface) == Brightness.dark
            ? Colors.white
            : Colors.black);

    final successColor = success ?? HermesColours.success;
    final warningColor = warning ?? HermesColours.warning;
    final errorColor = error ?? HermesColours.error;
    final infoColor = info ?? HermesColours.info;

    return HermesPalette(
      primary: primary,
      onPrimary: calculatedOnPrimary,
      secondary: secondary,
      onSecondary: calculatedOnSecondary,
      background: background,
      surface: surface,
      onSurface: calculatedOnSurface,
      success: successColor,
      onSuccess: onSuccess ?? Colors.white,
      warning: warningColor,
      onWarning: onWarning ?? Colors.black,
      error: errorColor,
      onError: onError ?? Colors.white,
      info: infoColor,
      onInfo: onInfo ?? Colors.white,
      highlight: highlight ?? secondary.withValues(alpha: 0.2),
      muted: muted ?? HermesColours.mediumGrey,
      divider: divider ?? HermesColours.lightGrey,
      overlay: overlay ?? Colors.black.withValues(alpha: 0.5),
    );
  }

  @override
  ThemeExtension<HermesPalette> copyWith({
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? onSecondary,
    Color? background,
    Color? surface,
    Color? onSurface,
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? error,
    Color? onError,
    Color? info,
    Color? onInfo,
    Color? highlight,
    Color? muted,
    Color? divider,
    Color? overlay,
  }) => HermesPalette(
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    secondary: secondary ?? this.secondary,
    onSecondary: onSecondary ?? this.onSecondary,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    onSurface: onSurface ?? this.onSurface,
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    error: error ?? this.error,
    onError: onError ?? this.onError,
    info: info ?? this.info,
    onInfo: onInfo ?? this.onInfo,
    highlight: highlight ?? this.highlight,
    muted: muted ?? this.muted,
    divider: divider ?? this.divider,
    overlay: overlay ?? this.overlay,
  );

  @override
  ThemeExtension<HermesPalette> lerp(
    covariant ThemeExtension<HermesPalette>? other,
    double t,
  ) {
    if (other is! HermesPalette) {
      return this;
    }

    return HermesPalette(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      onSecondary: Color.lerp(onSecondary, other.onSecondary, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
    );
  }
}

extension CodexPaletteExtension on ThemeData {
  HermesPalette get palette => extension<HermesPalette>()!;
}
