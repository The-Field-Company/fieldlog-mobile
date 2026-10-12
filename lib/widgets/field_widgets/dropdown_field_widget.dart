import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class FieldDropdown extends StatefulWidget {
  final String label;
  final bool isRequired;
  final List<MapEntry<String, String>> options;
  final ValueChanged<String?> onChanged;
  final String? initialValue;

  const FieldDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.isRequired = false,
    this.initialValue,
  });

  @override
  State<FieldDropdown> createState() => _FieldDropdownState();
}

class _FieldDropdownState extends State<FieldDropdown> {
  String? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: DropdownButtonFormField<String>(
        initialValue: _value,
        decoration: InputDecoration(
          labelText: widget.label + (widget.isRequired ? ' *' : ''),
        ),
        dropdownColor: AppColors.primaryBg,
        items: widget.options
            .map((o) => DropdownMenuItem(value: o.key, child: Text(o.value)))
            .toList(),
        validator: widget.isRequired
            ? (value) =>
                value == null ? '${widget.label} is required' : null
            : null,
        onChanged: (value) {
          setState(() => _value = value);
          widget.onChanged(value);
        },
      ),
    );
  }
}
