import 'billing_account_session.dart';

/// Default interval between background license polls when entitlements exist.
const Duration defaultLicensePollInterval = Duration(hours: 6);

/// Whether the account should run periodic license polling.
///
/// Polling is skipped when there is no assigned seat and no subscriptions in the
/// cached license. Manual [BillingSession.syncOnlineForAccount] remains available.
bool shouldPollLicenseEntitlements(BillingAccountSession? session) {
  if (session == null) return false;

  final payload = session.licensePayload;

  if (payload != null && payload.subscriptions.isNotEmpty) {
    return true;
  }

  return session.billingStats?.hasAssignedSeatForIdentity ?? false;
}
