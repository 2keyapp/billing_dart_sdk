import '../session/license_entitlements.dart';

/// Build-time configuration for using-party billing integration.
///
/// Host apps map dart-defines / env into this object, then call
/// [BillingSdk.configureFrom] and [BillingAuthClient.fromConfig].
class BillingSdkConfig {
  const BillingSdkConfig({
    required this.apiBaseUrl,
    required this.deepLinkScheme,
    required this.storagePrefix,
    this.publicKeyPem,
    this.publicKeyAsset,
    this.portalBaseUrl,
    this.shopPath = '/shop',
    this.licensePollInterval = defaultLicensePollInterval,
    this.addonPlanNameHints = const {},
  });

  /// Billing server origin (e.g. `https://billing.example.com`).
  /// Trailing `/api/v1` is normalized away.
  final String apiBaseUrl;

  /// App deep-link scheme for social OAuth callbacks (e.g. `myapp`).
  final String deepLinkScheme;

  /// Single namespace for auth cookie storage and session keys.
  ///
  /// Must be the same value used for [SecureBillingAuthStorage] and
  /// [SecureBillingSessionStore].
  final String storagePrefix;

  /// EC public key PEM (ES256) for license JWT verification.
  final String? publicKeyPem;

  /// Flutter asset path for the license public key (alternative to [publicKeyPem]).
  final String? publicKeyAsset;

  /// Portal / shop web origin. Defaults to [apiBaseUrl] when null/empty.
  final String? portalBaseUrl;

  /// Marketplace path appended to the portal origin (default `/shop`).
  final String shopPath;

  /// Background license poll interval (default 6 hours).
  final Duration licensePollInterval;

  /// Host product plan-name hints for numeric plan IDs in license JWTs.
  /// Empty by default — supply product-specific maps in the host app.
  final Map<String, List<String>> addonPlanNameHints;

  /// Resolved portal origin (explicit [portalBaseUrl] or [apiBaseUrl]).
  String get resolvedPortalBaseUrl {
    final portal = portalBaseUrl?.trim() ?? '';
    if (portal.isNotEmpty) return portal;
    return apiBaseUrl;
  }
}
