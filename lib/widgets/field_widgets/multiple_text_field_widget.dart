import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/survey_element.dart';
import '../../theme/app_colors.dart';

class MultipleTextFieldWidget extends StatefulWidget {
  final String label;
  final List<SurveyTextItem> items;
  final bool isRequired;
  final Map<String, dynamic>? initialValue;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const MultipleTextFieldWidget({
    super.key,
    required this.label,
    required this.items,
    required this.onChanged,
    this.isRequired = false,
    this.initialValue,
  });

  @override
  State<MultipleTextFieldWidget> createState() =>
      _MultipleTextFieldWidgetState();
}

class _MultipleTextFieldWidgetState extends State<MultipleTextFieldWidget> {
  late Map<String, dynamic> _values;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValue ?? {});
  }

  TextInputType _keyboardFor(String? inputType) {
    switch (inputType) {
      case 'number':
        return TextInputType.number;
      case 'email':
        return TextInputType.emailAddress;
      case 'url':
        return TextInputType.url;
      case 'tel':
        return TextInputType.phone;
      default:
        return TextInputType.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label + (widget.isRequired ? ' *' : ''),
            style: GoogleFonts.inter(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ...widget.items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                initialValue: _values[item.name]?.toString(),
                keyboardType: _keyboardFor(item.inputType),
                decoration: InputDecoration(
                  labelText: item.title + (item.isRequired ? ' *' : ''),
                  hintText: item.placeholder,
                ),
                validator: item.isRequired
                    ? (value) => (value == null || value.isEmpty)
                        ? '${item.title} is required'
                        : null
                    : null,
                onChanged: (v) {
                  _values[item.name] = v;
                  widget.onChanged(Map.from(_values));
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
