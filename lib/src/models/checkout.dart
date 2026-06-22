class CheckoutSessionResult {
  final String url;
  final String sessionId;

  const CheckoutSessionResult({required this.url, required this.sessionId});

  factory CheckoutSessionResult.fromJson(Map<String, dynamic> j) =>
      CheckoutSessionResult(
        url: j['url'] as String,
        sessionId: j['sessionId'] as String,
      );
}

class CreateCheckoutSessionRequest {
  final int planId;
  final int pricingId;
  final String successUrl;
  final String cancelUrl;
  final String? promoCode;

  const CreateCheckoutSessionRequest({
    required this.planId,
    required this.pricingId,
    required this.successUrl,
    required this.cancelUrl,
    this.promoCode,
  });

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'pricingId': pricingId,
        'successUrl': successUrl,
        'cancelUrl': cancelUrl,
        if (promoCode != null && promoCode!.isNotEmpty) 'promoCode': promoCode,
      };
}

class ResolveCheckoutDiscountsRequest {
  final int planId;
  final int pricingId;
  final String? promoCode;

  const ResolveCheckoutDiscountsRequest({
    required this.planId,
    required this.pricingId,
    this.promoCode,
  });

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'pricingId': pricingId,
        if (promoCode != null && promoCode!.isNotEmpty) 'promoCode': promoCode,
      };
}

class ResolvedCheckoutPricing {
  final double grossAmount;
  final double netAmount;
  final double discountAmount;
  final String currency;

  const ResolvedCheckoutPricing({
    required this.grossAmount,
    required this.netAmount,
    required this.discountAmount,
    required this.currency,
  });

  factory ResolvedCheckoutPricing.fromJson(Map<String, dynamic> j) =>
      ResolvedCheckoutPricing(
        grossAmount: (j['grossAmount'] as num).toDouble(),
        netAmount: (j['netAmount'] as num).toDouble(),
        discountAmount: (j['discountAmount'] as num).toDouble(),
        currency: j['currency'] as String? ?? 'USD',
      );
}

class FulfillCheckoutRequest {
  final String sessionId;

  const FulfillCheckoutRequest({required this.sessionId});

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
      };
}

class FulfillCheckoutResult {
  final bool fulfilled;
  final String? message;

  const FulfillCheckoutResult({required this.fulfilled, this.message});

  factory FulfillCheckoutResult.fromJson(Map<String, dynamic> j) =>
      FulfillCheckoutResult(
        fulfilled: j['subscriptionId'] != null || j['fulfilled'] == true,
        message: j['message'] as String?,
      );
}
