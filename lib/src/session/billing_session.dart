import '../api/billing_api_client.dart';
import '../auth/auth_user_profile.dart';
import '../auth/billing_auth_tokens.dart';
import '../exceptions/billing_sync_error.dart';
import '../models/billing_token_error.dart';
import '../models/billing_token_payload.dart';
import '../billing_sdk.dart';
import 'billing_account_session.dart';
import 'billing_session_store.dart';

sealed class SessionSyncOutcome {
  const SessionSyncOutcome();
}

class SessionSyncSuccess extends SessionSyncOutcome {
  const SessionSyncSuccess(this.session, {this.message = 'Subscription data updated.'});
  final BillingAccountSession session;
  final String message;
}

class SessionSyncFailure extends SessionSyncOutcome {
  const SessionSyncFailure(this.message, {this.error});
  final String message;
  final BillingSyncError? error;
}

sealed class SessionVerifyOutcome {
  const SessionVerifyOutcome();
}

class SessionVerifySuccess extends SessionVerifyOutcome {
  const SessionVerifySuccess(this.message);
  final String message;
}

class SessionVerifyFailure extends SessionVerifyOutcome {
  const SessionVerifyFailure(this.message);
  final String message;
}

/// Orchestrates auth tokens, license JWT persistence, online sync, and offline verify.
///
/// **Using party (SDK app):** sync loads assigned subscriptions into the license JWT.
/// **Paying party (portal):** [BillingAccountSession.canOpenBillingPortal] is true when
/// the authenticated identity owns the org; portal validates server-side.
class BillingSession {
  BillingSession({required BillingSessionStore store}) : _store = store;

  final BillingSessionStore _store;

  BillingTokenPayload? get payload => BillingSdk.getPayload();

  BillingAccountSession? _cachedSession;
  BillingAccountSession? get accountSession => _cachedSession;

  /// Restores persisted session and license JWT for [accountKey].
  Future<BillingAccountSession?> initForAccount(String accountKey) async {
    final session = await _store.readAccountSession(accountKey);
    _cachedSession = session;
    if (session?.licenseJwt != null) {
      BillingSdk.init(session!.licenseJwt);
    } else {
      final legacy = await _store.readToken(accountKey);
      BillingSdk.init(legacy);
    }
    return session;
  }

  /// Stores OAuth tokens after PKCE login (before license sync).
  Future<BillingAccountSession> persistAuthTokens({
    required String accountKey,
    required BillingAuthTokens tokens,
  }) async {
    final profile = AuthUserProfile.fromAccessToken(tokens.accessToken);
    final session = BillingAccountSession(
      authTokens: tokens,
      userProfile: profile,
      updatedAt: DateTime.now().toUtc(),
    );
    await _store.writeAccountSession(accountKey, session);
    _cachedSession = session;
    return session;
  }

  Future<void> persistLicense({
    required String accountKey,
    required String licenseJwt,
    BillingAccountSession? baseSession,
  }) async {
    BillingSdk.init(licenseJwt);
    final payload = BillingSdk.getPayload();
    final current = baseSession ?? _cachedSession;
    if (current == null) {
      await _store.writeToken(accountKey, licenseJwt);
      return;
    }
    final updated = current.copyWith(
      licenseJwt: licenseJwt,
      licensePayload: payload,
      updatedAt: DateTime.now().toUtc(),
    );
    await _writeSession(accountKey, updated, licenseJwt);
  }

  Future<void> clearAccount(String accountKey) async {
    await _store.deleteAccountSession(accountKey);
    await _store.deleteToken(accountKey);
    _cachedSession = null;
    BillingSdk.init(null);
  }

  Future<SessionVerifyOutcome> verifyOfflineToken({
    required String accountKey,
    required String token,
  }) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return const SessionVerifyFailure('Paste a billing token first.');
    }

    final result = BillingSdk.verifyAndDecode(trimmed);
    switch (result) {
      case VerifySuccess():
        await _store.writeToken(accountKey, trimmed);
        final current = _cachedSession;
        if (current != null) {
          await _writeSession(
            accountKey,
            current.copyWith(
              licenseJwt: trimmed,
              licensePayload: BillingSdk.getPayload(),
              updatedAt: DateTime.now().toUtc(),
            ),
            trimmed,
          );
        }
        return const SessionVerifySuccess(
          'Token verified. Subscription data updated.',
        );
      case VerifyFailure(:final error):
        return SessionVerifyFailure(error.message);
    }
  }

  /// Online sync: bootstrap org context → fetch license JWT → persist session.
  Future<SessionSyncOutcome> syncOnlineForAccount({
    required String accountKey,
    String? accessToken,
    String? payingPartyId,
  }) async {
    final authToken = (accessToken ?? _cachedSession?.accessToken ?? '').trim();
    if (authToken.isEmpty) {
      return const SessionSyncFailure(
        'No access token. Sign in to billing and try again.',
      );
    }

    final bootstrap = await BillingSdk.ensureBillingContext(
      authorizationToken: authToken,
    );
    if (bootstrap is BootstrapFailure) {
      return SessionSyncFailure(
        bootstrap.message,
        error: bootstrap.error,
      );
    }
    final stats = (bootstrap as BootstrapSuccess).stats;

    final result = await BillingSdk.syncFromServer(
      authorizationToken: authToken,
      payingPartyId: payingPartyId ?? _cachedSession?.payingPartyIdHeader,
    );

    switch (result) {
      case SyncSuccess(:final signedToken):
        BillingSdk.init(signedToken);
        final payload = BillingSdk.getPayload();
        final tokens = _cachedSession?.authTokens ??
            BillingAuthTokens(accessToken: authToken);
        final profile = _cachedSession?.userProfile ??
            AuthUserProfile.fromAccessToken(authToken);
        final session = BillingAccountSession(
          authTokens: tokens,
          userProfile: profile,
          billingStats: stats,
          licenseJwt: signedToken,
          licensePayload: payload,
          payingPartyIdHeader:
              payingPartyId ?? _cachedSession?.payingPartyIdHeader,
          updatedAt: DateTime.now().toUtc(),
        );
        await _writeSession(accountKey, session, signedToken);
        return SessionSyncSuccess(session);
      case SyncFailure(:final message, :final error):
        return SessionSyncFailure(message, error: error);
    }
  }

  /// Refreshes OAuth tokens and re-runs [syncOnlineForAccount].
  Future<SessionSyncOutcome> refreshAndSync({
    required String accountKey,
    required Future<BillingAuthTokens> Function(String refreshToken) refresh,
  }) async {
    final current = _cachedSession ?? await _store.readAccountSession(accountKey);
    final refreshToken = current?.authTokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return const SessionSyncFailure(
        'Session expired. Sign in again to sync billing.',
      );
    }
    try {
      final tokens = await refresh(refreshToken);
      await persistAuthTokens(accountKey: accountKey, tokens: tokens);
      return syncOnlineForAccount(
        accountKey: accountKey,
        accessToken: tokens.accessToken,
        payingPartyId: current?.payingPartyIdHeader,
      );
    } catch (e) {
      return SessionSyncFailure('Could not refresh session. Sign in again.');
    }
  }

  Future<void> _writeSession(
    String accountKey,
    BillingAccountSession session,
    String licenseJwt,
  ) async {
    await _store.writeAccountSession(accountKey, session);
    await _store.writeToken(accountKey, licenseJwt);
    _cachedSession = session;
  }
}
