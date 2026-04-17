import 'dart:convert';
import 'dart:developer' as developer;

import 'package:billing_flutter_sdk/src/logging/sdk_logger.dart';
import 'package:billing_flutter_sdk/src/models/addon_entitlement.dart';
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

sealed class BillingApiResult<T> {}

class BillingApiSuccess<T> implements BillingApiResult<T> {
  const BillingApiSuccess({required this.data});
  final T data;
}

class BillingApiFailure<T> implements BillingApiResult<T> {
  const BillingApiFailure({required this.message, this.statusCode});
  final String message;
  final int? statusCode;
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

  Map<String, String> _buildHeaders({
    required String authorizationToken,
    String? payingPartyId,
    Map<String, String>? extra,
  }) {
    final token = authorizationToken.toLowerCase().startsWith('bearer ')
        ? authorizationToken
        : 'Bearer $authorizationToken';
    final headers = <String, String>{'Authorization': token, ...?extra};
    final party = payingPartyId?.trim();
    if (party != null && party.isNotEmpty) {
      headers['X-Paying-Party-Id'] = party;
    }
    return headers;
  }

  Map<String, dynamic>? _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Map<String, dynamic>? _unwrapSuccessData(String body) {
    final root = _decodeJsonObject(body);
    final data = root?['data'];
    if (data is Map<String, dynamic>) return data;
    return root;
  }

  String _messageForStatus(int statusCode, {String? fallback}) {
    switch (statusCode) {
      case 400:
        return fallback ?? 'Bad request. Please verify your billing input.';
      case 401:
        return fallback ?? 'Session expired or invalid. Please sign in again.';
      case 403:
        return fallback ??
            'You do not have access to this billing action. Try another organization or contact your administrator.';
      case 404:
        return fallback ?? 'Requested billing resource was not found.';
      default:
        return fallback ?? 'Billing request failed. Try again later.';
    }
  }

  BillingApiFailure<T> _failureFromResponse<T>(http.Response response) {
    String? error;
    try {
      final root = _decodeJsonObject(response.body);
      error = root?['error'] as String? ?? root?['message'] as String?;
    } catch (_) {
      error = null;
    }
    return BillingApiFailure<T>(
      message: _messageForStatus(response.statusCode, fallback: error),
      statusCode: response.statusCode,
    );
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
    final uri = Uri.parse('${_baseUrl}api/billing/license');
    final headers = _buildHeaders(
      authorizationToken: raw,
      payingPartyId: payingPartyId,
    );

    BillingSdkLogger.info('fetchLicense: GET', uri.toString());

    try {
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = _unwrapSuccessData(response.body);
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
        return const SyncFailure(
          message: 'Sync failed. Invalid response from server.',
        );
      }

      final failure = _failureFromResponse<void>(response);
      BillingSdkLogger.error(
        'fetchLicense: failed',
        '${failure.statusCode} ${failure.message}',
      );
      return SyncFailure(message: failure.message);
    } catch (e, st) {
      BillingSdkLogger.error('fetchLicense: request failed', '$e');
      developer.log(
        'fetchLicense stack',
        name: 'BillingSdk',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return const SyncFailure(message: 'Sync failed. Try again later.');
    }
  }

  Future<BillingApiResult<AddonEntitlement>> fetchAddonEntitlement({
    required String authorizationToken,
    required String planId,
    String? payingPartyId,
  }) async {
    final rawToken = authorizationToken.trim();
    final rawPlanId = planId.trim();

    if (rawToken.isEmpty) {
      return const BillingApiFailure(
        message: 'Authorization token is required.',
      );
    }

    if (rawPlanId.isEmpty) {
      return const BillingApiFailure(message: 'planId is required.');
    }

    final uri = Uri.parse(
      '${_baseUrl}api/billing/addons/$rawPlanId/entitlement',
    );

    try {
      final response = await http.get(
        uri,
        headers: _buildHeaders(
          authorizationToken: rawToken,
          payingPartyId: payingPartyId,
        ),
      );
      if (response.statusCode == 200) {
        final data = _unwrapSuccessData(response.body);
        if (data == null) {
          return const BillingApiFailure(
            message: 'Invalid entitlement response from server.',
          );
        }
        return BillingApiSuccess(data: AddonEntitlement.fromJson(data));
      }
      return _failureFromResponse(response);
    } catch (e, st) {
      developer.log(
        'fetchAddonEntitlement stack',
        name: 'BillingSdk',
        level: 1000,
        error: e,
        stackTrace: st,
      );

      return const BillingApiFailure(
        message: 'Billing request failed. Try again later.',
      );
    }
  }

  Future<BillingApiResult<AddonEntitlement>> startAddonEvaluation({
    required String authorizationToken,
    required String planId,
    String? payingPartyId,
  }) async {
    final rawToken = authorizationToken.trim();
    final rawPlanId = planId.trim();
    if (rawToken.isEmpty) {
      return const BillingApiFailure(
        message: 'Authorization token is required.',
      );
    }
    if (rawPlanId.isEmpty) {
      return const BillingApiFailure(message: 'planId is required.');
    }
    final uri = Uri.parse('${_baseUrl}api/billing/addons/$rawPlanId/start');
    try {
      final response = await http.post(
        uri,
        headers: _buildHeaders(
          authorizationToken: rawToken,
          payingPartyId: payingPartyId,
        ),
      );
      if (response.statusCode == 200) {
        final data = _unwrapSuccessData(response.body);
        if (data == null) {
          return const BillingApiFailure(
            message: 'Invalid entitlement response from server.',
          );
        }
        return BillingApiSuccess(data: AddonEntitlement.fromJson(data));
      }
      return _failureFromResponse(response);
    } catch (e, st) {
      developer.log(
        'startAddonEvaluation stack',
        name: 'BillingSdk',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return const BillingApiFailure(
        message: 'Billing request failed. Try again later.',
      );
    }
  }

  Future<BillingApiResult<AddonPurchaseSession>> createAddonPurchaseSession({
    required String authorizationToken,
    required String planId,
    required String successUrl,
    required String cancelUrl,
    String? payingPartyId,
  }) async {
    final rawToken = authorizationToken.trim();
    final rawPlanId = planId.trim();
    if (rawToken.isEmpty) {
      return const BillingApiFailure(
        message: 'Authorization token is required.',
      );
    }
    if (rawPlanId.isEmpty) {
      return const BillingApiFailure(message: 'planId is required.');
    }
    if (successUrl.trim().isEmpty || cancelUrl.trim().isEmpty) {
      return const BillingApiFailure(
        message: 'successUrl and cancelUrl are required.',
      );
    }
    final uri = Uri.parse(
      '${_baseUrl}api/billing/addons/$rawPlanId/purchase-session',
    );
    try {
      final response = await http.post(
        uri,
        headers: _buildHeaders(
          authorizationToken: rawToken,
          payingPartyId: payingPartyId,
          extra: {'Content-Type': 'application/json'},
        ),
        body: jsonEncode({
          'successUrl': successUrl.trim(),
          'cancelUrl': cancelUrl.trim(),
        }),
      );
      if (response.statusCode == 200) {
        final data = _unwrapSuccessData(response.body);
        if (data == null) {
          return const BillingApiFailure(
            message: 'Invalid purchase session response from server.',
          );
        }
        return BillingApiSuccess(data: AddonPurchaseSession.fromJson(data));
      }
      return _failureFromResponse(response);
    } catch (e, st) {
      developer.log(
        'createAddonPurchaseSession stack',
        name: 'BillingSdk',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return const BillingApiFailure(
        message: 'Billing request failed. Try again later.',
      );
    }
  }

  Future<BillingApiResult<AddonAccess>> checkAddonAccess({
    required String authorizationToken,
    required String planId,
    String? payingPartyId,
  }) async {
    final rawToken = authorizationToken.trim();
    final rawPlanId = planId.trim();
    if (rawToken.isEmpty) {
      return const BillingApiFailure(
        message: 'Authorization token is required.',
      );
    }
    if (rawPlanId.isEmpty) {
      return const BillingApiFailure(message: 'planId is required.');
    }
    final uri = Uri.parse('${_baseUrl}api/billing/addons/$rawPlanId/access');
    try {
      final response = await http.get(
        uri,
        headers: _buildHeaders(
          authorizationToken: rawToken,
          payingPartyId: payingPartyId,
        ),
      );
      if (response.statusCode == 200) {
        final data = _unwrapSuccessData(response.body);
        if (data == null) {
          return const BillingApiFailure(
            message: 'Invalid add-on access response from server.',
          );
        }
        return BillingApiSuccess(data: AddonAccess.fromJson(data));
      }
      return _failureFromResponse(response);
    } catch (e, st) {
      developer.log(
        'checkAddonAccess stack',
        name: 'BillingSdk',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return const BillingApiFailure(
        message: 'Billing request failed. Try again later.',
      );
    }
  }
}
