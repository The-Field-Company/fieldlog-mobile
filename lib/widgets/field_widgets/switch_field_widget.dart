import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class FieldSwitch extends StatefulWidget {
  final String label;
  final ValueChanged<bool> onChanged;
  final bool initialValue;
  final String? labelTrue;
  final String? labelFalse;

  const FieldSwitch({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialValue = false,
    this.labelTrue,
    this.labelFalse,
  });

  @override
  State<FieldSwitch> createState() => _FieldSwitchState();
}

class _FieldSwitchState extends State<FieldSwitch> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _value
        ? (widget.labelTrue ?? 'Yes')
        : (widget.labelFalse ?? 'No');
    final hasCustomLabels =
        widget.labelTrue != null || widget.labelFalse != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: SwitchListTile(
        title: Text(
          widget.label,
          style: GoogleFonts.inter(
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: hasCustomLabels
            ? Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              )
            : null,
        value: _value,
        activeThumbColor: AppColors.accent,
        contentPadding: EdgeInsets.zero,
        onChanged: (value) {
          setState(() => _value = value);
          widget.onChanged(value);
        },
      ),
    );
  }
}
