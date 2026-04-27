import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/ui/model_configuration/slider_control.dart';

typedef ModelConfigurationConfirm =
    Future<void> Function(ModelConfigurationSnapshot snapshot);

class ModelConfiguration extends StatefulWidget {
  const ModelConfiguration({
    super.key,
    required this.modelName,
    required this.modelPath,
    required this.llamaCppDirectory,
    required this.onConfirm,
    this.onCancel,
  });

  final String modelName;
  final String modelPath;
  final String llamaCppDirectory;

  final ModelConfigurationConfirm onConfirm;

  final FutureOr<void> Function()? onCancel;

  @override
  State<ModelConfiguration> createState() => _ModelConfigurationState();
}

class _ModelConfigurationState extends State<ModelConfiguration> {
  int _ctx = 8;
  int _threads = (Platform.numberOfProcessors * 0.75).ceil();
  int _gpuLayers = 999;
  double _temperature = 0.7;
  double _topP = 0.8;
  int _topK = 20;
  int _batch = 512;
  int _uBatch = 512;
  int _miroStatMode = 0;
  double _repeatPenalty = 1.0;
  int _repeatLastN = 64;
  double _presencePenalty = 1.5;
  double _frequencyPenalty = 0.0;
  bool _thinking = false;
  bool _submitting = false;

  Future<void> _confirm() async {
    if (_submitting) return;

    setState(() => _submitting = true);

    try {
      await widget.onConfirm(
        ModelConfigurationSnapshot(
          modelName: widget.modelName,
          modelPath: widget.modelPath,
          llamaCppDirectory: widget.llamaCppDirectory,
          nCtx: _ctx * 1024,
          nThreads: _threads,
          nGpuLayers: _gpuLayers,
          temperature: _temperature,
          topP: _topP,
          topK: _topK,
          nBatch: _batch,
          nUBatch: _uBatch,
          mirostat: _miroStatMode,
          repeatPenalty: _repeatPenalty,
          repeatLastN: _repeatLastN,
          presencePenalty: _presencePenalty,
          frequencyPenalty: _frequencyPenalty,
          thinking: _thinking,
        ),
      );

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

  void _cancel() {
    final onCancel = widget.onCancel;

    if (_submitting && onCancel != null) {
      unawaited(Future<void>.sync(onCancel));
    }

    Navigator.of(context).pop();
  }

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
            SliderControl.decimal(
              label: 'Repeat Penalty',
              value: _repeatPenalty,
              min: 0.5,
              max: 2.0,
              step: 0.05,
              onChanged: (v) =>
                  setState(() => _repeatPenalty = v.clamp(0.5, 2.0).toDouble()),
            ),
            SliderControl.integer(
              label: 'Repeat Last N',
              value: _repeatLastN,
              min: 0,
              max: 2048,
              step: 16,
              onChanged: (v) => setState(() => _repeatLastN = v.clamp(0, 2048)),
            ),
            SliderControl.decimal(
              label: 'Presence Penalty',
              value: _presencePenalty,
              min: -2.0,
              max: 2.0,
              step: 0.1,
              onChanged: (v) => setState(
                () => _presencePenalty = v.clamp(-2.0, 2.0).toDouble(),
              ),
            ),
            SliderControl.decimal(
              label: 'Frequency Penalty',
              value: _frequencyPenalty,
              min: -2.0,
              max: 2.0,
              step: 0.1,
              onChanged: (v) => setState(
                () => _frequencyPenalty = v.clamp(-2.0, 2.0).toDouble(),
              ),
            ),
            SwitchListTile(
              title: const Text('Thinking'),
              value: _thinking,
              onChanged: (v) => setState(() => _thinking = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _cancel, child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _confirm,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm'),
        ),
      ],
    );
  }
}
