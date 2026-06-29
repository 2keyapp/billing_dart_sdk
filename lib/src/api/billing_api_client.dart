import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../exceptions/billing_sync_error.dart';
import '../logging/sdk_logger.dart';
import '../models/billing_stats.dart';
import '../models/plan.dart';

Map<String, dynamic> _unwrapData(Map<String, dynamic> json) {
  if (json.containsKey('data') && json['data'] is Map<String, dynamic>) {
    return json['data'] as Map<String, dynamic>;
  }
  return json;
}

List<dynamic> _unwrapList(Map<String, dynamic> json) {
  return json['data'] as List<dynamic>? ?? json['items'] as List<dynamic>? ?? [];
}

/// Result of syncing from the Billing API.
sealed class SyncResult {}

class SyncSuccess implements SyncResult {
  const SyncSuccess({required this.signedToken});
  final String signedToken;
}

class SyncFailure implements SyncResult {
  const SyncFailure({required this.message, this.error});
  final String message;
  final BillingSyncError? error;
}

/// Result of ensuring billing context via `GET /api/v1/subscriptions/me`.
sealed class BootstrapResult {
  const BootstrapResult();
}

class BootstrapSuccess extends BootstrapResult {
  const BootstrapSuccess(this.stats);
  final PayingPartyBillingStats stats;
}

class BootstrapFailure extends BootstrapResult {
  const BootstrapFailure({required this.message, this.error});
  final String message;
  final BillingSyncError? error;
}

/// Strips trailing slashes and, if present, a trailing `/api/v1` or legacy
/// `/api/billing` segment so callers may pass the Billing host
/// (`https://billing.example.com`) or a full API base URL.
String normalizeBillingApiBaseUrl(String input) {
  var s = input.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  for (final suffix in const ['/api/v1', '/api/billing']) {
    if (s.toLowerCase().endsWith(suffix)) {
      s = s.substring(0, s.length - suffix.length);
      while (s.endsWith('/')) {
        s = s.substring(0, s.length - 1);
      }
      break;
    }
  }
  return s;
}

/// Minimal HTTP client for SDK routes only (license, bootstrap, public plans).
class BillingApiClient {
  BillingApiClient({required String baseUrl, http.Client? httpClient})
      : _baseUrl = _originWithTrailingSlash(normalizeBillingApiBaseUrl(baseUrl)),
        _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;

  static String _originWithTrailingSlash(String origin) {
    if (origin.isEmpty) return origin;
    return origin.endsWith('/') ? origin : '$origin/';
  }

  /// GET `{origin}/api/v1/license` with billing access token.
  Future<SyncResult> fetchLicense({
    required String authorizationToken,
    String? payingPartyId,
  }) async {
    final raw = authorizationToken.trim();
    if (raw.isEmpty) {
      BillingSdkLogger.warning('fetchLicense: authorization token empty');
      return const SyncFailure(message: 'Authorization token is required.');
    }
    final token = raw.toLowerCase().startsWith('bearer ') ? raw : 'Bearer $raw';
    final uri = Uri.parse('${_baseUrl}api/v1/license');
    final headers = <String, String>{'Authorization': token};
    final party = payingPartyId?.trim();
    if (party != null && party.isNotEmpty) {
      headers['X-Paying-Party-Id'] = party;
    }

    BillingSdkLogger.info('fetchLicense: GET', uri.toString());

    try {
      final response = await _http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>?;
        final rawData = body?['data'];
        final data = rawData is Map<String, dynamic> ? rawData : body;
        final signed =
            data?['signedToken'] ?? data?['signed_token'] ?? data?['token'];

        if (signed is String && signed.isNotEmpty) {
          BillingSdkLogger.success(
            'fetchLicense: received signed token',
            '${signed.length} chars',
          );
          return SyncSuccess(signedToken: signed);
        }

        final err = BillingSyncError(
          kind: BillingSyncErrorKind.invalidResponse,
          userMessage:
              'Invalid response from billing server. Try again or report this issue.',
          technicalDetail: 'fetchLicense: 200 without signedToken',
        );
        return SyncFailure(message: err.userMessage, error: err);
      }

      final err = billingSyncErrorFromHttp(
        statusCode: response.statusCode,
        operation: 'fetchLicense',
        responseBody: response.body,
      );
      return SyncFailure(message: err.userMessage, error: err);
    } catch (e, st) {
      final err = billingSyncErrorFromNetwork(e, operation: 'fetchLicense');
      developer.log('fetchLicense stack', name: 'BillingSdk', error: e, stackTrace: st);
      return SyncFailure(message: err.userMessage, error: err);
    }
  }

  /// GET `{origin}/api/v1/subscriptions/me` — org context for using-party sync.
  Future<BootstrapResult> ensureBillingContext({
    required String authorizationToken,
  }) async {
    final raw = authorizationToken.trim();
    if (raw.isEmpty) {
      return const BootstrapFailure(message: 'Authorization token is required.');
    }
    final token = raw.toLowerCase().startsWith('bearer ') ? raw : 'Bearer $raw';
    final uri = Uri.parse('${_baseUrl}api/v1/subscriptions/me');

    BillingSdkLogger.info('ensureBillingContext: GET', uri.toString());

    try {
      final response = await _http.get(uri, headers: {'Authorization': token});

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final stats = PayingPartyBillingStats.fromJson(_unwrapData(body));
          return BootstrapSuccess(stats);
        }
        return BootstrapFailure(
          message: 'Invalid billing summary response.',
          error: const BillingSyncError(
            kind: BillingSyncErrorKind.invalidResponse,
            userMessage: 'Invalid billing summary response.',
          ),
        );
      }

      final err = billingSyncErrorFromHttp(
        statusCode: response.statusCode,
        operation: 'ensureBillingContext',
        responseBody: response.body,
      );
      return BootstrapFailure(message: err.userMessage, error: err);
    } catch (e, st) {
      final err = billingSyncErrorFromNetwork(e, operation: 'ensureBillingContext');
      developer.log('ensureBillingContext stack', name: 'BillingSdk', error: e, stackTrace: st);
      return BootstrapFailure(message: err.userMessage, error: err);
    }
  }

  /// GET `{origin}/api/v1/plans` — public catalog (no auth).
  Future<List<Plan>> fetchPlans({
    int? productId,
    String? billingInterval,
    bool includeInactive = false,
  }) async {
    final query = <String, String>{
      if (productId != null) 'productId': productId.toString(),
      if (billingInterval != null) 'billingInterval': billingInterval,
      if (includeInactive) 'includeInactive': 'true',
    };
    final uri = Uri.parse('${_baseUrl}api/v1/plans').replace(queryParameters: query);

    BillingSdkLogger.info('fetchPlans: GET', uri.toString());

    try {
      final response = await _http.get(uri);
      if (response.statusCode != 200) {
        BillingSdkLogger.error('fetchPlans: HTTP ${response.statusCode}');
        return [];
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return [];
      return _unwrapList(body)
          .whereType<Map<String, dynamic>>()
          .map(Plan.fromJson)
          .toList();
    } catch (e) {
      BillingSdkLogger.error('fetchPlans: failed', '$e');
      return [];
    }
  }

  void close() => _http.close();
}
