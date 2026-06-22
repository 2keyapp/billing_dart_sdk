import '../api/billing_api_client.dart';
import '../billing_client.dart';
import '../sdk.dart';

/// Convenience facade for add-on / plan checkout flows.
///
/// Wraps [BillingClient.checkout] and [BillingSdk.syncFromServer] so consumer
/// apps do not duplicate Stripe session + license refresh logic.
class AddonCheckoutFacade {
  AddonCheckoutFacade(this._client);

  final BillingClient _client;

  /// Preview promo / list pricing before checkout.
  Future<ResolvedCheckoutPricing> resolveDiscounts({
    required int planId,
    required int pricingId,
    String? promoCode,
  }) =>
      _client.checkout.resolveDiscounts(
        ResolveCheckoutDiscountsRequest(
          planId: planId,
          pricingId: pricingId,
          promoCode: promoCode,
        ),
      );

  /// Start a Stripe Checkout session for a plan or add-on purchase.
  Future<CheckoutSessionResult> startCheckout({
    required int planId,
    required int pricingId,
    required String successUrl,
    required String cancelUrl,
    String? promoCode,
  }) =>
      _client.checkout.createSession(
        CreateCheckoutSessionRequest(
          planId: planId,
          pricingId: pricingId,
          successUrl: successUrl,
          cancelUrl: cancelUrl,
          promoCode: promoCode,
        ),
      );

  /// Dev / fallback: fulfill checkout when webhook has not run yet.
  Future<FulfillCheckoutResult> fulfillCheckout({required String sessionId}) =>
      _client.checkout.fulfillSession(
        FulfillCheckoutRequest(sessionId: sessionId),
      );

  /// Refresh signed license JWT after successful checkout.
  Future<SyncResult> syncLicenseAfterPurchase({
    required String authorizationToken,
    String? payingPartyId,
  }) =>
      BillingSdk.syncFromServer(
        authorizationToken: authorizationToken,
        payingPartyId: payingPartyId,
      );
}
