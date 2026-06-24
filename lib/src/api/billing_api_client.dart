import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../logging/sdk_logger.dart';
import '../models/payment_method.dart';
import '../exceptions/billing_sync_error.dart';

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
  const BootstrapSuccess();
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

/// HTTP client for the Billing API (sync and optional public-key fetch).
class BillingApiClient {
  BillingApiClient({required String baseUrl})
      : _baseUrl =
            _originWithTrailingSlash(normalizeBillingApiBaseUrl(baseUrl));

  final String _baseUrl;

  static String _originWithTrailingSlash(String origin) {
    if (origin.isEmpty) return origin;
    return origin.endsWith('/') ? origin : '$origin/';
  }

  /// GET `{origin}/api/v1/license` with `Authorization: Bearer <token>`.
  ///
  /// [authorizationToken] must be an **AuthAPI** access token (audience must
  /// include Billing). Do not send raw IdP (e.g. Google) tokens.
  ///
  /// When [payingPartyId] is non-null and non-empty, sends
  /// `X-Paying-Party-Id` for multi-org / seat-holder context. Omit or pass null
  /// for the default payer.
  ///
  /// **HTTP errors:** [SyncFailure.message] is suitable to show the user.
  /// **401** — missing/expired/invalid token; **403** — not allowed for this
  /// route or [payingPartyId]; **404** — no billing account (when applicable).
  ///
  /// Response body: map with `signedToken` (JWT string), possibly under `data`.
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
      final response = await http.get(uri, headers: headers);

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

        BillingSdkLogger.error(
          'fetchLicense: 200 but no signedToken in response',
          response.body.length > 200
              ? '${response.body.substring(0, 200)}...'
              : response.body,
        );
        final err = BillingSyncError(
          kind: BillingSyncErrorKind.invalidResponse,
          userMessage: 'Invalid response from billing server. Try again or report this issue.',
          technicalDetail: 'fetchLicense: 200 without signedToken',
        );
        return SyncFailure(message: err.userMessage, error: err);
      }

      final err = billingSyncErrorFromHttp(
        statusCode: response.statusCode,
        operation: 'fetchLicense',
        responseBody: response.body,
      );
      BillingSdkLogger.error('fetchLicense: HTTP ${response.statusCode}', err.technicalDetail);
      return SyncFailure(message: err.userMessage, error: err);
    } catch (e, st) {
      final err = billingSyncErrorFromNetwork(e, operation: 'fetchLicense');
      BillingSdkLogger.error('fetchLicense: request failed', err.technicalDetail ?? '$e');
      developer.log(
        'fetchLicense stack',
        name: 'BillingSdk',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return SyncFailure(message: err.userMessage, error: err);
    }
  }

  /// GET `{origin}/api/v1/subscriptions/me` — ensures billing account context
  /// exists before license sync.
  Future<BootstrapResult> ensureBillingContext({
    required String authorizationToken,
  }) async {
    final raw = authorizationToken.trim();
    if (raw.isEmpty) {
      return const BootstrapFailure(
        message: 'Authorization token is required.',
      );
    }
    final token = raw.toLowerCase().startsWith('bearer ') ? raw : 'Bearer $raw';
    final uri = Uri.parse('${_baseUrl}api/v1/subscriptions/me');

    BillingSdkLogger.info('ensureBillingContext: GET', uri.toString());

    try {
      final response = await http.get(uri, headers: {'Authorization': token});

      if (response.statusCode == 200) {
        BillingSdkLogger.success('ensureBillingContext: ok');
        return const BootstrapSuccess();
      }

      final err = billingSyncErrorFromHttp(
        statusCode: response.statusCode,
        operation: 'ensureBillingContext',
        responseBody: response.body,
      );
      BillingSdkLogger.error(
        'ensureBillingContext: HTTP ${response.statusCode}',
        err.technicalDetail,
      );
      return BootstrapFailure(message: err.userMessage, error: err);
    } catch (e, st) {
      final err = billingSyncErrorFromNetwork(e, operation: 'ensureBillingContext');
      BillingSdkLogger.error(
        'ensureBillingContext: request failed',
        err.technicalDetail ?? '$e',
      );
      developer.log(
        'ensureBillingContext stack',
        name: 'BillingSdk',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return BootstrapFailure(message: err.userMessage, error: err);
    }
  }

  /// GET `{origin}/api/v1/payment-methods` — returns the list of saved
  /// payment methods for the authenticated user.
  ///
  /// Returns an empty list on any non-200 or parse error so callers can always
  /// safely iterate the result.
  Future<List<PaymentMethod>> fetchPaymentMethods({
    required String authorizationToken,
  }) async {
    final raw = authorizationToken.trim();
    if (raw.isEmpty) {
      BillingSdkLogger.warning('fetchPaymentMethods: token empty');
      return [];
    }
    final token = raw.toLowerCase().startsWith('bearer ') ? raw : 'Bearer $raw';
    final uri = Uri.parse('${_baseUrl}api/v1/payment-methods');

    BillingSdkLogger.info('fetchPaymentMethods: GET', uri.toString());

    try {
      final response = await http.get(uri, headers: {'Authorization': token});
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final list = body is List
            ? body
            : (body is Map ? (body['data'] as List?) ?? [] : []);
        return list
            .whereType<Map<String, dynamic>>()
            .map(PaymentMethod.fromJson)
            .toList();
      }
      BillingSdkLogger.error(
        'fetchPaymentMethods: unexpected status',
        '${response.statusCode}',
      );
      return [];
    } catch (e) {
      BillingSdkLogger.error('fetchPaymentMethods: request failed', '$e');
      return [];
    }
  }
}
