class FormComponent {
  final String type;
  final String key;
  final String label;
  final String? placeholder;
  final String? validation;
  final num? min;
  final num? max;
  final num? step;
  final List<FormOption> options;

  FormComponent({
    required this.type,
    required this.key,
    required this.label,
    this.placeholder,
    this.validation,
    this.min,
    this.max,
    this.step,
    this.options = const [],
  });

  bool get isRequired => validation == 'required';

  factory FormComponent.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    final values = data?['values'] as List<dynamic>?;

    return FormComponent(
      type: json['type'] ?? 'textfield',
      key: json['key'] ?? '',
      label: json['label'] ?? '',
      placeholder: json['placeholder'],
      validation: json['validation'],
      min: json['min'],
      max: json['max'],
      step: json['step'],
      options: values
              ?.map((v) => FormOption.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class FormOption {
  final String label;
  final String value;

  FormOption({required this.label, required this.value});

  factory FormOption.fromJson(Map<String, dynamic> json) {
    return FormOption(
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
    );
  }
}
