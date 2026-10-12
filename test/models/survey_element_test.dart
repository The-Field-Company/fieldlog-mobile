import 'package:flutter_test/flutter_test.dart';
import 'package:fieldlog_mobile/models/survey_element.dart';

void main() {
  group('SurveyElement._parseChoices', () {
    // SurveyJS sends choices in two formats depending on how the form was
    // built. Object format: [{"value":"a","text":"Alpha"}]. Primitive format:
    // ["a","b","c"]. The parser must handle both, or dropdowns render empty.

    test('parses object-format choices with value and text', () {
      final element = SurveyElement.fromJson({
        'type': 'dropdown',
        'name': 'color',
        'choices': [
          {'value': 'r', 'text': 'Red'},
          {'value': 'g', 'text': 'Green'},
        ],
      });

      expect(element.choices.length, 2);
      expect(element.choices[0].value, 'r');
      expect(element.choices[0].text, 'Red');
      expect(element.choices[1].value, 'g');
      expect(element.choices[1].text, 'Green');
    });

    test('parses primitive-format choices (bare strings)', () {
      final element = SurveyElement.fromJson({
        'type': 'dropdown',
        'name': 'color',
        'choices': ['Red', 'Green', 'Blue'],
      });

      expect(element.choices.length, 3);
      // Primitive choices use the value as both value and text.
      expect(element.choices[0].value, 'Red');
      expect(element.choices[0].text, 'Red');
    });

    test('parses primitive-format choices (bare integers)', () {
      final element = SurveyElement.fromJson({
        'type': 'dropdown',
        'name': 'rating',
        'choices': [1, 2, 3, 4, 5],
      });

      expect(element.choices.length, 5);
      expect(element.choices[0].value, '1');
      expect(element.choices[0].text, '1');
    });

    test('returns empty list when choices key is absent', () {
      final element = SurveyElement.fromJson({
        'type': 'text',
        'name': 'q1',
      });
      expect(element.choices, isEmpty);
    });
  });

  group('SurveyElement field name fallbacks', () {
    // SurveyJS changed key names across versions. These tests protect
    // the compatibility logic that handles both old and new key names.

    test('title falls back to name when title is absent', () {
      final element = SurveyElement.fromJson({
        'type': 'text',
        'name': 'full_name',
        // no 'title' key
      });
      expect(element.title, 'full_name');
    });

    test('title uses title when both title and name exist', () {
      final element = SurveyElement.fromJson({
        'type': 'text',
        'name': 'full_name',
        'title': 'What is your full name?',
      });
      expect(element.title, 'What is your full name?');
    });

    test('hasOther detects legacy hasOther key', () {
      final element = SurveyElement.fromJson({
        'type': 'radiogroup',
        'name': 'q1',
        'hasOther': true,
      });
      expect(element.hasOther, isTrue);
    });

    test('hasOther detects newer showOtherItem key', () {
      final element = SurveyElement.fromJson({
        'type': 'radiogroup',
        'name': 'q1',
        'showOtherItem': true,
      });
      expect(element.hasOther, isTrue);
    });

    test('hasOther is false when neither key is present', () {
      final element = SurveyElement.fromJson({
        'type': 'radiogroup',
        'name': 'q1',
      });
      expect(element.hasOther, isFalse);
    });

    test('placeholder falls back to placeHolder (capital H)', () {
      final element = SurveyElement.fromJson({
        'type': 'text',
        'name': 'q1',
        'placeHolder': 'Enter text...',
      });
      expect(element.placeholder, 'Enter text...');
    });

    test('placeholder prefers lowercase key when both exist', () {
      final element = SurveyElement.fromJson({
        'type': 'text',
        'name': 'q1',
        'placeholder': 'preferred',
        'placeHolder': 'fallback',
      });
      expect(element.placeholder, 'preferred');
    });
  });

  group('SurveyElement.showLabel default', () {
    // showLabel uses != false, not == true. This means null/absent/1/"yes"
    // all evaluate to true. Only explicit false turns it off.

    test('defaults to true when key is absent', () {
      final element = SurveyElement.fromJson({
        'type': 'imagepicker',
        'name': 'q1',
      });
      expect(element.showLabel, isTrue);
    });

    test('is false only when explicitly set to false', () {
      final element = SurveyElement.fromJson({
        'type': 'imagepicker',
        'name': 'q1',
        'showLabel': false,
      });
      expect(element.showLabel, isFalse);
    });

    test('is true when set to a non-false value like null', () {
      final element = SurveyElement.fromJson({
        'type': 'imagepicker',
        'name': 'q1',
        'showLabel': null,
      });
      expect(element.showLabel, isTrue);
    });
  });

  group('SurveyElement recursive panels', () {
    test('parses panel with nested elements', () {
      final panel = SurveyElement.fromJson({
        'type': 'panel',
        'name': 'contact_info',
        'title': 'Contact Information',
        'elements': [
          {'type': 'text', 'name': 'email', 'title': 'Email'},
          {'type': 'text', 'name': 'phone', 'title': 'Phone'},
        ],
      });

      expect(panel.type, 'panel');
      expect(panel.elements.length, 2);
      expect(panel.elements[0].name, 'email');
      expect(panel.elements[1].name, 'phone');
    });

    test('parses two levels of nesting (panel within panel)', () {
      final outer = SurveyElement.fromJson({
        'type': 'panel',
        'name': 'outer',
        'elements': [
          {
            'type': 'panel',
            'name': 'inner',
            'elements': [
              {'type': 'text', 'name': 'deep_field'},
            ],
          },
        ],
      });

      expect(outer.elements.length, 1);
      expect(outer.elements[0].type, 'panel');
      expect(outer.elements[0].elements.length, 1);
      expect(outer.elements[0].elements[0].name, 'deep_field');
    });
  });

  group('SurveyChoice', () {
    test('text falls back to value when text is missing', () {
      // The UI renders choice.text, not choice.value. If text is null
      // and there is no fallback, the dropdown shows empty strings.
      final choice = SurveyChoice.fromJson({'value': 'opt_a'});
      expect(choice.text, 'opt_a');
      expect(choice.value, 'opt_a');
    });

    test('numeric value is converted to string', () {
      final choice = SurveyChoice.fromJson({'value': 42, 'text': 'Answer'});
      expect(choice.value, '42');
      expect(choice.text, 'Answer');
    });

    test('preserves imageLink when present', () {
      final choice = SurveyChoice.fromJson({
        'value': 'lion',
        'text': 'Lion',
        'imageLink': 'https://example.com/lion.jpg',
      });
      expect(choice.imageLink, 'https://example.com/lion.jpg');
    });
  });

  group('SurveyTextItem', () {
    test('title falls back to name when absent', () {
      final item = SurveyTextItem.fromJson({'name': 'first_name'});
      expect(item.title, 'first_name');
    });

    test('placeholder falls back to placeHolder (capital H)', () {
      final item = SurveyTextItem.fromJson({
        'name': 'q1',
        'placeHolder': 'Enter here',
      });
      expect(item.placeholder, 'Enter here');
    });
  });

  group('SurveyPage', () {
    test('parses page with elements', () {
      final page = SurveyPage.fromJson({
        'name': 'page1',
        'title': 'Personal Info',
        'description': 'Enter your details',
        'elements': [
          {'type': 'text', 'name': 'name', 'title': 'Name'},
          {'type': 'text', 'name': 'email', 'title': 'Email'},
        ],
      });

      expect(page.name, 'page1');
      expect(page.title, 'Personal Info');
      expect(page.description, 'Enter your details');
      expect(page.elements.length, 2);
      expect(page.elements[0].name, 'name');
    });

    test('handles page with visibleIf expression', () {
      final page = SurveyPage.fromJson({
        'name': 'page2',
        'visibleIf': "{role} = 'admin'",
        'elements': [],
      });

      expect(page.visibleIf, "{role} = 'admin'");
      expect(page.elements, isEmpty);
    });

    test('handles missing elements key without crashing', () {
      final page = SurveyPage.fromJson({'name': 'empty_page'});
      expect(page.elements, isEmpty);
    });
  });
}
