import 'package:flutter_test/flutter_test.dart';
import 'package:fieldlog_mobile/models/form_component.dart';

void main() {
  group('FormComponent.fromJson options parsing', () {
    // Options live at json['data']['values'] — a nested path that is
    // non-obvious. If the backend ever flattens this to json['options'],
    // these tests will catch the breakage.

    test('extracts options from nested data.values structure', () {
      final component = FormComponent.fromJson({
        'type': 'select',
        'key': 'color',
        'label': 'Favorite Color',
        'data': {
          'values': [
            {'label': 'Red', 'value': 'red'},
            {'label': 'Blue', 'value': 'blue'},
          ],
        },
      });

      expect(component.options.length, 2);
      expect(component.options[0].label, 'Red');
      expect(component.options[0].value, 'red');
      expect(component.options[1].label, 'Blue');
      expect(component.options[1].value, 'blue');
    });

    test('returns empty options when data key is absent', () {
      final component = FormComponent.fromJson({
        'type': 'textfield',
        'key': 'name',
        'label': 'Name',
      });
      expect(component.options, isEmpty);
    });

    test('returns empty options when data exists but values key is absent', () {
      final component = FormComponent.fromJson({
        'type': 'select',
        'key': 'q1',
        'label': 'Q1',
        'data': {'other_key': 'something'},
      });
      expect(component.options, isEmpty);
    });
  });

  group('FormComponent.isRequired', () {
    // isRequired uses strict equality: validation == 'required'.
    // This means compound validation strings like 'required|min:3'
    // return false. This is a known limitation worth documenting.

    test('true when validation is exactly "required"', () {
      final component = FormComponent.fromJson({
        'type': 'textfield',
        'key': 'name',
        'label': 'Name',
        'validation': 'required',
      });
      expect(component.isRequired, isTrue);
    });

    test('false when validation is a compound string containing required', () {
      final component = FormComponent.fromJson({
        'type': 'textfield',
        'key': 'name',
        'label': 'Name',
        'validation': 'required|min:3',
      });
      expect(component.isRequired, isFalse);
    });

    test('false when validation is null', () {
      final component = FormComponent.fromJson({
        'type': 'textfield',
        'key': 'name',
        'label': 'Name',
      });
      expect(component.isRequired, isFalse);
    });
  });
}
