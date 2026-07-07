import 'dart:convert';

import 'package:billing_dart_sdk/src/auth/auth_user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$body.sig';
}

void main() {
  group('AuthUserProfile.fromTokens', () {
    test('merges email and name from id_token when access token only has sub', () {
      final access = _fakeJwt({'sub': 'user-uuid-123'});
      final id = _fakeJwt({
        'sub': 'user-uuid-123',
        'email': 'dev@example.com',
        'name': 'Dev User',
        'picture': 'https://example.com/photo.jpg',
        'email_verified': true,
      });

      final profile = AuthUserProfile.fromTokens(
        accessToken: access,
        idToken: id,
      );

      expect(profile.subject, 'user-uuid-123');
      expect(profile.email, 'dev@example.com');
      expect(profile.name, 'Dev User');
      expect(profile.picture, 'https://example.com/photo.jpg');
      expect(profile.displayName(), 'Dev User');
      expect(profile.accountKey, 'dev@example.com');
    });

    test('prefers access token email when present on both', () {
      final access = _fakeJwt({
        'sub': 'user-uuid-123',
        'email': 'access@example.com',
        'name': 'Access Name',
      });
      final id = _fakeJwt({
        'sub': 'user-uuid-123',
        'email': 'id@example.com',
        'name': 'Id Name',
      });

      final profile = AuthUserProfile.fromTokens(
        accessToken: access,
        idToken: id,
      );

      expect(profile.email, 'access@example.com');
      expect(profile.name, 'Access Name');
    });
  });
}
