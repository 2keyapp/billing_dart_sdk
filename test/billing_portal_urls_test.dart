import 'package:billing_dart_sdk/src/auth/billing_portal_urls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BillingPortalUrls', () {
    const urls = BillingPortalUrls(portalBaseUrl: 'https://portal.example.com');

    test('sessionHandoff builds handoff path without token', () {
      expect(
        urls.sessionHandoff().toString(),
        'https://portal.example.com/auth/handoff',
      );
    });

    test('sessionHandoff includes safe redirect path', () {
      expect(
        urls.sessionHandoff(redirectPath: '/subscriptions').toString(),
        'https://portal.example.com/auth/handoff?redirect=%2Fsubscriptions',
      );
    });

    test('sessionHandoff ignores unsafe redirect paths', () {
      expect(
        urls.sessionHandoff(redirectPath: '//evil.example.com').toString(),
        'https://portal.example.com/auth/handoff',
      );
    });
  });
}
