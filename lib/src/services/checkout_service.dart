import '../core/i_billing_http_client.dart';
import '../models/models.dart';
import 'service_helpers.dart';

class CheckoutService {
  final IBillingHttpClient _client;
  CheckoutService(this._client);

  Future<CheckoutSessionResult> createSession(
      CreateCheckoutSessionRequest req) async {
    final json = await _client.post('/checkout/checkout-session',
        body: req.toJson());
    final data = unwrapData(json);
    return CheckoutSessionResult.fromJson(data);
  }

  Future<ResolvedCheckoutPricing> resolveDiscounts(
      ResolveCheckoutDiscountsRequest req) async {
    final json = await _client.post('/checkout/discounts', body: req.toJson());
    final data = unwrapData(json);
    return ResolvedCheckoutPricing.fromJson(data);
  }

  Future<FulfillCheckoutResult> fulfillSession(
      FulfillCheckoutRequest req) async {
    final json = await _client.post('/checkout/fulfill', body: req.toJson());
    final data = unwrapData(json);
    return FulfillCheckoutResult.fromJson(data);
  }
}
