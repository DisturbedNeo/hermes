import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hermes/features/chat/presentation/a11y.dart';
import 'package:hermes/features/model/application/model_load_configuration.dart';
import 'package:hermes/features/chat/application/chat_workspace_controller.dart';
import 'package:hermes/features/settings/application/preferences_port.dart';
import 'package:hermes/features/model/application/model_catalog.dart';
import 'package:hermes/features/chat/presentation/chat/message/dot_pulse.dart';
import 'package:hermes/features/chat/presentation/model_configuration/model_configuration.dart';

enum ModelConfigurationSaveOutcome { notRequested, saved, failed }

@visibleForTesting
Future<ModelConfigurationSaveOutcome> startModelAndMaybeSaveConfiguration({
  required Future<void> Function() startModel,
  required VoidCallback onModelStarted,
  required bool saveAsDefault,
  required Future<bool> Function() saveConfiguration,
}) async {
  await startModel();
  onModelStarted();
  if (!saveAsDefault) return ModelConfigurationSaveOutcome.notRequested;

  return await saveConfiguration()
      ? ModelConfigurationSaveOutcome.saved
      : ModelConfigurationSaveOutcome.failed;
}

class ModelPicker extends StatefulWidget {
  const ModelPicker({
    super.key,
    required this.tabs,
    required this.preferencesService,
    required this.modelCatalog,
  });

  final ChatWorkspaceController tabs;
  final ModelPickerPreferencesPort preferencesService;
  final ModelCatalogPort modelCatalog;

  @override
  State<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<ModelPicker> {
  List<ModelDescriptor> _models = const [];
  String? _selected;

  bool _loading = true;
  String? _error;

  ChatWorkspaceController get _tabs => widget.tabs;
  ModelPickerPreferencesPort get _preferencesService =>
      widget.preferencesService;
  ModelCatalogPort get _modelCatalog => widget.modelCatalog;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_syncSelectedFromActiveModel);
    _tabs.serverManager.session.addListener(_syncSelectedFromActiveModel);
    _syncSelectedFromActiveModel();
    _loadModels();
  }

  @override
  void dispose() {
    _tabs.removeListener(_syncSelectedFromActiveModel);
    _tabs.serverManager.session.removeListener(_syncSelectedFromActiveModel);
    super.dispose();
  }

  void _syncSelectedFromActiveModel() {
    final activeModel = _tabs.serverManager.session.value.modelName;
    if (_selected == activeModel) return;
    if (!mounted) {
      _selected = activeModel;
      return;
    }
    setState(() => _selected = activeModel);
  }

  Future<void> _loadModels() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await _modelCatalog.listModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    if (_loading) {
      return AccessibleWidget(
        label: 'Loading models',
        value: 'Please wait while models are loaded',
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading…'),
            SizedBox(width: 8),
            SizedBox(
              width: 10,
              height: 10,
              child: DotPulse(color: bgColor.withValues(alpha: 0.25)),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return AccessibleWidget(
        label: 'Failed to load models',
        value: 'Error: $_error. Tap Retry to attempt loading again.',
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to load models: $_error')),
            AccessibleWidget(
              label: 'Retry loading models',
              isButton: true,
              child: TextButton(
                onPressed: _loadModels,
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      );
    }

    final byAlias = {for (final model in _models) model.alias: model};
    final aliases = byAlias.keys.toList()..sort((a, b) => a.compareTo(b));
    final selected = _selected;
    if (selected != null && !aliases.contains(selected)) {
      aliases.insert(0, selected);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 280),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Material(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
                child: AccessibleWidget(
                  label: _selected != null
                      ? 'Model: $_selected'
                      : 'Select a model',

                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selected,
                      hint: const Text('Select a model...'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      dropdownColor: bgColor,
                      items: aliases.map((alias) {
                        final modelIsAvailable = byAlias.containsKey(alias);
                        return DropdownMenuItem(
                          value: alias,
                          enabled: modelIsAvailable,
                          child: Text(
                            modelIsAvailable ? alias : '$alias (loaded)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) async {
                        if (v == null || !byAlias.containsKey(v)) return;
                        final model = byAlias[v]!;
                        final llamaCppDirectory =
                            await _preferencesService.getLlamaCppDirectory() ??
                            '';
                        final savedConfiguration = await _preferencesService
                            .getModelLoadConfiguration(v);
                        if (!context.mounted) return;

                        showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => ModelConfiguration(
                            modelName: v,
                            maxThreads: _modelCatalog.defaultThreadCount,
                            initialConfiguration:
                                savedConfiguration ??
                                ModelLoadConfiguration.defaults(
                                  nThreads: _modelCatalog.defaultThreadCount,
                                ),
                            hasSavedConfiguration: savedConfiguration != null,
                            onResetSavedConfiguration: () => _preferencesService
                                .removeModelLoadConfiguration(v),
                            onCancel: _tabs.serverManager.stop,
                            onConfirm:
                                (
                                  configuration, {
                                  required saveAsDefault,
                                }) async {
                                  final snapshot = configuration.toSnapshot(
                                    modelName: v,
                                    modelPath: model.path,
                                    llamaCppDirectory: llamaCppDirectory,
                                    maxThreads:
                                        _modelCatalog.defaultThreadCount,
                                  );
                                  setState(() {
                                    _selected = v;
                                    _loading = true;
                                    _error = null;
                                  });

                                  try {
                                    final saveOutcome =
                                        await startModelAndMaybeSaveConfiguration(
                                          startModel: () => _tabs.serverManager
                                              .startWithSnapshot(snapshot),
                                          onModelStarted: () => _tabs.activeChat
                                              ?.updateCurrentModelSnapshot(
                                                snapshot,
                                              ),
                                          saveAsDefault: saveAsDefault,
                                          saveConfiguration: () =>
                                              _preferencesService
                                                  .setModelLoadConfiguration(
                                                    v,
                                                    configuration,
                                                  ),
                                        );
                                    if (saveOutcome ==
                                            ModelConfigurationSaveOutcome
                                                .failed &&
                                        context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Model loaded, but its configuration '
                                            'could not be saved',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      setState(
                                        () => _selected = _tabs
                                            .serverManager
                                            .session
                                            .value
                                            .modelName,
                                      );
                                    }

                                    rethrow;
                                  } finally {
                                    if (mounted) {
                                      setState(() => _loading = false);
                                    }
                                  }
                                },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        AccessibleWidget(
          label: 'Refresh model list',
          isButton: true,
          child: IconButton(
            tooltip: 'Refresh',
            onPressed: _loadModels,
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }
}
