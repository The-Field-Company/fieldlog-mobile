import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class FieldDatePicker extends StatefulWidget {
  final String label;
  final bool isRequired;
  final ValueChanged<String> onChanged;
  final String? initialValue;

  const FieldDatePicker({
    super.key,
    required this.label,
    required this.onChanged,
    this.isRequired = false,
    this.initialValue,
  });

  @override
  State<FieldDatePicker> createState() => _FieldDatePickerState();
}

class _FieldDatePickerState extends State<FieldDatePicker> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  Future<void> _pick() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.accent,
                ),
          ),
          child: child!,
        );
      },
    );
    if (date != null) {
      final formatted =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      _controller.text = formatted;
      widget.onChanged(formatted);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: _controller,
        readOnly: true,
        onTap: _pick,
        decoration: InputDecoration(
          labelText: widget.label + (widget.isRequired ? ' *' : ''),
          suffixIcon:
              const Icon(Icons.calendar_today, size: 20, color: AppColors.textTertiary),
        ),
        validator: widget.isRequired
            ? (value) =>
                (value == null || value.isEmpty) ? '${widget.label} is required' : null
            : null,
      ),
    );
  }
}
