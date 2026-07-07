import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/billing_api_client.dart';
import '../logging/sdk_logger.dart';
import 'billing_auth_tokens.dart';
import 'billing_auth_discovery.dart';
import 'pkce.dart';

/// PKCE OAuth client for billing embedded auth at `/api/auth`.
class BillingAuthClient {
  BillingAuthClient({
    required String billingBaseUrl,
    this.clientId = 'billing_portal_web',
    this.defaultScope = 'openid profile email offline_access',
    this.apiAudience = 'billing',
    http.Client? httpClient,
  }) : _origin = normalizeBillingApiBaseUrl(billingBaseUrl),
       _http = httpClient ?? http.Client();

  final String _origin;
  final String clientId;
  final String defaultScope;
  final String apiAudience;
  final http.Client _http;

  String get authBaseUrl {
    final base = _origin.endsWith('/') ? _origin : '$_origin/';
    return '${base}api/auth';
  }

  /// GET `/api/auth/.well-known/oauth-providers` — which login methods are enabled.
  Future<BillingOAuthProvidersDocument> fetchOAuthProviders() async {
    final uri = Uri.parse('$authBaseUrl/.well-known/oauth-providers');
    BillingSdkLogger.info('BillingAuthClient: GET oauth-providers');
    final response = await _http.get(uri);
    if (response.statusCode != 200) {
      throw BillingAuthException(
        'Could not load auth providers (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const BillingAuthException('Invalid oauth-providers response.');
    }
    return BillingOAuthProvidersDocument.fromJson(decoded);
  }

  /// GET `/api/auth/.well-known/openid-configuration` — OIDC discovery document.
  Future<BillingOpenIdConfiguration> fetchOpenIdConfiguration() async {
    final uri = Uri.parse('$authBaseUrl/.well-known/openid-configuration');
    BillingSdkLogger.info('BillingAuthClient: GET openid-configuration');
    final response = await _http.get(uri);
    if (response.statusCode != 200) {
      throw BillingAuthException(
        'Could not load OpenID configuration (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const BillingAuthException('Invalid openid-configuration response.');
    }
    return BillingOpenIdConfiguration.fromJson(decoded);
  }

  /// Loads provider list and OIDC config together for login UI bootstrap.
  Future<BillingAuthDiscovery> discover() async {
    final results = await Future.wait([
      fetchOAuthProviders(),
      fetchOpenIdConfiguration(),
    ]);
    return BillingAuthDiscovery(
      providers: results[0] as BillingOAuthProvidersDocument,
      openId: results[1] as BillingOpenIdConfiguration,
    );
  }

  /// Builds the browser authorize URL for PKCE login.
  ///
  /// Pass [loginProvider] (`google`, `microsoft`, `email`) so embedded clients
  /// skip the server `/login` chooser and go straight to the IdP.
  Uri buildAuthorizeUrl({
    required String redirectUri,
    required String state,
    String? codeVerifier,
    String? scope,
    String? deviceId,
    String? platform,
    String? loginProvider,
  }) {
    final verifier = codeVerifier ?? generatePkceVerifier();
    final challenge = pkceChallengeS256(verifier);
    final params = <String, String>{
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': scope ?? defaultScope,
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
      if (loginProvider != null && loginProvider.isNotEmpty)
        'login_provider': loginProvider,
      if (apiAudience.isNotEmpty) 'resource': apiAudience,
    };
    return Uri.parse('$authBaseUrl/authorize').replace(queryParameters: params);
  }

  String resolveTokenEndpoint({String? tokenEndpoint}) {
    final configured = tokenEndpoint?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return '$authBaseUrl/oauth2/token';
  }

  /// Exchanges an authorization code for access + refresh tokens.
  Future<BillingAuthTokens> exchangeAuthorizationCode({
    required String code,
    required String redirectUri,
    required String codeVerifier,
    String? deviceId,
    String? tokenEndpoint,
  }) async {
    final uri = Uri.parse(resolveTokenEndpoint(tokenEndpoint: tokenEndpoint));
    final body = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'code_verifier': codeVerifier,
      if (apiAudience.isNotEmpty) 'resource': apiAudience,
    };
    BillingSdkLogger.info('BillingAuthClient: POST token (code exchange)');
    final response = await _http.post(
      uri,
      headers: _tokenRequestHeaders(deviceId: deviceId),
      body: _encodeFormBody(body),
    );
    return _parseTokenResponse(response);
  }

  /// Rotates access + refresh tokens.
  Future<BillingAuthTokens> refreshTokens(
    String refreshToken, {
    String? tokenEndpoint,
  }) async {
    final uri = Uri.parse(resolveTokenEndpoint(tokenEndpoint: tokenEndpoint));
    final body = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
      if (apiAudience.isNotEmpty) 'resource': apiAudience,
    };
    BillingSdkLogger.info('BillingAuthClient: POST refresh');
    final response = await _http.post(
      uri,
      headers: _tokenRequestHeaders(),
      body: _encodeFormBody(body),
    );
    return _parseTokenResponse(response);
  }

  /// Revokes refresh token session.
  Future<void> logout({String? refreshToken}) async {
    if (refreshToken == null || refreshToken.isEmpty) return;
    final uri = Uri.parse('$authBaseUrl/logout');
    await _http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    BillingSdkLogger.info('BillingAuthClient: POST logout');
  }

  BillingAuthTokens _parseTokenResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BillingAuthException(
        'Authentication failed (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const BillingAuthException('Invalid auth response.');
    }
    return BillingAuthTokens.fromJson(decoded);
  }

  Map<String, String> _tokenRequestHeaders({String? deviceId}) {
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    };
    if (deviceId != null && deviceId.isNotEmpty) {
      headers['X-Uids-Device-Id'] = deviceId;
    }
    return headers;
  }

  String _encodeFormBody(Map<String, String> fields) =>
      Uri(queryParameters: fields).query;

  void close() => _http.close();
}

class BillingAuthException implements Exception {
  const BillingAuthException(this.message, {this.statusCode, this.responseBody});

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() => message;
}

/// Convenience holder for an in-flight PKCE login (store [codeVerifier] until callback).
class BillingPkceRequest {
  BillingPkceRequest({
    required this.codeVerifier,
    required this.state,
    required this.redirectUri,
  });

  final String codeVerifier;
  final String state;
  final String redirectUri;

  factory BillingPkceRequest.create({
    required String redirectUri,
    String? state,
  }) {
    return BillingPkceRequest(
      codeVerifier: generatePkceVerifier(),
      state: state ?? generatePkceVerifier(byteLength: 16),
      redirectUri: redirectUri,
    );
  }
}
