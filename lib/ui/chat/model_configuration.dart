import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ModelConfiguration extends StatefulWidget {
  const ModelConfiguration({super.key, required this.onConfirm, this.onCancel});

  final void Function({
    required int ctx,
    required int threads,
    required int? gpuLayers,
  })
  onConfirm;

  final VoidCallback? onCancel;

  @override
  State<ModelConfiguration> createState() => _ModelConfigurationState();
}

class _ModelConfigurationState extends State<ModelConfiguration> {
  static const int _ctxMin = 1024;
  static const int _ctxMax = 262144;
  static const int _ctxDefault = 8192;
  static const int _ctxStep = 1024;

  int _toK(int tokens) => tokens ~/ 1024;
  int _fromK(int k) => k * 1024;

  List<int> get _ctxPresetKs {
    const base = [8, 16, 24, 32, 64, 128];
    final maxK = _toK(_ctxMax);
    return base.where((k) => k <= maxK).toList();
  }

  static const int _threadsMin = 1;

  static const int _gpuMin = 0;
  static const int _gpuMax = 999;
  static const int _gpuDefault = 999;

  late int _ctx = _ctxDefault;
  late int _threads = (Platform.numberOfProcessors * 0.75).ceil();
  late int _gpuLayersTemp = _gpuDefault;
  bool _allGpu = true;

  late final TextEditingController _ctxCtl = TextEditingController(
    text: _toK(_ctx).toString(),
  );
  late final TextEditingController _threadsCtl = TextEditingController(
    text: _threads.toString(),
  );
  late final TextEditingController _gpuCtl = TextEditingController(text: '');

  int get _threadsMax => Platform.numberOfProcessors;

  int _snapCtx(int v) {
    final snapped = ((v - _ctxMin) / _ctxStep).round() * _ctxStep + _ctxMin;
    return snapped.clamp(_ctxMin, _ctxMax);
  }

  int _clamp(int v, int min, int max) => v.clamp(min, max);

  @override
  void dispose() {
    _ctxCtl.dispose();
    _threadsCtl.dispose();
    _gpuCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Configure Model'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LabelledSection(
              label: 'Context length',
              helper:
                  'How many tokens the model can attend to. Shown in K (1K = 1024 tokens).',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Preset chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final k in _ctxPresetKs)
                        ChoiceChip(
                          label: Text('${k}K'),
                          selected: _toK(_ctx) == k && _ctx != _ctxMax,
                          onSelected: (_) {
                            setState(() {
                              _ctx = _snapCtx(_fromK(k));
                              _ctxCtl.text = _toK(
                                _ctx,
                              ).toString(); // store K in field
                            });
                          },
                        ),
                      ChoiceChip(
                        label: const Text('Max'),
                        selected: _ctx == _ctxMax,
                        onSelected: (_) {
                          setState(() {
                            _ctx = _ctxMax;
                            _ctxCtl.text = _toK(
                              _ctx,
                            ).toString(); // K view even for Max
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Slider (still stores tokens, labels in K)
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _ctx.toDouble(),
                          min: _ctxMin.toDouble(),
                          max: _ctxMax.toDouble(),
                          divisions: ((_ctxMax - _ctxMin) ~/ _ctxStep).clamp(
                            1,
                            1000,
                          ),
                          label: '${_toK(_ctx)}K',
                          onChanged: (v) {
                            setState(() {
                              _ctx = _snapCtx(v.round());
                              _ctxCtl.text = _toK(_ctx).toString();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      _NumberField(
                        controller: _ctxCtl,
                        enabled: true,
                        label: 'Value',
                        suffixText: 'K',
                        onChanged: (txt) {
                          final parsedK = int.tryParse(txt);
                          if (parsedK == null) return;
                          setState(() {
                            _ctx = _snapCtx(_fromK(parsedK));
                            _ctxCtl.text = _toK(_ctx).toString(); // normalize
                          });
                        },
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Min ${_toK(_ctxMin)}K • Max ${_toK(_ctxMax)}K',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            _LabelledSection(
              label: 'Number of threads',
              helper:
                  'Parallel CPU threads (max = detected cores: $_threadsMax).',
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _threads.toDouble(),
                      min: _threadsMin.toDouble(),
                      max: _threadsMax.toDouble(),
                      divisions: (_threadsMax - _threadsMin).clamp(1, 1000),
                      label: _threads.toString(),
                      onChanged: (v) {
                        setState(() {
                          _threads = _clamp(
                            v.round(),
                            _threadsMin,
                            _threadsMax,
                          );
                          _threadsCtl.text = _threads.toString();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  _NumberField(
                    controller: _threadsCtl,
                    enabled: true,
                    label: 'Value',
                    onChanged: (txt) {
                      final parsed = int.tryParse(txt);
                      if (parsed == null) return;
                      setState(() {
                        _threads = _clamp(parsed, _threadsMin, _threadsMax);
                        _threadsCtl.text = _threads.toString();
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _LabelledSection(
              label: 'Layers offloaded to GPU',
              helper: 'Use “All” to offload every supported layer.',
              child: Column(
                children: [
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All layers'),
                    value: _allGpu,
                    onChanged: (val) {
                      setState(() {
                        _allGpu = val ?? true;
                        if (_allGpu) {
                          _gpuCtl.text = '';
                        } else {
                          _gpuLayersTemp = _gpuDefault;
                          _gpuCtl.text = _gpuLayersTemp.toString();
                        }
                      });
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: _allGpu,
                          child: Opacity(
                            opacity: _allGpu ? 0.4 : 1,
                            child: Slider(
                              value: (_allGpu ? _gpuMax : _gpuLayersTemp)
                                  .toDouble(),
                              min: _gpuMin.toDouble(),
                              max: _gpuMax.toDouble(),
                              divisions: (_gpuMax - _gpuMin).clamp(1, 1000),
                              label: _allGpu
                                  ? 'All'
                                  : _gpuLayersTemp.toString(),
                              onChanged: (v) {
                                setState(() {
                                  _gpuLayersTemp = _clamp(
                                    v.round(),
                                    _gpuMin,
                                    _gpuMax,
                                  );
                                  _gpuCtl.text = _gpuLayersTemp.toString();
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _NumberField(
                        controller: _gpuCtl,
                        enabled: !_allGpu,
                        label: _allGpu ? 'All' : 'Value',
                        onChanged: (txt) {
                          if (_allGpu) return;
                          final parsed = int.tryParse(txt);
                          if (parsed == null) return;
                          setState(() {
                            _gpuLayersTemp = _clamp(parsed, _gpuMin, _gpuMax);
                            _gpuCtl.text = _gpuLayersTemp.toString();
                          });
                        },
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _allGpu
                          ? 'All (no limit)'
                          : 'Min $_gpuMin • Max $_gpuMax',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
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
              gpuLayers: _allGpu ? null : _gpuLayersTemp,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _LabelledSection extends StatelessWidget {
  const _LabelledSection({
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.textTheme.titleMedium),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(helper!, style: t.textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.enabled,
    required this.label,
    this.onChanged,
    this.suffixText,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final void Function(String)? onChanged;
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: TextField(
        controller: controller,
        enabled: enabled,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          labelText: label,
          suffixText: suffixText, // NEW
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
      ),
    );
  }
}
