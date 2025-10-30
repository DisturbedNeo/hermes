import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hermes/ui/model_configuration/slider_control.dart';

class ModelConfiguration extends StatefulWidget {
  const ModelConfiguration({super.key, required this.onConfirm, this.onCancel});

  final void Function({
    required int ctx,
    required int threads,
    required int? gpuLayers,
    required double temperature,
    required double topP,
    required int topK,
    required int batch,
    required int uBatch,
    required int miroStatMode,
  })
  onConfirm;

  final VoidCallback? onCancel;

  @override
  State<ModelConfiguration> createState() => _ModelConfigurationState();
}

class _ModelConfigurationState extends State<ModelConfiguration> {
  int _ctx = 8;
  int _threads = (Platform.numberOfProcessors * 0.75).ceil();
  int _gpuLayers = 999;
  double _temperature = 0.8;
  double _topP = 0.9;
  int _topK = 40;
  int _batch = 512;
  int _uBatch = 512;
  int _miroStatMode = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Configure Model',
        style: TextStyle(color: Colors.black),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderControl.integer(
              label: 'Context (K)',
              value: _ctx,
              min: 1,
              max: 256,
              step: 1,
              onChanged: (v) => setState(() => _ctx = v.clamp(1, 256)),
            ),
            SliderControl.integer(
              label: 'Threads',
              value: _threads,
              min: 1,
              max: Platform.numberOfProcessors,
              step: 1,
              onChanged: (v) => setState(
                () => _threads = v.clamp(1, Platform.numberOfProcessors),
              ),
            ),
            SliderControl.integer(
              label: 'GPU Layers',
              value: _gpuLayers,
              min: 0,
              max: 999,
              step: 1,
              onChanged: (v) => setState(() => _gpuLayers = v),
            ),
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
              step: 0.1,
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
            SliderControl.integer(
              label: 'Batch',
              value: _batch,
              min: 32,
              max: 1024,
              step: 32,
              onChanged: (v) => setState(() => _batch = v),
            ),
            SliderControl.integer(
              label: 'uBatch',
              value: _uBatch,
              min: 16,
              max: 256,
              step: 16,
              onChanged: (v) => setState(() => _uBatch = v),
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
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onCancel?.call();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onConfirm(
              ctx: _ctx * 1024,
              threads: _threads,
              gpuLayers: _gpuLayers,
              temperature: _temperature,
              topP: _topP,
              topK: _topK,
              batch: _batch,
              uBatch: _uBatch,
              miroStatMode: _miroStatMode,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
