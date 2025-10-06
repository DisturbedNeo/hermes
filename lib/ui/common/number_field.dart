import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NumberField extends StatelessWidget {
  const NumberField({
    super.key, 
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
          suffixText: suffixText,
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
      ),
    );
  }
}
