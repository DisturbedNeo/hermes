import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';

(Color bgColor, Color textColor) getColorsForRole(ColorScheme scheme, MessageRole role) {
    final bgColor = switch (role) {
      MessageRole.user => scheme.primaryContainer,
      MessageRole.assistant => scheme.secondaryContainer,
      MessageRole.system => scheme.tertiaryContainer,
    };

    final textColor = switch (role) {
      MessageRole.user => scheme.onPrimaryContainer,
      MessageRole.assistant => scheme.onSecondaryContainer,
      MessageRole.system => scheme.onTertiaryContainer,
    };

    return (bgColor, textColor);
}
