import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/core/enums/diagnostics_visibility.dart';
import 'package:hermes/core/models/model_call_diagnostics.dart';
import 'package:hermes/core/models/model_session_diagnostics.dart';
import 'package:hermes/core/services/preferences_service.dart';

class DiagnosticsBar extends StatefulWidget {
  const DiagnosticsBar({
    super.key,
    required this.diagnostics,
    required this.preferencesService,
  });

  final ModelSessionDiagnostics diagnostics;
  final PreferencesService preferencesService;

  @override
  State<DiagnosticsBar> createState() => _DiagnosticsBarState();
}

class _DiagnosticsBarState extends State<DiagnosticsBar> {
  PreferencesService get _preferences => widget.preferencesService;

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
    widget.diagnostics.setLiveTelemetryEnabled(
      visibility != DiagnosticsVisibility.off,
    );
    if (!mounted || visibility == _visibility) return;
    setState(() => _visibility = visibility);
  }

  @override
  Widget build(BuildContext context) {
    if (_visibility == DiagnosticsVisibility.off) {
      return const SizedBox.shrink();
    }

    final diagnostics = widget.diagnostics;
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

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _scrollingMetrics(context, _compactMetrics(context)),
            if (visibility == DiagnosticsVisibility.detailed) ...[
              for (final row in _detailedRows(context))
                _scrollingMetrics(context, row),
              _LogViewer(diagnostics: diagnostics),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _compactMetrics(BuildContext context) {
    final call = diagnostics.activeCall;
    return [
      _metric(
        context,
        diagnostics.state.icon,
        'Status',
        call == null ? diagnostics.state.label : _activeStatusText(call),
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
      if (diagnostics.compactionActive ||
          diagnostics.lastCompactionMessagesCovered != null)
        _metric(
          context,
          diagnostics.compactionActive
              ? Icons.sync
              : Icons.inventory_2_outlined,
          'Compaction',
          _compactionText(),
          tooltip: diagnostics.lastCompactionStatus,
        ),
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

  List<List<Widget>> _detailedRows(BuildContext context) {
    final snapshot = diagnostics.modelSnapshot;
    final call = diagnostics.displayCall;
    final totals = diagnostics.sessionTotals;
    final properties = diagnostics.serverProperties;

    return [
      [
        _group(context, 'Active / last call'),
        _metric(context, Icons.label_outline, 'Label', call?.label ?? 'n/a'),
        _metric(
          context,
          Icons.pending_outlined,
          'Phase',
          call == null ? 'n/a' : _statusName(call.status),
        ),
        if (diagnostics.activeCallCount > 1)
          _metric(
            context,
            Icons.layers_outlined,
            'Active calls',
            '${diagnostics.activeCallCount}',
          ),
        _metric(
          context,
          Icons.fingerprint,
          'Request ID',
          call?.serverRequestId ?? 'n/a',
          tooltip: call?.serverRequestId,
          selectable: true,
        ),
        _metric(context, Icons.percent, 'Prompt progress', _progressText(call)),
        _metric(context, Icons.input, 'Prompt', _tokenText(call?.promptTokens)),
        _metric(
          context,
          Icons.cached_outlined,
          'Cached',
          _tokenText(call?.cachedPromptTokens),
        ),
        _metric(
          context,
          Icons.memory_outlined,
          'Processed',
          _tokenText(call?.processedPromptTokens),
        ),
        _metric(
          context,
          Icons.output,
          'Generated',
          _tokenText(call?.generatedTokens),
        ),
        _metric(
          context,
          Icons.data_usage_outlined,
          'Context',
          call?.contextTokens == null
              ? 'n/a'
              : '${_formatInt(call!.contextTokens!)} / ${_formatNullableInt(call.contextLimitTokens)}',
        ),
      ],
      [
        _group(context, 'Call timing'),
        _metric(
          context,
          Icons.speed,
          'Prompt speed',
          _rate(call?.promptTokensPerSecond),
        ),
        _metric(
          context,
          Icons.speed_outlined,
          'Generation speed',
          _rate(call?.generationTokensPerSecond),
        ),
        _metric(context, Icons.timer_outlined, 'Prompt', _ms(call?.promptMs)),
        _metric(
          context,
          Icons.timer_outlined,
          'Generation',
          _ms(call?.generationMs),
        ),
        _metric(
          context,
          Icons.first_page,
          'TTFT',
          _durationText(call?.timeToFirstToken),
        ),
        _metric(
          context,
          Icons.timelapse,
          'End to end',
          _durationText(call?.endToEndDuration),
        ),
        _metric(
          context,
          Icons.flag_outlined,
          'Finish',
          call?.finishReason ?? 'n/a',
        ),
        _metric(
          context,
          Icons.auto_awesome_outlined,
          'Speculative',
          _ratio(call?.speculativeAcceptanceRatio),
        ),
        _metric(
          context,
          Icons.verified_outlined,
          'Accuracy',
          call?.accuracy.name ?? 'n/a',
          tooltip: _accuracyTooltip(call?.accuracy),
        ),
        if (call?.error != null)
          _metric(
            context,
            Icons.error_outline,
            'Error',
            call!.error!,
            color: Theme.of(context).colorScheme.error,
            tooltip: call.error,
          ),
      ],
      [
        _group(context, 'Session totals'),
        _metric(
          context,
          Icons.call_made,
          'Calls',
          '${totals.callsStarted} started / ${totals.callsCompleted} completed / ${totals.callsFailed} failed / ${totals.callsCancelled} cancelled',
        ),
        _metric(
          context,
          Icons.input,
          'Prompt',
          _formatInt(totals.promptTokens),
        ),
        _metric(
          context,
          Icons.output,
          'Generated',
          _formatInt(totals.generatedTokens),
        ),
        _metric(
          context,
          Icons.cached_outlined,
          'Cached',
          _formatInt(totals.cachedPromptTokens),
        ),
        _metric(
          context,
          Icons.percent,
          'Cache hit',
          _ratio(totals.cacheHitRatio),
        ),
        _metric(
          context,
          Icons.speed,
          'Prompt speed',
          _rate(totals.promptTokensPerSecond),
        ),
        _metric(
          context,
          Icons.speed_outlined,
          'Generation speed',
          _rate(totals.generationTokensPerSecond),
        ),
        _metric(
          context,
          Icons.first_page,
          'Average TTFT',
          _durationText(totals.averageTimeToFirstToken),
        ),
        _metric(
          context,
          Icons.memory_outlined,
          'Model time',
          _ms(totals.promptMs + totals.generationMs),
        ),
        _metric(
          context,
          Icons.timelapse,
          'End to end',
          _durationText(totals.endToEndDuration),
        ),
        _metric(
          context,
          Icons.auto_awesome_outlined,
          'Speculative',
          '${totals.acceptedDraftTokens}/${totals.draftTokens} (${_ratio(totals.speculativeAcceptanceRatio)})',
        ),
      ],
      [
        _group(context, 'Server / runtime'),
        _metric(
          context,
          Icons.build_outlined,
          'Build',
          properties?.buildInfo ?? call?.systemFingerprint ?? 'n/a',
        ),
        _metric(
          context,
          Icons.link_outlined,
          'Endpoint',
          diagnostics.baseUrl ?? 'n/a',
          selectable: true,
        ),
        _metric(
          context,
          Icons.timer_outlined,
          'Startup',
          _durationText(diagnostics.startupDuration),
        ),
        _metric(
          context,
          Icons.folder_outlined,
          'Executable',
          diagnostics.executablePath ?? 'n/a',
          tooltip: diagnostics.executablePath,
          selectable: true,
        ),
        _metric(
          context,
          Icons.folder_special_outlined,
          'Model path',
          properties?.modelPath ?? snapshot?.modelPath ?? 'n/a',
          tooltip: properties?.modelPath ?? snapshot?.modelPath,
          selectable: true,
        ),
        _metric(
          context,
          Icons.crop_free_outlined,
          'Context',
          '${_formatNullableInt(snapshot?.nCtx)} configured / ${_formatNullableInt(properties?.effectiveContextSize)} effective',
        ),
        _metric(
          context,
          Icons.view_stream_outlined,
          'Slots',
          _formatNullableInt(properties?.totalSlots),
        ),
        _metric(
          context,
          Icons.chat_bubble_outline,
          'Template capabilities',
          _mapText(properties?.chatTemplateCapabilities),
        ),
        _metric(
          context,
          Icons.multitrack_audio_outlined,
          'Modalities',
          _mapText(properties?.modalities),
        ),
      ],
      if (snapshot != null) ...[
        [
          _group(context, 'Configuration · compute'),
          _metric(
            context,
            Icons.settings_ethernet,
            'Threads',
            '${snapshot.nThreads}',
          ),
          _metric(context, Icons.developer_board, 'GPU layers', 'All'),
          _metric(
            context,
            Icons.flash_on,
            'Flash attention',
            _onOff(snapshot.flashAttention),
          ),
        ],
        [
          _group(context, 'Configuration · batching / cache'),
          _metric(
            context,
            Icons.view_module,
            'Batch / microbatch',
            '${snapshot.nBatch} / ${snapshot.nUBatch}',
          ),
          _metric(
            context,
            Icons.cached,
            'Prompt cache',
            _onOff(snapshot.cachePrompt),
          ),
          _metric(
            context,
            Icons.recycling,
            'Cache reuse',
            '${snapshot.cacheReuse}',
          ),
          _metric(
            context,
            Icons.storage,
            'KV quantization',
            _onOff(snapshot.kvCacheQuantizationEnabled),
          ),
          _metric(
            context,
            Icons.storage_outlined,
            'KV K / V',
            '${snapshot.kvCacheTypeK} / ${snapshot.kvCacheTypeV}',
          ),
        ],
        [
          _group(context, 'Configuration · sampling / penalties'),
          _metric(
            context,
            Icons.thermostat,
            'Temperature',
            '${snapshot.temperature}',
          ),
          _metric(
            context,
            Icons.tune,
            'Top P / K / min P',
            '${snapshot.topP} / ${snapshot.topK} / ${snapshot.minP}',
          ),
          _metric(
            context,
            Icons.analytics_outlined,
            'Mirostat',
            '${snapshot.mirostat}',
          ),
          _metric(
            context,
            Icons.repeat,
            'Repeat',
            '${snapshot.repeatPenalty} / ${snapshot.repeatLastN}',
          ),
          _metric(
            context,
            Icons.balance,
            'Presence / frequency',
            '${snapshot.presencePenalty} / ${snapshot.frequencyPenalty}',
          ),
        ],
        [
          _group(context, 'Configuration · reasoning / MTP'),
          _metric(
            context,
            Icons.psychology_outlined,
            'Reasoning',
            '${_onOff(snapshot.thinking)} / ${snapshot.reasoningEffort}',
          ),
          _metric(
            context,
            Icons.auto_awesome,
            'MTP',
            snapshot.mtpEnabled
                ? 'On / ${snapshot.mtpDraftTokens} draft tokens'
                : 'Off',
          ),
        ],
      ],
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
    bool selectable = false,
  }) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;
    final labelText = Text(
      '$label: $value',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(color: effectiveColor),
    );
    final text = selectable ? SelectionArea(child: labelText) : labelText;

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

    final semanticChild = Semantics(
      label: tooltip == null || tooltip.isEmpty
          ? '$label: $value'
          : '$label: $value. $tooltip',
      child: child,
    );
    if (tooltip == null || tooltip.isEmpty) return semanticChild;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: semanticChild,
    );
  }

  Widget _group(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  String _speedText() {
    final active = diagnostics.activeCall;
    if (active?.status == ModelCallStatus.processingPrompt) {
      return _rate(active?.promptTokensPerSecond);
    }
    if (active != null) {
      final exact = active.generationTokensPerSecond;
      if (exact != null) return _rate(exact);
      final estimated = active.estimatedGenerationTokensPerSecond;
      return estimated == null ? 'Starting' : '${_rate(estimated)} est.';
    }
    final speed = diagnostics.lastCall?.generationTokensPerSecond;
    return speed == null ? 'Idle' : 'last ${_rate(speed)}';
  }

  String _contextText() {
    final limit =
        diagnostics.contextLimitTokens ?? diagnostics.modelSnapshot?.nCtx;
    if (limit == null) return 'n/a';

    final used = diagnostics.displayContextTokens;
    if (used == null) return _formatInt(limit);
    final percent = limit <= 0 ? null : used * 100 / limit;
    final prefix = diagnostics.displayContextIsEstimate ? 'est. ' : '';
    return '$prefix${_formatInt(used)} / ${_formatInt(limit)}'
        '${percent == null ? '' : ' (${percent.toStringAsFixed(1)}%)'}';
  }

  String _activeStatusText(ModelCallDiagnostics call) {
    final progress = call.promptProgressFraction;
    final percent = progress == null
        ? ''
        : ' ${(progress * 100).toStringAsFixed(0)}%';
    return '${_statusName(call.status)} · ${call.label}$percent';
  }

  String _statusName(ModelCallStatus status) => switch (status) {
    ModelCallStatus.starting => 'Starting',
    ModelCallStatus.processingPrompt => 'Prefill',
    ModelCallStatus.generating => 'Generating',
    ModelCallStatus.completed => 'Completed',
    ModelCallStatus.failed => 'Failed',
    ModelCallStatus.cancelled => 'Cancelled',
  };

  String _progressText(ModelCallDiagnostics? call) {
    final fraction = call?.promptProgressFraction;
    if (fraction == null) return 'n/a';
    return '${(fraction * 100).toStringAsFixed(1)}%'
        ' (${_formatNullableInt(call?.promptProgressProcessed)} / '
        '${_formatNullableInt(call?.promptProgressTotal)})';
  }

  String _tokenText(int? value) =>
      value == null ? 'n/a' : '${_formatInt(value)} tokens';

  String _formatNullableInt(int? value) =>
      value == null ? 'n/a' : _formatInt(value);

  String _rate(double? value) =>
      value == null ? 'n/a' : '${value.toStringAsFixed(1)} t/s';

  String _ms(double? value) =>
      value == null ? 'n/a' : '${value.toStringAsFixed(1)} ms';

  String _ratio(double? value) =>
      value == null ? 'n/a' : '${(value * 100).toStringAsFixed(1)}%';

  String _onOff(bool value) => value ? 'On' : 'Off';

  String _mapText(Map<String, dynamic>? value) {
    if (value == null || value.isEmpty) return 'n/a';
    return value.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
  }

  String? _accuracyTooltip(TelemetryAccuracy? accuracy) => switch (accuracy) {
    TelemetryAccuracy.exact => 'Reported by llama-server.',
    TelemetryAccuracy.partial =>
      'Exact cumulative server values from an interrupted call.',
    TelemetryAccuracy.estimated =>
      'Fallback estimate because exact server telemetry was unavailable.',
    null => null,
  };

  String _compactionText() {
    if (diagnostics.compactionActive) return 'Compacting context...';

    final messages = diagnostics.lastCompactionMessagesCovered;
    final saved = diagnostics.lastCompactionTokensSaved;
    if (messages == null) return 'n/a';

    final savedText = saved == null
        ? 'tokens saved n/a'
        : '${_formatInt(saved)} tokens saved';
    return '$messages messages, $savedText';
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
