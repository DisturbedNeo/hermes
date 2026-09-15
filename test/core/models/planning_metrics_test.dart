import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/serialization/model_json.dart';

void main() {
  test('round-trips rollout metrics and derives rates', () {
    final started = DateTime(2026, 9, 12, 10, 0);
    final metrics = PlanningMetrics(
      planningCalls: 4,
      promptTokenEstimate: 1200,
      toolResultTokenEstimate: 340,
      planningCommandCount: 10,
      invalidCommandCount: 2,
      fullPlanRepairCount: 1,
      validationBlockerCount: 1,
      recoveryAttempts: 2,
      recoverySuccesses: 1,
      planningStartedAt: started,
      timeToFirstExecutableMs: 850,
    );

    final decoded = ModelJson.decode<PlanningMetrics>(
      ModelJson.encode(metrics),
    );

    expect(decoded.planningCalls, 4);
    expect(decoded.promptTokenEstimate, 1200);
    expect(decoded.invalidCommandRate, closeTo(0.2, 0.0001));
    expect(decoded.fullPlanRepairRate, closeTo(0.25, 0.0001));
    expect(decoded.recoverySuccessRate, closeTo(0.5, 0.0001));
    expect(decoded.timeToFirstExecutableMs, 850);
    expect(decoded.planningStartedAt, started);
  });
}
