class SurveyElement {
  final String type;
  final String name;
  final String title;
  final bool isRequired;
  final List<SurveyChoice> choices;
  final int? rateMax;

  // Expression strings
  final String? visibleIf;
  final String? enableIf;
  final String? requiredIf;

  // Text/input
  final String? placeholder;
  final dynamic defaultValue;
  final String? inputType;

  // Choice enhancements
  final bool hasOther;
  final String otherText;
  final bool showNoneItem;
  final String noneText;

  // Boolean
  final String? labelTrue;
  final String? labelFalse;

  // Rating
  final int rateMin;
  final String? rateType;

  // HTML
  final String? html;

  // Image
  final String? imageLink;

  // Panel (recursive)
  final List<SurveyElement> elements;
  final String? description;

  // MultipleText
  final List<SurveyTextItem> items;

  // Matrix
  final List<SurveyChoice> rows;
  final List<SurveyChoice> columns;

  // Slider/range
  final num? min;
  final num? max;
  final num? step;

  // ImagePicker
  final bool multiSelect;
  final bool showLabel;

  SurveyElement({
    required this.type,
    required this.name,
    required this.title,
    this.isRequired = false,
    this.choices = const [],
    this.rateMax,
    this.visibleIf,
    this.enableIf,
    this.requiredIf,
    this.placeholder,
    this.defaultValue,
    this.inputType,
    this.hasOther = false,
    this.otherText = 'Other (describe)',
    this.showNoneItem = false,
    this.noneText = 'None',
    this.labelTrue,
    this.labelFalse,
    this.rateMin = 1,
    this.rateType,
    this.html,
    this.imageLink,
    this.elements = const [],
    this.description,
    this.items = const [],
    this.rows = const [],
    this.columns = const [],
    this.min,
    this.max,
    this.step,
    this.multiSelect = false,
    this.showLabel = true,
  });

  factory SurveyElement.fromJson(Map<String, dynamic> json) {
    final choicesJson = json['choices'] as List<dynamic>?;
    final elementsJson = json['elements'] as List<dynamic>?;
    final itemsJson = json['items'] as List<dynamic>?;
    final rowsJson = json['rows'] as List<dynamic>?;
    final columnsJson = json['columns'] as List<dynamic>?;

    return SurveyElement(
      type: json['type'] ?? 'text',
      name: json['name'] ?? '',
      title: json['title'] ?? json['name'] ?? '',
      isRequired: json['isRequired'] == true,
      rateMax: json['rateMax'],
      choices: _parseChoices(choicesJson),
      visibleIf: json['visibleIf'],
      enableIf: json['enableIf'],
      requiredIf: json['requiredIf'],
      placeholder: json['placeholder'] ?? json['placeHolder'],
      defaultValue: json['defaultValue'],
      inputType: json['inputType'],
      hasOther: json['hasOther'] == true || json['showOtherItem'] == true,
      otherText: json['otherText'] ?? 'Other (describe)',
      showNoneItem: json['showNoneItem'] == true,
      noneText: json['noneText'] ?? 'None',
      labelTrue: json['labelTrue'],
      labelFalse: json['labelFalse'],
      rateMin: json['rateMin'] ?? 1,
      rateType: json['rateType'],
      html: json['html'],
      imageLink: json['imageLink'],
      elements: elementsJson
              ?.map((e) => SurveyElement.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      description: json['description'],
      items: itemsJson
              ?.map((i) => SurveyTextItem.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      rows: _parseChoices(rowsJson),
      columns: _parseChoices(columnsJson),
      min: json['min'],
      max: json['max'],
      step: json['step'],
      multiSelect: json['multiSelect'] == true,
      showLabel: json['showLabel'] != false,
    );
  }

  static List<SurveyChoice> _parseChoices(List<dynamic>? json) {
    if (json == null) return [];
    return json.map((c) {
      if (c is Map<String, dynamic>) {
        return SurveyChoice.fromJson(c);
      }
      return SurveyChoice(value: c.toString(), text: c.toString());
    }).toList();
  }
}

class SurveyChoice {
  final String value;
  final String text;
  final String? imageLink;

  SurveyChoice({required this.value, required this.text, this.imageLink});

  factory SurveyChoice.fromJson(Map<String, dynamic> json) {
    return SurveyChoice(
      value: json['value']?.toString() ?? '',
      text: json['text']?.toString() ?? json['value']?.toString() ?? '',
      imageLink: json['imageLink']?.toString(),
    );
  }
}

class SurveyTextItem {
  final String name;
  final String title;
  final bool isRequired;
  final String? placeholder;
  final String? inputType;

  SurveyTextItem({
    required this.name,
    required this.title,
    this.isRequired = false,
    this.placeholder,
    this.inputType,
  });

  factory SurveyTextItem.fromJson(Map<String, dynamic> json) {
    return SurveyTextItem(
      name: json['name'] ?? '',
      title: json['title'] ?? json['name'] ?? '',
      isRequired: json['isRequired'] == true,
      placeholder: json['placeholder'] ?? json['placeHolder'],
      inputType: json['inputType'],
    );
  }
}

class SurveyPage {
  final String name;
  final String? title;
  final String? description;
  final String? visibleIf;
  final List<SurveyElement> elements;

  SurveyPage({
    required this.name,
    required this.elements,
    this.title,
    this.description,
    this.visibleIf,
  });

  factory SurveyPage.fromJson(Map<String, dynamic> json) {
    final elementsJson = json['elements'] as List<dynamic>? ?? [];
    return SurveyPage(
      name: json['name'] ?? '',
      title: json['title'],
      description: json['description'],
      visibleIf: json['visibleIf'],
      elements: elementsJson
          .map((e) => SurveyElement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
