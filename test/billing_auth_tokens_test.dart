import 'dart:convert';

import 'package:billing_dart_sdk/src/auth/billing_auth_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BillingAuthTokens.fromJwtPluginToken', () {
    test('parses exp from JWT payload', () {
      final exp =
          DateTime.now().toUtc().add(const Duration(minutes: 15)).millisecondsSinceEpoch ~/
          1000;
      final token = _fakeJwt({'sub': 'user-1', 'exp': exp});

      final tokens = BillingAuthTokens.fromJwtPluginToken(token);
      expect(tokens.accessToken, token);
      expect(tokens.expiresInSeconds, isNotNull);
      expect(tokens.expiresInSeconds, greaterThan(0));
    });
  });
}

String _fakeJwt(Map<String, Object?> payload) {
  String segment(Map<String, Object?> value) {
    return base64Url
        .encode(utf8.encode(jsonEncode(value)))
        .replaceAll('=', '');
  }

  return '${segment({'alg': 'HS256'})}.${segment(payload)}.signature';
}
