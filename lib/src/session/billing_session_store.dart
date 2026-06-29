import 'billing_account_session.dart';
import 'billing_token_store.dart';

/// Persists license JWT, optional org context, and full [BillingAccountSession] per account.
abstract class BillingSessionStore implements BillingTokenStore {
  Future<BillingAccountSession?> readAccountSession(String accountKey);
  Future<void> writeAccountSession(String accountKey, BillingAccountSession session);
  Future<void> deleteAccountSession(String accountKey);
}
