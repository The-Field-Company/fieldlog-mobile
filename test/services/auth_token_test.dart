import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldlog_mobile/services/auth_service.dart';

/// Build a fake JWT with the given payload claims.
/// JWTs are header.payload.signature — we only need the payload to be valid
/// base64url-encoded JSON. Header and signature can be anything.
String _buildJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"RS256"}')).replaceAll('=', '');
  final body = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  const signature = 'fake_signature';
  return '$header.$body.$signature';
}

void main() {
  group('AuthService.getTokenExp', () {
    test('extracts exp and converts seconds to milliseconds', () {
      // The backend sends exp as Unix seconds. The app needs milliseconds
      // for comparison with DateTime.now().millisecondsSinceEpoch.
      const expSeconds = 1700000000; // 2023-11-14T22:13:20Z
      final token = _buildJwt({'exp': expSeconds, 'username': 'alice'});

      expect(AuthService.getTokenExp(token), expSeconds * 1000);
    });

    test('handles exp as a double (fractional seconds)', () {
      const expSeconds = 1700000000.7;
      final token = _buildJwt({'exp': expSeconds});

      // (1700000000.7 * 1000).toInt() = 1700000000700
      expect(AuthService.getTokenExp(token), 1700000000700);
    });

    test('returns 0 for token with wrong number of parts', () {
      expect(AuthService.getTokenExp('only-one-part'), 0);
      expect(AuthService.getTokenExp('two.parts'), 0);
      expect(AuthService.getTokenExp('a.b.c.d'), 0);
    });

    test('returns 0 for empty string', () {
      expect(AuthService.getTokenExp(''), 0);
    });

    test('returns 0 when payload is not valid base64', () {
      // Three dot-separated parts but the middle one is garbage.
      expect(AuthService.getTokenExp('header.!!!invalid!!!.sig'), 0);
    });

    test('returns 0 when payload JSON has no exp claim', () {
      // Valid base64 JSON but missing the exp field.
      // The code does (json['exp'] as num) which throws on null,
      // caught by the catch block → returns 0.
      final token = _buildJwt({'username': 'alice'});
      expect(AuthService.getTokenExp(token), 0);
    });
  });
}
