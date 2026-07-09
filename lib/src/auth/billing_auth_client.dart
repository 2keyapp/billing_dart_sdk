import 'package:better_auth/better_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/billing_api_client.dart';
import '../logging/sdk_logger.dart';
import 'billing_api_token_mint.dart';
import 'billing_auth_discovery.dart';
import 'billing_auth_exception.dart';
import 'billing_auth_tokens.dart';
import 'billing_portal_urls.dart';

/// Persists Better Auth session data via [FlutterSecureStorage].
class SecureBillingAuthStorage implements AuthStorage {
  SecureBillingAuthStorage({
    FlutterSecureStorage? storage,
    required this.storagePrefix,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final String storagePrefix;

  String _key(String name) => '$storagePrefix:$name';

  @override
  Future<String?> getItem(String key) => _storage.read(key: _key(key));

  @override
  Future<void> setItem(String key, String value) =>
      _storage.write(key: _key(key), value: value);

  @override
  Future<void> removeItem(String key) => _storage.delete(key: _key(key));
}

/// Billing auth client — Better Auth Flutter SDK against the billing server.
///
/// - **Identity:** social sign-in via `better_auth` + `flutterClient`
/// - **Billing API:** `GET /api/auth/token` after session (JWT plugin)
/// - **Portal:** one-time-token session handoff to the billing portal
class BillingAuthClient {
  BillingAuthClient({
    required String billingBaseUrl,
    required String deepLinkScheme,
    required AuthStorage storage,
    AuthSessionLauncher? sessionLauncher,
    this.storagePrefix = 'billing_scomm',
  })  : _origin = normalizeBillingApiBaseUrl(billingBaseUrl),
        deepLinkScheme = deepLinkScheme {
    final base = _origin.endsWith('/') ? _origin : '$_origin/';
    _authClient = createAuthClient(
      baseUrl: base,
      basePath: '/api/auth',
      plugin: flutterClient(
        FlutterClientOptions(
          scheme: deepLinkScheme,
          storage: storage,
          storagePrefix: storagePrefix,
          sessionLauncher: sessionLauncher,
        ),
      ),
      sessionOptions: const SessionOptions(
        refetchInterval: Duration(minutes: 5),
        refetchOnAppResume: true,
      ),
    );
    _tokenMint = BillingApiTokenMint(authBaseUrl: authBaseUrl);
  }

  final String _origin;
  final String storagePrefix;
  final String deepLinkScheme;
  late final AuthClient _authClient;
  late final BillingApiTokenMint _tokenMint;

  /// Underlying Better Auth client (advanced use / plugins).
  AuthClient get authClient => _authClient;

  String get authBaseUrl {
    final base = _origin.endsWith('/') ? _origin : '$_origin/';
    return '${base}api/auth';
  }

  /// Call when the app returns to the foreground (session refresh).
  void onAppResumed() => _authClient.onAppResumed();

  // ---------------------------------------------------------------------------
  // Better Auth — identity & session
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

  Future<SessionData?> getSession() async {
    final result = await _authClient.getSession();
    _throwOnError(result.error, 'Could not load session');
    return result.data;
  }

  Future<void> signOut() async {
    final result = await _authClient.signOut();
    _throwOnError(result.error, 'Sign out failed');
  }

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

  Future<BillingOpenIdConfiguration> fetchOpenIdConfiguration() async {
    final result =
        await _authClient.getJson('/.well-known/openid-configuration');
    _throwOnError(result.error, 'Could not load OpenID configuration');
    return BillingOpenIdConfiguration.fromJson(result.data ?? {});
  }

  Future<BillingAuthDiscovery> discover() async {
    final results = await Future.wait([
      fetchOAuthProviders(),
      fetchOpenIdConfiguration(),
    ]);
    return BillingAuthDiscovery(
      providers: results[0] as BillingOAuthProvidersDocument,
      openId: results[1] as BillingOpenIdConfiguration,
    );
  }

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

  void _throwOnError(AuthError? error, String fallback) {
    if (error == null) return;
    throw BillingAuthException(
      error.message.isNotEmpty ? error.message : fallback,
      statusCode: error.status,
    );
  }
}
