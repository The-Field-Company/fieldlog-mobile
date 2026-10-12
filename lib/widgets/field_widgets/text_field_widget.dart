import 'package:flutter/material.dart';

class FieldTextInput extends StatelessWidget {
  final String label;
  final String? placeholder;
  final bool isRequired;
  final int maxLines;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;
  final String? initialValue;

  const FieldTextInput({
    super.key,
    required this.label,
    required this.onChanged,
    this.placeholder,
    this.isRequired = false,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.initialValue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        initialValue: initialValue,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label + (isRequired ? ' *' : ''),
          hintText: placeholder,
        ),
        validator: isRequired
            ? (value) =>
                (value == null || value.isEmpty) ? '$label is required' : null
            : null,
        onChanged: onChanged,
      ),
    );
  }
}
