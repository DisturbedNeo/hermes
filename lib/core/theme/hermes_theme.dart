import 'package:flutter/material.dart';

class HermesTheme extends ThemeExtension<HermesTheme> {
  final AppBarTheme appBarTheme;
  final CardTheme cardTheme;
  final ElevatedButtonThemeData elevatedButtonTheme;
  final InputDecorationTheme inputDecorationTheme;
  final TabBarTheme tabBarTheme;

  const HermesTheme({
    required this.appBarTheme,
    required this.cardTheme,
    required this.elevatedButtonTheme,
    required this.inputDecorationTheme,
    required this.tabBarTheme,
  });

  factory HermesTheme.light({
    required Color primary,
    required Color secondary,
    required Color surface,
    required Color onSurface,
  }) => HermesTheme(
    appBarTheme: AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 2,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      color: surface,
      elevation: 3,
      shadowColor: primary.withAlpha(76),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 3,
        shadowColor: primary.withAlpha(128),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: TextStyle(color: onSurface.withAlpha(150)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
    tabBarTheme: TabBarTheme(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white.withAlpha(180),
      indicatorColor: secondary,
      indicatorSize: TabBarIndicatorSize.tab,
    ),
  );

  factory HermesTheme.dark({
    required Color primary,
    required Color secondary,
    required Color surface,
    required Color onSurface,
  }) => HermesTheme(
    appBarTheme: AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 2,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      color: surface,
      elevation: 4,
      shadowColor: Colors.black.withAlpha(102),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: secondary.withAlpha(51), width: 0.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shadowColor: Colors.black.withAlpha(77),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface.withAlpha(240),
      hintStyle: TextStyle(color: onSurface.withAlpha(150)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: surface.withAlpha(100)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: secondary.withAlpha(200), width: 2),
      ),
    ),
    tabBarTheme: TabBarTheme(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white.withAlpha(180),
      indicatorColor: secondary,
      indicatorSize: TabBarIndicatorSize.tab,
    ),
  );

  @override
  ThemeExtension<HermesTheme> copyWith({
    AppBarTheme? appBarTheme,
    CardTheme? cardTheme,
    ElevatedButtonThemeData? elevatedButtonTheme,
    InputDecorationTheme? inputDecorationTheme,
    TabBarTheme? tabBarTheme,
  }) => HermesTheme(
    appBarTheme: appBarTheme ?? this.appBarTheme,
    cardTheme: cardTheme ?? this.cardTheme,
    elevatedButtonTheme: elevatedButtonTheme ?? this.elevatedButtonTheme,
    inputDecorationTheme: inputDecorationTheme ?? this.inputDecorationTheme,
    tabBarTheme: tabBarTheme ?? this.tabBarTheme,
  );

  @override
  ThemeExtension<HermesTheme> lerp(
    covariant ThemeExtension<HermesTheme>? other,
    double t,
  ) {
    if (other is! HermesTheme) {
      return this;
    }

    return HermesTheme(
      appBarTheme: _lerpAppBarTheme(appBarTheme, other.appBarTheme, t),
      cardTheme: _lerpCardTheme(cardTheme, other.cardTheme, t),
      elevatedButtonTheme: _lerpElevatedButtonTheme(
        elevatedButtonTheme,
        other.elevatedButtonTheme,
        t,
      ),
      inputDecorationTheme: _lerpInputDecorationTheme(
        inputDecorationTheme,
        other.inputDecorationTheme,
        t,
      ),
      tabBarTheme: _lerpTabBarTheme(tabBarTheme, other.tabBarTheme, t),
    );
  }

  static AppBarTheme _lerpAppBarTheme(AppBarTheme a, AppBarTheme b, double t) =>
      AppBarTheme(
        backgroundColor: Color.lerp(a.backgroundColor, b.backgroundColor, t),
        foregroundColor: Color.lerp(a.foregroundColor, b.foregroundColor, t),
        elevation: lerpDouble(a.elevation, b.elevation, t),
        centerTitle: t < 0.5 ? a.centerTitle : b.centerTitle,
      );

  static CardTheme _lerpCardTheme(CardTheme a, CardTheme b, double t) =>
      CardTheme(
        color: Color.lerp(a.color, b.color, t),
        elevation: lerpDouble(a.elevation, b.elevation, t),
        shadowColor: Color.lerp(a.shadowColor, b.shadowColor, t),
        shape: t < 0.5 ? a.shape : b.shape,
      );

  static ElevatedButtonThemeData _lerpElevatedButtonTheme(
    ElevatedButtonThemeData a,
    ElevatedButtonThemeData b,
    double t,
  ) => t < 0.5 ? a : b;

  static InputDecorationTheme _lerpInputDecorationTheme(
    InputDecorationTheme a,
    InputDecorationTheme b,
    double t,
  ) => InputDecorationTheme(
    filled: t < 0.5 ? a.filled : b.filled,
    fillColor: Color.lerp(a.fillColor, b.fillColor, t),
    hintStyle: TextStyle.lerp(a.hintStyle, b.hintStyle, t),
    border: t < 0.5 ? a.border : b.border,
    focusedBorder: t < 0.5 ? a.focusedBorder : b.focusedBorder,
  );

  static TabBarTheme _lerpTabBarTheme(TabBarTheme a, TabBarTheme b, double t) =>
      TabBarTheme(
        labelColor: Color.lerp(a.labelColor, b.labelColor, t),
        unselectedLabelColor: Color.lerp(
          a.unselectedLabelColor,
          b.unselectedLabelColor,
          t,
        ),
        indicatorColor: Color.lerp(a.indicatorColor, b.indicatorColor, t),
        indicatorSize: t < 0.5 ? a.indicatorSize : b.indicatorSize,
      );

  static double? lerpDouble(double? a, double? b, double t) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return a + (b - a) * t;
  }
}

extension CodexThemeExtension on ThemeData {
  HermesTheme get codex => extension<HermesTheme>()!;
}
