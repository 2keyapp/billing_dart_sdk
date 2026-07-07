import 'jwt_payload.dart';

/// Identity extracted from billing OAuth tokens (display + role checks).
class AuthUserProfile {
  const AuthUserProfile({
    required this.subject,
    this.email,
    this.name,
    this.picture,
    this.emailVerified = false,
    this.identityProvider,
    this.audience,
    this.issuer,
    this.clientId,
    this.scope,
  });

  final String subject;
  final String? email;
  final String? name;
  final String? picture;
  final bool emailVerified;
  final String? identityProvider;
  final String? audience;
  final String? issuer;
  final String? clientId;
  final String? scope;

  /// Merges OIDC claims from access + id tokens (Better Auth profile fields
  /// often live only on the id_token).
  factory AuthUserProfile.fromTokens({
    required String accessToken,
    String? idToken,
  }) {
    final accessClaims = decodeJwtPayload(accessToken);
    if (accessClaims == null) {
      throw const FormatException('Invalid access token payload.');
    }
    final idClaims =
        idToken == null || idToken.trim().isEmpty
            ? null
            : decodeJwtPayload(idToken);

    final sub = accessClaims['sub'] ?? idClaims?['sub'];
    if (sub == null || '$sub'.isEmpty) {
      throw const FormatException('Access token missing sub claim.');
    }

    final email =
        _readString(accessClaims, 'email') ??
        _readString(idClaims, 'email') ??
        _readString(idClaims, 'preferred_username');

    final name =
        _readString(accessClaims, 'name') ??
        _readString(idClaims, 'name') ??
        _readString(idClaims, 'given_name');

    final picture =
        _readString(accessClaims, 'picture') ??
        _readString(idClaims, 'picture');

    final emailVerified =
        accessClaims['email_verified'] == true ||
        accessClaims['emailVerified'] == true ||
        idClaims?['email_verified'] == true ||
        idClaims?['emailVerified'] == true;

    return AuthUserProfile(
      subject: '$sub',
      email: email,
      name: name,
      picture: picture,
      emailVerified: emailVerified,
      identityProvider:
          _identityProviderHint(accessClaims) ??
          _identityProviderHint(idClaims),
      audience: _stringOrFirst(accessClaims['aud'] ?? idClaims?['aud']),
      issuer:
          _readString(accessClaims, 'iss') ?? _readString(idClaims, 'iss'),
      clientId:
          _readString(accessClaims, 'client_id') ??
          _readString(accessClaims, 'clientId') ??
          _readString(idClaims, 'client_id') ??
          _readString(idClaims, 'clientId'),
      scope: _readString(accessClaims, 'scope') ?? _readString(idClaims, 'scope'),
    );
  }

  factory AuthUserProfile.fromAccessToken(String accessToken) =>
      AuthUserProfile.fromTokens(accessToken: accessToken);

  /// Display name for UI — prefers [name], then email local-part, then [subject].
  String displayName() {
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) return trimmedName;
    final trimmedEmail = email?.trim();
    if (trimmedEmail != null &&
        trimmedEmail.isNotEmpty &&
        trimmedEmail.contains('@')) {
      return trimmedEmail.split('@').first;
    }
    return subject;
  }

  /// Account key / billing email — never falls back to opaque subject when email exists.
  String get accountKey {
    final trimmedEmail = email?.trim().toLowerCase();
    if (trimmedEmail != null && trimmedEmail.isNotEmpty) return trimmedEmail;
    return subject;
  }

  static String? _readString(Map<String, dynamic>? claims, String key) {
    if (claims == null) return null;
    final value = claims[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _identityProviderHint(Map<String, dynamic>? claims) {
    if (claims == null) return null;
    final candidates = [
      claims['identity_provider'],
      claims['identityProvider'],
      claims['idp_name'],
      claims['idp'],
      claims['amr'],
    ];
    for (final value in candidates) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is String) {
          final trimmed = first.trim();
          if (trimmed.isNotEmpty) return trimmed;
        }
      }
    }
    return null;
  }

  static String? _stringOrFirst(Object? aud) {
    if (aud is String) return aud;
    if (aud is List && aud.isNotEmpty) return '${aud.first}';
    return null;
  }
}
