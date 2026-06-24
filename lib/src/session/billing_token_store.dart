/// Persists billing license JWT and optional org billing context per account.
abstract class BillingTokenStore {
  Future<String?> readToken(String accountKey);
  Future<void> writeToken(String accountKey, String token);
  Future<void> deleteToken(String accountKey);

  Future<String?> readPayingPartyContext(String accountKey);
  Future<void> writePayingPartyContext(String accountKey, String contextValue);
  Future<void> deletePayingPartyContext(String accountKey);
}
