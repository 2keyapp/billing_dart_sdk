import 'package:billing_dart_sdk/src/auth/billing_auth_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BillingOAuthProvidersDocument', () {
    test('parses enabled providers from Better Auth oauth-providers shape', () {
      final doc = BillingOAuthProvidersDocument.fromJson({
        'issuer': 'https://billing.example.com/api/auth',
        'providers': [
          {
            'id': 'google',
            'enabled': true,
            'redirectUri': 'https://billing.example.com/api/auth/callback/google',
            'idpConsole': 'google_cloud',
          },
          {'id': 'microsoft', 'enabled': false},
          {'id': 'apple', 'enabled': true, 'redirectUri': 'https://billing.example.com/api/auth/callback/apple'},
          {'id': 'email', 'enabled': true},
        ],
      });

      expect(doc.issuer, 'https://billing.example.com/api/auth');
      expect(doc.isGoogleEnabled, isTrue);
      expect(doc.isMicrosoftEnabled, isFalse);
      expect(doc.isAppleEnabled, isTrue);
      expect(doc.isEmailEnabled, isTrue);
      expect(doc.enabledProviders, hasLength(3));
      expect(
        doc.enabledProviders.firstWhere((p) => p.id == 'google').redirectUri,
        contains('/callback/google'),
      );
    });
  });
}
