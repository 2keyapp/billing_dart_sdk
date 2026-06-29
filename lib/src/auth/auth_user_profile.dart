import 'jwt_payload.dart';

/// Identity extracted from a billing access token (display + role checks).
class AuthUserProfile {
  const AuthUserProfile({
    required this.subject,
    this.email,
    this.emailVerified = false,
    this.identityProvider,
    this.audience,
    this.issuer,
    this.clientId,
    this.scope,
  });

  final String subject;
  final String? email;
  final bool emailVerified;
  final String? identityProvider;
  final String? audience;
  final String? issuer;
  final String? clientId;
  final String? scope;

  factory AuthUserProfile.fromAccessToken(String accessToken) {
    final claims = decodeJwtPayload(accessToken);
    if (claims == null) {
      throw FormatException('Invalid access token payload.');
    }
    final sub = claims['sub'];
    if (sub == null || '$sub'.isEmpty) {
      throw FormatException('Access token missing sub claim.');
    }
    return AuthUserProfile(
      subject: '$sub',
      email: claims['email'] as String?,
      emailVerified: claims['email_verified'] == true || claims['emailVerified'] == true,
      identityProvider: claims['identity_provider'] as String? ??
          claims['identityProvider'] as String?,
      audience: _stringOrFirst(claims['aud']),
      issuer: claims['iss'] as String?,
      clientId: claims['client_id'] as String? ?? claims['clientId'] as String?,
      scope: claims['scope'] as String?,
    );
  }

  static String? _stringOrFirst(Object? aud) {
    if (aud is String) return aud;
    if (aud is List && aud.isNotEmpty) return '${aud.first}';
    return null;
  }
}
