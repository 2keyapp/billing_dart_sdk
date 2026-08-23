import 'dart:convert';

import 'billing_auth_session.dart';
import 'billing_auth_tokens.dart';
import 'auth_user_profile.dart';

/// Builds a billing [AuthUserProfile] after social / email sign-in.
///
/// Prefer JWT claims when present; fill gaps from the auth session user
/// (email/name often live only there). When the billing JWT omits `sub` (or is
/// not decodable), use the session user id so local persistence can finish.
AuthUserProfile billingProfileFromSignIn({
  required BillingAuthSessionUser sessionUser,
  required BillingAuthTokens tokens,
  String? loginProvider,
}) {
  AuthUserProfile? fromJwt;
  try {
    fromJwt = AuthUserProfile.fromTokens(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
    );
  } on FormatException {
    fromJwt = null;
  }

  final subject = _nonEmpty(fromJwt?.subject) ?? _nonEmpty(sessionUser.id);
  if (subject == null) {
    throw const FormatException('Sign-in session is missing a user id.');
  }

  final email = _nonEmpty(fromJwt?.email) ?? _nonEmpty(sessionUser.email);
  final name = _nonEmpty(fromJwt?.name) ?? _nonEmpty(sessionUser.name);
  final picture = _nonEmpty(fromJwt?.picture) ?? _nonEmpty(sessionUser.image);

  return AuthUserProfile(
    subject: subject,
    email: email,
    name: name,
    picture: picture,
    emailVerified: fromJwt?.emailVerified == true || sessionUser.emailVerified,
    identityProvider:
        _nonEmpty(fromJwt?.identityProvider) ?? _nonEmpty(loginProvider),
    audience: fromJwt?.audience,
    issuer: fromJwt?.issuer,
    clientId: fromJwt?.clientId,
    scope: fromJwt?.scope,
  );
}

/// Attaches an unsigned id_token carrying [profile] claims so
/// [BillingSession.persistAuthTokens] / [AuthUserProfile.fromTokens] can resolve
/// `sub` + email when the billing API JWT omits them.
BillingAuthTokens billingTokensWithProfileIdToken({
  required BillingAuthTokens tokens,
  required AuthUserProfile profile,
}) {
  try {
    final existing = AuthUserProfile.fromTokens(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
    );
    final emailOk = _nonEmpty(existing.email) != null;
    if (emailOk || _nonEmpty(profile.email) == null) {
      return tokens;
    }
  } on FormatException {
    // Continue — mint a claims id_token below.
  }

  final claims = <String, dynamic>{
    'sub': profile.subject,
    if (_nonEmpty(profile.email) != null) 'email': profile.email,
    if (_nonEmpty(profile.name) != null) 'name': profile.name,
    if (_nonEmpty(profile.picture) != null) 'picture': profile.picture,
    'email_verified': profile.emailVerified,
  };

  return BillingAuthTokens(
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    idToken: unsignedJwtForClaims(claims),
    tokenType: tokens.tokenType,
    expiresInSeconds: tokens.expiresInSeconds,
    scope: tokens.scope,
  );
}

/// Minimal unsigned JWT (header.payload.) for local claim merging only.
String unsignedJwtForClaims(Map<String, dynamic> claims) {
  String b64(Object value) {
    final bytes = utf8.encode(value is String ? value : jsonEncode(value));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  return '${b64('{"alg":"none","typ":"JWT"}')}.${b64(claims)}.';
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
