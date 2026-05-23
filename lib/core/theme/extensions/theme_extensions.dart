import 'package:flutter/material.dart';
import 'package:hermes/core/theme/extensions/button_theme.dart';
import 'package:hermes/core/theme/extensions/card_theme.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/extensions/input_theme.dart';

extension HermesThemeExtensions on ThemeData {
  HermesButtonTheme? get hermesButtonTheme => extension<HermesButtonTheme>();
  HermesCardTheme? get hermesCardTheme => extension<HermesCardTheme>();
  HermesInputTheme? get hermesInputTheme => extension<HermesInputTheme>();
  HermesPalette? get hermesPalette => extension<HermesPalette>();
}
