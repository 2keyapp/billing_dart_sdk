import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logging/sdk_logger.dart';
import 'billing_auth_exception.dart';
import 'billing_auth_tokens.dart';

/// Mints billing API JWTs via Better Auth `GET /api/auth/token` (JWT plugin).
class BillingApiTokenMint {
  BillingApiTokenMint({
    required this.authBaseUrl,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String authBaseUrl;
  final http.Client _http;

  /// Exchanges an active Better Auth session cookie for a billing API JWT.
  Future<BillingAuthTokens> mintFromSessionCookie(String sessionCookie) async {
    final cookie = sessionCookie.trim();
    if (cookie.isEmpty) {
      throw const BillingAuthException('No session cookie — sign in first');
    }

    final uri = Uri.parse('$authBaseUrl/token');
    final response = await _http.get(
      uri,
      headers: {
        'accept': 'application/json',
        'cookie': cookie,
      },
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw BillingAuthException(
        'Invalid token response (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BillingAuthException(
        body['message'] as String? ??
            body['error'] as String? ??
            'Token mint failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    final token = body['token'];
    if (token is! String || token.isEmpty) {
      throw const BillingAuthException('Token response missing token field');
    }

    BillingSdkLogger.info('BillingApiTokenMint: billing JWT minted');
    return BillingAuthTokens.fromJwtPluginToken(token);
  }

  void close() => _http.close();
}
