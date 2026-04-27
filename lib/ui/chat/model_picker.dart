import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/models_directory.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/ui/chat/message/dot_pulse.dart';
import 'package:hermes/ui/model_configuration/model_configuration.dart';

class ModelPicker extends StatefulWidget {
  const ModelPicker({super.key});

  @override
  State<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<ModelPicker> {
  Map<String, File> _models = {};
  String? _selected;

  bool _loading = true;
  String? _error;

  final _chatService = serviceProvider.get<ChatService>();
  final _preferencesService = serviceProvider.get<PreferencesService>();

  @override
  void initState() {
    super.initState();
    _chatService.addListener(_syncSelectedFromActiveModel);
    _chatService.serverManager.handle.addListener(_syncSelectedFromActiveModel);
    _syncSelectedFromActiveModel();
    _loadModels();
  }

  @override
  void dispose() {
    _chatService.removeListener(_syncSelectedFromActiveModel);
    _chatService.serverManager.handle.removeListener(_syncSelectedFromActiveModel);
    super.dispose();
  }

  void _syncSelectedFromActiveModel() {
    final activeModel = _chatService.serverManager.currentModelName;
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
      final models = await getModels();
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
      return Row(
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
      );
    }

    if (_error != null) {
      return Row(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 8),
          Expanded(child: Text('Failed to load models: $_error')),
          TextButton(onPressed: _loadModels, child: const Text('Retry')),
        ],
      );
    }

    final aliases = _models.keys.toList()..sort((a, b) => a.compareTo(b));
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
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selected,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    dropdownColor: bgColor,
                    items: aliases.map((alias) {
                      final modelIsAvailable = _models.containsKey(alias);
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
                      if (v == null || !_models.containsKey(v)) return;
                      final file = _models[v]!;
                      final llamaCppDirectory =
                          await _preferencesService.getLlamaCppDirectory() ??
                          '';
                      if (!context.mounted) return;

                      showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => ModelConfiguration(
                          modelName: v,
                          modelPath: file.path,
                          llamaCppDirectory: llamaCppDirectory,
                          onCancel: _chatService.serverManager.stop,
                          onConfirm: (snapshot) async {
                            setState(() {
                              _selected = v;
                              _loading = true;
                              _error = null;
                            });

                            try {
                              await _chatService.serverManager
                                  .startWithSnapshot(snapshot);
                              _chatService.setCurrentModelSnapshot(snapshot);
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => _selected = _chatService
                                      .serverManager
                                      .currentModelName,
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
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loadModels,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}
