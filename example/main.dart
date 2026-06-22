import 'package:billing_sdk/billing_sdk.dart';

Future<void> main() async {
  // ─── 1. Initialize the client ───────────────────────────────────────────
  final billing = BillingClient(
    baseUrl: 'http://localhost:3000',
    tokenProvider: () async {
      // Replace with your real auth token retrieval logic:
      // e.g. return await authService.getAccessToken();
      return 'your-jwt-token-here';
    },
  );

  try {
    // ─── 2. Health check ────────────────────────────────────────────────
    final health = await billing.health.check();
    print('API status: ${health.status} at ${health.timestamp}');

    // ─── 3. Browse products and plans ──────────────────────────────────
    final products = await billing.products.list();
    print('Products: ${products.map((p) => p.name).join(', ')}');

    final plans = await billing.plans.list(
      billingInterval: 'monthly',
      isActive: true,
    );
    print(
        'Plans: ${plans.map((p) => '${p.name} (${p.basePrice} ${p.currency})').join(', ')}');

    // ─── 4. Create a paying party (billing account) ─────────────────────
    final party = await billing.payingParties.create(
      CreatePayingPartyRequest(
        identityProvider: 'auth0',
        identitySubject: 'auth0|user123',
        organizationName: 'Acme Corp',
        billingEmail: 'billing@acme.com',
        billingAddress: BillingAddress(
          line1: '123 Main St',
          city: 'San Francisco',
          state: 'CA',
          postalCode: '94102',
          country: 'US',
        ),
      ),
    );
    print('Created paying party: ${party.id} — ${party.organizationName}');

    // ─── 5. Create a checkout session ───────────────────────────────────
    final session = await billing.checkout.createSession(
      CreateCheckoutSessionRequest(
        planId: plans.first.id,
        pricingId: 1,
        successUrl: 'https://yourapp.com/success',
        cancelUrl: 'https://yourapp.com/cancel',
      ),
    );
    print('Checkout URL: ${session.url}');

    // ─── 6. Create a subscription ───────────────────────────────────────
    final sub = await billing.subscriptions.create(
      CreateSubscriptionRequest(
        payingPartyId: int.parse(party.id),
        pricingId: 1,
        planId: plans.first.id,
        paymentProvider: 'stripe',
        userPartyEmail: 'user@acme.com',
        assignedIdentityProvider: 'auth0',
        assignedIdentitySubject: 'auth0|user123',
      ),
    );
    print('Subscription created: ${sub.id}, status: ${sub.status}');

    // ─── 7. Generate a recurring invoice ────────────────────────────────
    final invoice = await billing.invoices.generateRecurring(sub.id);
    print('Invoice #${invoice.id}: ${invoice.amount} ${invoice.currency}');

    // ─── 8. Finalize and send the invoice ───────────────────────────────
    final finalized = await billing.invoices.finalize(invoice.id);
    print('Invoice finalized, status: ${finalized.status.name}');

    // ─── 9. Validate a promo code ───────────────────────────────────────
    final validation = await billing.promoCodes.validate('SAVE20');
    print('Promo validation: $validation');

    // ─── 10. Get billing license ─────────────────────────────────────────
    final billingLicense = await billing.license.getBillingLicense();
    print(
        'License token (first 30 chars): ${billingLicense.signedToken.substring(0, 30)}…');

    // ─── 11. Tax calculation ─────────────────────────────────────────────
    final taxes = await billing.taxRules.calculate(
      CalculateTaxesRequest(
        jurisdiction: 'US-CA',
        productId: products.first.id,
        lineItems: [
          TaxLineItem(
              type: 'recurring', description: 'Monthly sub', amount: 49.99),
        ],
      ),
    );
    print('Tax calculation: $taxes');
  } on BillingApiException catch (e) {
    print('API error ${e.statusCode}: ${e.message}');
  } on BillingNetworkException catch (e) {
    print('Network error: ${e.message}');
  } finally {
    billing.dispose();
  }
}
