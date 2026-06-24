class Plan {
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

  /// Add-on code from plan metadata (e.g. `ai_assistant`).
  String? get resolvedAddonCode {
    if (addonCode != null && addonCode!.isNotEmpty) return addonCode;
    final raw = featuresJson?['addonCode'];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  /// Product line from plan metadata (e.g. `secmail`).
  String? get productLine {
    final raw = featuresJson?['productLine'];
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
      billingInterval: j['billingInterval'] as String,
      basePrice: (j['basePrice'] as num).toDouble(),
      currency: j['currency'] as String,
      features: (j['features'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          features,
      featuresJson: featuresJson,
      addonCode: j['addonCode'] as String?,
      isActive: j['isActive'] as bool? ?? true,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class Pricing {
  final int id;
  final int planId;
  final double price;
  final String currency;
  final String? billingInterval;
  final bool isActive;

  const Pricing({
    required this.id,
    required this.planId,
    required this.price,
    required this.currency,
    this.billingInterval,
    this.isActive = true,
  });

  factory Pricing.fromJson(Map<String, dynamic> j) => Pricing(
        id: j['id'] as int,
        planId: j['planId'] as int,
        price: ((j['price'] ?? j['basePrice']) as num).toDouble(),
        currency: j['currency'] as String,
        billingInterval: j['billingInterval'] as String?,
        isActive: j['isActive'] as bool? ?? true,
      );
}

class CreatePlanRequest {
  final int productId;
  final String name;
  final String? description;
  final String billingInterval;
  final double basePrice;
  final String currency;
  final List<String>? features;

  const CreatePlanRequest({
    required this.productId,
    required this.name,
    this.description,
    required this.billingInterval,
    required this.basePrice,
    required this.currency,
    this.features,
  });

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        if (description != null) 'description': description,
        'billingInterval': billingInterval,
        'basePrice': basePrice,
        'currency': currency,
        if (features != null) 'features': features,
      };
}

class UpdatePlanRequest {
  final String? name;
  final String? description;
  final double? basePrice;
  final String? currency;
  final List<String>? features;
  final bool? isActive;

  const UpdatePlanRequest({
    this.name,
    this.description,
    this.basePrice,
    this.currency,
    this.features,
    this.isActive,
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (basePrice != null) 'basePrice': basePrice,
        if (currency != null) 'currency': currency,
        if (features != null) 'features': features,
        if (isActive != null) 'isActive': isActive,
      };
}
