import 'package:better_auth/better_auth.dart' as ba;

import '../api/billing_api_client.dart';
import '../logging/sdk_logger.dart';
import 'billing_api_token_mint.dart';
import 'billing_auth_discovery.dart';
import 'billing_auth_exception.dart';
import 'billing_auth_session.dart';
import 'billing_auth_storage.dart';
import 'billing_auth_tokens.dart';
import 'billing_portal_urls.dart';

/// Adapts [BillingAuthStorage] to Better Auth's internal [ba.AuthStorage].
class _BetterAuthStorageAdapter implements ba.AuthStorage {
  _BetterAuthStorageAdapter(this._inner);

  final BillingAuthStorage _inner;

  @override
  Future<String?> getItem(String key) => _inner.getItem(key);

  @override
  Future<void> setItem(String key, String value) =>
      _inner.setItem(key, value);

  @override
  Future<void> removeItem(String key) => _inner.removeItem(key);
}

/// Billing auth client — Better Auth Flutter SDK against the billing server.
///
/// Host apps depend only on this facade (and other `billing_dart_sdk` types).
/// Better Auth stays an internal SDK dependency and is not re-exported.
///
/// - **Identity:** social / email sign-in
/// - **Billing API:** `GET /api/auth/token` after session (JWT plugin)
/// - **Portal:** one-time-token session handoff to the billing portal
class BillingAuthClient {
  BillingAuthClient({
    required String billingBaseUrl,
    required String deepLinkScheme,
    required BillingAuthStorage storage,
    AuthSessionLauncher? sessionLauncher,
    this.storagePrefix = 'billing_scomm',
  })  : _origin = normalizeBillingApiBaseUrl(billingBaseUrl),
        deepLinkScheme = deepLinkScheme {
    final base = _origin.endsWith('/') ? _origin : '$_origin/';
    _authClient = ba.createAuthClient(
      baseUrl: base,
      basePath: '/api/auth',
      plugin: ba.flutterClient(
        ba.FlutterClientOptions(
          scheme: deepLinkScheme,
          storage: _BetterAuthStorageAdapter(storage),
          storagePrefix: storagePrefix,
          sessionLauncher: sessionLauncher,
        ),
      ),
      sessionOptions: const ba.SessionOptions(
        refetchInterval: Duration(minutes: 5),
        refetchOnAppResume: true,
      ),
    );
    _tokenMint = BillingApiTokenMint(authBaseUrl: authBaseUrl);
  }

  final String _origin;
  final String storagePrefix;
  final String deepLinkScheme;
  late final ba.AuthClient _authClient;
  late final BillingApiTokenMint _tokenMint;

  String get authBaseUrl {
    final base = _origin.endsWith('/') ? _origin : '$_origin/';
    return '${base}api/auth';
  }

  /// Enables or disables Better Auth's built-in session polling.
  ///
  /// Host apps that refresh the session explicitly (app resume, sign-in, token
  /// refresh) should call `setOnline(false)` after construction.
  void setOnline(bool value) => _authClient.setOnline(value);

  /// Call when the app returns to the foreground (session refresh).
  void onAppResumed() => _authClient.onAppResumed();

  // ---------------------------------------------------------------------------
  // Identity & session
  // ---------------------------------------------------------------------------

  Future<void> signUpEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    final result = await _authClient.signUpEmail(
      email: email,
      password: password,
      name: name,
    );
    _throwOnError(result.error, 'Sign up failed');
  }

  Future<void> signInEmail({
    required String email,
    required String password,
  }) async {
    final result = await _authClient.signInEmail(
      email: email,
      password: password,
    );
    _throwOnError(result.error, 'Sign in failed');
  }

  Future<void> signInSocial({
    required String provider,
    String? callbackURL,
  }) async {
    final result = await _authClient.signInSocial(
      provider: provider,
      callbackURL: callbackURL ?? '$deepLinkScheme://auth/callback',
    );
    _throwOnError(result.error, 'Social sign-in failed');
  }

  Future<BillingAuthSession?> getSession() async {
    final result = await _authClient.getSession();
    _throwOnError(result.error, 'Could not load session');
    final data = result.data;
    if (data == null) return null;
    final user = data.user;
    return BillingAuthSession(
      user: BillingAuthSessionUser(
        id: user.id,
        email: user.email.isEmpty ? null : user.email,
        name: user.name.isEmpty ? null : user.name,
        image: user.image,
        emailVerified: user.emailVerified,
      ),
    );
  }

  Future<void> signOut() async {
    final result = await _authClient.signOut();
    _throwOnError(result.error, 'Sign out failed');
  }

  /// Clears persisted auth cookies/session cache on this device.
  Future<void> clearLocalAuthSession() =>
      _authClient.plugin?.clearSessionCache() ?? Future.value();

  Future<String> getSessionCookie() => _authClient.getCookie();

  // ---------------------------------------------------------------------------
  // Discovery — login UI bootstrap
  // ---------------------------------------------------------------------------

  /// Enabled login methods from `GET /api/auth/.well-known/oauth-providers`.
  Future<BillingOAuthProvidersDocument> fetchOAuthProviders() async {
    final result = await _authClient.getJson('/.well-known/oauth-providers');
    _throwOnError(result.error, 'Could not load auth providers');
    return BillingOAuthProvidersDocument.fromJson(result.data ?? {});
  }

  /// Login discovery — oauth-providers only (no OIDC metadata on billing).
  Future<BillingAuthDiscovery> discover() => fetchOAuthProviders();

  // ---------------------------------------------------------------------------
  // Billing API JWTs — JWT plugin (`GET /api/auth/token`)
  // ---------------------------------------------------------------------------

  /// Mints a billing API JWT from the current Better Auth session.
  Future<BillingAuthTokens> acquireApiToken() async {
    final cookie = await getSessionCookie();
    return _tokenMint.mintFromSessionCookie(cookie);
  }

  /// Re-mints the billing API JWT when the session is still valid.
  Future<BillingAuthTokens> refreshApiToken() => acquireApiToken();

  // ---------------------------------------------------------------------------
  // Portal session handoff (Flutter → browser)
  // ---------------------------------------------------------------------------

  Future<Uri> createPortalHandoffUrl({
    required String portalBaseUrl,
    String? redirectPath,
  }) async {
    final portalUrls = BillingPortalUrls(portalBaseUrl: portalBaseUrl);
    final target = portalUrls.sessionHandoff(redirectPath: redirectPath);
    final result = await _authClient.createSessionHandoffUrl(
      targetUrl: target.toString(),
    );
    if (result.error != null) {
      throw BillingAuthException(
        result.error?.message ?? 'Session handoff failed',
      );
    }
    final url = result.data;
    if (url == null) {
      throw const BillingAuthException(
        'Session handoff URL was not returned by the auth server.',
      );
    }
    BillingSdkLogger.info('BillingAuthClient: portal handoff URL ready');
    return url;
  }

  Future<void> dispose() async {
    _tokenMint.close();
    await _authClient.dispose();
  }

  void _throwOnError(ba.AuthError? error, String fallback) {
    if (error == null) return;
    throw BillingAuthException(
      error.message.isNotEmpty ? error.message : fallback,
      statusCode: error.status,
    );
  }
}
