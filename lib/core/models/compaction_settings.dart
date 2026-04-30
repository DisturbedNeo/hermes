class CompactionSettings {
  final bool enabled;
  final double triggerThreshold;
  final double hardLimitThreshold;
  final int recentWindowUnits;
  final bool allowEmergencyPayloadTruncation;

  const CompactionSettings({
    this.enabled = true,
    this.triggerThreshold = 0.80,
    this.hardLimitThreshold = 0.95,
    this.recentWindowUnits = 6,
    this.allowEmergencyPayloadTruncation = false,
  });

  CompactionSettings copyWith({
    bool? enabled,
    double? triggerThreshold,
    double? hardLimitThreshold,
    int? recentWindowUnits,
    bool? allowEmergencyPayloadTruncation,
  }) {
    return CompactionSettings(
      enabled: enabled ?? this.enabled,
      triggerThreshold: triggerThreshold ?? this.triggerThreshold,
      hardLimitThreshold: hardLimitThreshold ?? this.hardLimitThreshold,
      recentWindowUnits: recentWindowUnits ?? this.recentWindowUnits,
      allowEmergencyPayloadTruncation:
          allowEmergencyPayloadTruncation ??
          this.allowEmergencyPayloadTruncation,
    ).normalised();
  }

  CompactionSettings normalised() {
    final trigger = triggerThreshold.clamp(0.60, 0.90).toDouble();
    final hard = hardLimitThreshold.clamp(trigger, 0.99).toDouble();
    return CompactionSettings(
      enabled: enabled,
      triggerThreshold: trigger,
      hardLimitThreshold: hard,
      recentWindowUnits: recentWindowUnits.clamp(2, 10).toInt(),
      allowEmergencyPayloadTruncation: allowEmergencyPayloadTruncation,
    );
  }
}
