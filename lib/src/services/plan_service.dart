import '../core/i_billing_http_client.dart';
import '../models/models.dart';
import 'service_helpers.dart';

class PlanService {
  final IBillingHttpClient _client;
  PlanService(this._client);

  Future<List<Plan>> list({
    int? productId,
    String? billingInterval,
    bool includeInactive = false,
  }) async {
    final json = await _client.get('/plans', query: {
      if (productId != null) 'productId': productId.toString(),
      if (billingInterval != null) 'billingInterval': billingInterval,
      if (includeInactive) 'includeInactive': 'true',
    }, requiresAuth: false);
    return unwrapList(json)
        .map((e) => Plan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Plan> get(int id) async {
    final json = await _client.get('/plans/$id');
    return Plan.fromJson(unwrapData(json));
  }

  Future<List<Pricing>> getPricings(int planId) async {
    final json =
        await _client.get('/plans/$planId/pricings', requiresAuth: false);
    return unwrapList(json)
        .map((e) => Pricing.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Plan> create(CreatePlanRequest req) async {
    final json = await _client.post('/plans', body: req.toJson());
    return Plan.fromJson(unwrapData(json));
  }

  Future<Plan> update(int id, UpdatePlanRequest req) async {
    final json = await _client.patch('/plans/$id', body: req.toJson());
    return Plan.fromJson(unwrapData(json));
  }

  Future<void> delete(int id) async {
    await _client.delete('/plans/$id');
  }
}
