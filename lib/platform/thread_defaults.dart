import 'dart:io';

/// Platform-specific default kept outside the shared value model.
int get defaultModelThreadCount => Platform.numberOfProcessors;
