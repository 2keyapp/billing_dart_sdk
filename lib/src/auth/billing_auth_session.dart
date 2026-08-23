/// Identity fields from a live billing auth session (`/get-session`).
///
/// SDK-owned stand-in for Better Auth's session user so host apps never import
/// `package:better_auth`.
class BillingAuthSessionUser {
  const BillingAuthSessionUser({
    required this.id,
    this.email,
    this.name,
    this.image,
    this.emailVerified = false,
  });

  final String id;
  final String? email;
  final String? name;
  final String? image;
  final bool emailVerified;
}

/// Live auth session snapshot for using-party apps.
class BillingAuthSession {
  const BillingAuthSession({required this.user});

  final BillingAuthSessionUser user;
}

/// Opens an auth session in a browser / ASWebAuthenticationSession-style UI
/// and returns the final redirect URL on success.
///
/// Wire this to the host app's OAuth launcher (loopback, deep link, etc.).
typedef AuthSessionLauncher = Future<Uri?> Function({
  required Uri authorizationUrl,
  required Uri callbackUrl,
});
