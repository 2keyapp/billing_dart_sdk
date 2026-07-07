/// OAuth tokens returned by billing embedded auth (`POST /api/auth/token`).
class BillingAuthTokens {
  const BillingAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.tokenType = 'Bearer',
    this.expiresInSeconds,
    this.scope,
  });

  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final String tokenType;
  final int? expiresInSeconds;
  final String? scope;

  /// Estimated access-token expiry (local clock). Null when [expiresInSeconds] missing.
  DateTime? get expiresAt {
    final seconds = expiresInSeconds;
    if (seconds == null) return null;
    return DateTime.now().toUtc().add(Duration(seconds: seconds));
  }

  bool get isAccessTokenExpired {
    final at = expiresAt;
    if (at == null) return false;
    return DateTime.now().toUtc().isAfter(at);
  }

  factory BillingAuthTokens.fromJson(Map<String, dynamic> json) {
    final access = json['access_token'] ?? json['accessToken'];
    if (access is! String || access.isEmpty) {
      throw FormatException('access_token required.');
    }
    final refresh = json['refresh_token'] ?? json['refreshToken'];
    final idToken = json['id_token'] ?? json['idToken'];
    final expiresIn = json['expires_in'] ?? json['expiresIn'];
    return BillingAuthTokens(
      accessToken: access,
      refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
      idToken: idToken is String && idToken.isNotEmpty ? idToken : null,
      tokenType: json['token_type'] as String? ?? json['tokenType'] as String? ?? 'Bearer',
      expiresInSeconds: expiresIn is int
          ? expiresIn
          : expiresIn is num
              ? expiresIn.toInt()
              : int.tryParse('$expiresIn'),
      scope: json['scope'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        if (idToken != null) 'id_token': idToken,
        'token_type': tokenType,
        if (expiresInSeconds != null) 'expires_in': expiresInSeconds,
        if (scope != null) 'scope': scope,
      };
}
