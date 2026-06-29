import 'dart:async';

enum BillingAddonEntitlementStatus {
  notStarted,
  trialActive,
  trialExpired,
  activePaid,
  gracePeriod,
  cancelled,
  revoked,
  unknown,
}

String billingAddonEntitlementStatusName(BillingAddonEntitlementStatus status) {
  switch (status) {
    case BillingAddonEntitlementStatus.notStarted:
      return 'not_started';
    case BillingAddonEntitlementStatus.trialActive:
      return 'trial_active';
    case BillingAddonEntitlementStatus.trialExpired:
      return 'trial_expired';
    case BillingAddonEntitlementStatus.activePaid:
      return 'active_paid';
    case BillingAddonEntitlementStatus.gracePeriod:
      return 'grace_period';
    case BillingAddonEntitlementStatus.cancelled:
      return 'cancelled';
    case BillingAddonEntitlementStatus.revoked:
      return 'revoked';
    case BillingAddonEntitlementStatus.unknown:
      return 'unknown';
  }
}

bool billingHasAddonAccess(BillingAddonEntitlementStatus status) {
  return status == BillingAddonEntitlementStatus.trialActive ||
      status == BillingAddonEntitlementStatus.activePaid ||
      status == BillingAddonEntitlementStatus.gracePeriod;
}

bool billingShouldShowPurchaseBanner(BillingAddonEntitlementStatus status) {
  return status == BillingAddonEntitlementStatus.notStarted ||
      status == BillingAddonEntitlementStatus.trialActive ||
      status == BillingAddonEntitlementStatus.trialExpired ||
      status == BillingAddonEntitlementStatus.gracePeriod ||
      status == BillingAddonEntitlementStatus.cancelled ||
      status == BillingAddonEntitlementStatus.revoked ||
      status == BillingAddonEntitlementStatus.unknown;
}

bool billingCanStartEvaluation(BillingAddonEntitlementStatus status) {
  return status == BillingAddonEntitlementStatus.notStarted;
}

bool billingCanPurchaseAddon(BillingAddonEntitlementStatus status) {
  return status != BillingAddonEntitlementStatus.activePaid &&
      status != BillingAddonEntitlementStatus.gracePeriod;
}

/// Maps JWT subscription_status to add-on entitlement when purchased.
BillingAddonEntitlementStatus billingAddonStatusFromSubscription(
  String subscriptionStatus,
) {
  switch (subscriptionStatus.toLowerCase()) {
    case 'active':
    case 'trialing':
      return BillingAddonEntitlementStatus.activePaid;
    case 'past_due':
      return BillingAddonEntitlementStatus.gracePeriod;
    case 'canceled':
    case 'cancelled':
      return BillingAddonEntitlementStatus.cancelled;
    case 'paused':
      return BillingAddonEntitlementStatus.revoked;
    default:
      return BillingAddonEntitlementStatus.unknown;
  }
}

final class BillingAddonDefinition {
  const BillingAddonDefinition({
    required this.planId,
    required this.trialDays,
    required this.listPrice,
    required this.currency,
    required this.billingPeriod,
    required this.purchaseUrl,
    this.pricingId,
  });

  final String planId;
  final int trialDays;
  final double listPrice;
  final String currency;
  final String billingPeriod;
  final String purchaseUrl;
  final String? pricingId;
}

final class BillingAddonEntitlement {
  const BillingAddonEntitlement({
    required this.planId,
    required this.status,
    required this.rawStatus,
    required this.hasAccess,
    required this.daysLeft,
    required this.trialEndsAt,
    required this.price,
    required this.currency,
    required this.billingPeriod,
    required this.purchaseUrl,
    required this.messageKey,
    required this.pricingId,
    required this.trialTotalDays,
    required this.canStartTrial,
    required this.canPurchase,
    required this.showBanner,
    required this.showPurchaseCta,
    required this.showEvaluationCta,
  });

  final String planId;
  final BillingAddonEntitlementStatus status;
  final String rawStatus;
  final bool hasAccess;
  final int daysLeft;
  final DateTime? trialEndsAt;
  final double price;
  final String currency;
  final String billingPeriod;
  final String? purchaseUrl;
  final String messageKey;
  final String? pricingId;
  final int trialTotalDays;
  final bool canStartTrial;
  final bool canPurchase;
  final bool showBanner;
  final bool showPurchaseCta;
  final bool showEvaluationCta;
}

abstract interface class BillingEntitlementStore {
  String? getString(String key);
  bool? getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
}

final class BillingAddonEntitlementManager {
  const BillingAddonEntitlementManager(this.store);

  final BillingEntitlementStore store;

  static String trialStartedAtKey(String planId) =>
      'addon_trial_started_$planId';
  static String purchasedKey(String planId) => 'addon_purchased_$planId';

  DateTime? readTrialStartedAt(String planId) {
    final iso = store.getString(trialStartedAtKey(planId));
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toUtc();
  }

  Future<void> writeTrialStartedAt(String planId, DateTime startedAtUtc) async {
    await store.setString(
      trialStartedAtKey(planId),
      startedAtUtc.toIso8601String(),
    );
  }

  bool readPurchased(String planId) =>
      store.getBool(purchasedKey(planId)) ?? false;

  Future<void> writePurchased(String planId, {bool value = true}) async {
    await store.setBool(purchasedKey(planId), value);
  }

  Future<bool> resolvePurchased({
    required String planId,
    required bool supportsLocalPurchasedFlag,
    required FutureOr<bool> Function(String planId) hasPurchasedFromSource,
  }) async {
    if (await hasPurchasedFromSource(planId)) {
      return true;
    }
    if (supportsLocalPurchasedFlag) {
      return readPurchased(planId);
    }
    return false;
  }

  BillingAddonEntitlement buildEntitlement({
    required BillingAddonDefinition addon,
    required DateTime nowUtc,
    required DateTime? trialStartedAtUtc,
    required bool purchased,
    required String trialActiveMessageKey,
    required String trialExpiredMessageKey,
    required String notStartedMessageKey,
    String? subscriptionStatus,
  }) {
    final trialDays = addon.trialDays;
    final trialEndsAt = trialStartedAtUtc?.add(Duration(days: trialDays));
    final daysLeft = trialEndsAt == null
        ? 0
        : trialEndsAt.difference(nowUtc).inDays.clamp(0, trialDays);

    final BillingAddonEntitlementStatus status;
    if (purchased) {
      status = subscriptionStatus != null && subscriptionStatus.isNotEmpty
          ? billingAddonStatusFromSubscription(subscriptionStatus)
          : BillingAddonEntitlementStatus.activePaid;
    } else if (trialStartedAtUtc == null) {
      status = BillingAddonEntitlementStatus.notStarted;
    } else if (nowUtc.isBefore(trialEndsAt!)) {
      status = BillingAddonEntitlementStatus.trialActive;
    } else {
      status = BillingAddonEntitlementStatus.trialExpired;
    }

    return BillingAddonEntitlement(
      planId: addon.planId,
      status: status,
      rawStatus: billingAddonEntitlementStatusName(status),
      hasAccess: billingHasAddonAccess(status),
      daysLeft: daysLeft,
      trialEndsAt: trialEndsAt,
      price: addon.listPrice,
      currency: addon.currency,
      billingPeriod: addon.billingPeriod,
      purchaseUrl: addon.purchaseUrl.isEmpty ? null : addon.purchaseUrl,
      messageKey: status == BillingAddonEntitlementStatus.trialActive
          ? trialActiveMessageKey
          : status == BillingAddonEntitlementStatus.trialExpired
              ? trialExpiredMessageKey
              : notStartedMessageKey,
      pricingId: addon.pricingId,
      trialTotalDays: trialDays,
      canStartTrial: billingCanStartEvaluation(status),
      canPurchase: billingCanPurchaseAddon(status),
      showBanner: billingShouldShowPurchaseBanner(status),
      showPurchaseCta: billingCanPurchaseAddon(status),
      showEvaluationCta: billingCanStartEvaluation(status),
    );
  }

  Future<BillingAddonEntitlement> refresh({
    required BillingAddonDefinition addon,
    required bool supportsLocalPurchasedFlag,
    required FutureOr<bool> Function(String planId) hasPurchasedFromSource,
    required String trialActiveMessageKey,
    required String trialExpiredMessageKey,
    required String notStartedMessageKey,
    bool autoStartTrialIfNotStarted = false,
    FutureOr<void> Function(String planId, DateTime startedAtUtc)?
        onTrialAutoStarted,
    FutureOr<String?> Function(String planId)? subscriptionStatusForPlan,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    var trialStartedAt = readTrialStartedAt(addon.planId);
    final purchased = await resolvePurchased(
      planId: addon.planId,
      supportsLocalPurchasedFlag: supportsLocalPurchasedFlag,
      hasPurchasedFromSource: hasPurchasedFromSource,
    );

    if (autoStartTrialIfNotStarted && trialStartedAt == null && !purchased) {
      trialStartedAt = nowUtc;
      await writeTrialStartedAt(addon.planId, trialStartedAt);
      if (onTrialAutoStarted != null) {
        await onTrialAutoStarted(addon.planId, trialStartedAt);
      }
    }

    String? subscriptionStatus;
    if (purchased && subscriptionStatusForPlan != null) {
      subscriptionStatus = await subscriptionStatusForPlan(addon.planId);
    }

    return buildEntitlement(
      addon: addon,
      nowUtc: nowUtc,
      trialStartedAtUtc: trialStartedAt,
      purchased: purchased,
      trialActiveMessageKey: trialActiveMessageKey,
      trialExpiredMessageKey: trialExpiredMessageKey,
      notStartedMessageKey: notStartedMessageKey,
      subscriptionStatus: subscriptionStatus,
    );
  }

  Future<BillingAddonEntitlement> startTrial({
    required BillingAddonDefinition addon,
    required bool supportsLocalPurchasedFlag,
    required FutureOr<bool> Function(String planId) hasPurchasedFromSource,
    required String trialActiveMessageKey,
    required String trialExpiredMessageKey,
    required String notStartedMessageKey,
    FutureOr<void> Function(String planId, DateTime startedAtUtc)?
        onTrialStarted,
  }) async {
    final purchased = await resolvePurchased(
      planId: addon.planId,
      supportsLocalPurchasedFlag: supportsLocalPurchasedFlag,
      hasPurchasedFromSource: hasPurchasedFromSource,
    );
    if (!purchased) {
      final current = readTrialStartedAt(addon.planId);
      if (current == null) {
        final startedAt = DateTime.now().toUtc();
        await writeTrialStartedAt(addon.planId, startedAt);
        if (onTrialStarted != null) {
          await onTrialStarted(addon.planId, startedAt);
        }
      }
    }

    return refresh(
      addon: addon,
      supportsLocalPurchasedFlag: supportsLocalPurchasedFlag,
      hasPurchasedFromSource: hasPurchasedFromSource,
      trialActiveMessageKey: trialActiveMessageKey,
      trialExpiredMessageKey: trialExpiredMessageKey,
      notStartedMessageKey: notStartedMessageKey,
    );
  }
}
