/// Billing portal URL helper for paying-party management (validated server-side).
class BillingPortalUrls {
  const BillingPortalUrls({required this.portalBaseUrl});

  /// Portal web app origin, e.g. `https://billing.example.com` or dedicated portal host.
  final String portalBaseUrl;

  /// Opens portal home; user must be paying-party owner (server validates access token).
  Uri home({String? accessToken}) {
    final base = portalBaseUrl.endsWith('/')
        ? portalBaseUrl.substring(0, portalBaseUrl.length - 1)
        : portalBaseUrl;
    if (accessToken == null || accessToken.isEmpty) {
      return Uri.parse(base);
    }
    return Uri.parse(base).replace(
      queryParameters: {'access_token': accessToken},
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
