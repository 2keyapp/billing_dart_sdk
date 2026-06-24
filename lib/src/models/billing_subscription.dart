import 'jwt_payload_keys.dart';

/// A single subscription in the billing token payload.
/// Each element of top-level `subscriptions[]`.
class BillingSubscription {
  const BillingSubscription({
    required this.subscriptionId,
    required this.planId,
    required this.productId,
    required this.planName,
    required this.productName,
    required this.subscriptionStatus,
    required this.validUntil,
    this.addonCode,
    this.assignedUserPartyId,
  });

  final String subscriptionId;
  final String planId;
  final String productId;
  final String planName;
  final String productName;
  final String subscriptionStatus;
  final DateTime validUntil;
  /// Stable add-on code from billing (`linux`, `ai_assistant`, …).
  final String? addonCode;
  final String? assignedUserPartyId;

  /// Parses from subscription object in JWT payload. Throws [FormatException] if invalid.
  factory BillingSubscription.fromJson(Map<String, dynamic> json) {
    final subscriptionId = getKey(json, 'subscription_id', 'subscriptionId');
    final planId = getKey(json, 'plan_id', 'planId');
    final productId = getKey(json, 'product_id', 'productId');
    final planName = getKey(json, 'plan_name', 'planName');
    final productName = getKey(json, 'product_name', 'productName');
    final status = getKey(json, 'subscription_status', 'subscriptionStatus');
    final validUntil = getKey(json, 'valid_until', 'validUntil');
    if (subscriptionId is! String)
      throw FormatException('subscriptions[].subscription_id required.');
    if (planId is! String)
      throw FormatException('subscriptions[].plan_id required.');
    if (productId is! String)
      throw FormatException('subscriptions[].product_id required.');
    if (planName is! String)
      throw FormatException('subscriptions[].plan_name required.');
    if (productName is! String)
      throw FormatException('subscriptions[].product_name required.');
    if (status is! String)
      throw FormatException('subscriptions[].subscription_status required.');
    final validUntilInt = parseInt(validUntil);
    if (validUntilInt == null)
      throw FormatException(
        'subscriptions[].valid_until required (Unix timestamp).',
      );
    final assigned = getKey(
      json,
      'assigned_user_party_id',
      'assignedUserPartyId',
    );
    final addonCodeRaw = getKey(json, 'addon_code', 'addonCode');
    return BillingSubscription(
      subscriptionId: subscriptionId,
      planId: planId,
      productId: productId,
      planName: planName,
      productName: productName,
      subscriptionStatus: status,
      validUntil: dateTimeFromUnixSeconds(validUntilInt),
      addonCode: addonCodeRaw is String && addonCodeRaw.isNotEmpty
          ? addonCodeRaw
          : null,
      assignedUserPartyId:
          assigned is String && assigned.isNotEmpty ? assigned : null,
    );
  }

  /// Matches a catalog add-on id (stable code or numeric billing plan id).
  bool matchesAddonRef(String addonRef) {
    final target = addonRef.trim().toLowerCase();
    if (target.isEmpty) return false;
    if (planId.toLowerCase() == target) return true;
    if (addonCode?.toLowerCase() == target) return true;
    return false;
  }

  /// Whether this subscription is currently active (e.g. active, trialing).
  bool get isActive =>
      subscriptionStatus.toLowerCase() == 'active' ||
      subscriptionStatus.toLowerCase() == 'trialing';

  /// Whether the validity period has ended (now > valid_until).
  bool get isPeriodEnded => DateTime.now().isAfter(validUntil);
}
