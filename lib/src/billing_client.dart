import 'package:dio/dio.dart';
import 'core/billing_dio_client.dart';
import 'core/i_billing_http_client.dart';
import 'core/token_provider.dart';
import 'services/services.dart';

export 'core/token_provider.dart';
export 'exceptions/exceptions.dart';
export 'models/models.dart';
export 'services/services.dart';

/// The single entry-point for the Billing SDK.
///
/// Instantiate once, reuse everywhere.
///
/// ```dart
/// final billing = BillingClient(
///   baseUrl: 'https://api.example.com',
///   tokenProvider: () async => await auth.getToken(),
/// );
///
/// final plans   = await billing.plans.list(billingInterval: 'monthly');
/// final invoice = await billing.invoices.get(42);
/// ```
class BillingClient {
  // ─── Services ─────────────────────────────────────────────────────────────

  final HealthService health;
  final CheckoutService checkout;
  final PayingPartyService payingParties;
  final ProductService products;
  final PlanService plans;
  final SubscriptionService subscriptions;
  final InvoiceService invoices;
  final TaxRuleService taxRules;
  final AffiliateService affiliates;
  final PromoCodeService promoCodes;
  final CommissionService commissions;
  final PaymentMethodService paymentMethods;
  final LicenseService license;

  final IBillingHttpClient _http;

  // ─── Constructors ─────────────────────────────────────────────────────────

  /// Creates a [BillingClient] backed by the built-in Dio transport.
  ///
  /// [baseUrl]        — Billing host or API base, e.g. `https://api.example.com`
  ///                    or `https://api.example.com/api/v1`.
  /// [tokenProvider]  — Async callback returning a valid JWT bearer token (or null for public calls).
  /// [payingPartyId]  — Optional paying party for multi-org context (`X-Paying-Party-Id`).
  /// [defaultHeaders] — Additional headers merged into every request.
  /// [dio]            — Optional pre-configured [Dio] instance for advanced customisation or testing.
  factory BillingClient({
    required String baseUrl,
    TokenProvider? tokenProvider,
    String? payingPartyId,
    Map<String, String> defaultHeaders = const {},
    Dio? dio,
  }) {
    final http = BillingDioClient(
      baseUrl: baseUrl,
      tokenProvider: tokenProvider,
      payingPartyId: payingPartyId,
      defaultHeaders: defaultHeaders,
      dio: dio,
    );
    return BillingClient._fromClient(http);
  }

  /// Creates a [BillingClient] from a custom [IBillingHttpClient].
  ///
  /// Useful for testing: pass in a mock that implements [IBillingHttpClient]
  /// without ever touching the network.
  ///
  /// ```dart
  /// final billing = BillingClient.withClient(MockHttpClient());
  /// ```
  factory BillingClient.withClient(IBillingHttpClient client) =>
      BillingClient._fromClient(client);

  BillingClient._fromClient(IBillingHttpClient http)
      : _http = http,
        health = HealthService(http),
        checkout = CheckoutService(http),
        payingParties = PayingPartyService(http),
        products = ProductService(http),
        plans = PlanService(http),
        subscriptions = SubscriptionService(http),
        invoices = InvoiceService(http),
        taxRules = TaxRuleService(http),
        affiliates = AffiliateService(http),
        promoCodes = PromoCodeService(http),
        commissions = CommissionService(http),
        paymentMethods = PaymentMethodService(http),
        license = LicenseService(http);

  /// Releases the underlying HTTP client. Call when done with the SDK.
  void dispose() => _http.dispose();
}
