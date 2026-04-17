enum AddonEntitlementStatus {
  notStarted,
  trialActive,
  trialExpired,
  activePaid,
  gracePeriod,
  cancelled,
  revoked,
  unknown,
}

AddonEntitlementStatus parseAddonEntitlementStatus(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'not_started':
      return AddonEntitlementStatus.notStarted;
    case 'trial_active':
      return AddonEntitlementStatus.trialActive;
    case 'trial_expired':
      return AddonEntitlementStatus.trialExpired;
    case 'active_paid':
      return AddonEntitlementStatus.activePaid;
    case 'grace_period':
      return AddonEntitlementStatus.gracePeriod;
    case 'cancelled':
      return AddonEntitlementStatus.cancelled;
    case 'revoked':
      return AddonEntitlementStatus.revoked;
    default:
      return AddonEntitlementStatus.unknown;
  }
}

String addonEntitlementStatusName(AddonEntitlementStatus status) {
  switch (status) {
    case AddonEntitlementStatus.notStarted:
      return 'not_started';
    case AddonEntitlementStatus.trialActive:
      return 'trial_active';
    case AddonEntitlementStatus.trialExpired:
      return 'trial_expired';
    case AddonEntitlementStatus.activePaid:
      return 'active_paid';
    case AddonEntitlementStatus.gracePeriod:
      return 'grace_period';
    case AddonEntitlementStatus.cancelled:
      return 'cancelled';
    case AddonEntitlementStatus.revoked:
      return 'revoked';
    case AddonEntitlementStatus.unknown:
      return 'unknown';
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

double? _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String? _parseString(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

bool hasAddonAccess(AddonEntitlementStatus status) {
  return status == AddonEntitlementStatus.trialActive ||
      status == AddonEntitlementStatus.activePaid;
}

bool shouldShowPurchaseBanner(AddonEntitlementStatus status) {
  return status == AddonEntitlementStatus.notStarted ||
      status == AddonEntitlementStatus.trialActive ||
      status == AddonEntitlementStatus.trialExpired ||
      status == AddonEntitlementStatus.gracePeriod ||
      status == AddonEntitlementStatus.cancelled ||
      status == AddonEntitlementStatus.revoked ||
      status == AddonEntitlementStatus.unknown;
}

bool canStartEvaluation(AddonEntitlementStatus status) {
  return status == AddonEntitlementStatus.notStarted;
}

bool canPurchaseAddon(AddonEntitlementStatus status) {
  return status != AddonEntitlementStatus.activePaid;
}

class AddonEntitlement {
  const AddonEntitlement({
    required this.planId,
    required this.status,
    required this.hasAccess,
    required this.daysLeft,
    required this.canStartTrial,
    required this.canPurchase,
    required this.showBanner,
    required this.showPurchaseCta,
    required this.showEvaluationCta,
    this.planName,
    this.trialEndsAt,
    this.price,
    this.currency,
    this.billingPeriod,
    this.purchaseUrl,
    this.messageKey,
    this.pricingId,
    this.trialTotalDays,
    this.rawStatus,
  });

  final String planId;
  final String? planName;
  final AddonEntitlementStatus status;
  final String? rawStatus;
  final bool hasAccess;
  final int daysLeft;
  final DateTime? trialEndsAt;
  final double? price;
  final String? currency;
  final String? billingPeriod;
  final String? purchaseUrl;
  final String? messageKey;
  final String? pricingId;
  final int? trialTotalDays;
  final bool canStartTrial;
  final bool canPurchase;
  final bool showBanner;
  final bool showPurchaseCta;
  final bool showEvaluationCta;

  factory AddonEntitlement.fromJson(Map<String, dynamic> json) {
    final statusRaw = _parseString(json['status']) ?? 'unknown';
    final status = parseAddonEntitlementStatus(statusRaw);
    final daysLeft =
        _parseInt(json['daysLeft']) ?? _parseInt(json['days_left']) ?? 0;
    final planId =
        _parseString(json['planId']) ??
        _parseString(json['plan_id']) ??
        json['planId']?.toString() ??
        json['plan_id']?.toString();
    if (planId == null || planId.isEmpty) {
      throw FormatException('planId required.');
    }
    return AddonEntitlement(
      planId: planId,
      planName:
          _parseString(json['planName']) ?? _parseString(json['plan_name']),
      status: status,
      rawStatus: statusRaw,
      hasAccess: hasAddonAccess(status),
      daysLeft: daysLeft,
      trialEndsAt: _parseDateTime(json['trialEndsAt'] ?? json['trial_ends_at']),
      price: _parseDouble(json['price']),
      currency: _parseString(json['currency']),
      billingPeriod:
          _parseString(json['billingPeriod']) ??
          _parseString(json['billing_period']),
      purchaseUrl:
          _parseString(json['purchaseUrl']) ??
          _parseString(json['purchase_url']),
      messageKey:
          _parseString(json['messageKey']) ?? _parseString(json['message_key']),
      pricingId:
          _parseString(json['pricingId']) ??
          _parseString(json['pricing_id']) ??
          json['pricingId']?.toString() ??
          json['pricing_id']?.toString(),
      trialTotalDays:
          _parseInt(json['trialTotalDays']) ??
          _parseInt(json['trial_total_days']),
      canStartTrial: canStartEvaluation(status),
      canPurchase: canPurchaseAddon(status),
      showBanner: shouldShowPurchaseBanner(status),
      showPurchaseCta: canPurchaseAddon(status),
      showEvaluationCta: canStartEvaluation(status),
    );
  }
}

class AddonAccess {
  const AddonAccess({
    required this.allowed,
    required this.status,
    this.daysLeft,
    this.trialEndsAt,
    this.rawStatus,
  });

  final bool allowed;
  final AddonEntitlementStatus status;
  final String? rawStatus;
  final int? daysLeft;
  final DateTime? trialEndsAt;

  factory AddonAccess.fromJson(Map<String, dynamic> json) {
    final statusRaw = _parseString(json['status']) ?? 'unknown';
    return AddonAccess(
      allowed: json['allowed'] == true,
      status: parseAddonEntitlementStatus(statusRaw),
      rawStatus: statusRaw,
      daysLeft: _parseInt(json['daysLeft']) ?? _parseInt(json['days_left']),
      trialEndsAt: _parseDateTime(json['trialEndsAt'] ?? json['trial_ends_at']),
    );
  }
}

class AddonPurchaseSession {
  const AddonPurchaseSession({required this.url, this.sessionId});

  final String url;
  final String? sessionId;

  factory AddonPurchaseSession.fromJson(Map<String, dynamic> json) {
    final url = _parseString(json['url']);
    if (url == null) throw FormatException('url required.');
    return AddonPurchaseSession(
      url: url,
      sessionId:
          _parseString(json['sessionId']) ?? _parseString(json['session_id']),
    );
  }
}
