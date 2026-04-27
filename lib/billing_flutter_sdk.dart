/// Billing Flutter SDK – init, sync from server, paste+verify.
///
/// Usage:
/// 1. Call [BillingSdk.configure] with [billingApiBaseUrl] and optionally [publicKeyPem].
/// 2. On app start, call [BillingSdk.init] with the saved token from storage.
/// 3. Use [BillingSdk.getPayload] for add-on checks.
/// 4. For "Sync billing" button: [BillingSdk.syncFromServer].
/// 5. For paste flow: [BillingSdk.verifyAndDecode]; show [BillingTokenError.message] on failure.
library;

export 'package:billing_flutter_sdk/src/api/billing_api_client.dart'
    show SyncResult, SyncSuccess, SyncFailure, normalizeBillingApiBaseUrl;
export 'package:billing_flutter_sdk/src/billing_sdk.dart';
export 'package:billing_flutter_sdk/src/models/billing_subscription.dart';
export 'package:billing_flutter_sdk/src/models/billing_token_error.dart';
export 'package:billing_flutter_sdk/src/models/billing_token_payload.dart';
export 'package:billing_flutter_sdk/src/models/paying_party.dart';
export 'package:billing_flutter_sdk/src/keys/public_key_loader_asset.dart'
    show loadPublicKeyFromAsset;
