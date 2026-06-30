import 'billing_subscription.dart';
import 'jwt_payload_keys.dart';
import 'paying_party.dart';

/// Default expiry when JWT has no exp claim.
final DateTime _defaultExpiresAt = DateTime.utc(2099, 12, 31);

/// Decoded billing license token payload from the signed JWT.
/// Flat shape: payload_version, iss, aud, iat, exp, paying_party, subscriptions[].
class BillingTokenPayload {
  const BillingTokenPayload({
    required this.payloadVersion,
    required this.expiresAt,
    required this.payingParty,
    required this.subscriptions,
    this.issuedAt,
    this.issuer,
    this.audience,
  });

  final int payloadVersion;
  final DateTime expiresAt;
  final DateTime? issuedAt;
  final String? issuer;
  final String? audience;
  final PayingParty payingParty;
  final List<BillingSubscription> subscriptions;

  /// Parses from JWT payload map. Throws [FormatException] if required fields are missing/invalid.
  factory BillingTokenPayload.fromJson(Map<String, dynamic> json) {
    final version = parseInt(getKey(json, 'payload_version', 'payloadVersion'));
    if (version == null)
      throw FormatException('payload_version (number) required.');
    final exp = parseInt(json['exp']);
    final expiresAt = exp != null
        ? dateTimeFromUnixSeconds(exp)
        : _defaultExpiresAt;
    final payingPartyRaw = getKey(json, 'paying_party', 'payingParty');
    if (payingPartyRaw is! Map<String, dynamic>)
      throw FormatException('paying_party object required.');
    final payingParty = PayingParty.fromJson(payingPartyRaw);
    final subscriptionsRaw = json['subscriptions'];
    if (subscriptionsRaw is! List)
      throw FormatException('subscriptions array required.');
    final subscriptions = <BillingSubscription>[];
    for (var i = 0; i < subscriptionsRaw.length; i++) {
      final item = subscriptionsRaw[i];
      if (item is! Map<String, dynamic>)
        throw FormatException('subscriptions[$i] must be an object.');
      subscriptions.add(BillingSubscription.fromJson(item));
    }
    final iat = parseInt(json['iat']);
    return BillingTokenPayload(
      payloadVersion: version,
      expiresAt: expiresAt,
      payingParty: payingParty,
      subscriptions: subscriptions,
      issuedAt: iat != null ? dateTimeFromUnixSeconds(iat) : null,
      issuer: json['iss'] is String ? json['iss'] as String : null,
      audience: json['aud'] is String ? json['aud'] as String : null,
    );
  }

  /// Convenience alias for [payingParty] (e.g. when migrating from mailbox-based payloads).
  PayingParty? get firstPayingParty => payingParty;

  /// List of subscription IDs.
  List<String> get subscriptionIds =>
      subscriptions.map((s) => s.subscriptionId).toList();

  /// Billing email from paying party.
  String? get email =>
      payingParty.billingEmail.isNotEmpty ? payingParty.billingEmail : null;

  /// Active subscriptions only (status active or trialing).
  List<BillingSubscription> get activeSubscriptions =>
      subscriptions.where((s) => s.isActive).toList();

  /// Whether this payload has an active subscription with the given subscription ID.
  bool hasSubscription(String subscriptionId) =>
      subscriptions.any((s) => s.subscriptionId == subscriptionId);

  /// Whether the payload has any subscription for the given plan (add-on check).
  bool hasPlan(String planId) =>
      subscriptions.any((s) => s.planId == planId && s.isActive);

  /// Whether the payload has any subscription for the given product.
  bool hasProduct(String productId) =>
      subscriptions.any((s) => s.productId == productId && s.isActive);

  /// Whether the payload has an active subscription for the given add-on code.
  bool hasAddon(String addonCode) => subscriptions.any(
        (s) => s.isActive && s.addonCode == addonCode,
      );

  /// Whether the token is still valid (not expired).
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillingTokenPayload &&
          runtimeType == other.runtimeType &&
          payloadVersion == other.payloadVersion &&
          expiresAt == other.expiresAt &&
          payingParty == other.payingParty &&
          _listEquals(subscriptions, other.subscriptions);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    payloadVersion,
    expiresAt,
    payingParty,
    Object.hashAll(subscriptions),
  );
}
