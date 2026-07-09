/// Billing portal URL helper for paying-party management (validated server-side).
class BillingPortalUrls {
  const BillingPortalUrls({required this.portalBaseUrl});

  /// Portal web app origin, e.g. `https://billing.example.com` or dedicated portal host.
  final String portalBaseUrl;

  String get _base {
    return portalBaseUrl.endsWith('/')
        ? portalBaseUrl.substring(0, portalBaseUrl.length - 1)
        : portalBaseUrl;
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
