import 'package:flutter/material.dart';
import 'package:hermes/ui/common/labelled_section.dart';

class SliderControl<T extends num> extends StatefulWidget {
  final String label;
  final String? helperText;

  final T value;
  final T min;
  final T max;
  final T step;

  final double Function(T value) toDouble;
  final T Function(double value) fromDouble;

  final ValueChanged<T> onChanged;

  const SliderControl({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.toDouble,
    required this.fromDouble,
    required this.onChanged,
    this.helperText,
  });

  // Static builders (legal, and return concrete types)
  static SliderControl<int> integer({
    Key? key,
    required String label,
    String? helperText,
    required int value,
    required int min,
    required int max,
    int step = 1,
    required ValueChanged<int> onChanged,
  }) {
    return SliderControl<int>(
      key: key,
      label: label,
      helperText: helperText,
      value: value,
      min: min,
      max: max,
      step: step,
      toDouble: (v) => v.toDouble(),
      fromDouble: (d) => d.round(),
      onChanged: onChanged,
    );
  }

  static SliderControl<double> decimal({
    Key? key,
    required String label,
    String? helperText,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    return SliderControl<double>(
      key: key,
      label: label,
      helperText: helperText,
      value: value,
      min: min,
      max: max,
      step: step,
      toDouble: (v) => v,
      fromDouble: (d) => d,
      onChanged: onChanged,
    );
  }

  @override
  State<SliderControl<T>> createState() => _SliderControlState<T>();
}

class _SliderControlState<T extends num> extends State<SliderControl<T>> {
  late final TextEditingController _controller;
  late double _dMin, _dMax, _dStep, _dValue;

  @override
  void initState() {
    super.initState();
    _dMin = widget.toDouble(widget.min);
    _dMax = widget.toDouble(widget.max);
    _dStep = widget.toDouble(widget.step);
    _dValue = _clamp(widget.toDouble(widget.value));
    _controller = TextEditingController(text: _format(_dValue));
  }

  @override
  void didUpdateWidget(covariant SliderControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dMin = widget.toDouble(widget.min);
    _dMax = widget.toDouble(widget.max);
    _dStep = widget.toDouble(widget.step);
    final newVal = _clamp(widget.toDouble(widget.value));
    if (newVal != _dValue) {
      _dValue = newVal;
      final s = _format(_dValue);
      if (_controller.text != s) _controller.text = s;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _clamp(double v) => v.clamp(_dMin, _dMax);
  double _snap(double v) {
    if (_dStep <= 0) return _clamp(v);
    final steps = ((v - _dMin) / _dStep).round();
    return _clamp(_dMin + steps * _dStep);
  }

  void _setDouble(double v, {bool snap = true}) {
    final next = snap ? _snap(v) : _clamp(v);
    if (next == _dValue) return;
    setState(() {
      _dValue = next;
      final s = _format(_dValue);
      if (_controller.text != s) _controller.text = s;
    });
    widget.onChanged(widget.fromDouble(_dValue));
  }

  String _format(double v) {
    if (T == int) return v.round().toString();
    final s = v.toStringAsFixed(6);
    return RegExp(r'\.?0+$').hasMatch(s)
        ? s.replaceFirst(RegExp(r'\.?0+$'), '')
        : s;
  }

  int? get _divisions {
    if (_dStep <= 0) return null;
    final count = ((_dMax - _dMin) / _dStep).round();
    return count > 0 ? count : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LabelledSection(
      label: widget.label,
      helper: widget.helperText,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Decrease',
            onPressed: () => _setDouble(_dValue - _dStep),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(
            child: Semantics(
              label:
                  "${widget.label} (Min: ${widget.min}, Max: ${widget.max}, Step: ${widget.step})",
              value: _format(_dValue),
              child: Slider(
                value: _dValue,
                min: _dMin,
                max: _dMax,
                divisions: _divisions,
                label: _format(_dValue),
                onChanged: (d) => _setDouble(d),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Increase',
            onPressed: () => _setDouble(_dValue + _dStep),
            icon: const Icon(Icons.add_circle_outline),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 88,
            child: TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Value',
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              onFieldSubmitted: (s) {
                final parsed = T == int
                    ? (int.tryParse(s)?.toDouble())
                    : double.tryParse(s);
                if (parsed != null) _setDouble(parsed);
                final normalised = _format(_dValue);
                if (_controller.text != normalised) {
                  _controller.text = normalised;
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Min: ${widget.min}', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              Text('Step: ${widget.step}', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              Text('Max: ${widget.max}', style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
