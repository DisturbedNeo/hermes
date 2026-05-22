/// Centralised constants for all SharedPreferences key names.
///
/// Keeping keys in one place prevents typos and makes it easy to audit every
/// preference used by the application.
abstract final class PreferencesKeys {
  PreferencesKeys._();

  /// Path to the application's data directory (SQLite database location).
  static const String dataLocation = 'data_location_path';

  /// Whether dark mode is enabled.
  static const String darkMode = 'is_dark_mode';

  /// Currently selected theme ID.
  static const String themeId = 'theme_id';

  /// Directory containing Llama.cpp binaries.
  static const String llamaCppDirectory = 'llama_cpp_directory';

  /// Directory containing model files.
  static const String modelsDirectory = 'models_directory';

  /// Visibility level for diagnostics overlays.
  static const String diagnosticsVisibility = 'diagnostics_visibility';

  /// Prefix for world overview tab index keys (suffix is the world ID).
  static const String worldOverviewTabPrefix = 'last_tab_index_';

  // ── Context compaction settings ───────────────────────────────────────

  /// Whether context compaction is enabled.
  static const String contextCompactionEnabled = 'context_compaction_enabled';

  /// Trigger threshold for compaction (fraction of context window).
  static const String contextCompactionTrigger =
      'context_compaction_trigger_threshold';

  /// Hard limit threshold — force truncation at this fraction.
  static const String contextCompactionHardLimit =
      'context_compaction_hard_limit_threshold';

  /// Number of recent messages to retain after compaction.
  static const String contextCompactionRecentWindow =
      'context_compaction_recent_window_units';

  /// Whether emergency payload truncation is allowed.
  static const String contextCompactionEmergencyTruncation =
      'context_compaction_emergency_truncation';

  // ── Job system settings ───────────────────────────────────────────────

  /// Whether the job system is enabled.
  static const String jobSystemEnabled = 'job_system_enabled';

  /// Whether to require approval before file edits by jobs.
  static const String jobSystemApprovalBeforeFileEdits =
      'job_system_approval_before_file_edits';

  /// Whether to show job messages in the chat stream.
  static const String jobSystemShowMessagesInChat =
      'job_system_show_messages_in_chat';
}
