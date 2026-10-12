import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/form_component.dart';
import '../theme/app_colors.dart';
import 'field_widgets/text_field_widget.dart';
import 'field_widgets/dropdown_field_widget.dart';
import 'field_widgets/radio_field_widget.dart';
import 'field_widgets/checkbox_field_widget.dart';
import 'field_widgets/slider_field_widget.dart';
import 'field_widgets/date_field_widget.dart';
import 'field_widgets/time_field_widget.dart';

class FormkitRenderer extends StatefulWidget {
  final List<dynamic> components;
  final Future<void> Function(Map<String, dynamic> data) onSubmit;

  const FormkitRenderer({
    super.key,
    required this.components,
    required this.onSubmit,
  });

  @override
  State<FormkitRenderer> createState() => _FormkitRendererState();
}

class _FormkitRendererState extends State<FormkitRenderer> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _data = {};
  late List<FormComponent> _parsed;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _parsed = widget.components
        .map((c) => FormComponent.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  @override
  void didUpdateWidget(FormkitRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.components, oldWidget.components)) {
      _parsed = widget.components
          .map((c) => FormComponent.fromJson(c as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(Map.from(_data));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildField(FormComponent comp) {
    switch (comp.type) {
      case 'textarea':
        return FieldTextInput(
          label: comp.label,
          placeholder: comp.placeholder,
          isRequired: comp.isRequired,
          maxLines: 4,
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'email':
        return FieldTextInput(
          label: comp.label,
          placeholder: comp.placeholder,
          isRequired: comp.isRequired,
          keyboardType: TextInputType.emailAddress,
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'url':
        return FieldTextInput(
          label: comp.label,
          placeholder: comp.placeholder,
          isRequired: comp.isRequired,
          keyboardType: TextInputType.url,
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'tel':
        return FieldTextInput(
          label: comp.label,
          placeholder: comp.placeholder,
          isRequired: comp.isRequired,
          keyboardType: TextInputType.phone,
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'number':
        return FieldTextInput(
          label: comp.label,
          placeholder: comp.placeholder,
          isRequired: comp.isRequired,
          keyboardType: TextInputType.number,
          onChanged: (v) => _data[comp.key] = num.tryParse(v) ?? v,
        );
      case 'range':
        return FieldSlider(
          label: comp.label,
          min: comp.min ?? 0,
          max: comp.max ?? 100,
          step: comp.step ?? 1,
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'date':
        return FieldDatePicker(
          label: comp.label,
          isRequired: comp.isRequired,
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'time':
        return FieldTimePicker(
          label: comp.label,
          isRequired: comp.isRequired,
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'datetime':
        return FieldTimePicker(
          label: comp.label,
          isRequired: comp.isRequired,
          includeDate: true,
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'select':
        return FieldDropdown(
          label: comp.label,
          isRequired: comp.isRequired,
          options:
              comp.options.map((o) => MapEntry(o.value, o.label)).toList(),
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'radio':
        return FieldRadioGroup(
          label: comp.label,
          isRequired: comp.isRequired,
          options:
              comp.options.map((o) => MapEntry(o.value, o.label)).toList(),
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'checkbox':
        return FieldCheckbox(
          label: comp.label,
          onChanged: (v) => _data[comp.key] = v,
        );
      case 'color':
      case 'file':
      case 'password':
        // M5: render a visible placeholder so users know a field is present but
        // not supported in mobile FormKit mode, rather than silently hiding it.
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${comp.label} (not supported in this form mode)',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      default:
        // textfield and any unknown types
        return FieldTextInput(
          label: comp.label,
          placeholder: comp.placeholder,
          isRequired: comp.isRequired,
          onChanged: (v) => _data[comp.key] = v,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final components = _parsed;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: components.map(_buildField).toList(),
            ),
          ),
          // Submit button bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
