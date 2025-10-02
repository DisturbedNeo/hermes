import 'package:flutter/material.dart';
import 'package:hermes/core/enums/hermes_button_type.dart';

class HermesButtonTheme extends ThemeExtension<HermesButtonTheme> {
  final ButtonStyle primaryStyle;
  final ButtonStyle secondaryStyle;
  final ButtonStyle outlinedStyle;
  final ButtonStyle textStyle;
  final ButtonStyle dangerStyle;

  const HermesButtonTheme({
    required this.primaryStyle,
    required this.secondaryStyle,
    required this.outlinedStyle,
    required this.textStyle,
    required this.dangerStyle,
  });

  factory HermesButtonTheme.light({
    required Color primary,
    required Color onPrimary,
    required Color secondary,
    required Color onSecondary,
    required Color error,
    required Color onError,
  }) => HermesButtonTheme(
    primaryStyle: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(primary),
      foregroundColor: WidgetStatePropertyAll(onPrimary),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return onPrimary.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return onPrimary.withValues(alpha: 0.08);
        }
        return null;
      }),
      elevation: const WidgetStatePropertyAll(3),
      shadowColor: WidgetStatePropertyAll(primary.withAlpha(128)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    secondaryStyle: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(secondary),
      foregroundColor: WidgetStatePropertyAll(onSecondary),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return onSecondary.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return onSecondary.withValues(alpha: 0.08);
        }
        return null;
      }),
      elevation: const WidgetStatePropertyAll(2),
      shadowColor: WidgetStatePropertyAll(secondary.withAlpha(128)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedStyle: ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(primary),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return primary.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return primary.withValues(alpha: 0.08);
        }
        return null;
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: primary),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    textStyle: ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(primary),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return primary.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return primary.withValues(alpha: 0.08);
        }
        return null;
      }),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    ),
    dangerStyle: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(error),
      foregroundColor: WidgetStatePropertyAll(onError),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return onError.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return onError.withValues(alpha: 0.08);
        }
        return null;
      }),
      elevation: const WidgetStatePropertyAll(3),
      shadowColor: WidgetStatePropertyAll(error.withAlpha(128)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
  );

  factory HermesButtonTheme.dark({
    required Color primary,
    required Color onPrimary,
    required Color secondary,
    required Color onSecondary,
    required Color error,
    required Color onError,
  }) => HermesButtonTheme(
    primaryStyle: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(primary),
      foregroundColor: WidgetStatePropertyAll(onPrimary),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return onPrimary.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return onPrimary.withValues(alpha: 0.10);
        }
        return null;
      }),
      elevation: const WidgetStatePropertyAll(4),
      shadowColor: WidgetStatePropertyAll(Colors.black.withAlpha(77)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    secondaryStyle: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(secondary),
      foregroundColor: WidgetStatePropertyAll(onSecondary),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return onSecondary.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return onSecondary.withValues(alpha: 0.10);
        }
        return null;
      }),
      elevation: const WidgetStatePropertyAll(3),
      shadowColor: WidgetStatePropertyAll(Colors.black.withAlpha(77)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedStyle: ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(primary),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return primary.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return primary.withValues(alpha: 0.10);
        }
        return null;
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: primary),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    textStyle: ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(primary),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return primary.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return primary.withValues(alpha: 0.10);
        }
        return null;
      }),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    ),
    dangerStyle: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(error),
      foregroundColor: WidgetStatePropertyAll(onError),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return onError.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return onError.withValues(alpha: 0.10);
        }
        return null;
      }),
      elevation: const WidgetStatePropertyAll(4),
      shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.3)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
  );

  ButtonStyle getStyleForVariant(HermesButtonType variant) {
    switch (variant) {
      case HermesButtonType.primary:
        return primaryStyle;
      case HermesButtonType.secondary:
        return secondaryStyle;
      case HermesButtonType.outlined:
        return outlinedStyle;
      case HermesButtonType.text:
        return textStyle;
      case HermesButtonType.danger:
        return dangerStyle;
    }
  }

  @override
  ThemeExtension<HermesButtonTheme> copyWith({
    ButtonStyle? primaryStyle,
    ButtonStyle? secondaryStyle,
    ButtonStyle? outlinedStyle,
    ButtonStyle? textStyle,
    ButtonStyle? dangerStyle,
  }) => HermesButtonTheme(
    primaryStyle: primaryStyle ?? this.primaryStyle,
    secondaryStyle: secondaryStyle ?? this.secondaryStyle,
    outlinedStyle: outlinedStyle ?? this.outlinedStyle,
    textStyle: textStyle ?? this.textStyle,
    dangerStyle: dangerStyle ?? this.dangerStyle,
  );

  @override
  ThemeExtension<HermesButtonTheme> lerp(
    covariant ThemeExtension<HermesButtonTheme>? other,
    double t,
  ) {
    if (other is! HermesButtonTheme) {
      return this;
    }

    return t < 0.5 ? this : other;
  }
}

extension CodexButtonThemeExtension on ThemeData {
  HermesButtonTheme get codexButton => extension<HermesButtonTheme>()!;
}
