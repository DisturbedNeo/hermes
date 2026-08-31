import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/model_load_configuration.dart';
import 'package:hermes/ui/model_configuration/slider_control.dart';

typedef ModelConfigurationConfirm =
    Future<void> Function(
      ModelLoadConfiguration configuration, {
      required bool saveAsDefault,
    });

typedef ModelConfigurationReset = Future<bool> Function();

class ModelConfiguration extends StatefulWidget {
  const ModelConfiguration({
    super.key,
    required this.modelName,
    required this.initialConfiguration,
    required this.hasSavedConfiguration,
    required this.onConfirm,
    required this.onResetSavedConfiguration,
    this.onCancel,
  });

  final String modelName;
  final ModelLoadConfiguration initialConfiguration;
  final bool hasSavedConfiguration;

  final ModelConfigurationConfirm onConfirm;
  final ModelConfigurationReset onResetSavedConfiguration;

  final FutureOr<void> Function()? onCancel;

  @override
  State<ModelConfiguration> createState() => _ModelConfigurationState();
}

class _ModelConfigurationState extends State<ModelConfiguration> {
  static const double _dialogWidthFraction = 0.5;
  static const double _dialogMinWidth = 480;
  static const double _dialogMaxWidth = 760;
  static const double _dialogHorizontalInset = 40;
  static const String _reasoningOff = 'off';
  static const Map<String, String> _reasoningLabels = {
    _reasoningOff: 'Off',
    'default': 'Default',
    'minimal': 'Minimal',
    'low': 'Low',
    'medium': 'Medium',
    'high': 'High',
    'xhigh': 'X-high',
    'max': 'Max',
  };

  late int _ctx;
  late int _threads;
  late double _temperature;
  late double _topP;
  late int _topK;
  late double _minP;
  late int _batch;
  late int _uBatch;
  late int _miroStatMode;
  late double _repeatPenalty;
  late int _repeatLastN;
  late double _presencePenalty;
  late double _frequencyPenalty;
  late String _reasoningMode;
  late bool _mtpEnabled;
  late final TextEditingController _mtpModelPathController;
  late final ScrollController _mtpModelPathScrollController;
  late int _mtpDraftTokens;
  late bool _flashAttention;
  late bool _cachePrompt;
  late int _cacheReuse;
  late bool _kvCacheQuantizationEnabled;
  late String _kvCacheTypeK;
  late String _kvCacheTypeV;
  late bool _hasSavedConfiguration;
  bool _submitting = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _mtpModelPathController = TextEditingController();
    _mtpModelPathScrollController = ScrollController(keepScrollOffset: false);
    _hasSavedConfiguration = widget.hasSavedConfiguration;
    _applyConfiguration(widget.initialConfiguration);
  }

  @override
  void dispose() {
    _mtpModelPathController.dispose();
    _mtpModelPathScrollController.dispose();
    super.dispose();
  }

  void _applyConfiguration(ModelLoadConfiguration configuration) {
    final config = configuration.normalised();
    _ctx = config.nCtx ~/ 1024;
    _threads = config.nThreads;
    _temperature = config.temperature;
    _topP = config.topP;
    _topK = config.topK;
    _minP = config.minP;
    _batch = config.nBatch;
    _uBatch = config.nUBatch;
    _miroStatMode = config.mirostat;
    _repeatPenalty = config.repeatPenalty;
    _repeatLastN = config.repeatLastN;
    _presencePenalty = config.presencePenalty;
    _frequencyPenalty = config.frequencyPenalty;
    _reasoningMode = config.thinking ? config.reasoningEffort : _reasoningOff;
    _mtpEnabled = config.mtpEnabled;
    _mtpModelPathController.text = config.mtpModelPath ?? '';
    _mtpDraftTokens = config.mtpDraftTokens;
    _flashAttention = config.flashAttention;
    _cachePrompt = config.cachePrompt;
    _cacheReuse = config.cacheReuse;
    _kvCacheQuantizationEnabled = config.kvCacheQuantizationEnabled;
    _kvCacheTypeK = config.kvCacheTypeK;
    _kvCacheTypeV = config.kvCacheTypeV;
  }

  ModelLoadConfiguration get _configuration => ModelLoadConfiguration(
    nCtx: _ctx * 1024,
    nThreads: _threads,
    temperature: _temperature,
    topP: _topP,
    topK: _topK,
    minP: _minP,
    nBatch: _batch,
    nUBatch: _uBatch,
    mirostat: _miroStatMode,
    repeatPenalty: _repeatPenalty,
    repeatLastN: _repeatLastN,
    presencePenalty: _presencePenalty,
    frequencyPenalty: _frequencyPenalty,
    thinking: _reasoningMode != _reasoningOff,
    reasoningEffort: _reasoningMode == _reasoningOff
        ? ModelLoadConfiguration.defaultReasoningEffort
        : _reasoningMode,
    mtpEnabled: _mtpEnabled,
    mtpModelPath: ModelConfigurationSnapshot.normaliseOptionalModelPath(
      _mtpModelPathController.text,
    ),
    mtpDraftTokens: _mtpDraftTokens,
    flashAttention: _flashAttention,
    cachePrompt: _cachePrompt,
    cacheReuse: _cacheReuse,
    kvCacheQuantizationEnabled: _kvCacheQuantizationEnabled,
    kvCacheTypeK: _kvCacheTypeK,
    kvCacheTypeV: _kvCacheTypeV,
  );

  Future<void> _confirm({required bool saveAsDefault}) async {
    if (_submitting || _resetting) return;

    setState(() => _submitting = true);

    try {
      await widget.onConfirm(_configuration, saveAsDefault: saveAsDefault);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start model: $e')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _resetToDefaults() async {
    if (_submitting || _resetting) return;

    setState(() => _resetting = true);
    bool removed;
    try {
      removed = await widget.onResetSavedConfiguration();
    } catch (_) {
      removed = false;
    }
    if (!mounted) return;

    if (!removed) {
      setState(() => _resetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to reset saved configuration')),
      );
      return;
    }

    setState(() {
      _applyConfiguration(ModelLoadConfiguration.defaults());
      _hasSavedConfiguration = false;
      _resetting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved configuration removed')),
    );
  }

  Future<void> _selectMtpModelFile() async {
    const typeGroup = XTypeGroup(
      label: 'GGUF models',
      extensions: <String>['gguf'],
    );
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      confirmButtonText: 'Select MTP model',
    );
    if (file == null || !mounted) return;

    _mtpModelPathController.text = file.path;
  }

  void _cancel() {
    final onCancel = widget.onCancel;

    if (_submitting && onCancel != null) {
      unawaited(Future<void>.sync(onCancel));
    }

    Navigator.of(context).pop();
  }

  double _dialogWidth(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final availableWidth = math.max(
      0.0,
      viewportWidth - (_dialogHorizontalInset * 2),
    );
    if (availableWidth <= _dialogMinWidth) {
      return availableWidth;
    }

    final maxWidth = math.min(_dialogMaxWidth, availableWidth);
    final preferredWidth = availableWidth * _dialogWidthFraction;
    return preferredWidth.clamp(_dialogMinWidth, maxWidth).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = _dialogWidth(context);

    return AlertDialog(
      constraints: BoxConstraints.tightFor(width: dialogWidth),
      title: const Text(
        'Configure Model',
        style: TextStyle(color: Colors.black),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _hasSavedConfiguration
                  ? 'Saved configuration loaded for ${widget.modelName}'
                  : 'Using default configuration for ${widget.modelName}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _ConfigurationSection(
              title: 'Core',
              subtitle: 'Most-used startup choices',
              icon: Icons.tune,
              initiallyExpanded: true,
              children: [
                SliderControl.integer(
                  label: 'Context (K)',
                  value: _ctx,
                  min: 1,
                  max: 2048,
                  step: 1,
                  onChanged: (v) => setState(() => _ctx = v),
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('reasoning-mode'),
                  initialValue: _reasoningMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reasoning',
                    helperText: 'Controls thinking and model reasoning effort',
                    border: OutlineInputBorder(),
                  ),
                  items: _reasoningLabels.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (mode) {
                    if (mode == null) return;
                    setState(() => _reasoningMode = mode);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ConfigurationSection(
              title: 'Performance',
              subtitle: 'CPU, GPU, and batching',
              icon: Icons.memory,
              children: [
                SliderControl.integer(
                  label: 'Threads',
                  value: _threads,
                  min: 1,
                  max: Platform.numberOfProcessors,
                  step: 1,
                  onChanged: (v) => setState(() => _threads = v),
                ),
                SliderControl.integer(
                  label: 'Batch',
                  value: _batch,
                  min: 256,
                  max: 8192,
                  step: 256,
                  onChanged: (v) => setState(() => _batch = v),
                ),
                SliderControl.integer(
                  label: 'uBatch',
                  value: _uBatch,
                  min: 256,
                  max: 8192,
                  step: 256,
                  onChanged: (v) => setState(() => _uBatch = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Flash Attention'),
                  value: _flashAttention,
                  onChanged: (v) => setState(() => _flashAttention = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('MTP speculative decoding'),
                  subtitle: const Text(
                    'Uses compatible MTP/NextN weights from the main GGUF or '
                    'a sidecar',
                  ),
                  value: _mtpEnabled,
                  onChanged: (v) => setState(() => _mtpEnabled = v),
                ),
                if (_mtpEnabled) ...[
                  TextFormField(
                    key: const ValueKey('mtp-model-path'),
                    controller: _mtpModelPathController,
                    scrollController: _mtpModelPathScrollController,
                    decoration: InputDecoration(
                      labelText: 'MTP model file (optional)',
                      helperText:
                          'Leave blank to use weights bundled in the main GGUF',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Select MTP model file',
                        onPressed: _selectMtpModelFile,
                        icon: const Icon(Icons.folder_open),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SliderControl.integer(
                    key: const PageStorageKey<String>('mtp-draft-tokens'),
                    label: 'Draft tokens',
                    value: _mtpDraftTokens,
                    min: ModelConfigurationSnapshot.minMtpDraftTokens,
                    max: ModelConfigurationSnapshot.maxMtpDraftTokens,
                    step: 1,
                    onChanged: (v) => setState(() => _mtpDraftTokens = v),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            _ConfigurationSection(
              title: 'Sampling',
              subtitle: 'Token selection behavior',
              icon: Icons.scatter_plot_outlined,
              children: [
                SliderControl.decimal(
                  label: 'Temperature',
                  value: _temperature,
                  min: 0.0,
                  max: 1.5,
                  step: 0.1,
                  onChanged: (v) => setState(() => _temperature = v),
                ),
                SliderControl.decimal(
                  label: 'Top P',
                  value: _topP,
                  min: 0.1,
                  max: 1.0,
                  step: 0.05,
                  onChanged: (v) => setState(() => _topP = v),
                ),
                SliderControl.integer(
                  label: 'Top K',
                  value: _topK,
                  min: 0,
                  max: 100,
                  step: 1,
                  onChanged: (v) => setState(() => _topK = v),
                ),
                SliderControl.decimal(
                  label: 'Min P',
                  value: _minP,
                  min: 0.0,
                  max: 1.0,
                  step: 0.05,
                  onChanged: (v) => setState(() => _minP = v),
                ),
                SliderControl.integer(
                  label: 'Mirostat',
                  value: _miroStatMode,
                  min: 0,
                  max: 2,
                  step: 1,
                  onChanged: (v) => setState(() => _miroStatMode = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ConfigurationSection(
              title: 'Repetition',
              subtitle: 'Penalties and repeat window',
              icon: Icons.repeat,
              children: [
                SliderControl.decimal(
                  label: 'Repeat Penalty',
                  value: _repeatPenalty,
                  min: 0.5,
                  max: 2.0,
                  step: 0.05,
                  onChanged: (v) =>
                      setState(() => _repeatPenalty = v.toDouble()),
                ),
                SliderControl.integer(
                  label: 'Repeat Last N',
                  value: _repeatLastN,
                  min: 0,
                  max: 2048,
                  step: 16,
                  onChanged: (v) => setState(() => _repeatLastN = v),
                ),
                SliderControl.decimal(
                  label: 'Presence Penalty',
                  value: _presencePenalty,
                  min: -2.0,
                  max: 2.0,
                  step: 0.1,
                  onChanged: (v) =>
                      setState(() => _presencePenalty = v.toDouble()),
                ),
                SliderControl.decimal(
                  label: 'Frequency Penalty',
                  value: _frequencyPenalty,
                  min: -2.0,
                  max: 2.0,
                  step: 0.1,
                  onChanged: (v) =>
                      setState(() => _frequencyPenalty = v.toDouble()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ConfigurationSection(
              title: 'Cache',
              subtitle: 'Prompt reuse and KV cache format',
              icon: Icons.storage_outlined,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cache Prompt'),
                  value: _cachePrompt,
                  onChanged: (v) => setState(() => _cachePrompt = v),
                ),
                if (_cachePrompt) ...[
                  SliderControl.integer(
                    label: 'Cache Reuse',
                    value: _cacheReuse,
                    min: ModelConfigurationSnapshot.minCacheReuse,
                    max: ModelConfigurationSnapshot.maxCacheReuse,
                    step: 1,
                    onChanged: (v) => setState(() => _cacheReuse = v),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Quantise KV Cache'),
                  value: _kvCacheQuantizationEnabled,
                  onChanged: (v) =>
                      setState(() => _kvCacheQuantizationEnabled = v),
                ),
                if (_kvCacheQuantizationEnabled) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _kvCacheTypeK,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'K cache type',
                      border: OutlineInputBorder(),
                    ),
                    items: ModelConfigurationSnapshot.allowedKvCacheTypes.map((
                      type,
                    ) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (type) {
                      if (type == null) return;
                      setState(() => _kvCacheTypeK = type);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _kvCacheTypeV,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'V cache type',
                      border: OutlineInputBorder(),
                    ),
                    items: ModelConfigurationSnapshot.allowedKvCacheTypes.map((
                      type,
                    ) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (type) {
                      if (type == null) return;
                      setState(() => _kvCacheTypeV = type);
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (_hasSavedConfiguration)
          TextButton(
            onPressed: _submitting || _resetting ? null : _resetToDefaults,
            child: _resetting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Reset to defaults'),
          ),
        TextButton(
          onPressed: _submitting || _resetting ? null : _cancel,
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: _submitting || _resetting
              ? null
              : () => _confirm(saveAsDefault: false),
          child: const Text('Load model'),
        ),
        FilledButton(
          onPressed: _submitting || _resetting
              ? null
              : () => _confirm(saveAsDefault: true),
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save & load'),
        ),
      ],
    );
  }
}

class _ConfigurationSection extends StatelessWidget {
  const _ConfigurationSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey<String>('model-configuration-$title'),
            initiallyExpanded: initiallyExpanded,
            maintainState: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: Icon(icon, color: scheme.primary),
            title: Text(title, style: theme.textTheme.titleMedium),
            subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            collapsedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            children: [
              const SizedBox(height: 4),
              for (final child in children) ...[
                child,
                if (child != children.last) const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
