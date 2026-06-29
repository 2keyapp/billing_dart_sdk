import 'dart:convert';

import 'billing_account_session.dart';
import 'billing_session_store.dart';

/// In-memory [BillingSessionStore] for tests and prototyping.
class InMemoryBillingSessionStore implements BillingSessionStore {
  final Map<String, String> _tokens = {};
  final Map<String, String> _partyContext = {};
  final Map<String, String> _sessions = {};

  @override
  Future<void> deleteAccountSession(String accountKey) async {
    _sessions.remove(accountKey);
    await deleteToken(accountKey);
  }

  @override
  Future<void> deletePayingPartyContext(String accountKey) async {
    _partyContext.remove(accountKey);
  }

  @override
  Future<void> deleteToken(String accountKey) async {
    _tokens.remove(accountKey);
  }

  @override
  Future<BillingAccountSession?> readAccountSession(String accountKey) async {
    final raw = _sessions[accountKey];
    if (raw == null) return null;
    return BillingAccountSession.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  @override
  Future<String?> readPayingPartyContext(String accountKey) async =>
      _partyContext[accountKey];

  @override
  Future<String?> readToken(String accountKey) async => _tokens[accountKey];

  @override
  Future<void> writeAccountSession(
    String accountKey,
    BillingAccountSession session,
  ) async {
    _sessions[accountKey] = jsonEncode(session.toJson());
  }

  @override
  Future<void> writePayingPartyContext(
    String accountKey,
    String contextValue,
  ) async {
    _partyContext[accountKey] = contextValue;
  }

  @override
  Future<void> writeToken(String accountKey, String token) async {
    _tokens[accountKey] = token;
  }
}
