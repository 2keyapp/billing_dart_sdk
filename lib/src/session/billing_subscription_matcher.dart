import '../models/billing_subscription.dart';
import '../models/billing_token_payload.dart';

/// Plan-name hints when JWT only has numeric [BillingSubscription.planId].
const Map<String, List<String>> defaultAddonRefPlanNameHints = {
  'ai_assistant': ['local-ai', 'local ai', 'ai assistant'],
  'scomm_connector': ['scomm connect', 'scomm connector', 'connector'],
  'linux': ['linux'],
  'accent_color': ['accent', 'colour', 'color', 'custom colour'],
};

/// True when [subscription] is an active seat for stable billing code [addonRef].
bool billingSubscriptionMatchesAddonRef(
  BillingSubscription subscription,
  String addonRef, {
  List<String> nameKeywords = const [],
  Map<String, List<String>> planNameHints = defaultAddonRefPlanNameHints,
}) {
  if (!subscription.isActive) return false;

  final target = addonRef.trim().toLowerCase();
  if (target.isEmpty) return false;

  if (subscription.planId.toLowerCase() == target) return true;
  if (subscription.matchesAddonRef(target)) return true;

  final keywords = <String>{
    ...nameKeywords.map((k) => k.toLowerCase()),
    ...?planNameHints[target],
  };

  if (keywords.isEmpty) return false;

  final productName = subscription.productName.toLowerCase();
  final planName = subscription.planName.toLowerCase();
  return keywords.any(
    (keyword) => productName.contains(keyword) || planName.contains(keyword),
  );
}

/// First matching active subscription renewal date, if any.
DateTime? billingRenewalForAddonRef(
  BillingTokenPayload? payload,
  String addonRef, {
  List<String> nameKeywords = const [],
  Map<String, List<String>> planNameHints = defaultAddonRefPlanNameHints,
}) {
  if (payload == null) return null;
  for (final sub in payload.subscriptions) {
    if (!billingSubscriptionMatchesAddonRef(
      sub,
      addonRef,
      nameKeywords: nameKeywords,
      planNameHints: planNameHints,
    )) {
      continue;
    }
    return sub.validUntil;
  }
  return null;
}

bool billingHasActiveAddonRef(
  BillingTokenPayload? payload,
  String addonRef, {
  List<String> nameKeywords = const [],
  Map<String, List<String>> planNameHints = defaultAddonRefPlanNameHints,
}) {
  if (payload == null) return false;
  return payload.subscriptions.any(
    (sub) => billingSubscriptionMatchesAddonRef(
      sub,
      addonRef,
      nameKeywords: nameKeywords,
      planNameHints: planNameHints,
    ),
  );
}
