import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'billing_account_session.dart';
import 'billing_session_store.dart';

/// [BillingSessionStore] backed by [FlutterSecureStorage].
///
/// Use the same [storagePrefix] as [SecureBillingAuthStorage] / [BillingSdkConfig].
class SecureBillingSessionStore implements BillingSessionStore {
  SecureBillingSessionStore({
    required this.storagePrefix,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final String storagePrefix;

  String get _tokenPrefix => '$storagePrefix:token:';
  String get _payingPartyPrefix => '$storagePrefix:paying_party:';
  String get _sessionPrefix => '$storagePrefix:account_session:';

  String _sanitize(String accountKey) =>
      accountKey.replaceAll(RegExp(r'[^a-zA-Z0-9._@-]'), '_');

  String _tokenKey(String accountKey) => '$_tokenPrefix${_sanitize(accountKey)}';

  String _payingPartyKey(String accountKey) =>
      '$_payingPartyPrefix${_sanitize(accountKey)}';

  String _sessionKey(String accountKey) =>
      '$_sessionPrefix${_sanitize(accountKey)}';

  @override
  Future<String?> readToken(String accountKey) =>
      _storage.read(key: _tokenKey(accountKey));

  @override
  Future<void> writeToken(String accountKey, String token) =>
      _storage.write(key: _tokenKey(accountKey), value: token);

  @override
  Future<void> deleteToken(String accountKey) =>
      _storage.delete(key: _tokenKey(accountKey));

  @override
  Future<String?> readPayingPartyContext(String accountKey) =>
      _storage.read(key: _payingPartyKey(accountKey));

  @override
  Future<void> writePayingPartyContext(
    String accountKey,
    String contextValue,
  ) =>
      _storage.write(key: _payingPartyKey(accountKey), value: contextValue);

  @override
  Future<void> deletePayingPartyContext(String accountKey) =>
      _storage.delete(key: _payingPartyKey(accountKey));

  @override
  Future<BillingAccountSession?> readAccountSession(String accountKey) async {
    final raw = await _storage.read(key: _sessionKey(accountKey));
    if (raw == null || raw.isEmpty) return null;
    return BillingAccountSession.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> writeAccountSession(
    String accountKey,
    BillingAccountSession session,
  ) =>
      _storage.write(
        key: _sessionKey(accountKey),
        value: jsonEncode(session.toJson()),
      );

  @override
  Future<void> deleteAccountSession(String accountKey) async {
    await _storage.delete(key: _sessionKey(accountKey));
    await deletePayingPartyContext(accountKey);
  }
}
