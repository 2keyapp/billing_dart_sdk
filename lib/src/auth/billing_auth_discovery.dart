/// Enabled login methods from `GET /api/auth/.well-known/oauth-providers`.
class BillingOAuthProvidersDocument {
  const BillingOAuthProvidersDocument({
    required this.issuer,
    required this.providers,
  });

  final String issuer;
  final List<BillingAuthProviderInfo> providers;

  /// Providers the server has enabled (google, microsoft, apple, email, …).
  List<BillingAuthProviderInfo> get enabledProviders =>
      providers.where((p) => p.enabled).toList();

  bool get isGoogleEnabled => _isEnabled('google');
  bool get isMicrosoftEnabled => _isEnabled('microsoft');
  bool get isAppleEnabled => _isEnabled('apple');
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
    this.redirectUri,
    this.idpConsole,
    this.authorizedRedirectUris = const [],
  });

  /// Provider id: `google`, `microsoft`, `apple`, `email`, …
  final String id;
  final bool enabled;

  /// Better Auth social callback URL (`{issuer}/callback/{id}`).
  final String? redirectUri;
  final String? idpConsole;

  /// Legacy shape; populated from [redirectUri] when present.
  final List<String> authorizedRedirectUris;

  factory BillingAuthProviderInfo.fromJson(Map<String, dynamic> json) {
    final redirectUri = json['redirectUri'] as String?;
    final redirects = json['authorizedRedirectUris'];
    final legacyRedirects = redirects is List
        ? redirects.map((e) => e.toString()).toList()
        : const <String>[];
    return BillingAuthProviderInfo(
      id: json['id'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      redirectUri: redirectUri,
      idpConsole: json['idpConsole'] as String?,
      authorizedRedirectUris: redirectUri != null && redirectUri.isNotEmpty
          ? [redirectUri, ...legacyRedirects]
          : legacyRedirects,
    );
  }
}

/// Combined auth discovery for client login screens.
typedef BillingAuthDiscovery = BillingOAuthProvidersDocument;
