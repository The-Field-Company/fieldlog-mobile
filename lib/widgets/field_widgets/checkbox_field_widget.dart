import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class FieldCheckbox extends StatefulWidget {
  final String label;
  final ValueChanged<bool> onChanged;
  final bool initialValue;

  const FieldCheckbox({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialValue = false,
  });

  @override
  State<FieldCheckbox> createState() => _FieldCheckboxState();
}

class _FieldCheckboxState extends State<FieldCheckbox> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: CheckboxListTile(
        title: Text(
          widget.label,
          style: GoogleFonts.inter(
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
        value: _value,
        activeColor: AppColors.accent,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (value) {
          setState(() => _value = value ?? false);
          widget.onChanged(_value);
        },
      ),
    );
  }
}

class FieldMultiCheckbox extends StatefulWidget {
  final String label;
  final bool isRequired;
  final List<MapEntry<String, String>> options;
  final ValueChanged<List<String>> onChanged;
  final List<String>? initialValue;

  const FieldMultiCheckbox({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.isRequired = false,
    this.initialValue,
  });

  @override
  State<FieldMultiCheckbox> createState() => _FieldMultiCheckboxState();
}

class _FieldMultiCheckboxState extends State<FieldMultiCheckbox> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue?.toSet() ?? {};
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<List<String>>(
        initialValue: _selected.toList(),
        validator: widget.isRequired
            ? (value) =>
                _selected.isEmpty ? '${widget.label} is required' : null
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
              ...widget.options.map(
                (o) => CheckboxListTile(
                  title: Text(o.value,
                      style: GoogleFonts.inter(
                          fontSize: 15, color: AppColors.textPrimary)),
                  value: _selected.contains(o.key),
                  activeColor: AppColors.accent,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selected.add(o.key);
                      } else {
                        _selected.remove(o.key);
                      }
                    });
                    state.didChange(_selected.toList());
                    widget.onChanged(_selected.toList());
                  },
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
