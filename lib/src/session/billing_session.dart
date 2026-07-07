import 'dart:async';

import '../api/billing_api_client.dart';
import '../auth/auth_user_profile.dart';
import '../auth/billing_auth_tokens.dart';
import '../exceptions/billing_sync_error.dart';
import '../models/billing_token_error.dart';
import '../models/billing_token_payload.dart';
import '../billing_sdk.dart';
import 'billing_account_session.dart';
import 'billing_session_store.dart';
import 'license_entitlements.dart';

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
///
/// Periodic polling runs only when [shouldPollLicenseEntitlements] is true (assigned
/// seat or subscriptions in the license). Manual [syncOnlineForAccount] always works.
class BillingSession {
  BillingSession({required BillingSessionStore store}) : _store = store;

  final BillingSessionStore _store;

  BillingTokenPayload? get payload => BillingSdk.getPayload();

  BillingAccountSession? _cachedSession;
  BillingAccountSession? get accountSession => _cachedSession;

  Timer? _pollTimer;
  String? _pollingAccountKey;
  Duration _pollInterval = defaultLicensePollInterval;
  bool _pollInFlight = false;

  bool get isLicensePollingActive => _pollTimer != null;

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
    String? licenseEtag,
  }) async {
    BillingSdk.init(licenseJwt);
    final payload = BillingSdk.getPayload();
    final current = baseSession ?? _cachedSession;
    if (current == null) {
      await _store.writeToken(accountKey, licenseJwt);
      return;
    }
    final now = DateTime.now().toUtc();
    final updated = current.copyWith(
      licenseJwt: licenseJwt,
      licensePayload: payload,
      licenseEtag: licenseEtag,
      lastLicenseSyncAt: now,
      updatedAt: now,
    );
    await _writeSession(accountKey, updated, licenseJwt);
    await _reconcileLicensePolling(accountKey);
  }

  Future<void> clearAccount(String accountKey) async {
    stopLicensePolling();
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

  /// Full online sync (always requests a fresh license). Use for manual "Sync billing".
  Future<SessionSyncOutcome> syncOnlineForAccount({
    required String accountKey,
    String? accessToken,
    String? payingPartyId,
  }) =>
      _syncLicenseForAccount(
        accountKey: accountKey,
        accessToken: accessToken,
        payingPartyId: payingPartyId,
        useCachedEtag: false,
      );

  /// Conditional sync using stored ETag — for foreground resume and background polling.
  Future<SessionSyncOutcome> syncIfLicenseChanged({
    required String accountKey,
    String? accessToken,
    String? payingPartyId,
  }) =>
      _syncLicenseForAccount(
        accountKey: accountKey,
        accessToken: accessToken,
        payingPartyId: payingPartyId,
        useCachedEtag: true,
      );

  /// Call when the host app returns to the foreground.
  Future<SessionSyncOutcome?> onAppForeground({required String accountKey}) {
    return syncIfLicenseChanged(accountKey: accountKey);
  }

  /// Starts periodic license checks. Polling is a no-op until entitlements exist.
  void startLicensePolling({
    required String accountKey,
    Duration interval = defaultLicensePollInterval,
  }) {
    _pollingAccountKey = accountKey;
    _pollInterval = interval;
    _pollTimer?.cancel();
    _pollTimer = null;
    unawaited(_reconcileLicensePolling(accountKey));
  }

  /// Stops background license polling.
  void stopLicensePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollingAccountKey = null;
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

  Future<SessionSyncOutcome> _syncLicenseForAccount({
    required String accountKey,
    String? accessToken,
    String? payingPartyId,
    required bool useCachedEtag,
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

    final partyId = payingPartyId ?? _cachedSession?.payingPartyIdHeader;
    final ifNoneMatch =
        useCachedEtag ? _cachedSession?.licenseEtag : null;

    final result = await BillingSdk.syncFromServer(
      authorizationToken: authToken,
      payingPartyId: partyId,
      ifNoneMatch: ifNoneMatch,
    );

    final now = DateTime.now().toUtc();
    final tokens = _cachedSession?.authTokens ??
        BillingAuthTokens(accessToken: authToken);
    final profile = _cachedSession?.userProfile ??
        AuthUserProfile.fromAccessToken(authToken);

    switch (result) {
      case SyncNotModified(:final etag):
        final unchanged = (_cachedSession ??
                BillingAccountSession(
                  authTokens: tokens,
                  userProfile: profile,
                ))
            .copyWith(
          billingStats: stats,
          licenseEtag: etag ?? _cachedSession?.licenseEtag,
          lastLicenseSyncAt: now,
          payingPartyIdHeader: partyId,
          updatedAt: now,
        );
        await _store.writeAccountSession(accountKey, unchanged);
        _cachedSession = unchanged;
        await _reconcileLicensePolling(accountKey);
        return SessionSyncSuccess(
          unchanged,
          message: 'License already up to date.',
        );
      case SyncSuccess(:final signedToken, :final etag):
        BillingSdk.init(signedToken);
        final payload = BillingSdk.getPayload();
        final session = BillingAccountSession(
          authTokens: tokens,
          userProfile: profile,
          billingStats: stats,
          licenseJwt: signedToken,
          licensePayload: payload,
          licenseEtag: etag,
          payingPartyIdHeader: partyId,
          lastLicenseSyncAt: now,
          updatedAt: now,
        );
        await _writeSession(accountKey, session, signedToken);
        await _reconcileLicensePolling(accountKey);
        return SessionSyncSuccess(session);
      case SyncFailure(:final message, :final error):
        return SessionSyncFailure(message, error: error);
    }
  }

  Future<void> _pollTick(String accountKey) async {
    if (_pollInFlight) return;
    if (!shouldPollLicenseEntitlements(_cachedSession)) {
      await _reconcileLicensePolling(accountKey);
      return;
    }
    _pollInFlight = true;
    try {
      await syncIfLicenseChanged(accountKey: accountKey);
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _reconcileLicensePolling(String accountKey) async {
    final key = _pollingAccountKey ?? accountKey;
    if (!shouldPollLicenseEntitlements(_cachedSession)) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_pollingAccountKey == null) {
      return;
    }
    if (_pollTimer != null) {
      return;
    }
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollTick(key));
    });
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
