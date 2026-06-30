/// Enabled login methods from `GET /api/auth/.well-known/oauth-providers`.
class BillingOAuthProvidersDocument {
  const BillingOAuthProvidersDocument({
    required this.issuer,
    required this.providers,
  });

  final String issuer;
  final List<BillingAuthProviderInfo> providers;

  /// Providers the server has enabled (google, microsoft, email, …).
  List<BillingAuthProviderInfo> get enabledProviders =>
      providers.where((p) => p.enabled).toList();

  bool get isGoogleEnabled => _isEnabled('google');
  bool get isMicrosoftEnabled => _isEnabled('microsoft');
  bool get isEmailEnabled => _isEnabled('email');

  bool _isEnabled(String id) =>
      providers.any((p) => p.id == id && p.enabled);

  factory BillingOAuthProvidersDocument.fromJson(Map<String, dynamic> json) {
    final raw = json['providers'];
    final list = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(BillingAuthProviderInfo.fromJson)
            .toList()
        : <BillingAuthProviderInfo>[];
    return BillingOAuthProvidersDocument(
      issuer: json['issuer'] as String? ?? '',
      providers: list,
    );
  }
}

class BillingAuthProviderInfo {
  const BillingAuthProviderInfo({
    required this.id,
    required this.enabled,
    this.authorizedRedirectUris = const [],
    this.idpConsole,
  });

  /// Provider id: `google`, `microsoft`, `email`, …
  final String id;
  final bool enabled;
  final List<String> authorizedRedirectUris;
  final String? idpConsole;

  factory BillingAuthProviderInfo.fromJson(Map<String, dynamic> json) {
    final redirects = json['authorizedRedirectUris'];
    return BillingAuthProviderInfo(
      id: json['id'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      authorizedRedirectUris: redirects is List
          ? redirects.map((e) => e.toString()).toList()
          : const [],
      idpConsole: json['idpConsole'] as String?,
    );
  }
}

/// OIDC discovery from `GET /api/auth/.well-known/openid-configuration`.
class BillingOpenIdConfiguration {
  const BillingOpenIdConfiguration({
    required this.issuer,
    this.authorizationEndpoint,
    this.tokenEndpoint,
    this.jwksUri,
    this.scopesSupported = const [],
    this.grantTypesSupported = const [],
    this.codeChallengeMethodsSupported = const [],
  });

  final String issuer;
  final String? authorizationEndpoint;
  final String? tokenEndpoint;
  final String? jwksUri;
  final List<String> scopesSupported;
  final List<String> grantTypesSupported;
  final List<String> codeChallengeMethodsSupported;

  bool get supportsPkceS256 =>
      codeChallengeMethodsSupported.map((m) => m.toUpperCase()).contains('S256');

  factory BillingOpenIdConfiguration.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? raw) {
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).toList();
    }

    return BillingOpenIdConfiguration(
      issuer: json['issuer'] as String? ?? '',
      authorizationEndpoint: json['authorization_endpoint'] as String?,
      tokenEndpoint: json['token_endpoint'] as String?,
      jwksUri: json['jwks_uri'] as String?,
      scopesSupported: strings(json['scopes_supported']),
      grantTypesSupported: strings(json['grant_types_supported']),
      codeChallengeMethodsSupported:
          strings(json['code_challenge_methods_supported']),
    );
  }
}

/// Combined auth discovery for client login screens.
class BillingAuthDiscovery {
  const BillingAuthDiscovery({
    required this.providers,
    required this.openId,
  });

  final BillingOAuthProvidersDocument providers;
  final BillingOpenIdConfiguration openId;
}
