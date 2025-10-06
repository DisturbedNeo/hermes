import 'package:flutter/material.dart';
import 'package:hermes/ui/common/labelled_section.dart';
import 'package:hermes/ui/common/number_field.dart';

class GpuOffloadSection extends StatefulWidget {
  const GpuOffloadSection({
    super.key, 
    required this.allLayers,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final bool allLayers;
  final int value;
  final int min;
  final int max;
  final void Function(bool allLayers, int? value) onChanged;

  @override
  State<GpuOffloadSection> createState() => _GpuOffloadSectionState();
}

class _GpuOffloadSectionState extends State<GpuOffloadSection> {
  late final TextEditingController _ctl;
  String _lastText = '';
  late bool _all;
  late int _val;

  @override
  void initState() {
    super.initState();
    _all = widget.allLayers;
    _val = widget.value.clamp(widget.min, widget.max);
    _ctl = TextEditingController(text: _all ? '' : _val.toString());
    _lastText = _ctl.text;
  }

  @override
  void didUpdateWidget(covariant GpuOffloadSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.allLayers != _all) {
      _all = widget.allLayers;
      final text = _all ? '' : _val.toString();
      if (_lastText != text) {
        _ctl.text = text;
        _lastText = text;
      }
    }
    if (widget.value != _val) {
      _val = widget.value.clamp(widget.min, widget.max);
      if (!_all) {
        final normalized = _val.toString();
        if (_lastText != normalized) {
          _ctl.text = normalized;
          _lastText = normalized;
        }
      }
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _toggleAll(bool v) {
    if (v == _all) return;
    setState(() {
      _all = v;
      final text = _all ? '' : _val.toString();
      if (_lastText != text) {
        _ctl.text = text;
        _lastText = text;
      }
    });
    widget.onChanged(_all, _all ? null : _val);
  }

  void _setVal(int v) {
    final clamped = v.clamp(widget.min, widget.max);
    if (clamped == _val) return;
    setState(() {
      _val = clamped;
      if (!_all) {
        final normalized = _val.toString();
        if (_lastText != normalized) {
          _ctl.text = normalized;
          _lastText = normalized;
        }
      }
    });
    widget.onChanged(_all, _all ? null : _val);
  }

  @override
  Widget build(BuildContext context) {
    final bodySmall = Theme.of(context).textTheme.bodySmall;

    return LabelledSection(
      label: 'Layers offloaded to GPU',
      helper: 'Use “All” to offload every supported layer.',
      child: Column(
        children: [
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('All layers'),
            value: _all,
            onChanged: (val) => _toggleAll(val ?? true),
          ),
          Row(
            children: [
              Expanded(
                child: AbsorbPointer(
                  absorbing: _all,
                  child: Opacity(
                    opacity: _all ? 0.4 : 1,
                    child: Semantics(
                      label: 'GPU layers slider',
                      value: _all ? 'All layers' : '$_val layers',
                      child: Slider(
                        value: (_all ? widget.max : _val).toDouble(),
                        min: widget.min.toDouble(),
                        max: widget.max.toDouble(),
                        divisions: (widget.max - widget.min).clamp(1, 1000),
                        label: _all ? 'All' : _val.toString(),
                        onChanged: (v) => _setVal(v.round()),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: NumberField(
                  controller: _ctl,
                  enabled: !_all,
                  label: _all ? 'All' : 'Value',
                  onChanged: (txt) {
                    if (_all) return;
                    final parsed = int.tryParse(txt);
                    if (parsed == null) return;
                    _setVal(parsed);
                    final normalized = _val.toString();
                    if (_lastText != normalized) {
                      _ctl.text = normalized;
                      _lastText = normalized;
                    }
                  },
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _all ? 'All (no limit)' : 'Min ${widget.min} • Max ${widget.max}',
              style: bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}