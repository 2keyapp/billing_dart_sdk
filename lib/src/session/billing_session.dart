import '../api/billing_api_client.dart';
import '../exceptions/billing_sync_error.dart';
import '../models/billing_token_error.dart';
import '../models/billing_token_payload.dart';
import '../sdk.dart';
import 'billing_token_store.dart';
import 'paying_party_context.dart';

sealed class SessionSyncOutcome {
  const SessionSyncOutcome();
}

class SessionSyncSuccess extends SessionSyncOutcome {
  const SessionSyncSuccess(this.message);
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

/// Orchestrates license JWT persistence, online sync, and offline verification.
class BillingSession {
  BillingSession({required BillingTokenStore store}) : _store = store;

  final BillingTokenStore _store;

  BillingTokenPayload? get payload => BillingSdk.getPayload();

  Future<void> initForAccount(String accountKey) async {
    final token = await _store.readToken(accountKey);
    BillingSdk.init(token);
  }

  Future<void> persistToken(String accountKey, String signedToken) async {
    await _store.writeToken(accountKey, signedToken);
    BillingSdk.init(signedToken);
  }

  Future<void> clearAccount(String accountKey) async {
    await _store.deleteToken(accountKey);
    BillingSdk.init(null);
  }

  Future<String?> readPayingPartyContext(String accountKey) =>
      _store.readPayingPartyContext(accountKey);

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
        await persistToken(accountKey, trimmed);
        return const SessionVerifySuccess(
          'Token verified. Subscription data updated.',
        );
      case VerifyFailure(:final error):
        return SessionVerifyFailure(error.message);
    }
  }

  Future<SessionSyncOutcome> syncOnlineForAccount({
    required String accountKey,
    required String authorizationToken,
    String rawPayingPartyContext = '',
    String? payingPartyId,
  }) async {
    final authToken = authorizationToken.trim();
    if (authToken.isEmpty || authToken == 'null') {
      return const SessionSyncFailure(
        'No session token for this profile. Sign in again so billing can verify identity.',
      );
    }

    final payingPartyContext = parsePayingPartyContext(rawPayingPartyContext);
    if (payingPartyContext == '') {
      return const SessionSyncFailure(
        'Enter a valid paying party email or a valid domain/URL.',
      );
    }

    if (payingPartyContext == null) {
      await _store.deletePayingPartyContext(accountKey);
    } else {
      await _store.writePayingPartyContext(accountKey, payingPartyContext);
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

    final result = await BillingSdk.syncFromServer(
      authorizationToken: authToken,
      payingPartyId: payingPartyId,
    );

    switch (result) {
      case SyncSuccess(:final signedToken):
        await persistToken(accountKey, signedToken);
        return const SessionSyncSuccess('Subscription data updated.');
      case SyncFailure(:final message, :final error):
        return SessionSyncFailure(message, error: error);
    }
  }
}
