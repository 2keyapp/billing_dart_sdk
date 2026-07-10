import 'dart:convert';

import 'package:billing_dart_sdk/src/api/billing_api_client.dart';
import 'package:billing_dart_sdk/src/catalog/plan_catalog.dart';
import 'package:billing_dart_sdk/src/keys/default_public_key.dart';
import 'package:billing_dart_sdk/src/keys/public_key_loader.dart';
import 'package:billing_dart_sdk/src/keys/public_key_loader_asset.dart';
import 'package:billing_dart_sdk/src/models/billing_stats.dart';
import 'package:billing_dart_sdk/src/models/billing_token_error.dart';
import 'package:billing_dart_sdk/src/models/billing_token_payload.dart';
import 'package:billing_dart_sdk/src/verification/token_verifier.dart';

/// Client SDK for **using-party apps**: auth token → license sync → offline entitlements.
///
/// Not a full Billing API mirror. Wraps only:
/// - License JWT verify + sync (`GET /api/v1/license`)
/// - Account bootstrap (`GET /api/v1/subscriptions/me`)
/// - Public plan catalog (`GET /api/v1/plans`)
///
/// Use [BillingAuthClient] for Better Auth login and [BillingSession] for persisted state.
class BillingSdk {
  BillingSdk._();

  static String? _billingApiBaseUrl;
  static String? _publicKeyPem;
  static TokenVerifier? _verifier;
  static BillingApiClient? _apiClient;

  static BillingTokenPayload? _currentPayload;
  static String? _loadedKeyFingerprint;

  static String? get loadedKeyFingerprint => _loadedKeyFingerprint;

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

  static void configure({
    String? billingApiBaseUrl,
    String? publicKeyPem,
    String? publicKeyPath,
  }) {
    if (billingApiBaseUrl != null) _billingApiBaseUrl = billingApiBaseUrl;
    if (publicKeyPem != null) _publicKeyPem = publicKeyPem;
    if (publicKeyPath != null && publicKeyPath.trim().isNotEmpty) {
      _publicKeyPem = loadPublicKeyFromPath(publicKeyPath.trim());
      _loadedKeyFingerprint = _pemFingerprint(_publicKeyPem!);
    } else if (publicKeyPem != null) {
      _loadedKeyFingerprint = _pemFingerprint(publicKeyPem);
    }
    _verifier = null;
    _apiClient = null;
  }

  static Future<void> configureWithAsset({
    String? billingApiBaseUrl,
    required String publicKeyAsset,
  }) async {
    final pem = await loadPublicKeyFromAsset(publicKeyAsset);
    configure(billingApiBaseUrl: billingApiBaseUrl, publicKeyPem: pem);
  }

  static void resetForTesting() {
    _billingApiBaseUrl = null;
    _publicKeyPem = null;
    _verifier = null;
    _apiClient = null;
    _currentPayload = null;
    _loadedKeyFingerprint = null;
  }

  static String? getJwtAlg(String signedToken) {
    try {
      final parts = signedToken.trim().split('.');
      if (parts.length < 2) return null;
      final raw = parts[0].replaceAll('-', '+').replaceAll('_', '/');
      final pad = raw.length % 4;
      final padded = pad == 2 ? '$raw==' : pad == 3 ? '$raw=' : raw;
      final map = jsonDecode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>?;
      return map?['alg'] as String?;
    } catch (_) {
      return null;
    }
  }

  static TokenVerifier get _verifierOrThrow {
    return _verifier ??= TokenVerifier(publicKeyPem: _publicKeyPem ?? defaultPublicKeyPem);
  }

  static BillingApiClient get _apiClientOrThrow {
    final base = _billingApiBaseUrl;
    if (base == null || base.isEmpty) {
      throw StateError(
        'BillingSdk: call configure(billingApiBaseUrl: ...) before API calls.',
      );
    }
    return _apiClient ??= BillingApiClient(baseUrl: base);
  }

  static void init(String? savedSignedJson) {
    if (savedSignedJson == null || savedSignedJson.trim().isEmpty) {
      _currentPayload = null;
      return;
    }
    final result = _verifierOrThrow.verifyAndDecode(savedSignedJson.trim());
    switch (result) {
      case VerifySuccess(:final payload):
        _currentPayload = payload;
      case VerifyFailure():
        _currentPayload = null;
    }
  }

  static BillingTokenPayload? getPayload() => _currentPayload;

  static Future<SyncResult> syncFromServer({
    required String authorizationToken,
    String? payingPartyId,
    String? ifNoneMatch,
  }) async {
    final result = await _apiClientOrThrow.fetchLicense(
      authorizationToken: authorizationToken,
      payingPartyId: payingPartyId,
      ifNoneMatch: ifNoneMatch,
    );
    switch (result) {
      case SyncNotModified():
        return result;
      case SyncSuccess(:final signedToken):
        final verifyResult = _verifierOrThrow.verifyAndDecode(signedToken);
        switch (verifyResult) {
          case VerifySuccess(:final payload):
            _currentPayload = payload;
            return result;
          case VerifyFailure(:final error):
            return SyncFailure(message: error.message);
        }
      case SyncFailure():
        return result;
    }
  }

  static Future<BootstrapResult> ensureBillingContext({
    required String authorizationToken,
  }) =>
      _apiClientOrThrow.ensureBillingContext(
        authorizationToken: authorizationToken,
      );

  static Future<PayingPartyBillingStats> fetchBillingStats({
    required String authorizationToken,
  }) async {
    final result = await ensureBillingContext(
      authorizationToken: authorizationToken,
    );
    if (result is BootstrapSuccess) return result.stats;
    throw StateError((result as BootstrapFailure).message);
  }

  /// Public monthly + annual plan catalog for in-app pricing UI.
  static Future<PlanCatalog> fetchPlanCatalog({
    int? productId,
    bool includeInactive = false,
  }) =>
      PlanCatalog.load(
        _apiClientOrThrow,
        productId: productId,
        includeInactive: includeInactive,
      );

  static VerifyResult verifyAndDecode(String pastedJson) {
    final result = _verifierOrThrow.verifyAndDecode(pastedJson.trim());
    if (result case VerifySuccess(:final payload)) {
      _currentPayload = payload;
    }
    return result;
  }
}
