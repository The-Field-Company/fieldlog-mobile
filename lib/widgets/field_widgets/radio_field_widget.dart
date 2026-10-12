import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class FieldRadioGroup extends StatefulWidget {
  final String label;
  final bool isRequired;
  final List<MapEntry<String, String>> options;
  final ValueChanged<String?> onChanged;
  final String? initialValue;

  const FieldRadioGroup({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.isRequired = false,
    this.initialValue,
  });

  @override
  State<FieldRadioGroup> createState() => _FieldRadioGroupState();
}

class _FieldRadioGroupState extends State<FieldRadioGroup> {
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
      child: FormField<String>(
        initialValue: _value,
        validator: widget.isRequired
            ? (value) =>
                _value == null ? '${widget.label} is required' : null
            : null,
        builder: (state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label + (widget.isRequired ? ' *' : ''),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: _value,
                onChanged: (value) {
                  setState(() => _value = value);
                  state.didChange(value);
                  widget.onChanged(value);
                },
                child: Column(
                  children: widget.options.map(
                    (o) => RadioListTile<String>(
                      title: Text(o.value,
                          style: GoogleFonts.inter(
                              fontSize: 15, color: AppColors.textPrimary)),
                      value: o.key,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ).toList(),
                ),
              ),
              if (state.hasError)
                Text(
                  state.errorText!,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.error),
                ),
            ],
          );
        },
      ),
    );
  }
}
