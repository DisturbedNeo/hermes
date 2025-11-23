import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';

(Color bgColor, Color textColor) getColorsForRole(ColorScheme scheme, MessageRole role) {
    final bgColor = switch (role) {
      MessageRole.user => scheme.primaryContainer,
      MessageRole.assistant => scheme.secondaryContainer,
      MessageRole.system => scheme.tertiaryContainer,
      MessageRole.tool => scheme.errorContainer,
    };

    final textColor = switch (role) {
      MessageRole.user => scheme.onPrimaryContainer,
      MessageRole.assistant => scheme.onSecondaryContainer,
      MessageRole.system => scheme.onTertiaryContainer,
      MessageRole.tool => scheme.onErrorContainer,
    };

    return (bgColor, textColor);
}
