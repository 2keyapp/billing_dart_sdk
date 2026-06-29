import '../api/billing_api_client.dart';
import '../models/plan.dart';

/// Monthly and annual public plan listings for in-app catalog UI.
class PlanCatalog {
  const PlanCatalog({
    required this.monthly,
    required this.annual,
  });

  final List<Plan> monthly;
  final List<Plan> annual;

  List<Plan> get all => [...monthly, ...annual];

  bool get isEmpty => monthly.isEmpty && annual.isEmpty;

  /// Loads public catalog plans grouped by billing interval (no auth).
  static Future<PlanCatalog> load(
    BillingApiClient client, {
    int? productId,
    bool includeInactive = false,
  }) async {
    final monthly = await client.fetchPlans(
      productId: productId,
      billingInterval: BillingInterval.monthly,
      includeInactive: includeInactive,
    );
    final annual = await client.fetchPlans(
      productId: productId,
      billingInterval: BillingInterval.annual,
      includeInactive: includeInactive,
    );
    return PlanCatalog(monthly: monthly, annual: annual);
  }
}
