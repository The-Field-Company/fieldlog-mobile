import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/survey_element.dart';
import '../theme/app_colors.dart';
import '../utils/expression_engine.dart';
import 'field_widgets/text_field_widget.dart';
import 'field_widgets/dropdown_field_widget.dart';
import 'field_widgets/radio_field_widget.dart';
import 'field_widgets/checkbox_field_widget.dart';
import 'field_widgets/switch_field_widget.dart';
import 'field_widgets/rating_field_widget.dart';
import 'field_widgets/date_field_widget.dart';
import 'field_widgets/time_field_widget.dart';
import 'field_widgets/slider_field_widget.dart';
import 'field_widgets/html_field_widget.dart';
import 'field_widgets/multiple_text_field_widget.dart';
import 'field_widgets/matrix_field_widget.dart';
import 'field_widgets/tagbox_field_widget.dart';
import 'field_widgets/ranking_field_widget.dart';
import 'field_widgets/image_field_widget.dart';
import 'field_widgets/file_field_widget.dart';
import 'field_widgets/image_picker_field_widget.dart';

class SurveyjsRenderer extends StatefulWidget {
  final Map<String, dynamic> schema;
  final Future<void> Function(Map<String, dynamic> data) onSubmit;

  const SurveyjsRenderer({
    super.key,
    required this.schema,
    required this.onSubmit,
  });

  @override
  State<SurveyjsRenderer> createState() => _SurveyjsRendererState();
}

class _SurveyjsRendererState extends State<SurveyjsRenderer> {
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _data = {};
  int _currentPage = 0;
  bool _submitting = false;

  List<SurveyPage> get _allPages {
    final pagesJson = widget.schema['pages'] as List<dynamic>? ?? [];
    return pagesJson
        .map((p) => SurveyPage.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  List<SurveyPage> get _visiblePages {
    return _allPages
        .where((p) => ExpressionEngine.evaluate(p.visibleIf, _data))
        .toList();
  }

  bool get _isMultiPage => _visiblePages.length > 1;

  @override
  void initState() {
    super.initState();
    _applyDefaults();
  }

  void _applyDefaults() {
    for (final page in _allPages) {
      _applyDefaultsForElements(page.elements);
    }
  }

  void _applyDefaultsForElements(List<SurveyElement> elements) {
    for (final element in elements) {
      if (element.defaultValue != null && !_data.containsKey(element.name)) {
        _data[element.name] = element.defaultValue;
      }
      // Recurse into panels
      if (element.elements.isNotEmpty) {
        _applyDefaultsForElements(element.elements);
      }
    }
  }

  void _updateData(String name, dynamic value) {
    setState(() {
      _data[name] = value;
    });
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

  void _nextPage() {
    if (!_formKey.currentState!.validate()) return;
    final pages = _visiblePages;
    if (_currentPage < pages.length - 1) {
      setState(() {
        _currentPage++;
        _formKey = GlobalKey<FormState>();
      });
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
        _formKey = GlobalKey<FormState>();
      });
    }
  }

  // ── Build options list with none/other support ──

  List<MapEntry<String, String>> _buildOptions(SurveyElement element) {
    final options = <MapEntry<String, String>>[];
    if (element.showNoneItem) {
      options.add(MapEntry('none', element.noneText));
    }
    options.addAll(element.choices.map((c) => MapEntry(c.value, c.text)));
    if (element.hasOther) {
      options.add(MapEntry('other', element.otherText));
    }
    return options;
  }

  // ── Input type → keyboard type mapping ──

  TextInputType _keyboardForInputType(String? inputType) {
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

  // ── Element builder ──

  Widget _buildElement(SurveyElement element) {
    // Expression evaluation
    if (!ExpressionEngine.evaluate(element.visibleIf, _data)) {
      return const SizedBox.shrink();
    }

    final isEnabled = ExpressionEngine.evaluate(element.enableIf, _data);
    final isRequired = element.isRequired ||
        (element.requiredIf != null &&
            ExpressionEngine.evaluate(element.requiredIf, _data));

    Widget child;

    switch (element.type) {
      case 'text':
        child = _buildTextElement(element, isRequired);
      case 'comment':
        child = FieldTextInput(
          label: element.title,
          isRequired: isRequired,
          maxLines: 4,
          placeholder: element.placeholder,
          initialValue: _data[element.name]?.toString(),
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'dropdown':
        child = _buildDropdownWithOther(element, isRequired);
      case 'radiogroup':
        child = _buildRadioWithOther(element, isRequired);
      case 'checkbox':
        child = _buildCheckboxWithOther(element, isRequired);
      case 'boolean':
        child = FieldSwitch(
          label: element.title,
          labelTrue: element.labelTrue,
          labelFalse: element.labelFalse,
          initialValue: _data[element.name] as bool? ??
              (element.defaultValue == true),
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'rating':
        child = FieldRating(
          label: element.title,
          isRequired: isRequired,
          maxRating: element.rateMax ?? 5,
          rateMin: element.rateMin,
          rateType: element.rateType,
          initialValue: _data[element.name] as int?,
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'slider':
        child = FieldSlider(
          label: element.title,
          min: element.min ?? 0,
          max: element.max ?? 100,
          step: element.step ?? 1,
          initialValue: (_data[element.name] as num?)?.toDouble(),
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'html':
        child = HtmlFieldWidget(html: element.html ?? '');
      case 'image':
        child = ImageFieldWidget(
          imageLink: element.imageLink ?? '',
          label: element.title,
        );
      case 'imagepicker':
        child = ImagePickerFieldWidget(
          label: element.title,
          choices: element.choices,
          multiSelect: element.multiSelect,
          showLabel: element.showLabel,
          isRequired: isRequired,
          initialValue: _data[element.name],
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'panel':
        child = _buildPanel(element);
      case 'multipletext':
        child = MultipleTextFieldWidget(
          label: element.title,
          items: element.items,
          isRequired: isRequired,
          initialValue: _data[element.name] as Map<String, dynamic>?,
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'matrix':
        child = MatrixFieldWidget(
          label: element.title,
          rows: element.rows,
          columns: element.columns,
          isRequired: isRequired,
          initialValue: _data[element.name] as Map<String, dynamic>?,
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'tagbox':
        child = TagboxFieldWidget(
          label: element.title,
          isRequired: isRequired,
          options: element.choices
              .map((c) => MapEntry(c.value, c.text))
              .toList(),
          initialValue: (_data[element.name] as List?)?.cast<String>(),
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'ranking':
        child = RankingFieldWidget(
          label: element.title,
          choices: element.choices
              .map((c) => MapEntry(c.value, c.text))
              .toList(),
          initialValue: (_data[element.name] as List?)?.cast<String>(),
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'file':
        child = FileFieldWidget(
          label: element.title,
          isRequired: isRequired,
          onChanged: (v) => _updateData(element.name, v),
        );
      default:
        child = Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Text(
              'Unsupported field type: ${element.type}',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        );
    }

    if (!isEnabled) {
      child = IgnorePointer(
        child: Opacity(opacity: 0.5, child: child),
      );
    }

    return KeyedSubtree(
      key: ValueKey(element.name),
      child: child,
    );
  }

  // ── Text element with inputType routing ──

  Widget _buildTextElement(SurveyElement element, bool isRequired) {
    switch (element.inputType) {
      case 'date':
        return FieldDatePicker(
          label: element.title,
          isRequired: isRequired,
          initialValue: _data[element.name]?.toString(),
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'datetime-local':
        return FieldTimePicker(
          label: element.title,
          isRequired: isRequired,
          includeDate: true,
          initialValue: _data[element.name]?.toString(),
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'time':
        return FieldTimePicker(
          label: element.title,
          isRequired: isRequired,
          initialValue: _data[element.name]?.toString(),
          onChanged: (v) => _updateData(element.name, v),
        );
      case 'range':
        return FieldSlider(
          label: element.title,
          min: element.min ?? 0,
          max: element.max ?? 100,
          step: element.step ?? 1,
          initialValue: (_data[element.name] as num?)?.toDouble(),
          onChanged: (v) => _updateData(element.name, v),
        );
      default:
        return FieldTextInput(
          label: element.title,
          isRequired: isRequired,
          placeholder: element.placeholder,
          keyboardType: _keyboardForInputType(element.inputType),
          initialValue: _data[element.name]?.toString(),
          onChanged: (v) => _updateData(element.name, v),
        );
    }
  }

  // ── Choice types with hasOther / showNoneItem ──

  Widget _buildDropdownWithOther(SurveyElement element, bool isRequired) {
    if (!element.hasOther && !element.showNoneItem) {
      return FieldDropdown(
        label: element.title,
        isRequired: isRequired,
        options: element.choices
            .map((c) => MapEntry(c.value, c.text))
            .toList(),
        initialValue: _data[element.name]?.toString(),
        onChanged: (v) => _updateData(element.name, v),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldDropdown(
          label: element.title,
          isRequired: isRequired,
          options: _buildOptions(element),
          initialValue: _data[element.name]?.toString(),
          onChanged: (v) => _updateData(element.name, v),
        ),
        if (_data[element.name] == 'other')
          FieldTextInput(
            key: ValueKey('${element.name}-Comment'),
            label: '${element.title} - please specify',
            onChanged: (v) =>
                _updateData('${element.name}-Comment', v),
            initialValue:
                _data['${element.name}-Comment']?.toString(),
          ),
      ],
    );
  }

  Widget _buildRadioWithOther(SurveyElement element, bool isRequired) {
    if (!element.hasOther && !element.showNoneItem) {
      return FieldRadioGroup(
        label: element.title,
        isRequired: isRequired,
        options: element.choices
            .map((c) => MapEntry(c.value, c.text))
            .toList(),
        initialValue: _data[element.name]?.toString(),
        onChanged: (v) => _updateData(element.name, v),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldRadioGroup(
          label: element.title,
          isRequired: isRequired,
          options: _buildOptions(element),
          initialValue: _data[element.name]?.toString(),
          onChanged: (v) => _updateData(element.name, v),
        ),
        if (_data[element.name] == 'other')
          FieldTextInput(
            key: ValueKey('${element.name}-Comment'),
            label: '${element.title} - please specify',
            onChanged: (v) =>
                _updateData('${element.name}-Comment', v),
            initialValue:
                _data['${element.name}-Comment']?.toString(),
          ),
      ],
    );
  }

  Widget _buildCheckboxWithOther(SurveyElement element, bool isRequired) {
    if (!element.hasOther && !element.showNoneItem) {
      return FieldMultiCheckbox(
        label: element.title,
        isRequired: isRequired,
        options: element.choices
            .map((c) => MapEntry(c.value, c.text))
            .toList(),
        initialValue: (_data[element.name] as List?)?.cast<String>(),
        onChanged: (v) => _updateData(element.name, v),
      );
    }
    final selected = (_data[element.name] as List?)?.cast<String>() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldMultiCheckbox(
          label: element.title,
          isRequired: isRequired,
          options: _buildOptions(element),
          initialValue: selected,
          onChanged: (v) => _updateData(element.name, v),
        ),
        if (selected.contains('other'))
          FieldTextInput(
            key: ValueKey('${element.name}-Comment'),
            label: '${element.title} - please specify',
            onChanged: (v) =>
                _updateData('${element.name}-Comment', v),
            initialValue:
                _data['${element.name}-Comment']?.toString(),
          ),
      ],
    );
  }

  // ── Panel ──

  Widget _buildPanel(SurveyElement element) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (element.title.isNotEmpty)
              Text(
                element.title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            if (element.description != null) ...[
              const SizedBox(height: 4),
              Text(
                element.description!,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (element.title.isNotEmpty || element.description != null)
              const SizedBox(height: 12),
            ...element.elements.map(_buildElement),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _visiblePages;
    if (pages.isEmpty) {
      return const Center(child: Text('No form elements found'));
    }

    // Clamp page index if pages were hidden
    if (_currentPage >= pages.length) {
      _currentPage = pages.length - 1;
    }

    final currentPage = pages[_currentPage];

    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Page header (title + indicator)
          if (_isMultiPage || currentPage.title != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                children: [
                  if (_isMultiPage)
                    Text(
                      'Page ${_currentPage + 1} of ${pages.length}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  if (currentPage.title != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      currentPage.title!,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                  if (currentPage.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      currentPage.description!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          // Form fields
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children:
                  currentPage.elements.map(_buildElement).toList(),
            ),
          ),
          // Bottom bar
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
              child: _isMultiPage
                  ? Row(
                      children: [
                        if (_currentPage > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _prevPage,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accent,
                                side: const BorderSide(
                                    color: AppColors.accent),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: const Text('Previous'),
                            ),
                          ),
                        if (_currentPage > 0)
                          const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _submitting
                                ? null
                                : (_currentPage < pages.length - 1
                                    ? _nextPage
                                    : _submit),
                            child: _submitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(_currentPage < pages.length - 1
                                    ? 'Next'
                                    : 'Submit'),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
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
