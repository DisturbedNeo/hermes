import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/core/enums/diagnostics_visibility.dart';
import 'package:hermes/core/models/model_session_diagnostics.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';

class DiagnosticsBar extends StatefulWidget {
  const DiagnosticsBar({super.key});

  @override
  State<DiagnosticsBar> createState() => _DiagnosticsBarState();
}

class _DiagnosticsBarState extends State<DiagnosticsBar> {
  final _tabs = serviceProvider.get<ChatTabsService>();
  final _preferences = serviceProvider.get<PreferencesService>();

  DiagnosticsVisibility _visibility = DiagnosticsVisibility.off;

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_loadVisibility);
    _loadVisibility();
  }

  @override
  void dispose() {
    _preferences.removeListener(_loadVisibility);
    super.dispose();
  }

  Future<void> _loadVisibility() async {
    final visibility = await _preferences.getDiagnosticsVisibility();
    if (!mounted || visibility == _visibility) return;
    setState(() => _visibility = visibility);
  }

  @override
  Widget build(BuildContext context) {
    if (_visibility == DiagnosticsVisibility.off) {
      return const SizedBox.shrink();
    }

    final diagnostics = _tabs.serverManager.diagnostics;
    return AnimatedBuilder(
      animation: diagnostics,
      builder: (context, _) {
        return _DiagnosticsBand(
          diagnostics: diagnostics,
          visibility: _visibility,
        );
      },
    );
  }
}

class _DiagnosticsBand extends StatelessWidget {
  const _DiagnosticsBand({required this.diagnostics, required this.visibility});

  final ModelSessionDiagnostics diagnostics;
  final DiagnosticsVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.65);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _scrollingMetrics(context, _compactMetrics(context)),
          if (visibility == DiagnosticsVisibility.detailed) ...[
            _scrollingMetrics(context, _detailedMetrics(context)),
            _LogViewer(diagnostics: diagnostics),
          ],
        ],
      ),
    );
  }

  List<Widget> _compactMetrics(BuildContext context) {
    return [
      _metric(
        context,
        diagnostics.state.icon,
        'Status',
        diagnostics.state.label,
        color: diagnostics.state.color(Theme.of(context).colorScheme),
      ),
      _metric(
        context,
        Icons.memory_outlined,
        'Model',
        diagnostics.modelSnapshot?.modelName ?? 'No model',
      ),
      _metric(context, Icons.speed_outlined, 'Speed', _speedText()),
      _metric(context, Icons.data_usage_outlined, 'Context', _contextText()),
      if (diagnostics.lastError != null)
        _metric(
          context,
          Icons.warning_amber_outlined,
          'Issue',
          'Last error',
          color: Theme.of(context).colorScheme.error,
          tooltip: diagnostics.lastError,
        ),
    ];
  }

  List<Widget> _detailedMetrics(BuildContext context) {
    final snapshot = diagnostics.modelSnapshot;

    return [
      _metric(
        context,
        Icons.crop_free_outlined,
        'Ctx',
        snapshot == null ? 'n/a' : _formatInt(snapshot.nCtx),
      ),
      _metric(
        context,
        Icons.settings_ethernet_outlined,
        'Threads',
        snapshot == null ? 'n/a' : '${snapshot.nThreads}',
      ),
      _metric(
        context,
        Icons.developer_board_outlined,
        'GPU layers',
        snapshot == null ? 'n/a' : '${snapshot.nGpuLayers}',
      ),
      _metric(
        context,
        Icons.view_module_outlined,
        'Batch',
        snapshot == null ? 'n/a' : '${snapshot.nBatch}/${snapshot.nUBatch}',
      ),
      _metric(
        context,
        Icons.folder_outlined,
        'llama.cpp',
        diagnostics.executablePath == null ? 'Not resolved' : 'Resolved',
        tooltip: diagnostics.executablePath,
      ),
      _metric(
        context,
        Icons.link_outlined,
        'Server',
        diagnostics.baseUrl ?? 'n/a',
      ),
      _metric(
        context,
        Icons.timer_outlined,
        'Startup',
        _durationText(diagnostics.startupDuration),
      ),
    ];
  }

  Widget _scrollingMetrics(BuildContext context, List<Widget> children) {
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: children),
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    Color? color,
    String? tooltip,
  }) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;
    final text = Text(
      '$label: $value',
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(color: effectiveColor),
    );

    final child = Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: effectiveColor),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: text,
          ),
        ],
      ),
    );

    if (tooltip == null || tooltip.isEmpty) return child;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: child,
    );
  }

  String _speedText() {
    final speed = diagnostics.streamTokensPerSecond;
    if (speed == null) return diagnostics.isStreaming ? 'Starting' : 'Idle';

    final rate = '${speed.toStringAsFixed(1)} t/s est.';
    return diagnostics.isStreaming ? rate : 'last $rate';
  }

  String _contextText() {
    final snapshot = diagnostics.modelSnapshot;
    if (snapshot == null) return 'n/a';

    final estimate = diagnostics.estimatedContextTokens;
    if (estimate == null) return _formatInt(snapshot.nCtx);

    return 'est. ${_formatInt(estimate)} / ${_formatInt(snapshot.nCtx)}';
  }

  String _durationText(Duration? duration) {
    if (duration == null) {
      return diagnostics.state == ModelServerState.starting
          ? 'Starting'
          : 'n/a';
    }

    final seconds = duration.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }

  String _formatInt(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final fromEnd = text.length - i;
      buffer.write(text[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write(',');
    }
    return buffer.toString();
  }
}

class _LogViewer extends StatelessWidget {
  const _LogViewer({required this.diagnostics});

  final ModelSessionDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final logs = diagnostics.logs;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Text(
          'Server logs (${logs.length})',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        children: [
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy all'),
                onPressed: logs.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: _formatLogs(logs)),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Diagnostics copied')),
                        );
                      },
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear view'),
                onPressed: logs.isEmpty ? null : diagnostics.clearLogs,
              ),
            ],
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.65),
              ),
            ),
            child: logs.isEmpty
                ? Text(
                    'No server logs captured.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      _formatLogs(logs),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.25,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatLogs(List<ModelSessionLogEntry> logs) {
    return logs
        .map(
          (entry) =>
              '${_time(entry.timestamp)} ${entry.source.padRight(9)} ${entry.message}',
        )
        .join('\n');
  }

  String _time(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

extension on ModelServerState {
  String get label => switch (this) {
    ModelServerState.stopped => 'Stopped',
    ModelServerState.starting => 'Starting',
    ModelServerState.ready => 'Ready',
    ModelServerState.failed => 'Failed',
    ModelServerState.cancelled => 'Cancelled',
  };

  IconData get icon => switch (this) {
    ModelServerState.stopped => Icons.power_settings_new,
    ModelServerState.starting => Icons.sync,
    ModelServerState.ready => Icons.check_circle_outline,
    ModelServerState.failed => Icons.error_outline,
    ModelServerState.cancelled => Icons.cancel_outlined,
  };

  Color color(ColorScheme scheme) => switch (this) {
    ModelServerState.ready => scheme.primary,
    ModelServerState.failed => scheme.error,
    ModelServerState.cancelled => scheme.error,
    ModelServerState.starting => scheme.tertiary,
    ModelServerState.stopped => scheme.onSurfaceVariant,
  };
}
