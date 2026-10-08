/// The kind of bounded project-planning pass being performed.
enum ProjectPlanningPass { bootstrap, maintenance, graphMaintenance, split }

/// The model-facing tool surface for one planning pass.
enum ProjectPlanningToolProfile {
  bootstrap,
  maintenance,
  graphMaintenance,
  split,
}

/// Runtime limits applied to one project-planning transaction.
///
/// These limits bound the amount of new plan state a model can introduce in a
/// single pass. They intentionally do not impose a time or token limit on the
/// model: a pass may still reason for as long as the caller allows, but its
/// committed result remains a small, recoverable frontier.
class ProjectPlanningLimits {
  const ProjectPlanningLimits({
    required this.maxNewTasks,
    this.minNewTasks = 0,
    this.requireExecutableSlice = false,
    this.requireActiveMilestone = false,
  }) : assert(maxNewTasks >= 0),
       assert(minNewTasks >= 0),
       assert(minNewTasks <= maxNewTasks);

  static const bootstrap = ProjectPlanningLimits(
    maxNewTasks: 3,
    requireExecutableSlice: true,
    requireActiveMilestone: true,
  );

  static const maintenance = ProjectPlanningLimits(maxNewTasks: 3);

  static const graphMaintenance = ProjectPlanningLimits(maxNewTasks: 0);

  static const split = ProjectPlanningLimits(maxNewTasks: 3, minNewTasks: 2);

  final int maxNewTasks;
  final int minNewTasks;
  final bool requireExecutableSlice;
  final bool requireActiveMilestone;
}
