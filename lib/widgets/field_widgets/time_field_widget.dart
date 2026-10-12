import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class FieldTimePicker extends StatefulWidget {
  final String label;
  final bool isRequired;
  final bool includeDate;
  final ValueChanged<String> onChanged;
  final String? initialValue;

  const FieldTimePicker({
    super.key,
    required this.label,
    required this.onChanged,
    this.isRequired = false,
    this.includeDate = false,
    this.initialValue,
  });

  @override
  State<FieldTimePicker> createState() => _FieldTimePickerState();
}

class _FieldTimePickerState extends State<FieldTimePicker> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  Future<void> _pick() async {
    String result = '';

    if (widget.includeDate) {
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
      if (date == null || !mounted) return;
      result =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
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

    if (time != null) {
      final timeStr =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      result = widget.includeDate ? '$result $timeStr' : timeStr;
      _controller.text = result;
      widget.onChanged(result);
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
          suffixIcon: Icon(
            widget.includeDate ? Icons.event : Icons.access_time,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ),
        validator: widget.isRequired
            ? (value) =>
                (value == null || value.isEmpty) ? '${widget.label} is required' : null
            : null,
      ),
    );
  }
}
