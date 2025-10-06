import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/models_directory.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/service_provider.dart';
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
  StreamSubscription<FileSystemEvent>? _fsSub;

  final LlamaServerManager serverManager = serviceProvider
      .get<LlamaServerManager>();

  @override
  void initState() {
    super.initState();
    _loadModels();
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
  void dispose() {
    _fsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = Theme.of(context).colorScheme.secondaryContainer;

    if (_loading) {
      return const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Loading models…'),
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
                    items: _models.keys.map((alias) {
                      return DropdownMenuItem(
                        value: alias,
                        child: Text(alias, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == null || !_models.containsKey(v)) return;
                      final file = _models[v]!;

                      showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => ModelConfiguration(
                          onConfirm:
                              ({
                                required int ctx,
                                required int threads,
                                required int? gpuLayers,
                              }) async {
                                setState(() {
                                  _selected = v;
                                  _loading = true;
                                });

                                await serverManager.start(
                                  modelPath: file.path,
                                  modelName: v,
                                  nCtx: ctx,
                                  nThreads: threads,
                                  nGpuLayers: gpuLayers ?? 999,
                                );

                                setState(() {
                                  _loading = false;
                                });
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
