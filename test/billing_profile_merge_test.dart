import 'dart:convert';

import 'package:billing_dart_sdk/billing_dart_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

String _fakeJwt(Map<String, dynamic> claims) {
  String b64(Object value) {
    final bytes = utf8.encode(value is String ? value : jsonEncode(value));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  return '${b64('{"alg":"none","typ":"JWT"}')}.${b64(claims)}.sig';
}

BillingAuthSessionUser _sessionUser({
  required String id,
  required String email,
  String name = 'Ada',
}) {
  return BillingAuthSessionUser(
    id: id,
    email: email,
    name: name,
    image: null,
    emailVerified: true,
  );
}

void main() {
  group('billingProfileFromSignIn', () {
    test('uses session user when JWT has no sub claim', () {
      final access = _fakeJwt({'email': 'jwt@example.com'});
      final tokens = BillingAuthTokens(accessToken: access);
      final sessionUser =
          _sessionUser(id: 'user-42', email: 'ada@example.com', name: 'Ada');

      final profile = billingProfileFromSignIn(
        sessionUser: sessionUser,
        tokens: tokens,
        loginProvider: 'google',
      );

      expect(profile.subject, 'user-42');
      expect(profile.email, 'ada@example.com');
      expect(profile.name, 'Ada');
      expect(profile.identityProvider, 'google');
    });

    test('prefers JWT sub/email when present', () {
      final access = _fakeJwt({
        'sub': 'jwt-sub',
        'email': 'jwt@example.com',
        'name': 'Jwt Name',
      });
      final tokens = BillingAuthTokens(accessToken: access);
      final sessionUser =
          _sessionUser(id: 'user-42', email: 'ada@example.com');

      final profile = billingProfileFromSignIn(
        sessionUser: sessionUser,
        tokens: tokens,
        loginProvider: 'microsoft',
      );

      expect(profile.subject, 'jwt-sub');
      expect(profile.email, 'jwt@example.com');
      expect(profile.name, 'Jwt Name');
    });
  });

  group('billingTokensWithProfileIdToken', () {
    test('attaches id_token so fromTokens can resolve missing sub', () {
      final access = _fakeJwt({'aud': 'billing'});
      final tokens = BillingAuthTokens(accessToken: access);
      const profile = AuthUserProfile(
        subject: 'user-42',
        email: 'ada@example.com',
        name: 'Ada',
      );

      final enriched = billingTokensWithProfileIdToken(
        tokens: tokens,
        profile: profile,
      );

      expect(enriched.idToken, isNotNull);
      final resolved = AuthUserProfile.fromTokens(
        accessToken: enriched.accessToken,
        idToken: enriched.idToken,
      );
      expect(resolved.subject, 'user-42');
      expect(resolved.email, 'ada@example.com');
    });
  });

  group('BillingAuthRedirect', () {
    test('desktop uses loopback; mobile uses deep link', () {
      expect(
        BillingAuthRedirect.resolveSocialCallbackUrl(
          deepLinkScheme: 'myapp',
          isMobile: false,
          desktopLoopbackUri: 'http://localhost:8085/auth-callback',
        ),
        'http://localhost:8085/auth-callback',
      );
      expect(
        BillingAuthRedirect.resolveSocialCallbackUrl(
          deepLinkScheme: 'myapp',
          isMobile: true,
          desktopLoopbackUri: 'http://localhost:8085/auth-callback',
        ),
        'myapp://auth/callback',
      );
    });
  });
}
