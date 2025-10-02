import 'package:flutter/material.dart';

class HermesCardTheme extends ThemeExtension<HermesCardTheme> {
  final CardTheme cardTheme;
  final double defaultPadding;
  final double defaultMargin;
  final BorderRadius defaultBorderRadius;

  const HermesCardTheme({
    required this.cardTheme,
    required this.defaultPadding,
    required this.defaultMargin,
    required this.defaultBorderRadius,
  });

  factory HermesCardTheme.light({
    required Color primary,
    required Color surface,
  }) => HermesCardTheme(
    cardTheme: CardTheme(
      color: surface,
      elevation: 3,
      shadowColor: primary.withAlpha(76),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
    ),
    defaultPadding: 16.0,
    defaultMargin: 8.0,
    defaultBorderRadius: BorderRadius.circular(12),
  );

  factory HermesCardTheme.dark({
    required Color secondary,
    required Color surface,
  }) => HermesCardTheme(
    cardTheme: CardTheme(
      color: surface,
      elevation: 4,
      shadowColor: Colors.black.withAlpha(102),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: secondary.withAlpha(51), width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    defaultPadding: 16.0,
    defaultMargin: 8.0,
    defaultBorderRadius: BorderRadius.circular(12),
  );

  @override
  ThemeExtension<HermesCardTheme> copyWith({
    CardTheme? cardTheme,
    double? defaultPadding,
    double? defaultMargin,
    BorderRadius? defaultBorderRadius,
  }) => HermesCardTheme(
    cardTheme: cardTheme ?? this.cardTheme,
    defaultPadding: defaultPadding ?? this.defaultPadding,
    defaultMargin: defaultMargin ?? this.defaultMargin,
    defaultBorderRadius: defaultBorderRadius ?? this.defaultBorderRadius,
  );

  @override
  ThemeExtension<HermesCardTheme> lerp(
    covariant ThemeExtension<HermesCardTheme>? other,
    double t,
  ) {
    if (other is! HermesCardTheme) {
      return this;
    }

    return HermesCardTheme(
      cardTheme: _lerpCardTheme(cardTheme, other.cardTheme, t),
      defaultPadding: lerpDouble(defaultPadding, other.defaultPadding, t),
      defaultMargin: lerpDouble(defaultMargin, other.defaultMargin, t),
      defaultBorderRadius:
          t < 0.5 ? defaultBorderRadius : other.defaultBorderRadius,
    );
  }

  static CardTheme _lerpCardTheme(CardTheme a, CardTheme b, double t) =>
      CardTheme(
        color: Color.lerp(a.color, b.color, t),
        shadowColor: Color.lerp(a.shadowColor, b.shadowColor, t),
        elevation: lerpDouble(a.elevation, b.elevation, t),
        margin: t < 0.5 ? a.margin : b.margin,
        shape: t < 0.5 ? a.shape : b.shape,
        clipBehavior: t < 0.5 ? a.clipBehavior : b.clipBehavior,
      );

  static double lerpDouble(double? a, double? b, double t) {
    if (a == null && b == null) return 16.0;
    if (a == null) return b!;
    if (b == null) return a;
    return a + (b - a) * t;
  }
}

extension CodexCardThemeExtension on ThemeData {
  HermesCardTheme? get codexCard => extension<HermesCardTheme>();
}
