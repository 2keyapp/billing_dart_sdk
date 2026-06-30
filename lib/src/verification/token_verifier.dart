import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../logging/sdk_logger.dart';
import '../models/billing_token_error.dart';
import '../models/billing_token_payload.dart';

/// Verifies and decodes a signed JWT into [BillingTokenPayload] or returns
/// a [BillingTokenError] with a user-facing message.
class TokenVerifier {
  TokenVerifier({required String publicKeyPem})
    : _publicKey = ECPublicKey(publicKeyPem);

  final ECPublicKey _publicKey;

  /// Verifies the token and returns either [VerifySuccess] with payload or
  /// [VerifyFailure] with a user-facing error for the app to show.
  VerifyResult verifyAndDecode(String signedToken) {
    final trimmed = signedToken.trim();

    if (trimmed.isEmpty) {
      return _failure(BillingTokenErrorReason.malformed);
    }

    try {
      final jwt = JWT.tryVerify(
        trimmed,
        _publicKey,
        checkExpiresIn: true,
        checkNotBefore: false,
      );

      if (jwt == null) {
        final algHint = _jwtAlgFromToken(trimmed);
        if (algHint != null) {
          BillingSdkLogger.warning(
            'Token signed with alg=$algHint; SDK expects ES256 (EC key). Key must match signer.',
          );
        }
        return _failure(BillingTokenErrorReason.invalidSignature);
      }

      final payloadMap = jwt.payload;
      if (payloadMap is! Map<String, dynamic>) {
        return _failure(
          BillingTokenErrorReason.missingClaims,
          detail: 'Expected a JSON object payload.',
        );
      }
      try {
        final payload = BillingTokenPayload.fromJson(payloadMap);
        return VerifySuccess(payload);
      } on FormatException catch (e) {
        return _failure(
          BillingTokenErrorReason.missingClaims,
          detail: e.message,
        );
      }
    } on JWTExpiredException {
      return _failure(BillingTokenErrorReason.expired);
    } on JWTException catch (e) {
      final reason = _reasonFromMessage(e.message);

      return VerifyFailure(
        BillingTokenError(
          message: _userMessage(reason, e.message),
          reason: reason,
        ),
      );
    } catch (_) {
      return _failure(BillingTokenErrorReason.malformed);
    }
  }

  /// Decodes JWT header and returns "alg" if present (e.g. "ES256", "RS256").
  static String? _jwtAlgFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final padded = parts[0].replaceAll('-', '+').replaceAll('_', '/');
      switch (padded.length % 4) {
        case 2:
          final b = utf8.decode(base64Url.decode('$padded=='));
          return _algFromHeaderJson(b);
        case 3:
          final b = utf8.decode(base64Url.decode('$padded='));
          return _algFromHeaderJson(b);
        default:
          final b = utf8.decode(base64Url.decode(padded));
          return _algFromHeaderJson(b);
      }
    } catch (_) {
      return null;
    }
  }

  static String? _algFromHeaderJson(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>?;
      return map?['alg'] as String?;
    } catch (_) {
      return null;
    }
  }

  VerifyFailure _failure(BillingTokenErrorReason reason, {String? detail}) {
    var message = _userMessage(reason);
    if (reason == BillingTokenErrorReason.missingClaims &&
        detail != null &&
        detail.isNotEmpty) {
      message = '$message $detail';
    }
    BillingSdkLogger.error(
      'Token verification failed',
      'reason=$reason — $message',
    );
    return VerifyFailure(BillingTokenError(message: message, reason: reason));
  }

  BillingTokenErrorReason _reasonFromMessage(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('expired')) return BillingTokenErrorReason.expired;

    if (lower.contains('signature')) {
      return BillingTokenErrorReason.invalidSignature;
    }

    if (lower.contains('invalid') || lower.contains('malformed')) {
      return BillingTokenErrorReason.malformed;
    }

    return BillingTokenErrorReason.unknown;
  }

  String _userMessage(BillingTokenErrorReason reason, [String fallback = '']) {
    return switch (reason) {
      BillingTokenErrorReason.invalidSignature =>
        'Invalid token. It may have been copied incorrectly.',
      BillingTokenErrorReason.expired =>
        'This token has expired. Please sync or get a new token from the billing portal.',
      BillingTokenErrorReason.malformed =>
        'Invalid format. Please paste the full token from the billing portal.',
      BillingTokenErrorReason.missingClaims =>
        'Token is missing required data.',
      BillingTokenErrorReason.unknown =>
        fallback.isNotEmpty
            ? fallback
            : 'Invalid token. It may have been copied incorrectly.',
    };
  }
}
