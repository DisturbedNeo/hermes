enum DiagnosticsVisibility { off, compact, detailed }

extension DiagnosticsVisibilityLabel on DiagnosticsVisibility {
  String get label => switch (this) {
    DiagnosticsVisibility.off => 'Off',
    DiagnosticsVisibility.compact => 'Compact',
    DiagnosticsVisibility.detailed => 'Detailed',
  };

  static DiagnosticsVisibility fromName(String? name) {
    return DiagnosticsVisibility.values.firstWhere(
      (v) => v.name == name,
      orElse: () => DiagnosticsVisibility.off,
    );
  }
}
