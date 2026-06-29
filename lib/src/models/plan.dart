/// Public catalog plan from `GET /api/v1/plans` (no auth required).
class Plan {
  const Plan({
    required this.id,
    required this.productId,
    required this.name,
    this.description,
    required this.billingInterval,
    required this.basePrice,
    required this.currency,
    this.features = const [],
    this.featuresJson,
    this.addonCode,
    this.isActive = true,
  });

  final int id;
  final int productId;
  final String name;
  final String? description;
  final String billingInterval;
  final double basePrice;
  final String currency;
  final List<String> features;
  final Map<String, dynamic>? featuresJson;
  final String? addonCode;
  final bool isActive;

  /// Add-on code from plan metadata (e.g. `ai_assistant`).
  String? get resolvedAddonCode {
    if (addonCode != null && addonCode!.isNotEmpty) return addonCode;
    final raw = featuresJson?['addonCode'];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  factory Plan.fromJson(Map<String, dynamic> j) {
    final featuresRaw = j['featuresJson'] ?? j['features_json'];
    List<String> features = const [];
    Map<String, dynamic>? featuresJson;

    if (featuresRaw is List) {
      features = featuresRaw.map((e) => e.toString()).toList();
    } else if (featuresRaw is Map<String, dynamic>) {
      featuresJson = featuresRaw;
      final nested = featuresRaw['features'];
      if (nested is List) {
        features = nested.map((e) => e.toString()).toList();
      }
    }

    return Plan(
      id: _parseInt(j['id']) ?? 0,
      productId: _parseInt(j['productId'] ?? j['product_id']) ?? 0,
      name: j['name'] as String,
      description: j['description'] as String?,
      billingInterval:
          (j['billingInterval'] ?? j['billing_interval']) as String,
      basePrice: ((j['basePrice'] ?? j['base_price']) as num).toDouble(),
      currency: j['currency'] as String,
      features:
          (j['features'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              features,
      featuresJson: featuresJson,
      addonCode: j['addonCode'] as String? ?? j['addon_code'] as String?,
      isActive: j['isActive'] as bool? ?? j['is_active'] as bool? ?? true,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Server billing interval values (`monthly`, `annual`).
abstract final class BillingInterval {
  static const monthly = 'monthly';
  static const annual = 'annual';
  static const yearly = annual;
}
