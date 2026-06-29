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
    this.usingPartyIdentityProvider,
    this.usingPartyIdentitySubject,
    this.usingPartyEmail,
    this.assignedUserPartyId,
  });

  final String subscriptionId;
  final String planId;
  final String productId;
  final String planName;
  final String productName;
  final String subscriptionStatus;
  final DateTime validUntil;
  final String? addonCode;
  final String? usingPartyIdentityProvider;
  final String? usingPartyIdentitySubject;
  final String? usingPartyEmail;
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
    final addon = getKey(json, 'addon_code', 'addonCode');
    final usingProvider = getKey(
      json,
      'using_party_identity_provider',
      'usingPartyIdentityProvider',
    );
    final usingSubject = getKey(
      json,
      'using_party_identity_subject',
      'usingPartyIdentitySubject',
    );
    final usingEmail = getKey(json, 'using_party_email', 'usingPartyEmail');
    return BillingSubscription(
      subscriptionId: subscriptionId,
      planId: planId,
      productId: productId,
      planName: planName,
      productName: productName,
      subscriptionStatus: status,
      validUntil: dateTimeFromUnixSeconds(validUntilInt),
      addonCode: addon is String && addon.isNotEmpty ? addon : null,
      usingPartyIdentityProvider:
          usingProvider is String && usingProvider.isNotEmpty ? usingProvider : null,
      usingPartyIdentitySubject:
          usingSubject is String && usingSubject.isNotEmpty ? usingSubject : null,
      usingPartyEmail: usingEmail is String && usingEmail.isNotEmpty ? usingEmail : null,
      assignedUserPartyId: assigned is String && assigned.isNotEmpty
          ? assigned
          : null,
    );
  }

  /// Whether this subscription is currently active (e.g. active, trialing).
  bool get isActive =>
      subscriptionStatus.toLowerCase() == 'active' ||
      subscriptionStatus.toLowerCase() == 'trialing';

  /// Whether [addonRef] matches server [addonCode] metadata.
  bool matchesAddonRef(String addonRef) {
    final code = addonCode;
    if (code == null || code.isEmpty) return false;
    return code.toLowerCase() == addonRef.trim().toLowerCase();
  }

  /// Whether the validity period has ended (now > valid_until).
  bool get isPeriodEnded => DateTime.now().isAfter(validUntil);
}
