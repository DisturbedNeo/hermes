import 'package:flutter/material.dart';
import 'package:hermes/core/theme/extensions/button_theme.dart';
import 'package:hermes/core/theme/extensions/card_theme.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/extensions/input_theme.dart';

class HermesThemeBuilder {
  final HermesPalette _palette;
  final bool _isDark;
  
  HermesButtonTheme? _buttonTheme;
  HermesCardTheme? _cardTheme;
  HermesInputTheme? _inputTheme;
  TextTheme? _textTheme;
  TabBarTheme? _tabBarTheme;
  AppBarTheme? _appBarTheme;
  
  HermesThemeBuilder({
    required HermesPalette palette,
    required bool isDark,
  }) : _palette = palette, _isDark = isDark;
  
  HermesThemeBuilder withButtonTheme(HermesButtonTheme buttonTheme) {
    _buttonTheme = buttonTheme;
    return this;
  }
  
  HermesThemeBuilder withCardTheme(HermesCardTheme cardTheme) {
    _cardTheme = cardTheme;
    return this;
  }
  
  HermesThemeBuilder withInputTheme(HermesInputTheme inputTheme) {
    _inputTheme = inputTheme;
    return this;
  }
  
  HermesThemeBuilder withTextTheme(TextTheme textTheme) {
    _textTheme = textTheme;
    return this;
  }
  
  HermesThemeBuilder withTabBarTheme(TabBarTheme tabBarTheme) {
    _tabBarTheme = tabBarTheme;
    return this;
  }
  
  HermesThemeBuilder withAppBarTheme(AppBarTheme appBarTheme) {
    _appBarTheme = appBarTheme;
    return this;
  }
  
  ThemeData build() {
    final buttonTheme = _buttonTheme ?? (_isDark 
        ? HermesButtonTheme.dark(
            primary: _palette.primary,
            onPrimary: _palette.onPrimary,
            secondary: _palette.secondary,
            onSecondary: _palette.onSecondary,
            error: _palette.error,
            onError: _palette.onError,
          )
        : HermesButtonTheme.light(
            primary: _palette.primary,
            onPrimary: _palette.onPrimary,
            secondary: _palette.secondary,
            onSecondary: _palette.onSecondary,
            error: _palette.error,
            onError: _palette.onError,
          ));
    
    final cardTheme = _cardTheme ?? (_isDark
        ? HermesCardTheme.dark(
            secondary: _palette.secondary,
            surface: _palette.surface,
          )
        : HermesCardTheme.light(
            primary: _palette.primary,
            surface: _palette.surface,
          ));
    
    final inputTheme = _inputTheme ?? (_isDark
        ? HermesInputTheme.dark(
            secondary: _palette.secondary,
            surface: _palette.surface,
            onSurface: _palette.onSurface,
          ) 
        : HermesInputTheme.light(
            primary: _palette.primary,
            surface: _palette.surface,
            onSurface: _palette.onSurface,
          ));
    
    final textTheme = _textTheme ?? _createDefaultTextTheme();
    
    final tabBarTheme = _tabBarTheme ?? TabBarTheme(
      labelColor: _palette.onPrimary,
      unselectedLabelColor: _palette.onPrimary.withAlpha(180),
      indicatorColor: _palette.secondary,
      indicatorSize: TabBarIndicatorSize.tab,
    );
    
    final appBarTheme = _appBarTheme ?? AppBarTheme(
      backgroundColor: _palette.primary,
      foregroundColor: _palette.onPrimary,
      elevation: _isDark ? 2 : 1,
      centerTitle: false,
    );
    
    final colorScheme = (_isDark ? ColorScheme.dark : ColorScheme.light)(
      primary: _palette.primary,
      onPrimary: _palette.onPrimary,
      secondary: _palette.secondary,
      onSecondary: _palette.onSecondary,
      tertiary: _palette.tertiary,
      onTertiary: _palette.onTertiary,
      surface: _palette.surface,
      onSurface: _palette.onSurface,
      background: _palette.background,
      onBackground: _palette.onSurface,
      error: _palette.error,
      onError: _palette.onError,
    );
    
    final dividerTheme = DividerThemeData(
      color: _palette.divider,
      thickness: 1,
      space: 1,
    );

    final elevatedButtonTheme = ElevatedButtonThemeData(
      style: buttonTheme.primaryStyle,
    );
    
    final textButtonTheme = TextButtonThemeData(
      style: buttonTheme.textStyle,
    );
    
    final outlinedButtonTheme = OutlinedButtonThemeData(
      style: buttonTheme.outlinedStyle,
    );
    
    return (_isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true)).copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _palette.background,
      
      appBarTheme: appBarTheme,
      cardTheme: cardTheme.cardTheme.data,
      inputDecorationTheme: inputTheme.inputDecorationTheme,
      textSelectionTheme: inputTheme.textSelectionTheme,
      elevatedButtonTheme: elevatedButtonTheme,
      textButtonTheme: textButtonTheme,
      outlinedButtonTheme: outlinedButtonTheme,
      tabBarTheme: tabBarTheme.data,
      textTheme: textTheme,
      dividerTheme: dividerTheme,
      
      extensions: [
        _palette,
        buttonTheme,
        cardTheme,
        inputTheme,
      ],
    );
  }
  
  TextTheme _createDefaultTextTheme() {
    final headlineColor = _isDark ? _palette.secondary : _palette.primary;
    final bodyColor = _palette.onSurface;
    
    return TextTheme(
      bodyLarge: TextStyle(color: bodyColor),
      bodyMedium: TextStyle(color: bodyColor),
      bodySmall: TextStyle(color: bodyColor),
      displayLarge: TextStyle(color: bodyColor, fontWeight: FontWeight.bold),
      displayMedium: TextStyle(color: bodyColor, fontWeight: FontWeight.bold),
      displaySmall: TextStyle(color: bodyColor, fontWeight: FontWeight.bold),
      headlineLarge: TextStyle(color: headlineColor, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: headlineColor, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(color: bodyColor, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: bodyColor, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(color: bodyColor, fontWeight: FontWeight.w600),
      labelLarge: TextStyle(color: _palette.onPrimary),
    );
  }
}
