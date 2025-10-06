import 'package:flutter/material.dart';

(Color bgColor, Color textColor) getColorsForRole(ColorScheme scheme, String role) {
    final bgColor = switch (role) {
      'user' => scheme.primaryContainer,
      'assistant' => scheme.secondaryContainer,
      'system' => scheme.tertiaryContainer,
      'tool' => scheme.errorContainer,
      _ => scheme.surface,
    };

    final textColor = switch (role) {
      'user' => scheme.onPrimaryContainer,
      'assistant' => scheme.onSecondaryContainer,
      'system' => scheme.onTertiaryContainer,
      'tool' => scheme.onErrorContainer,
      _ => scheme.onSurface,
    };

    return (bgColor, textColor);
}
