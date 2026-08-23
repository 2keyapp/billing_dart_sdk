/// Billing portal URL helper for paying-party management (validated server-side).
class BillingPortalUrls {
  const BillingPortalUrls({
    required this.portalBaseUrl,
    this.shopPath = '/shop',
  });

  /// Portal web app origin, e.g. `https://billing.example.com` or dedicated portal host.
  final String portalBaseUrl;

  /// Marketplace path appended to the portal origin (default `/shop`).
  final String shopPath;

  String get _base {
    return portalBaseUrl.endsWith('/')
        ? portalBaseUrl.substring(0, portalBaseUrl.length - 1)
        : portalBaseUrl;
  }

  String get _normalizedShopPath {
    final configured = shopPath.trim().isEmpty ? '/shop' : shopPath.trim();
    return configured.startsWith('/') ? configured : '/$configured';
  }

  /// Opens portal home; user must be paying-party owner (server validates access token).
  Uri home({String? accessToken}) {
    if (accessToken == null || accessToken.isEmpty) {
      return Uri.parse(_base);
    }
    return Uri.parse(_base).replace(
      queryParameters: {'access_token': accessToken},
    );
  }

  /// Marketplace / shop landing page.
  Uri marketplace({String? accessToken}) {
    final path = _normalizedShopPath;
    final uri = Uri.parse('$_base$path');
    final token = accessToken?.trim();
    if (token == null || token.isEmpty) return uri;
    return uri.replace(queryParameters: {'access_token': token});
  }

  /// Portal shop path for a plan by numeric id, e.g. `/shop/12`.
  String planPurchasePath(int planId) {
    final base = _normalizedShopPath;
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$normalizedBase/$planId';
  }

  /// Full portal purchase URL for [planId].
  Uri planPurchase(int planId, {String? accessToken}) {
    final uri = Uri.parse('$_base${planPurchasePath(planId)}');
    final token = accessToken?.trim();
    if (token == null || token.isEmpty) return uri;
    return uri.replace(queryParameters: {'access_token': token});
  }

  /// Session handoff entry — Flutter app opens this after minting a one-time token.
  ///
  /// The portal verifies `token` and continues PKCE to establish browser JWTs.
  Uri sessionHandoff({String? redirectPath}) {
    final params = <String, String>{};
    final redirect = redirectPath?.trim();
    if (redirect != null &&
        redirect.isNotEmpty &&
        redirect.startsWith('/') &&
        !redirect.startsWith('//')) {
      params['redirect'] = redirect;
    }
    return Uri.parse('$_base/auth/handoff').replace(
      queryParameters: params.isEmpty ? null : params,
    );
  }

  /// OAuth authorize entry for portal login (PKCE handled by portal or app).
  Uri authLogin({required String billingAuthBaseUrl, required String state}) {
    final auth = billingAuthBaseUrl.endsWith('/')
        ? billingAuthBaseUrl.substring(0, billingAuthBaseUrl.length - 1)
        : billingAuthBaseUrl;
    return Uri.parse('$auth/login').replace(queryParameters: {'state': state});
  }
}
