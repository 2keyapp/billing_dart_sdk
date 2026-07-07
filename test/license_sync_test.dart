import 'package:billing_dart_sdk/billing_dart_sdk.dart';
import 'package:billing_dart_sdk/src/api/billing_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('shouldPollLicenseEntitlements', () {
    test('false when session is null', () {
      expect(shouldPollLicenseEntitlements(null), isFalse);
    });

    test('false when no seat and no license subscriptions', () {
      final session = BillingAccountSession(
        authTokens: const BillingAuthTokens(accessToken: 'a'),
        userProfile: const AuthUserProfile(subject: 'u'),
        billingStats: PayingPartyBillingStats(
          payingParty: const PayingPartyBillingSummary(
            id: '1',
            organizationName: 'Org',
            billingEmail: 'a@b.com',
          ),
          counts: const BillingCounts(
            subscriptions: SubscriptionStatusCounts(),
            orders: OrderStatusCounts(),
            invoices: InvoiceStatusCounts(),
          ),
          hasAssignedSeatForIdentity: false,
        ),
      );
      expect(shouldPollLicenseEntitlements(session), isFalse);
    });

    test('true when assigned seat flag is set', () {
      final session = BillingAccountSession(
        authTokens: const BillingAuthTokens(accessToken: 'a'),
        userProfile: const AuthUserProfile(subject: 'u'),
        billingStats: PayingPartyBillingStats(
          payingParty: const PayingPartyBillingSummary(
            id: '1',
            organizationName: 'Org',
            billingEmail: 'a@b.com',
          ),
          counts: const BillingCounts(
            subscriptions: SubscriptionStatusCounts(active: 1),
            orders: OrderStatusCounts(),
            invoices: InvoiceStatusCounts(),
          ),
          hasAssignedSeatForIdentity: true,
        ),
      );
      expect(shouldPollLicenseEntitlements(session), isTrue);
    });
  });

  group('BillingApiClient.fetchLicense', () {
    test('returns SyncNotModified on HTTP 304', () async {
      final client = MockClient((request) async {
        expect(request.headers['if-none-match'], '"etag-abc"');
        return http.Response('', 304, headers: {'etag': '"etag-abc"'});
      });
      final api = BillingApiClient(
        baseUrl: 'https://billing.example.com',
        httpClient: client,
      );
      final result = await api.fetchLicense(
        authorizationToken: 'token',
        ifNoneMatch: 'etag-abc',
      );
      expect(result, isA<SyncNotModified>());
      expect((result as SyncNotModified).etag, 'etag-abc');
    });
  });
}
