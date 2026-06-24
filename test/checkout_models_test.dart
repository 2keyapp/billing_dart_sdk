import 'package:billing_sdk/billing_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('CreateCheckoutSessionRequest', () {
    test('serializes promoCode when set', () {
      const req = CreateCheckoutSessionRequest(
        planId: 1,
        pricingId: 2,
        successUrl: 'scomm://billing/success',
        cancelUrl: 'scomm://billing/cancel',
        promoCode: 'SAVE10',
      );
      expect(req.toJson()['promoCode'], 'SAVE10');
    });
  });

  group('FulfillCheckoutRequest', () {
    test('only sends sessionId', () {
      const req = FulfillCheckoutRequest(sessionId: 'cs_test');
      expect(req.toJson(), {'sessionId': 'cs_test'});
    });
  });

  group('Plan.fromJson', () {
    test('parses object-shaped featuresJson and addonCode', () {
      final plan = Plan.fromJson({
        'id': 1,
        'productId': 9,
        'name': 'AI Assistant',
        'billingInterval': 'monthly',
        'basePrice': 9.99,
        'currency': 'USD',
        'featuresJson': {
          'addonCode': 'secmail.ai_assistant',
          'features': ['Smart reply'],
        },
      });
      expect(plan.resolvedAddonCode, 'secmail.ai_assistant');
      expect(plan.features, contains('Smart reply'));
    });
  });

  group('billingAddonStatusFromSubscription', () {
    test('maps past_due to grace period', () {
      expect(
        billingAddonStatusFromSubscription('past_due'),
        BillingAddonEntitlementStatus.gracePeriod,
      );
    });
  });
}
