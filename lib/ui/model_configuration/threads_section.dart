import 'package:flutter/material.dart';
import 'package:hermes/ui/common/labelled_section.dart';
import 'package:hermes/ui/common/number_field.dart';

class ThreadsSection extends StatefulWidget {
  const ThreadsSection({
    super.key, 
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<ThreadsSection> createState() => _ThreadsSectionState();
}

class _ThreadsSectionState extends State<ThreadsSection> {
  late final TextEditingController _ctl;
  String _lastText = '';
  int _value = 0;

  @override
  void initState() {
    super.initState();
    _value = widget.value.clamp(widget.min, widget.max);
    _ctl = TextEditingController(text: _value.toString());
    _lastText = _ctl.text;
  }

  @override
  void didUpdateWidget(covariant ThreadsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _value) {
      _value = widget.value.clamp(widget.min, widget.max);
      final normalized = _value.toString();
      if (_lastText != normalized) {
        _ctl.text = normalized;
        _lastText = normalized;
      }
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _set(int v) {
    final clamped = v.clamp(widget.min, widget.max);
    if (clamped == _value) return;
    setState(() {
      _value = clamped;
      final normalized = _value.toString();
      if (_lastText != normalized) {
        _ctl.text = normalized;
        _lastText = normalized;
      }
    });
    widget.onChanged(_value);
  }

  @override
  Widget build(BuildContext context) {
    return LabelledSection(
      label: 'Number of threads',
      helper: 'Parallel CPU threads (max = detected cores: ${widget.max}).',
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: 'Threads slider',
              value: '$_value threads',
              child: Slider(
                value: _value.toDouble(),
                min: widget.min.toDouble(),
                max: widget.max.toDouble(),
                divisions: (widget.max - widget.min).clamp(1, 1000),
                label: _value.toString(),
                onChanged: (v) => _set(v.round()),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: NumberField(
              controller: _ctl,
              enabled: true,
              label: 'Value',
              onChanged: (txt) {
                final parsed = int.tryParse(txt);
                if (parsed == null) return;
                _set(parsed);
                final normalized = _value.toString();
                if (_lastText != normalized) {
                  _ctl.text = normalized;
                  _lastText = normalized;
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}