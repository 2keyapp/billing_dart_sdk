import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/billing_api_client.dart';
import '../logging/sdk_logger.dart';
import 'billing_auth_tokens.dart';
import 'pkce.dart';

/// PKCE OAuth client for billing embedded auth at `/api/auth`.
class BillingAuthClient {
  BillingAuthClient({
    required String billingBaseUrl,
    this.clientId = 'billing_portal_web',
    this.defaultScope = 'openid profile email',
    http.Client? httpClient,
  }) : _origin = normalizeBillingApiBaseUrl(billingBaseUrl),
       _http = httpClient ?? http.Client();

  final String _origin;
  final String clientId;
  final String defaultScope;
  final http.Client _http;

  String get authBaseUrl {
    final base = _origin.endsWith('/') ? _origin : '$_origin/';
    return '${base}api/auth';
  }

  /// Builds the browser authorize URL for PKCE login.
  Uri buildAuthorizeUrl({
    required String redirectUri,
    required String state,
    String? codeVerifier,
    String? scope,
    String? deviceId,
    String? platform,
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
    };
    return Uri.parse('$authBaseUrl/authorize').replace(queryParameters: params);
  }

  /// Exchanges an authorization code for access + refresh tokens.
  Future<BillingAuthTokens> exchangeAuthorizationCode({
    required String code,
    required String redirectUri,
    required String codeVerifier,
    String? deviceId,
  }) async {
    final uri = Uri.parse('$authBaseUrl/token');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (deviceId != null && deviceId.isNotEmpty) {
      headers['X-Uids-Device-Id'] = deviceId;
    }
    final body = jsonEncode({
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'code_verifier': codeVerifier,
    });
    BillingSdkLogger.info('BillingAuthClient: POST token (code exchange)');
    final response = await _http.post(uri, headers: headers, body: body);
    return _parseTokenResponse(response);
  }

  /// Rotates access + refresh tokens.
  Future<BillingAuthTokens> refreshTokens(String refreshToken) async {
    final uri = Uri.parse('$authBaseUrl/refresh');
    final response = await _http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    BillingSdkLogger.info('BillingAuthClient: POST refresh');
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
