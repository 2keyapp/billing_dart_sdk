/// Billing SDK — a generic, extensible Dart client for the Billing API.
library billing_sdk;

// Main client — the only thing most consumers need to import.
export 'src/billing_client.dart';
export 'src/sdk.dart';

// Re-export public surface so consumers can import from one place.
export 'src/core/token_provider.dart';
export 'src/core/i_billing_http_client.dart';
export 'src/exceptions/exceptions.dart';
export 'src/models/models.dart';
export 'src/services/services.dart';
export 'src/entitlements/addon_entitlements.dart';
export 'src/checkout/addon_checkout_facade.dart';

// Token verification and sync
export 'src/verification/token_verifier.dart';
export 'src/api/billing_api_client.dart';
export 'src/logging/sdk_logger.dart';

// Card validation (pure Dart — no Flutter dependency)
export 'src/validation/card_validator.dart';
