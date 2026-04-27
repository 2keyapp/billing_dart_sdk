import 'dart:convert';
import 'dart:developer' as developer;

import 'package:billing_flutter_sdk/src/logging/sdk_logger.dart';
import 'package:http/http.dart' as http;

/// Result of syncing from the Billing API.
sealed class SyncResult {}

class SyncSuccess implements SyncResult {
  const SyncSuccess({required this.signedToken});
  final String signedToken;
}

class SyncFailure implements SyncResult {
  const SyncFailure({required this.message});
  final String message;
}

/// Strips trailing slashes and, if present, a trailing `/api/billing` segment so
/// callers may pass either the Billing host (`https://billing.example.com`) or
/// the full API base (`https://billing.example.com/api/billing`).
String normalizeBillingApiBaseUrl(String input) {
  var s = input.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  const suffix = '/api/billing';
  if (s.toLowerCase().endsWith(suffix)) {
    s = s.substring(0, s.length - suffix.length);
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
  }
  return s;
}

/// HTTP client for the Billing API (sync and optional public-key fetch).
class BillingApiClient {
  BillingApiClient({required String baseUrl})
    : _baseUrl = _originWithTrailingSlash(normalizeBillingApiBaseUrl(baseUrl));

  final String _baseUrl;

  static String _originWithTrailingSlash(String origin) {
    if (origin.isEmpty) return origin;
    return origin.endsWith('/') ? origin : '$origin/';
  }

  /// GET `{origin}/api/billing/license` with `Authorization: Bearer <token>`.
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
    final uri = Uri.parse('${_baseUrl}api/billing/license');
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
        final signed = data?['signedToken'] ?? data?['signed_token'] ?? data?['token'];

        if (signed is String && signed.isNotEmpty) {
          BillingSdkLogger.success('fetchLicense: received signed token', '${signed.length} chars');
          return SyncSuccess(signedToken: signed);
        }

        BillingSdkLogger.error('fetchLicense: 200 but no signedToken in response', response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body);
        return const SyncFailure(
          message: 'Sync failed. Invalid response from server.',
        );
      }

      if (response.statusCode == 400) {
        BillingSdkLogger.error('fetchLicense: 400 Bad request');
        return const SyncFailure(message: 'Bad request. Check your token.');
      }

      if (response.statusCode == 401) {
        BillingSdkLogger.error('fetchLicense: 401 Unauthorized');
        return const SyncFailure(
          message: 'Session expired or invalid. Please sign in again.',
        );
      }

      if (response.statusCode == 403) {
        BillingSdkLogger.error('fetchLicense: 403 Forbidden');
        return const SyncFailure(
          message:
              'You do not have access to this billing action. Try another organization or contact your administrator.',
        );
      }

      if (response.statusCode == 404) {
        BillingSdkLogger.error('fetchLicense: 404 Not found');
        return const SyncFailure(
          message: 'No billing account found for this user.',
        );
      }

      BillingSdkLogger.error('fetchLicense: unexpected status', '${response.statusCode}');
      return const SyncFailure(message: 'Sync failed. Try again later.');
    } catch (e, st) {
      BillingSdkLogger.error('fetchLicense: request failed', '$e');
      developer.log('fetchLicense stack', name: 'BillingSdk', level: 1000, error: e, stackTrace: st);
      return const SyncFailure(message: 'Sync failed. Try again later.');
    }
  }
}
