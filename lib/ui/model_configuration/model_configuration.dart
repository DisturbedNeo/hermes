import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hermes/ui/model_configuration/context_length_section.dart';
import 'package:hermes/ui/model_configuration/gpu_offload_section.dart';
import 'package:hermes/ui/model_configuration/threads_section.dart';

class ModelConfiguration extends StatefulWidget {
  const ModelConfiguration({
    super.key,
    required this.onConfirm,
    this.onCancel,
  });

  final void Function({
    required int ctx,
    required int threads,
    required int? gpuLayers,
  }) onConfirm;

  final VoidCallback? onCancel;

  @override
  State<ModelConfiguration> createState() =>
      _ModelConfigurationState();
}

class _ModelConfigurationState extends State<ModelConfiguration> {
  // ---- Context
  static const int _ctxMin = 1024;
  static const int _ctxMax = 262144;
  static const int _ctxDefault = 8192;
  static const int _ctxStep = 1024;

  // ---- Threads
  static const int _threadsMin = 1;

  // ---- GPU layers
  static const int _gpuMin = 0;
  static const int _gpuMax = 999;
  static const int _gpuDefault = 999;

  // State
  int _ctx = _ctxDefault;
  int _threads = (Platform.numberOfProcessors * 0.75).ceil();
  bool _allGpu = true;
  int _gpuLayers = _gpuDefault;

  int get _threadsMax => Platform.numberOfProcessors;

  int _toK(int tokens) => tokens ~/ 1024;
  int _fromK(int k) => k * 1024;

  int _snapCtx(int v) {
    final snapped =
        ((v - _ctxMin) / _ctxStep).round() * _ctxStep + _ctxMin;
    return snapped.clamp(_ctxMin, _ctxMax);
  }

  List<int> get _ctxPresetKs {
    const base = [8, 16, 24, 32, 64, 128];
    final maxK = _toK(_ctxMax);
    return base.where((k) => k <= maxK).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure Model', style: TextStyle(color: Colors.black)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContextLengthSection(
              valueTokens: _ctx,
              minTokens: _ctxMin,
              maxTokens: _ctxMax,
              stepTokens: _ctxStep,
              presetKs: _ctxPresetKs,
              toK: _toK,
              fromK: _fromK,
              snapTokens: _snapCtx,
              onChanged: (tokens) => setState(() => _ctx = _snapCtx(tokens)),
            ),
            const SizedBox(height: 16),
            ThreadsSection(
              value: _threads,
              min: _threadsMin,
              max: _threadsMax,
              onChanged: (v) => setState(
                () => _threads = v.clamp(_threadsMin, _threadsMax),
              ),
            ),
            const SizedBox(height: 16),
            GpuOffloadSection(
              allLayers: _allGpu,
              value: _gpuLayers,
              min: _gpuMin,
              max: _gpuMax,
              onChanged: (all, v) => setState(() {
                _allGpu = all;
                if (!_allGpu && v != null) {
                  _gpuLayers = v.clamp(_gpuMin, _gpuMax);
                }
              }),
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
              ctx: _ctx,
              threads: _threads,
              gpuLayers: _allGpu ? null : _gpuLayers,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
