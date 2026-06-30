import 'package:billing_dart_sdk/src/auth/billing_auth_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BillingOAuthProvidersDocument', () {
    test('parses enabled providers from server shape', () {
      final doc = BillingOAuthProvidersDocument.fromJson({
        'issuer': 'https://billing.example.com/api/auth',
        'providers': [
          {
            'id': 'google',
            'enabled': true,
            'authorizedRedirectUris': ['https://cb/oauth/google/callback'],
            'idpConsole': 'google_cloud',
          },
          {'id': 'microsoft', 'enabled': false},
          {'id': 'email', 'enabled': true},
        ],
      });

      expect(doc.isGoogleEnabled, isTrue);
      expect(doc.isMicrosoftEnabled, isFalse);
      expect(doc.isEmailEnabled, isTrue);
      expect(doc.enabledProviders, hasLength(2));
    });
  });

  group('BillingOpenIdConfiguration', () {
    test('parses OIDC discovery document', () {
      final cfg = BillingOpenIdConfiguration.fromJson({
        'issuer': 'https://billing.example.com/api/auth',
        'authorization_endpoint': 'https://billing.example.com/api/auth/authorize',
        'token_endpoint': 'https://billing.example.com/api/auth/token',
        'code_challenge_methods_supported': ['S256'],
        'grant_types_supported': ['authorization_code', 'refresh_token'],
      });

      expect(cfg.supportsPkceS256, isTrue);
      expect(cfg.grantTypesSupported, contains('authorization_code'));
    });
  });
}
