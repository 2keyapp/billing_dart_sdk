import 'dart:convert';

import 'package:billing_sdk/src/api/billing_api_client.dart';
import 'package:billing_sdk/src/keys/default_public_key.dart';
import 'package:billing_sdk/src/keys/public_key_loader.dart';
import 'package:billing_sdk/src/logging/sdk_logger.dart';
import 'package:billing_sdk/src/models/billing_token_error.dart';
import 'package:billing_sdk/src/models/billing_token_payload.dart';
import 'package:billing_sdk/src/models/payment_method.dart';
import 'package:billing_sdk/src/verification/token_verifier.dart';

/// Billing SDK: init from saved token, sync from server, paste+verify.
///
/// **HTTP routes used today**
/// - [syncFromServer] → `GET /api/v1/license` (Bearer + optional
///   `X-Paying-Party-Id`). Other routes (subscriptions, seats, etc.) are not
///   wrapped here yet; call the Billing API directly if needed.
///
/// **Auth:** Pass the same **AuthAPI** access token the app uses elsewhere (audience
/// must include Billing). Do not send raw IdP tokens to Billing.
///
/// **License JWT:** [configure] supplies a PEM to verify the signed license JWT
/// offline; that is separate from API authentication (no Billing verification
/// keys are embedded for HTTP auth).
///
/// Call [configure] before first use (at least [publicKeyPem] from Billing API).
/// Then [init] on app start with saved token, and use [getPayload] for add-on checks.
class BillingSdk {
  BillingSdk._();

  static String? _billingApiBaseUrl;
  static String? _publicKeyPem;
  static TokenVerifier? _verifier;
  static BillingApiClient? _apiClient;

  static BillingTokenPayload? _currentPayload;

  /// Last loaded key fingerprint (for debugging). Set when key is configured.
  static String? _loadedKeyFingerprint;

  /// Fingerprint of the currently configured public key (last 24 chars of base64 body).
  /// Use to verify the key in use matches your file (e.g. keys/billing_public.pem).
  static String? get loadedKeyFingerprint => _loadedKeyFingerprint;

  /// Short fingerprint of PEM content (last 24 chars of base64 body) for log verification.
  static String _pemFingerprint(String pem) {
    const begin = '-----BEGIN PUBLIC KEY-----';
    const end = '-----END PUBLIC KEY-----';
    final start = pem.indexOf(begin);
    final endIdx = pem.indexOf(end);
    if (start < 0 || endIdx <= start) return '?';
    final body = pem
        .substring(start + begin.length, endIdx)
        .replaceAll(RegExp(r'\s'), '');
    return body.length >= 24 ? body.substring(body.length - 24) : body;
  }

  /// Configures the SDK. Call before [init], [syncFromServer], or [verifyAndDecode].
  ///
  /// [billingApiBaseUrl] – Billing **origin** for HTTP calls, e.g.
  /// `https://billing.example.com`. Paths use the `/api/v1` prefix
  /// internally. You may also pass `https://billing.example.com/api/v1` or the
  /// legacy `.../api/billing`; both are normalized to the same origin.
  /// [publicKeyPem] – PEM string to verify JWTs; if null, uses embedded default
  /// (replace with key from Billing API in production).
  /// [publicKeyPath] – path to a .pem file; file content is read and validated for
  /// standard PEM boundaries (-----BEGIN PUBLIC KEY----- / -----END PUBLIC KEY-----).
  /// Not supported on web (throws [UnsupportedError]); use [publicKeyPem] there.
  ///
  /// For embedding the key in your build, use [configureWithAsset] with an asset path
  /// (e.g. `keys/billing_public.pem`; avoid paths starting with `assets/` on web).
  static void configure({
    String? billingApiBaseUrl,
    String? publicKeyPem,
    String? publicKeyPath,
  }) {
    if (billingApiBaseUrl != null) _billingApiBaseUrl = billingApiBaseUrl;
    if (publicKeyPem != null) _publicKeyPem = publicKeyPem;
    if (publicKeyPath != null && publicKeyPath.trim().isNotEmpty) {
      try {
        _publicKeyPem = loadPublicKeyFromPath(publicKeyPath.trim());
        _loadedKeyFingerprint = _pemFingerprint(_publicKeyPem!);
        BillingSdkLogger.info(
          'Configured: public key from path',
          '${publicKeyPath.trim()} — fingerprint: $_loadedKeyFingerprint',
        );
      } catch (e) {
        BillingSdkLogger.error(
          'Configure: failed to load public key from path',
          '$publicKeyPath — $e',
        );
        rethrow;
      }
    } else if (publicKeyPem != null) {
      _loadedKeyFingerprint = _pemFingerprint(publicKeyPem);
      BillingSdkLogger.info(
        'Configured: public key set from PEM (${publicKeyPem.length} chars)',
        _loadedKeyFingerprint,
      );
    }
    if (billingApiBaseUrl != null) {
      BillingSdkLogger.info('Configured: billingApiBaseUrl', billingApiBaseUrl);
    }
    _verifier = null;
    _apiClient = null;
  }

  /// Configures the SDK with an async key loader.
  ///
  /// Useful for app-level key bootstrap (for example, loading a PEM from
  /// Flutter assets) while keeping key wiring inside the SDK bootstrap flow.
  static Future<void> configureWithKeyLoader({
    String? billingApiBaseUrl,
    required Future<String> Function() loadPublicKeyPem,
  }) async {
    final pem = await loadPublicKeyPem();
    configure(billingApiBaseUrl: billingApiBaseUrl, publicKeyPem: pem);
  }

  /// Resets all static state. For testing only.
  static void resetForTesting() {
    _billingApiBaseUrl = null;
    _publicKeyPem = null;
    _verifier = null;
    _apiClient = null;
    _currentPayload = null;
    _loadedKeyFingerprint = null;
  }

  /// Reads the JWT header and returns the "alg" value (e.g. "ES256", "RS256").
  /// Use when verification fails to check if the token uses the expected algorithm.
  static String? getJwtAlg(String signedToken) {
    final trimmed = signedToken.trim();
    try {
      final parts = trimmed.split('.');
      if (parts.length < 2) return null;
      final raw = parts[0].replaceAll('-', '+').replaceAll('_', '/');
      final pad = raw.length % 4;
      final padded = pad == 2
          ? '$raw=='
          : pad == 3
              ? '$raw='
              : raw;
      final decoded = utf8.decode(base64Url.decode(padded));
      final map = jsonDecode(decoded) as Map<String, dynamic>?;
      return map?['alg'] as String?;
    } catch (_) {
      return null;
    }
  }

  static TokenVerifier get _verifierOrThrow {
    final pem = _publicKeyPem ?? defaultPublicKeyPem;

    return _verifier ??= TokenVerifier(publicKeyPem: pem);
  }

  static BillingApiClient get _apiClientOrThrow {
    final base = _billingApiBaseUrl;

    if (base == null || base.isEmpty) {
      throw StateError(
        'BillingSdk: call configure(billingApiBaseUrl: ...) before syncFromServer.',
      );
    }

    return _apiClient ??= BillingApiClient(baseUrl: base);
  }

  /// Initializes the SDK with the saved signed token (e.g. from secure storage).
  /// On success, stores payload in memory for [getPayload]. On null/invalid/expired, state stays empty.
  static void init(String? savedSignedJson) {
    if (savedSignedJson == null || savedSignedJson.trim().isEmpty) {
      BillingSdkLogger.info('init: no saved token — payload cleared');
      _currentPayload = null;
      return;
    }

    final result = _verifierOrThrow.verifyAndDecode(savedSignedJson.trim());

    switch (result) {
      case VerifySuccess(:final payload):
        _currentPayload = payload;
        BillingSdkLogger.success(
          'init: token verified — payingParty=${payload.payingParty.id}, subscriptions=${payload.subscriptionIds.length}',
        );
      case VerifyFailure(:final error):
        _currentPayload = null;
        BillingSdkLogger.error(
          'init: token invalid',
          'reason=${error.reason} — ${error.message}',
        );
    }
  }

  /// Returns the current in-memory payload, or null if not initialized or invalid.
  static BillingTokenPayload? getPayload() => _currentPayload;

  /// Syncs from the Billing API: `GET /api/v1/license`.
  ///
  /// [authorizationToken] — AuthAPI access token (Bearer added if missing).
  /// [payingPartyId] — optional `paying_parties.id` as a string for
  /// `X-Paying-Party-Id` when the user acts for another payer; omit for default.
  ///
  /// On success, updates in-memory state. Returns [SyncResult]; on failure,
  /// show [SyncFailure.message] to the user (handles 401/403/404 with distinct copy).
  static Future<SyncResult> syncFromServer({
    required String authorizationToken,
    String? payingPartyId,
  }) async {
    BillingSdkLogger.info('syncFromServer: requesting license from API');
    final client = _apiClientOrThrow;
    final result = await client.fetchLicense(
      authorizationToken: authorizationToken,
      payingPartyId: payingPartyId,
    );

    switch (result) {
      case SyncSuccess(:final signedToken):
        final verifyResult = _verifierOrThrow.verifyAndDecode(signedToken);

        switch (verifyResult) {
          case VerifySuccess(:final payload):
            _currentPayload = payload;
            BillingSdkLogger.success(
              'syncFromServer: success — payingParty=${payload.payingParty.id}, subscriptions=${payload.subscriptionIds.length}',
            );
            return result;
          case VerifyFailure(:final error):
            BillingSdkLogger.error(
              'syncFromServer: token from API failed verification',
              'reason=${error.reason}',
            );
            return SyncFailure(message: error.message);
        }
      case SyncFailure(:final message):
        BillingSdkLogger.error('syncFromServer: failed', message);
        return result;
    }
  }

  /// Ensures billing account context via `GET /api/v1/subscriptions/me`.
  static Future<BootstrapResult> ensureBillingContext({
    required String authorizationToken,
  }) async {
    BillingSdkLogger.info('ensureBillingContext: requesting subscriptions/me');
    return _apiClientOrThrow.ensureBillingContext(
      authorizationToken: authorizationToken,
    );
  }

  /// Fetches saved payment methods for the authenticated user.
  ///
  /// [authorizationToken] — AuthAPI access token (Bearer added if missing).
  /// Returns an empty list if the SDK is not configured or the request fails.
  static Future<List<PaymentMethod>> fetchPaymentMethods({
    required String authorizationToken,
  }) async {
    BillingSdkLogger.info('fetchPaymentMethods: requesting from API');
    try {
      final client = _apiClientOrThrow;
      return await client.fetchPaymentMethods(
        authorizationToken: authorizationToken,
      );
    } catch (e) {
      BillingSdkLogger.error('fetchPaymentMethods: failed', '$e');
      return [];
    }
  }

  /// Verifies pasted JSON (signed token) and returns payload or error.
  /// On success, updates in-memory state and the app should persist the raw token for [init] on next launch.
  /// On failure, show [BillingTokenError.message] in an error notification.
  static VerifyResult verifyAndDecode(String pastedJson) {
    final result = _verifierOrThrow.verifyAndDecode(pastedJson.trim());

    switch (result) {
      case VerifySuccess(:final payload):
        _currentPayload = payload;
        BillingSdkLogger.success(
          'verifyAndDecode: success — payingParty=${payload.payingParty.id}, subscriptions=${payload.subscriptionIds.length}',
        );
      case VerifyFailure(:final error):
        BillingSdkLogger.error(
          'verifyAndDecode: failed',
          'reason=${error.reason} — ${error.message}',
        );
    }

    return result;
  }
}
