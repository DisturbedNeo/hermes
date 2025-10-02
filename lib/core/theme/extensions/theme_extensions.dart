import 'package:flutter/material.dart';
import 'package:hermes/core/theme/extensions/button_theme.dart';
import 'package:hermes/core/theme/extensions/card_theme.dart';
import 'package:hermes/core/theme/extensions/hermes_palette.dart';
import 'package:hermes/core/theme/extensions/input_theme.dart';

extension HermesThemeExtensions on ThemeData {
  HermesButtonTheme? get codexButtonTheme => extension<HermesButtonTheme>();
  HermesCardTheme? get codexCardTheme => extension<HermesCardTheme>();
  HermesInputTheme? get codexInputTheme => extension<HermesInputTheme>();
  HermesPalette? get codexPalette => extension<HermesPalette>();
}
