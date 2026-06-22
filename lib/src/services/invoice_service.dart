import '../core/i_billing_http_client.dart';
import '../models/models.dart';
import 'service_helpers.dart';

class InvoiceService {
  final IBillingHttpClient _client;
  InvoiceService(this._client);

  Future<List<Invoice>> listMine({
    int limit = 50,
    int offset = 0,
    String? status,
  }) async {
    final json = await _client.get('/invoices/me', query: {
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (status != null) 'status': status,
    });
    return unwrapList(json)
        .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Invoice> get(int id) async {
    final json = await _client.get('/invoices/$id');
    return Invoice.fromJson(unwrapData(json));
  }

  Future<Invoice> create(CreateInvoiceRequest req) async {
    final json = await _client.post('/invoices', body: req.toJson());
    return Invoice.fromJson(unwrapData(json));
  }

  Future<Invoice> update(int id, UpdateInvoiceRequest req) async {
    final json = await _client.patch('/invoices/$id', body: req.toJson());
    return Invoice.fromJson(unwrapData(json));
  }

  Future<Invoice> finalize(int id) async {
    final json = await _client.post('/invoices/$id/finalize');
    return Invoice.fromJson(unwrapData(json));
  }

  Future<Invoice> markSent(int id) async {
    final json = await _client.post('/invoices/$id/mark-sent');
    return Invoice.fromJson(unwrapData(json));
  }

  Future<Invoice> generateRecurring(int subscriptionId) async {
    final json = await _client.post('/invoices/generate/recurring',
        body: {'subscriptionId': subscriptionId});
    return Invoice.fromJson(unwrapData(json));
  }

  Future<Invoice> generateProration(GenerateProrationRequest req) async {
    final json =
        await _client.post('/invoices/generate/proration', body: req.toJson());
    return Invoice.fromJson(unwrapData(json));
  }

  Future<List<Invoice>> listBySubscription(int subscriptionId) async {
    final json = await _client.get('/invoices/subscription/$subscriptionId');
    return unwrapList(json)
        .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Invoice>> listByPayingParty(int payingPartyId) async {
    final json = await _client.get('/invoices/paying-party/$payingPartyId');
    return unwrapList(json)
        .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
