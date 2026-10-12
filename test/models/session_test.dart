import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldlog_mobile/models/session.dart';

// Simulate what jsonDecode produces: all maps are Map<String, dynamic>.
// Dart map literals in tests produce Map<dynamic, dynamic> when the
// compiler can't infer the type, which would cause false type errors.
Map<String, dynamic> _json(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void main() {
  group('Session.fromJson', () {
    test('parses a complete API response correctly', () {
      final session = Session.fromJson(_json({
        'id': 42,
        'name': 'Bird Count',
        'description': 'Weekly bird survey',
        'form_config': {
          'form_mode': 'surveyjs',
          'track_location': true,
          'schema': {'pages': []},
        },
        'is_active': true,
        'is_public': false,
        'created_at': '2026-01-15T10:00:00Z',
      }));

      expect(session.id, 42);
      expect(session.name, 'Bird Count');
      expect(session.description, 'Weekly bird survey');
      expect(session.formMode, 'surveyjs');
      expect(session.trackLocation, isTrue);
      expect(session.isActive, isTrue);
      expect(session.isPublic, isFalse);
      expect(session.createdAt, '2026-01-15T10:00:00Z');
    });

    test('throws when id is null — no safe default for a primary key', () {
      // id has no ?? fallback in fromJson. This is intentional: a session
      // without an id is invalid and should fail loudly at parse time,
      // not silently propagate null through the app.
      expect(
        () => Session.fromJson(_json({
          'id': null,
          'name': 'Test',
          'form_config': {},
        })),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws when id is missing entirely', () {
      expect(
        () => Session.fromJson(_json({
          'name': 'Test',
          'form_config': {},
        })),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('Session computed getters', () {
    test('formMode defaults to formkit when form_config is empty', () {
      // This default determines which renderer loads. If it changes,
      // every session without an explicit form_mode renders differently.
      final session = Session.fromJson(_json({'id': 1, 'form_config': {}}));
      expect(session.formMode, 'formkit');
    });

    test('trackLocation requires exactly true, not truthy values', () {
      // Uses == true, so integers, strings, etc. are all false.
      // This protects against accidental GPS activation from bad data.
      final withTrue = Session.fromJson(_json({
        'id': 1,
        'form_config': {'track_location': true},
      }));
      final withOne = Session.fromJson(_json({
        'id': 1,
        'form_config': {'track_location': 1},
      }));
      final withString = Session.fromJson(_json({
        'id': 1,
        'form_config': {'track_location': 'yes'},
      }));
      final withMissing = Session.fromJson(_json({
        'id': 1,
        'form_config': {},
      }));

      expect(withTrue.trackLocation, isTrue);
      expect(withOne.trackLocation, isFalse);
      expect(withString.trackLocation, isFalse);
      expect(withMissing.trackLocation, isFalse);
    });

    test('components returns empty list when form_config has no components key', () {
      // Downstream code iterates this list — null would crash.
      final session = Session.fromJson(_json({'id': 1, 'form_config': {}}));
      expect(session.components, isEmpty);
      expect(session.components, isA<List>());
    });

    test('schema returns null when form_config has no schema key', () {
      // SurveyJS renderer checks for null to know if schema is available.
      final session = Session.fromJson(_json({'id': 1, 'form_config': {}}));
      expect(session.schema, isNull);
    });
  });
}
