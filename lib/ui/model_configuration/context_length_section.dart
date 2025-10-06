import 'package:flutter/material.dart';
import 'package:hermes/ui/common/labelled_section.dart';
import 'package:hermes/ui/common/number_field.dart';

class ContextLengthSection extends StatefulWidget {
  const ContextLengthSection({
    super.key, 
    required this.valueTokens,
    required this.minTokens,
    required this.maxTokens,
    required this.stepTokens,
    required this.presetKs,
    required this.toK,
    required this.fromK,
    required this.snapTokens,
    required this.onChanged,
  });

  final int valueTokens;
  final int minTokens;
  final int maxTokens;
  final int stepTokens;
  final List<int> presetKs;
  final int Function(int tokens) toK;
  final int Function(int k) fromK;
  final int Function(int tokens) snapTokens;
  final ValueChanged<int> onChanged;

  @override
  State<ContextLengthSection> createState() => _ContextLengthSectionState();
}

class _ContextLengthSectionState extends State<ContextLengthSection> {
  late final TextEditingController _kCtl;
  String _lastText = '';

  bool get _isMax => _value == widget.maxTokens;

  int _value = 0;

  @override
  void initState() {
    super.initState();
    _value = widget.valueTokens.clamp(widget.minTokens, widget.maxTokens);
    _kCtl = TextEditingController(text: widget.toK(_value).toString());
    _lastText = _kCtl.text;
  }

  @override
  void didUpdateWidget(covariant ContextLengthSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.valueTokens != _value) {
      _value = widget.valueTokens.clamp(widget.minTokens, widget.maxTokens);
      final normalized = widget.toK(_value).toString();
      if (_lastText != normalized) {
        _kCtl.text = normalized;
        _lastText = normalized;
      }
    }
  }

  @override
  void dispose() {
    _kCtl.dispose();
    super.dispose();
  }

  void _setTokens(int tokens) {
    final snapped = widget.snapTokens(tokens);
    if (snapped == _value) return;
    setState(() {
      _value = snapped;
      final normalized = widget.toK(_value).toString();
      if (_lastText != normalized) {
        _kCtl.text = normalized;
        _lastText = normalized;
      }
    });
    widget.onChanged(_value);
  }

  @override
  Widget build(BuildContext context) {
    final bodySmall = Theme.of(context).textTheme.bodySmall;

    return LabelledSection(
      label: 'Context length',
      helper:
          'How many tokens the model can attend to. Shown in K (1K = 1024 tokens).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in widget.presetKs)
                ChoiceChip(
                  label: Text('${k}K'),
                  selected: widget.toK(_value) == k && !_isMax,
                  onSelected: (_) => _setTokens(widget.fromK(k)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Context length slider',
                  value: '${widget.toK(_value)} K tokens',
                  child: Slider(
                    value: _value.toDouble(),
                    min: widget.minTokens.toDouble(),
                    max: widget.maxTokens.toDouble(),
                    divisions: ((widget.maxTokens - widget.minTokens) ~/
                            widget.stepTokens)
                        .clamp(1, 1000),
                    label: '${widget.toK(_value)}K',
                    onChanged: (v) => _setTokens(v.round()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: NumberField(
                  controller: _kCtl,
                  enabled: true,
                  label: 'Value',
                  suffixText: 'K',
                  onChanged: (txt) {
                    final parsedK = int.tryParse(txt);
                    if (parsedK == null) return;

                    _setTokens(widget.fromK(parsedK));

                    final normalized = widget.toK(_value).toString();
                    if (_lastText != normalized) {
                      _kCtl.text = normalized;
                      _lastText = normalized;
                    }
                  },
                ),
              ),
            ],
          ),
          Text(
            'Min ${widget.toK(widget.minTokens)}K • Max ${widget.toK(widget.maxTokens)}K',
            style: bodySmall,
          ),
        ],
      ),
    );
  }
}